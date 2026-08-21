import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krag_app/constants/index.dart' as constants;
import 'package:cryptography/cryptography.dart';
import '../utils/encoding.dart';
import '../utils/logger.dart';
import 'providers.dart';
import 'keys_store.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final bool isVerifyingDrive;
  final bool isGoogleDriveConnected;
  final Uint8List? vaultSalt;
  final String? error;
  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.isVerifyingDrive = false,
    this.isGoogleDriveConnected = false,
    this.vaultSalt,
    this.error,
  });
  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    bool? isVerifyingDrive,
    bool? isGoogleDriveConnected,
    Uint8List? vaultSalt,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      isVerifyingDrive: isVerifyingDrive ?? this.isVerifyingDrive,
      isGoogleDriveConnected:
          isGoogleDriveConnected ?? this.isGoogleDriveConnected,
      vaultSalt: vaultSalt ?? this.vaultSalt,
      error: error,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(() => _checkRestoration());
    return const AuthState(isLoading: true);
  }

  Future<void> _checkRestoration() async {
    KragLogger.info(LogDomain.auth, 'Checking restoration state...');
    try {
      final googleAuth = ref.read(googleAuthServiceProvider);
      final sessionService = ref.read(sessionServiceProvider);
      final isDriveConnected = await googleAuth.restoreSession();
      KragLogger.info(LogDomain.auth, 'Drive connected:$isDriveConnected');
      if (isDriveConnected) {
        KragLogger.info(
          LogDomain.auth,
          'Auth successful-waiting for Firebase Auth token propagation...',
        );
        await Future.delayed(const Duration(milliseconds: 250));
        final currentUser = ref.read(userIdProvider);
        if (currentUser == 'anonymous') {
          KragLogger.warn(
            LogDomain.auth,
            'Firebase Auth not ready after delay-waiting additional time',
          );
          await Future.delayed(const Duration(milliseconds: 150));
        }
        final verifiedUser = ref.read(userIdProvider);
        KragLogger.info(
            LogDomain.auth, 'Firebase Auth verified-User ID:$verifiedUser');
      }
      final sessionData = await sessionService.loadDMKFromSession();
      KragLogger.info(
          LogDomain.auth, 'Session DMK loaded:${sessionData != null}');
      final prefs = await SharedPreferences.getInstance();
      final savedSalt = prefs.getString(constants.StorageKeys.vaultSalt);
      Uint8List? saltBytes;
      if (savedSalt != null) {
        saltBytes = base64ToUint8Array(savedSalt);
        KragLogger.info(LogDomain.crypto, 'Local salt found');
      } else {
        KragLogger.info(LogDomain.crypto, 'No local salt found');
      }
      bool isVaultUnlocked = false;
      if (sessionData != null &&
          sessionData['k'] != null &&
          saltBytes != null) {
        final List<int> keyBytes = (sessionData['k'] as List).cast<int>();
        final SecretKey dmk = SecretKey(keyBytes);
        ref.read(keysStoreProvider.notifier).setKeys(dmk, saltBytes);
        isVaultUnlocked = true;
        KragLogger.info(LogDomain.auth, 'Vault unlocked from session');
      }
      state = state.copyWith(
        isLoading: false,
        isGoogleDriveConnected: isDriveConnected,
        isAuthenticated: isVaultUnlocked,
        vaultSalt: saltBytes,
        error: null,
      );
      if (isDriveConnected && saltBytes == null) {
        KragLogger.info(
          LogDomain.auth,
          'Drive connected but no salt. Fetching from storage...',
        );
        await _fetchSaltFromDrive();
      }
    } catch (e, stack) {
      KragLogger.error(LogDomain.auth, 'Restoration check failed', e, stack);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _fetchSaltFromDrive() async {
    if (state.isVerifyingDrive) return;
    state = state.copyWith(isVerifyingDrive: true);
    KragLogger.info(LogDomain.sync, 'Fetching salt from storage...');
    try {
      final adapter = ref.read(driveAdapterProvider);
      final vaultKeyService = ref.read(vaultKeyServiceProvider);
      KragLogger.info(LogDomain.sync, 'Adapter and vault key service ready');
      await adapter.initializeRootFolder(
        constants.AppConstants.vaultRootFolderName,
      );
      KragLogger.info(LogDomain.sync, 'Root folder initialized');
      final salt = await vaultKeyService.getSalt();
      if (salt != null) {
        KragLogger.info(LogDomain.sync, 'Salt retrieved from storage');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          constants.StorageKeys.vaultSalt,
          uint8ArrayToBase64(salt),
        );
        state = state.copyWith(vaultSalt: salt);
      } else {
        KragLogger.warn(LogDomain.sync, 'Salt file not found in storage');
      }
    } catch (e, stack) {
      KragLogger.error(
          LogDomain.sync, 'Failed to fetch salt from storage', e, stack);
    } finally {
      state = state.copyWith(isVerifyingDrive: false);
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final googleAuth = ref.read(googleAuthServiceProvider);
      KragLogger.info(
          LogDomain.auth, 'AuthNotifier:Starting Google sign-in...');
      await googleAuth.signIn();
      KragLogger.info(LogDomain.auth, 'AuthNotifier:Google sign-in completed');
      KragLogger.info(
        LogDomain.auth,
        'AuthNotifier:Waiting for auth state propagation...',
      );
      await Future.delayed(const Duration(milliseconds: 150));
      KragLogger.info(
        LogDomain.auth,
        'AuthNotifier:Auth state propagation complete,proceeding to restoration check',
      );
      await _checkRestoration();
    } catch (e, stack) {
      KragLogger.error(LogDomain.auth, 'Sign in failed', e, stack);
      final msg = e.toString().replaceAll('Exception:', '');
      state = state.copyWith(
        isLoading: false,
        error: msg,
      );
    }
  }

  Future<void> handleUnlock(String password, bool isNewVault) async {
    state = state.copyWith(
      isLoading: true,
      isVerifyingDrive: true,
      error: null,
    );
    KragLogger.info(
        LogDomain.auth, 'Handling vault unlock. New vault:$isNewVault');
    try {
      if (!state.isGoogleDriveConnected && state.vaultSalt == null) {
        throw Exception("Connect Drive first to retrieve vault configuration");
      }
      final vaultKeyService = ref.read(vaultKeyServiceProvider);
      Map<String, dynamic> result;
      if (isNewVault) {
        if (!state.isGoogleDriveConnected) {
          throw Exception("Connect Drive first");
        }
        result = await vaultKeyService.initializeVault(password);
        KragLogger.info(LogDomain.crypto, 'Vault initialized successfully');
      } else {
        result = await vaultKeyService.unlockVault(
          password,
          storedSalt: state.vaultSalt,
        );
        KragLogger.info(LogDomain.crypto, 'Vault unlocked successfully');
      }
      final SecretKey dmkKey = result['dmk'];
      final Uint8List salt = result['salt'];
      final List<int> dmkBytes = await dmkKey.extractBytes();
      await ref.read(sessionServiceProvider).saveDMKToSession({'k': dmkBytes});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        constants.StorageKeys.vaultSalt,
        uint8ArrayToBase64(salt),
      );
      ref.read(keysStoreProvider.notifier).setKeys(dmkKey, salt);
      state = state.copyWith(
        isAuthenticated: true,
        vaultSalt: salt,
        isLoading: false,
        isVerifyingDrive: false,
      );
    } on Exception catch (e, stack) {
      final errorMessage = e.toString();
      KragLogger.error(LogDomain.auth, 'Unlock failed', e, stack);
      String userFacingError;
      if (errorMessage.contains('Session expired')) {
        userFacingError = 'Session expired. Please sign in again.';
        KragLogger.warn(
          LogDomain.auth,
          'Session expired detected during unlock. Setting user-friendly message.',
        );
      } else if (errorMessage.contains('Not authenticated with Google Drive')) {
        userFacingError =
            'Google Drive authentication required. Please sign in.';
      } else {
        userFacingError =
            'Unlock failed:${errorMessage.replaceAll('Exception:', '')}';
      }
      state = state.copyWith(
        isLoading: false,
        isVerifyingDrive: false,
        error: userFacingError,
      );
    } catch (e, stack) {
      KragLogger.error(LogDomain.auth, 'Unlock failed', e, stack);
      state = state.copyWith(
        isLoading: false,
        isVerifyingDrive: false,
        error: 'Unlock failed:${e.toString().replaceAll('Exception:', '')}',
      );
    }
  }

  Future<void> handleLogout() async {
    KragLogger.info(LogDomain.auth, 'Logging out...');

    // Clear index cache before clearing session to ensure we have access to providers
    try {
      final indexManager = await ref.read(indexManagerProvider.future);
      await indexManager?.clearCache();
    } catch (e) {
      KragLogger.warn(
          LogDomain.auth, 'Failed to clear index cache during logout: $e');
    }

    await ref.read(googleAuthServiceProvider).signOut();
    await ref.read(sessionServiceProvider).clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(constants.StorageKeys.vaultSalt);

    ref.invalidate(driveSyncServiceProvider);
    ref.read(keysStoreProvider.notifier).clearKeys();
    state = const AuthState(isLoading: false);
  }

  Future<void> invalidateSessionDueToAuthError([String? errorContext]) async {
    try {
      KragLogger.warn(
        LogDomain.auth,
        'Invalidating session due to auth error. Context:${errorContext ?? 'Unknown'}',
      );

      // Clear index cache
      try {
        final indexManager = await ref.read(indexManagerProvider.future);
        await indexManager?.clearCache();
      } catch (e) {
        KragLogger.warn(LogDomain.auth,
            'Failed to clear index cache during session invalidation: $e');
      }

      await ref.read(googleAuthServiceProvider).signOut();
      await ref.read(sessionServiceProvider).clearSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(constants.StorageKeys.vaultSalt);

      ref.invalidate(driveSyncServiceProvider);
      ref.read(keysStoreProvider.notifier).clearKeys();
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        isVerifyingDrive: false,
        isGoogleDriveConnected: false,
        vaultSalt: null,
        error: 'Session expired. Please sign in again.',
      );
      KragLogger.info(
        LogDomain.auth,
        'Session invalidated successfully due to auth error.',
      );
    } catch (e, stack) {
      KragLogger.error(
          LogDomain.auth, 'Failed to invalidate session', e, stack);
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        error: 'Session expired. Please sign in again.',
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final authStoreProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
