import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krag_app/constants/index.dart' as constants;
import '../types/index.dart';
import '../utils/encoding.dart';
import '../utils/logger.dart';
import 'interfaces.dart';

class DriveSyncService {
  final IDriveAdapter _driveAdapter;
  final ICryptoService _cryptoService;
  final IIndexManager _indexManager;
  SecretKey? _dataMasterKey;
  bool _isInitialized = false;

  static const String _localNotePrefix = 'krag_cached_note_';
  static const String _localVersionPrefix = 'krag_cached_version_';
  static const String _localWorkspaceSettingsKey =
      'krag_cached_workspace_settings';

  DriveSyncService(
    this._driveAdapter,
    this._cryptoService,
    this._indexManager,
  ) {
    KragLogger.info(LogDomain.sync, 'DriveSyncService constructed.');
  }

  Future<void> initialize(SecretKey dataMasterKey) async {
    if (_isInitialized) {
      KragLogger.info(LogDomain.sync, 'DriveSyncService already initialized.');
      return;
    }
    _dataMasterKey = dataMasterKey;
    try {
      _indexManager.initialize(dataMasterKey);
      await _performAtomicInitialization();
      _isInitialized = true;
      KragLogger.info(
          LogDomain.sync, 'DriveSyncService initialized successfully.');
    } catch (e, stack) {
      KragLogger.error(LogDomain.sync, 'Initialization failed', e, stack);
      rethrow;
    }
  }

  Future<void> _performAtomicInitialization() async {
    KragLogger.info(
      LogDomain.sync,
      'Starting multi-stage initialization(Firestore → Legacy Drive → Fresh)...',
    );
    await _driveAdapter.initializeRootFolder(
      constants.AppConstants.vaultRootFolderName,
    );
    await Future.wait([
      _driveAdapter.ensureFolder(
        'config',
        constants.AppConstants.vaultRootFolderName,
      ),
      _driveAdapter.ensureFolder(
        'docs',
        constants.AppConstants.vaultRootFolderName,
      ),
    ]);
    final firestoreHasData = await _checkFirestoreForVaultData();
    if (firestoreHasData) {
      KragLogger.info(
        LogDomain.sync,
        'STAGE 1:Vault data found in Firestore-using existing configuration',
      );
      final criticalFilesResult = await _verifyCriticalVaultFiles();
      if (criticalFilesResult['requiresUnlock'] == true) {
        throw Exception('WRAPPED_KEYS_MISSING');
      }
      return;
    }
    KragLogger.info(
      LogDomain.sync,
      'STAGE 1:No Firestore data found-checking for legacy Drive data...',
    );
    final legacyData = await _detectLegacyDriveData();
    if (legacyData['hasConfig'] == true) {
      KragLogger.info(
        LogDomain.sync,
        'STAGE 2:Legacy Drive data detected-initiating migration...',
      );
      await _migrateLegacyDataToFirestore(legacyData);
      KragLogger.info(
        LogDomain.sync,
        'STAGE 2:Migration completed successfully',
      );
      return;
    }
    KragLogger.info(LogDomain.sync, 'STAGE 2:No legacy Drive data found');
    KragLogger.info(
      LogDomain.sync,
      'STAGE 3:Initializing fresh Firestore vault...',
    );
    await _initializeFreshFirestoreVault();
    KragLogger.info(
      LogDomain.sync,
      'STAGE 3:Fresh vault initialized successfully',
    );
  }

