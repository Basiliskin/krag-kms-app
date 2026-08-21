import 'dart:convert';
import 'dart:typed_data';
import 'package:krag_app/utils/logger.dart';
import 'package:krag_app/constants/index.dart' as constants;
import '../utils/encoding.dart';
import 'interfaces.dart';
import 'crypto_service.dart';
import '../types/index.dart';

class VaultKeyService implements IVaultKeyService {
  static const String _saltFile = 'salt.json';
  static const String _wrappedKeysFile = 'wrapped_keys.json';

  final IDriveAdapter _driveAdapter;
  final CryptoService _cryptoService;

  VaultKeyService(this._driveAdapter, this._cryptoService);

  @override
  Future<bool> vaultExists() async {
    try {
      final configPath = await _ensureConfigFolder();

      // PRIORITY 1: Check Firestore first
      KragLogger.info(
        LogDomain.crypto,
        'VaultKeyService: Checking vault existence in Firestore...',
      );

      try {
        final firestoreFiles = await _driveAdapter.listFiles(configPath);
        final hasSaltInFirestore =
            firestoreFiles.any((f) => f.name == _saltFile);

        if (hasSaltInFirestore) {
          KragLogger.info(
            LogDomain.crypto,
            'VaultKeyService: Vault found in Firestore',
          );
          return true;
        }
      } catch (e) {
        KragLogger.warn(
          LogDomain.crypto,
          'VaultKeyService: Firestore check failed: $e',
        );
      }

      KragLogger.info(
        LogDomain.crypto,
        'VaultKeyService: No vault found in Firestore',
      );

      return false;
    } catch (e) {
      KragLogger.warn(
        LogDomain.crypto,
        'VaultKeyService: Error checking vault existence: $e',
      );
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> initializeVault(String password) async {
    KragLogger.info(
      LogDomain.crypto,
      'VaultKeyService: Initializing new vault in Firestore...',
    );

    final salt = await _cryptoService.generateSalt();
    final kek = await _cryptoService.deriveKey(password, salt);
    final dmk = await _cryptoService.generateDMK();

    final wrapResult = await _cryptoService.wrapDMK(kek, dmk);
    final iv = wrapResult['iv'] as Uint8List;
    final wrappedKey = wrapResult['wrappedKey'] as String;

    final configPath = await _ensureConfigFolder();

    KragLogger.info(
      LogDomain.crypto,
      'VaultKeyService: Creating salt.json at path: $configPath',
    );

    // Save salt
    final saltJson = jsonEncode({'salt': uint8ArrayToBase64(salt)});
    final saltBytes = stringToBytes(saltJson);
    await _driveAdapter.ensureFile(
      _saltFile,
      saltBytes,
      'application/json',
      configPath,
    );

    KragLogger.info(
      LogDomain.crypto,
      'VaultKeyService: Creating wrapped_keys.json at path: $configPath',
    );

    // Save wrapped keys
    final wrappedKeysJson = jsonEncode({
      'iv': uint8ArrayToBase64(iv),
      'wrappedKey': wrappedKey,
    });
    final wrappedKeysBytes = stringToBytes(wrappedKeysJson);
    final wrappedKeysFileId = await _driveAdapter.ensureFile(
      _wrappedKeysFile,
      wrappedKeysBytes,
      'application/json',
      configPath,
    );

    // Verify creation
    bool verified = false;
    int attempts = 0;
    while (attempts < 3 && !verified) {
      final files = await _driveAdapter.listFiles(configPath, useCache: false);
      verified = files.any((f) => f.name == _saltFile) &&
          files.any((f) => f.name == _wrappedKeysFile);

      if (!verified) {
        attempts++;
        KragLogger.warn(
          LogDomain.crypto,
          'VaultKeyService: Verification attempt $attempts/3 - files not yet visible',
        );
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }

    if (!verified) {
      throw Exception(
        'VaultKeyService: Failed to verify vault configuration documents after creation.',
      );
    }

    KragLogger.info(
      LogDomain.crypto,
      'VaultKeyService: Vault initialization verified successfully',
    );

    final metadata = await _driveAdapter.getFileMetadata(wrappedKeysFileId);
    final wrappedKeysTimestamp =
        DateTime.parse(metadata.modifiedTime).millisecondsSinceEpoch;

    return {
      'salt': salt,
      'kek': kek,
      'dmk': dmk,
      'wrappedKeysTimestamp': wrappedKeysTimestamp,
    };
  }

  @override
  Future<Map<String, dynamic>> unlockVault(
    String password, {
    Uint8List? storedSalt,
  }) async {
    final configPath = await _ensureConfigFolder();

    // PRIORITY 1: Try to get salt from Firestore
    String? saltFileId = await _findFileInFirestore(configPath, _saltFile);
    Uint8List salt;

    if (saltFileId == null) {
      if (storedSalt != null) {
        KragLogger.info(
          LogDomain.crypto,
          'VaultKeyService: Salt document missing in Firestore, recreating from local salt',
        );
        salt = storedSalt;
        await _driveAdapter.ensureFile(
          _saltFile,
          stringToBytes(jsonEncode({'salt': uint8ArrayToBase64(salt)})),
          'application/json',
          configPath,
        );
      } else {
        throw Exception(
          'VaultKeyService: Vault salt not found and no local fallback available.',
        );
      }
    } else {
      KragLogger.info(
        LogDomain.crypto,
        'VaultKeyService: Retrieved salt from Firestore',
      );
      final saltBytes = await _driveAdapter.getFile(saltFileId);
      final saltJson = jsonDecode(bytesToString(saltBytes));
      salt = base64ToUint8Array(saltJson['salt']);
    }

    final kek = await _cryptoService.deriveKey(password, salt);

    // PRIORITY 1: Try to get wrapped keys from Firestore
    String? wrappedKeysFileId =
        await _findFileInFirestore(configPath, _wrappedKeysFile);

    if (wrappedKeysFileId == null) {
      KragLogger.info(
        LogDomain.crypto,
        'VaultKeyService: Wrapped_keys document missing in Firestore, generating new DMK',
      );
      final newDmk = await _cryptoService.generateDMK();
      final wrapResult = await _cryptoService.wrapDMK(kek, newDmk);

      await _driveAdapter.ensureFile(
        _wrappedKeysFile,
        stringToBytes(jsonEncode({
          'iv': uint8ArrayToBase64(wrapResult['iv']),
          'wrappedKey': wrapResult['wrappedKey'],
        })),
        'application/json',
        configPath,
      );

      return {
        'salt': salt,
        'kek': kek,
        'dmk': newDmk,
        'wrappedKeysTimestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }

    KragLogger.info(
      LogDomain.crypto,
      'VaultKeyService: Retrieved wrapped keys from Firestore',
    );

    final metadata = await _driveAdapter.getFileMetadata(wrappedKeysFileId);
    final wrappedKeysTimestamp =
        DateTime.parse(metadata.modifiedTime).millisecondsSinceEpoch;

    final wrappedKeysBytes = await _driveAdapter.getFile(wrappedKeysFileId);
    final wrappedKeysJson = jsonDecode(bytesToString(wrappedKeysBytes));

    final iv = base64ToUint8Array(wrappedKeysJson['iv']);
    final dmk = await _cryptoService.unwrapDMK(
      kek,
      iv,
      wrappedKeysJson['wrappedKey'],
    );

    return {
      'salt': salt,
      'kek': kek,
      'dmk': dmk,
      'wrappedKeysTimestamp': wrappedKeysTimestamp,
    };
  }

  @override
  Future<Uint8List?> getSalt() async {
    try {
      final configPath = await _ensureConfigFolder();

      // PRIORITY 1: Try Firestore first
      final saltFileId = await _findFileInFirestore(configPath, _saltFile);

      if (saltFileId == null) {
        KragLogger.info(
          LogDomain.crypto,
          'VaultKeyService: Salt not found in Firestore',
        );
        return null;
      }

      final saltBytes = await _driveAdapter.getFile(saltFileId);
      final saltJson = jsonDecode(bytesToString(saltBytes));

      KragLogger.info(
        LogDomain.crypto,
        'VaultKeyService: Salt retrieved from Firestore',
      );

      return base64ToUint8Array(saltJson['salt']);
    } catch (e) {
      KragLogger.warn(
        LogDomain.crypto,
        'VaultKeyService: Error retrieving salt: $e',
      );
      return null;
    }
  }

  /// FIXED: Use correct path from constants
  Future<String> _ensureConfigFolder() async {
    return constants.FolderPaths.config; // Returns 'krag-vault/config'
  }

  /// Helper to find files in Firestore
  Future<String?> _findFileInFirestore(
    String folderId,
    String fileName,
  ) async {
    try {
      final files = await _driveAdapter.listFiles(folderId);
      final matching = files.where((f) => f.name == fileName).toList();

      if (matching.isEmpty) return null;

      // Return most recent if multiple exist
      matching.sort((a, b) => DateTime.parse(b.modifiedTime)
          .compareTo(DateTime.parse(a.modifiedTime)));

      return matching.first.id;
    } catch (e) {
      KragLogger.warn(
        LogDomain.crypto,
        'VaultKeyService: Error finding file $fileName in Firestore: $e',
      );
      return null;
    }
  }
}
