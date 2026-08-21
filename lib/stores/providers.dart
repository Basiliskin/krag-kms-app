import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/google_auth_service.dart';
import '../services/firestore_adapter.dart';
import '../services/crypto_service.dart';
import '../services/vault_key_service.dart';
import '../services/session_service.dart';
import '../services/drive_sync_service.dart';
import '../services/index_manager.dart';
import '../services/file_hydration_service.dart';
import '../services/orphan_reconciliation_service.dart';
import '../services/interfaces.dart';
import '../utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final sessionServiceProvider = Provider<ISessionService>((ref) {
  return SessionService();
});

final googleAuthServiceProvider = Provider((ref) => GoogleAuthService());

final cryptoServiceProvider = Provider<ICryptoService>(
  (ref) => CryptoService(),
);

final userIdProvider = Provider<String>((ref) {
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser != null) {
    KragLogger.info(
      LogDomain.auth,
      'userIdProvider: Current user found. User ID: ${currentUser.uid}',
    );
    return currentUser.uid;
  } else {
    KragLogger.warn(
      LogDomain.auth,
      'userIdProvider: No authenticated user. Using "anonymous" fallback.',
    );
    return 'anonymous';
  }
});

final authStateStreamProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// CRITICAL FIX: Ensure provider rebuilds when auth state changes
final driveAdapterProvider = Provider<IDriveAdapter>((ref) {
  final firestore = ref.watch(firestoreProvider);

  // Watch auth state stream to trigger rebuilds on auth changes
  final authState = ref.watch(authStateStreamProvider);

  final userId = authState.when(
    data: (user) {
      final id = user?.uid ?? 'anonymous';
      KragLogger.info(
        LogDomain.sync,
        'driveAdapterProvider: Creating adapter with user ID: $id (from auth stream)',
      );
      return id;
    },
    loading: () {
      // During loading, try to get current user directly
      final currentUser = FirebaseAuth.instance.currentUser;
      final id = currentUser?.uid ?? 'anonymous';
      KragLogger.info(
        LogDomain.sync,
        'driveAdapterProvider: Creating adapter with user ID: $id (from currentUser during loading)',
      );
      return id;
    },
    error: (_, __) {
      KragLogger.warn(
        LogDomain.sync,
        'driveAdapterProvider: Error in auth stream, falling back to anonymous',
      );
      return 'anonymous';
    },
  );

  KragLogger.info(
    LogDomain.sync,
    'driveAdapterProvider: Instantiating FirestoreAdapter for user: $userId',
  );

  return FirestoreAdapter(firestore, userId);
});

final vaultKeyServiceProvider = Provider<IVaultKeyService>((ref) {
  final driveAdapter = ref.watch(driveAdapterProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  return VaultKeyService(driveAdapter, cryptoService as CryptoService);
});

final indexManagerProvider = FutureProvider<IIndexManager?>((ref) async {
  KragLogger.info(
    LogDomain.sync,
    'IndexManager provider: Starting initialization...',
  );

  final sessionService = ref.watch(sessionServiceProvider);
  final dmkMap = await sessionService.loadDMKFromSession();

  if (dmkMap == null) return null;

  final driveAdapter = ref.watch(driveAdapterProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);

  final rawBytes = (dmkMap['k'] as List).cast<int>();
  final secretKey = SecretKey(rawBytes);

  final indexManager = IndexManager(driveAdapter, cryptoService);
  indexManager.initialize(secretKey);

  return indexManager;
});

final fileHydrationServiceProvider =
    FutureProvider<IFileHydrationService?>((ref) async {
  final sessionService = ref.watch(sessionServiceProvider);
  final dmkMap = await sessionService.loadDMKFromSession();

  if (dmkMap == null) return null;

  final driveAdapter = ref.watch(driveAdapterProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  final indexManager = await ref.watch(indexManagerProvider.future);

  if (indexManager == null) return null;

  final rawBytes = (dmkMap['k'] as List).cast<int>();
  final secretKey = SecretKey(rawBytes);

  final hydrationService = FileHydrationService(
    driveAdapter,
    cryptoService,
    indexManager,
  );
  hydrationService.initialize(secretKey);

  return hydrationService;
});

final orphanReconciliationServiceProvider =
    FutureProvider<IOrphanReconciliationService?>((ref) async {
  final sessionService = ref.watch(sessionServiceProvider);
  final dmkMap = await sessionService.loadDMKFromSession();

  if (dmkMap == null) return null;

  final driveAdapter = ref.watch(driveAdapterProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  final indexManager = await ref.watch(indexManagerProvider.future);
  final hydrationService = await ref.watch(fileHydrationServiceProvider.future);

  if (indexManager == null || hydrationService == null) return null;

  final rawBytes = (dmkMap['k'] as List).cast<int>();
  final secretKey = SecretKey(rawBytes);

  final reconciliationService = OrphanReconciliationService(
    driveAdapter,
    cryptoService,
    indexManager,
    hydrationService,
  );
  reconciliationService.initialize(secretKey);

  return reconciliationService;
});

final driveSyncServiceProvider = FutureProvider<DriveSyncService?>((ref) async {
  final sessionService = ref.watch(sessionServiceProvider);
  final dmkMap = await sessionService.loadDMKFromSession();

  if (dmkMap == null) return null;

  final driveAdapter = ref.watch(driveAdapterProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  final indexManager = await ref.watch(indexManagerProvider.future);

  if (indexManager == null) return null;

  final rawBytes = (dmkMap['k'] as List).cast<int>();
  final secretKey = SecretKey(rawBytes);

  final syncService = DriveSyncService(
    driveAdapter,
    cryptoService,
    indexManager,
  );

  try {
    await syncService.initialize(secretKey);
    return syncService;
  } catch (e, stack) {
    KragLogger.error(
      LogDomain.sync,
      'DriveSyncService provider: Initialization failed',
      e,
      stack,
    );
    return null;
  }
});