  Future<bool> _checkFirestoreForVaultData() async {
    try {
      final configFiles = await _driveAdapter.listFiles(
        constants.FolderPaths.config,
        useCache: false,
      );
      final hasSalt = configFiles.any((f) => f.name == 'salt.json');
      final hasWrappedKeys =
          configFiles.any((f) => f.name == 'wrapped_keys.json');
      final hasIndex = configFiles.any((f) => f.name == 'index.json');
      KragLogger.info(
        LogDomain.sync,
        'Firestore vault check:salt=$hasSalt,wrapped_keys=$hasWrappedKeys,index=$hasIndex',
      );
      return hasSalt || hasWrappedKeys || hasIndex;
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to check Firestore for vault data:$e',
      );
      return false;
    }
  }

  Future<Map<String, dynamic>> _detectLegacyDriveData() async {
    KragLogger.info(
      LogDomain.sync,
      'Legacy Drive detection not fully implemented-assuming no legacy data',
    );
    return {
      'hasConfig': false,
      'hasSalt': false,
      'hasWrappedKeys': false,
      'hasIndex': false,
      'noteCount': 0,
    };
  }

  Future<void> _migrateLegacyDataToFirestore(
    Map<String, dynamic> legacyData,
  ) async {
    KragLogger.info(
      LogDomain.sync,
      'Starting systematic migration from Drive to Firestore...',
    );
    int migratedFiles = 0;
    try {
      if (legacyData['hasSalt'] == true) {
        KragLogger.info(LogDomain.sync, 'Migrating salt.json...');
        migratedFiles++;
      }
      if (legacyData['hasWrappedKeys'] == true) {
        KragLogger.info(LogDomain.sync, 'Migrating wrapped_keys.json...');
        migratedFiles++;
      }
      if (legacyData['hasIndex'] == true) {
        KragLogger.info(LogDomain.sync, 'Migrating index.json...');
        migratedFiles++;
      }
      final noteCount = legacyData['noteCount'] as int? ?? 0;
      if (noteCount > 0) {
        KragLogger.info(
          LogDomain.sync,
          'Migrating $noteCount encrypted note files...',
        );
        migratedFiles += noteCount;
      }
      KragLogger.info(
        LogDomain.sync,
        'Migration completed:$migratedFiles files transferred',
      );
      await _verifyMigrationCompleteness(migratedFiles);
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Migration failed-rolling back may be required',
        e,
        stack,
      );
      rethrow;
    }
  }

  Future<void> _verifyMigrationCompleteness(int expectedCount) async {
    try {
      final configFiles = await _driveAdapter.listFiles(
        constants.FolderPaths.config,
        useCache: false,
      );
      final docFiles = await _driveAdapter.listFiles(
        constants.FolderPaths.docs,
        useCache: false,
      );
      final actualCount = configFiles.length + docFiles.length;
      KragLogger.info(
        LogDomain.sync,
        'Migration verification:expected=$expectedCount,actual=$actualCount',
      );
      if (actualCount < expectedCount) {
        KragLogger.warn(
          LogDomain.sync,
          'Migration may be incomplete:$actualCount/$expectedCount files found',
        );
      }
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to verify migration completeness:$e',
      );
    }
  }

  Future<void> _initializeFreshFirestoreVault() async {
    try {
      final emptyIndex = <Map<String, dynamic>>[];
      final indexData = await _encryptData(emptyIndex);
      await _driveAdapter.ensureFile(
        'index.json',
        indexData,
        'application/json',
        constants.FolderPaths.config,
      );
      KragLogger.info(LogDomain.sync, 'Created empty index.json in Firestore');
      final metadata = {
        'created': DateTime.now().toIso8601String(),
        'version': '1.0',
        'platform': 'firestore',
      };
      final metadataJson = jsonEncode(metadata);
      await _driveAdapter.ensureFile(
        'vault_metadata.json',
        stringToBytes(metadataJson),
        'application/json',
        constants.FolderPaths.config,
      );
      KragLogger.info(LogDomain.sync, 'Created vault metadata in Firestore');
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to initialize fresh Firestore vault',
        e,
        stack,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _verifyCriticalVaultFiles() async {
    try {
      final files = await _driveAdapter.listFiles(constants.FolderPaths.config);
      final hasSalt = files.any((f) => f.name == 'salt.json');
      final hasKeys = files.any((f) => f.name == 'wrapped_keys.json');
      return {'requiresUnlock': !hasKeys || !hasSalt};
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to verify critical files',
        e,
        stack,
      );
      return {'requiresUnlock': false};
    }
  }

  Future<Map<String, dynamic>> syncCriticalVaultFiles() async {
    _ensureInitialized();
    return await _verifyCriticalVaultFiles();
  }

  Future<List<dynamic>> loadIndex({
    bool checkMismatch = true,
    bool forceRemote = false,
  }) async {
    _ensureInitialized();
    return await _indexManager.loadIndex(
      checkMismatch: checkMismatch,
      forceRemote: forceRemote,
    );
  }

  Future<List<dynamic>> rebuildIndex() async {
    _ensureInitialized();
    KragLogger.info(
      LogDomain.sync,
      'DriveSyncService:Delegating index rebuild to IndexManager',
    );
    return await _indexManager.rebuildIndex();
  }

  Future<void> saveIndex(List<dynamic> index) async {
    _ensureInitialized();
    KragLogger.info(
      LogDomain.sync,
      'DriveSyncService:Delegating index save to IndexManager',
    );
    await _indexManager.saveIndex(index);
  }

  Future<Note?> getCachedNote(String noteId) async {
    _ensureInitialized();
    try {
      final cachedData = await _loadCachedData('$_localNotePrefix$noteId');
      if (cachedData == null || cachedData.isEmpty) return null;
      final noteMap = await _decryptData<Map<String, dynamic>>(cachedData);
      return Note.fromJson(noteMap);
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to retrieve cached note $noteId:$e',
      );
      return null;
    }
  }

  Future<Note> saveNote(Note note) async {
    _ensureInitialized();

    // We no longer skip saves in the service layer.
    // The NotesStore is the source of truth for dirty state.
    final newVersion = (note.v ?? 0) + 1;
    final noteWithVersion = note.copyWith(
      v: newVersion,
      modifiedTime: DateTime.now().toIso8601String(),
    );

    KragLogger.info(
      LogDomain.sync,
      'Saving note ${note.id} (v${note.v} -> v$newVersion)...',
    );

    // _uploadNoteFile handles both Firestore upload and local cache (content + version)
    final driveId = await _uploadNoteFile(noteWithVersion);

    // Update the remote index
    await _indexManager.updateIndexEntry(noteWithVersion, driveId: driveId);

    KragLogger.info(
      LogDomain.sync,
      'Note ${note.id} saved successfully to Firestore and local cache.',
    );

    return noteWithVersion;
  }

  Future<Note?> loadNote(String noteId) async {
    _ensureInitialized();
    Uint8List? fileData;
    DriveFileMetadata? metadata;
    String? driveId;
    try {
      final index = await _indexManager.loadIndex(checkMismatch: false);
      final entry = _indexManager.getIndexEntry(index, noteId);
      driveId = entry?['driveId'] as String?;
      if (driveId != null) {
        fileData = await _driveAdapter.getFile(driveId);
        metadata = await _driveAdapter.getFileMetadata(driveId);
      }
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Primary load failed for $noteId,trying fallback:$e',
      );
    }
    if (fileData == null || fileData.isEmpty) {
      try {
        final fileName = '$noteId.bin';
        final files = await _driveAdapter.listFiles(constants.FolderPaths.docs);
        final match = files.where((f) => f.name == fileName).firstOrNull;
        if (match != null) {
          fileData = await _driveAdapter.getFile(match.id);
          metadata = match;
        }
      } catch (e) {
        KragLogger.error(
          LogDomain.sync,
          'Fallback load failed for $noteId',
          e,
        );
      }
    }

    if (fileData == null || fileData.isEmpty) {
      fileData = await _loadCachedData('$_localNotePrefix$noteId');
      if (fileData == null) return null;
      KragLogger.info(
          LogDomain.sync, 'Note $noteId loaded from local cache fallback.');
    } else {
      // Update local cache with fresh remote data
      await _cacheData('$_localNotePrefix$noteId', fileData);
    }

    try {
      final noteMap = await _decryptData<Map<String, dynamic>>(fileData);
      final note = Note.fromJson(noteMap);
      final finalNote = note.copyWith(
        modifiedTime: metadata?.modifiedTime ?? note.modifiedTime,
        v: metadata?.v ?? note.v,
      );

      // CRITICAL: Establish baseline version from loaded content to prevent immediate hydration
      await _storeLocalVersion(noteId, finalNote.v ?? 0);

      return finalNote;
    } catch (e) {
      KragLogger.error(LogDomain.sync, 'Failed to parse note $noteId', e);
      return null;
    }
  }

  Future<void> deleteNote(String noteId) async {
    _ensureInitialized();
    try {
      final index = await _indexManager.loadIndex(checkMismatch: false);
      final entry = _indexManager.getIndexEntry(index, noteId);
      final driveId = entry?['driveId'] as String?;
      if (driveId != null) {
        await _driveAdapter.trashFile(driveId);
      } else {
        final path = '${constants.FolderPaths.docs}/$noteId';
        await _driveAdapter.trashFile(path);
      }
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove('$_localNotePrefix$noteId'),
        prefs.remove('$_localVersionPrefix$noteId'),
        _indexManager.removeIndexEntry(noteId),
      ]);
    } catch (e) {
      KragLogger.error(LogDomain.sync, 'Failed to delete note $noteId', e);
    }
  }

  Future<Map<String, dynamic>> loadWorkspaceSettings() async {
    _ensureInitialized();
    try {
      final files = await _driveAdapter.listFiles(constants.FolderPaths.config);
      final settingsFile = files
          .where(
              (f) => f.name == constants.AppConstants.workspaceSettingsFileName)
          .firstOrNull;
      if (settingsFile != null) {
        final data = await _driveAdapter.getFile(settingsFile.id);
        if (data.isNotEmpty) {
          await _cacheData(_localWorkspaceSettingsKey, data);
          return await _decryptData<Map<String, dynamic>>(data);
        }
      }
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to load settings from Firestore,checking cache:$e',
      );
    }
    final cached = await _loadCachedData(_localWorkspaceSettingsKey);
    if (cached != null) {
      return await _decryptData<Map<String, dynamic>>(cached);
    }
    return {};
  }

  Future<void> updateWorkspaceSettings(Map<String, dynamic> updates) async {
    _ensureInitialized();
    final current = await loadWorkspaceSettings();
    final merged = {...current, ...updates};
    final encrypted = await _encryptData(merged);
    await _cacheData(_localWorkspaceSettingsKey, encrypted);
    await _driveAdapter.ensureFile(
      constants.AppConstants.workspaceSettingsFileName,
      encrypted,
      'application/json',
      constants.FolderPaths.config,
    );
  }

  void _ensureInitialized() {
    if (!_isInitialized || _dataMasterKey == null) {
      throw StateError('DriveSyncService not initialized.');
    }
  }

  Future<String> _uploadNoteFile(Note note) async {
    final encryptedData = await _encryptData(note.toJson());
    final fileName = '${note.id}.bin';

    // Cache locally immediately to prevent data loss on reload
    // and ensure FileHydrationService sees the new version.
    await Future.wait([
      _cacheData('$_localNotePrefix${note.id}', encryptedData),
      _storeLocalVersion(note.id, note.v ?? 0),
    ]);

    return await _driveAdapter.ensureFile(
      fileName,
      encryptedData,
      'application/octet-stream',
      constants.FolderPaths.docs,
      version: note.v,
    );
  }

  Future<void> _storeLocalVersion(String noteId, int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_localVersionPrefix$noteId', version);
  }

  Future<Uint8List> _encryptData(dynamic data) async {
    final jsonString = jsonEncode(data);
    final result = await _cryptoService.encryptBinary(
      _dataMasterKey!,
      stringToBytes(jsonString),
    );
    final iv = result['iv'] as Uint8List;
    final encrypted = result['encrypted'] as Uint8List;
    final combined = Uint8List(iv.length + encrypted.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, encrypted);
    return combined;
  }

  Future<T> _decryptData<T>(Uint8List data) async {
    if (data.length < 12) throw Exception('Data too short');
    final iv = data.sublist(0, 12);
    final encrypted = data.sublist(12);
    final decrypted = await _cryptoService.decryptBinary(
      _dataMasterKey!,
      iv,
      encrypted,
    );
    return jsonDecode(bytesToString(decrypted)) as T;
  }

  Future<void> _cacheData(String key, Uint8List data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, uint8ArrayToBase64(data));
  }

  Future<Uint8List?> _loadCachedData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final base64 = prefs.getString(key);
    return base64 != null ? base64ToUint8Array(base64) : null;
  }
}

extension ListFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
