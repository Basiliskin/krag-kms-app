import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'package:krag_app/constants/index.dart' as constants;
import '../types/index.dart';
import '../utils/encoding.dart';
import '../utils/logger.dart';
import 'interfaces.dart';

class IndexManager implements IIndexManager {
  final IDriveAdapter _driveAdapter;
  final ICryptoService _cryptoService;
  SecretKey? _dataMasterKey;

  static const String _indexFileName = 'index.json';
  static const String _localIndexKey = 'krag_cached_index';
  static const String _localIndexMetaKey = 'krag_cached_index_meta';
  static const int _indexCacheTtlMs = 5 * 60 * 1000;

  IndexManager(this._driveAdapter, this._cryptoService);

  @override
  void initialize(SecretKey dataMasterKey) {
    _dataMasterKey = dataMasterKey;
    KragLogger.info(
      LogDomain.sync,
      'IndexManager initialized with Firestore-backed strategy',
    );
  }

  @override
  Future<List<dynamic>> loadIndex({
    bool checkMismatch = true,
    bool forceRemote = false,
  }) async {
    KragLogger.info(LogDomain.sync, 'Loading index(forceRemote:$forceRemote)');
    List<dynamic> currentIndex = [];
    _IndexLoadResult? localResult;
    _IndexLoadResult? remoteResult;

    if (!forceRemote) {
      localResult = await _loadLocalIndex();
      if (localResult != null) {
        final isFresh = _isCacheFresh(localResult.metadata);
        if (isFresh) {
          currentIndex = localResult.index;
          KragLogger.info(
            LogDomain.sync,
            'Using fresh local cache(${currentIndex.length}entries)',
          );
          if (checkMismatch && currentIndex.isNotEmpty) {
            _performMismatchCheck(currentIndex);
          }
          return currentIndex;
        }
        KragLogger.info(
            LogDomain.sync, 'Local cache stale,attempting remote fetch');
      }
    }

    remoteResult = await _loadRemoteIndex();
    if (remoteResult != null) {
      currentIndex = remoteResult.index;
      await _forceUpdateLocalCache(
          remoteResult.encrypted, remoteResult.metadata);
      KragLogger.info(
        LogDomain.sync,
        'Remote index loaded(${currentIndex.length}entries)',
      );
    } else if (localResult != null) {
      currentIndex = localResult.index;
      KragLogger.warn(
        LogDomain.sync,
        'Remote fetch failed,falling back to stale local cache',
      );
    } else {
      KragLogger.error(
        LogDomain.sync,
        'Failed to load index from both remote and local sources',
      );
      currentIndex = [];
    }

    if (checkMismatch && currentIndex.isNotEmpty) {
      await _performMismatchCheck(currentIndex);
    }
    return currentIndex;
  }

  @override
  Future<void> saveIndex(List<dynamic> index) async {
    KragLogger.info(LogDomain.sync, 'Saving index with ${index.length}entries');
    final encryptedData = await _encryptData(index);
    await _driveAdapter.ensureFile(
      _indexFileName,
      encryptedData,
      'application/json',
      constants.FolderPaths.config,
    );
    final metadata = {
      'size': encryptedData.length,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'entryCount': index.length,
    };
    await _forceUpdateLocalCache(encryptedData, metadata);
    KragLogger.info(
      LogDomain.sync,
      'Index saved successfully to Firestore and local cache',
    );
  }

  @override
  Future<void> updateIndexEntry(Note note, {String? driveId}) async {
    final index = await loadIndex(checkMismatch: false, forceRemote: false);
    final entry = {
      'id': note.id,
      'title': note.title,
      'tags': note.tags,
      'labels': note.labels,
      'modifiedTime': note.modifiedTime,
      'parentId': note.parentId,
      '_v': note.v,
    };
    final existingIndex = index.indexWhere((i) => i['id'] == note.id);
    if (existingIndex >= 0) {
      if (driveId == null && index[existingIndex]['driveId'] != null) {
        entry['driveId'] = index[existingIndex]['driveId'];
      } else if (driveId != null) {
        entry['driveId'] = driveId;
      }
      index[existingIndex] = entry;
    } else {
      if (driveId != null) entry['driveId'] = driveId;
      index.add(entry);
    }
    await saveIndex(index);
  }

  @override
  Future<void> removeIndexEntry(String noteId) async {
    final index = await loadIndex(checkMismatch: false, forceRemote: false);
    final initialLength = index.length;
    index.removeWhere((i) => i['id'] == noteId);
    if (index.length != initialLength) {
      KragLogger.info(LogDomain.sync, 'Removing note $noteId from index');
      await saveIndex(index);
    }
  }

  @override
  Future<List<dynamic>> rebuildIndex() async {
    KragLogger.info(
      LogDomain.sync,
      'Rebuilding index from Firestore documents...',
    );
    final newIndex = <Map<String, dynamic>>[];
    try {
      final files = await _driveAdapter.listFiles(
        constants.FolderPaths.docs,
        useCache: false,
      );
      final noteFiles = files
          .where((f) => f.name.endsWith('.bin') || !f.name.contains('.'))
          .toList();
      for (final file in noteFiles) {
        try {
          final fileData = await _driveAdapter.getFile(file.id);
          if (fileData.isEmpty) continue;
          final noteMap = await _decryptData<Map<String, dynamic>>(fileData);
          final note = Note.fromJson(noteMap);
          newIndex.add({
            'id': note.id,
            'title': note.title,
            'tags': note.tags,
            'labels': note.labels,
            'modifiedTime': note.modifiedTime,
            'parentId': note.parentId,
            '_v': note.v,
            'driveId': file.id,
          });
        } catch (e) {
          KragLogger.warn(
            LogDomain.sync,
            'Failed to recover note from document ${file.id}:$e',
          );
        }
      }
      await saveIndex(newIndex);
      return newIndex;
    } catch (e, stack) {
      KragLogger.error(LogDomain.sync, 'Failed to rebuild index', e, stack);
      return [];
    }
  }

  @override
  Future<List<dynamic>> reconcileIndex(
    List<dynamic> currentIndex,
    List<DriveFileMetadata> physicalFiles,
  ) async {
    KragLogger.info(LogDomain.sync, 'Starting index reconciliation...');
    try {
      final (prunedIndex, ghostIds) = await pruneGhostEntries(
        currentIndex,
        physicalFiles,
      );
      bool changed = ghostIds.isNotEmpty;
      final indexMap = {
        for (var item in prunedIndex) item['id'] as String: item
      };
      for (final file in physicalFiles) {
        final noteId = file.name.replaceAll('.bin', '');
        final indexEntry = indexMap[noteId];
        bool fetchNeeded = false;
        if (indexEntry == null) {
          KragLogger.info(
            LogDomain.sync,
            'Reconcile:Found orphan document $noteId. Restoring.',
          );
          fetchNeeded = true;
        } else {
          final indexV = indexEntry['_v'] as int? ?? 0;
          final fileV = file.v ?? 0;
          if (fileV > indexV || indexEntry['driveId'] != file.id) {
            fetchNeeded = true;
          }
        }
        if (fetchNeeded) {
          try {
            final fileData = await _driveAdapter.getFile(file.id);
            final noteMap = await _decryptData<Map<String, dynamic>>(fileData);
            final note = Note.fromJson(noteMap);
            final entry = {
              'id': note.id,
              'title': note.title,
              'tags': note.tags,
              'labels': note.labels,
              'modifiedTime': note.modifiedTime,
              'parentId': note.parentId,
              '_v': note.v,
              'driveId': file.id,
            };
            final idx = prunedIndex.indexWhere((e) => e['id'] == noteId);
            if (idx != -1) {
              prunedIndex[idx] = entry;
            } else {
              prunedIndex.add(entry);
            }
            changed = true;
          } catch (e) {
            KragLogger.warn(
              LogDomain.sync,
              'Reconcile:Failed to process document $noteId:$e',
            );
          }
        }
      }
      if (changed) {
        await saveIndex(prunedIndex);
      }
      return prunedIndex;
    } catch (e, stack) {
      KragLogger.error(LogDomain.sync, 'Reconciliation failed', e, stack);
      return currentIndex;
    }
  }

  @override
  Future<(List<Map<String, dynamic>>, List<String>)> pruneGhostEntries(
    List<dynamic> currentIndex,
    List<DriveFileMetadata> physicalFiles,
  ) async {
    final prunedIndex = List<Map<String, dynamic>>.from(
      currentIndex.map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final physicalFileIds = {
      for (var file in physicalFiles) file.name.replaceAll('.bin', '')
    };
    final potentialGhosts = prunedIndex
        .where((entry) => !physicalFileIds.contains(entry['id']))
        .toList();
    final confirmedGhostIds = <String>[];
    for (final entry in potentialGhosts) {
      final noteId = entry['id'] as String;
      final driveId = entry['driveId'] as String?;
      if (driveId != null) {
        try {
          await _driveAdapter.getFileMetadata(driveId);
        } catch (e) {
          confirmedGhostIds.add(noteId);
        }
      } else {
        confirmedGhostIds.add(noteId);
      }
    }
    if (confirmedGhostIds.isNotEmpty) {
      if (currentIndex.length > 5 &&
          confirmedGhostIds.length / currentIndex.length > 0.5) {
        KragLogger.error(
          LogDomain.sync,
          'Mass ghost detection triggered. Aborting pruning.',
        );
        throw Exception('Safety Guard:Mass ghost detection triggered.');
      }
      for (final id in confirmedGhostIds) {
        prunedIndex.removeWhere((e) => e['id'] == id);
      }
    }
    return (prunedIndex, confirmedGhostIds);
  }

  @override
  Map<String, dynamic>? getIndexEntry(List<dynamic> index, String noteId) {
    try {
      return index.firstWhere(
        (entry) => entry['id'] == noteId,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localIndexKey);
    await prefs.remove(_localIndexMetaKey);
    KragLogger.info(LogDomain.sync, 'IndexManager: Local cache cleared');
  }

  Future<_IndexLoadResult?> _loadRemoteIndex() async {
    try {
      final files = await _driveAdapter.listFiles(constants.FolderPaths.config);
      final indexFile =
          files.where((f) => f.name == _indexFileName).firstOrNull;
      if (indexFile == null) return null;
      final encryptedData = await _driveAdapter.getFile(indexFile.id);
      if (encryptedData.isEmpty) return null;
      final index = await _decryptData<List<dynamic>>(encryptedData);
      final metadata = {
        'driveId': indexFile.id,
        'modifiedTime': indexFile.modifiedTime,
        'size': encryptedData.length,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      return _IndexLoadResult(
        index: index.cast<Map<String, dynamic>>(),
        encrypted: encryptedData,
        metadata: metadata,
      );
    } catch (e, stack) {
      KragLogger.error(LogDomain.sync, 'Failed to load remote index', e, stack);
      return null;
    }
  }

  Future<_IndexLoadResult?> _loadLocalIndex() async {
    try {
      final encryptedData = await _loadCachedData(_localIndexKey);
      if (encryptedData == null || encryptedData.isEmpty) return null;
      final metaDataBytes = await _loadCachedData(_localIndexMetaKey);
      Map<String, dynamic> metadata = {};
      if (metaDataBytes != null) {
        metadata =
            jsonDecode(bytesToString(metaDataBytes)) as Map<String, dynamic>;
      }
      final index = await _decryptData<List<dynamic>>(encryptedData);
      return _IndexLoadResult(
        index: index.cast<Map<String, dynamic>>(),
        encrypted: encryptedData,
        metadata: metadata,
      );
    } catch (e) {
      KragLogger.warn(LogDomain.sync, 'Failed to load local index cache:$e');
      return null;
    }
  }

  Future<void> _forceUpdateLocalCache(
    Uint8List encryptedData,
    Map<String, dynamic> metadata,
  ) async {
    await _cacheData(_localIndexKey, encryptedData);
    await _cacheData(_localIndexMetaKey, stringToBytes(jsonEncode(metadata)));
  }

  bool _isCacheFresh(Map<String, dynamic> metadata) {
    final timestamp = metadata['timestamp'] as int?;
    if (timestamp == null) return false;
    return DateTime.now().millisecondsSinceEpoch - timestamp < _indexCacheTtlMs;
  }

  Future<void> _performMismatchCheck(List<dynamic> currentIndex) async {
    try {
      KragLogger.info(
        LogDomain.sync,
        '[_performMismatchCheck] : $currentIndex',
      );
      final docFiles = await _driveAdapter.listFiles(
        constants.FolderPaths.docs,
        useCache: false,
      );
      final noteFiles = docFiles
          .where((f) => f.name.endsWith('.bin') || !f.name.contains('.'))
          .toList();
      if (noteFiles.length != currentIndex.length) {
        KragLogger.warn(
            LogDomain.sync, 'Index mismatch detected. Reconciling...');
        await reconcileIndex(currentIndex, noteFiles);
      }
    } catch (e) {
      KragLogger.error(LogDomain.sync, 'Mismatch check failed', e);
    }
  }

  Future<Uint8List> _encryptData(dynamic data) async {
    if (_dataMasterKey == null) throw Exception('Data master key not set');
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
    if (_dataMasterKey == null) throw Exception('Data master key not set');
    if (data.length < 12) throw Exception('Data too short');
    final iv = data.sublist(0, 12);
    final encrypted = data.sublist(12);
    var decryptedBytes = await _cryptoService.decryptBinary(
      _dataMasterKey!,
      iv,
      encrypted,
    );
    if (decryptedBytes.length > 2 &&
        decryptedBytes[0] == 0x1F &&
        decryptedBytes[1] == 0x8B) {
      decryptedBytes =
          Uint8List.fromList(GZipDecoder().decodeBytes(decryptedBytes));
    }
    return jsonDecode(bytesToString(decryptedBytes)) as T;
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

class _IndexLoadResult {
  final List<Map<String, dynamic>> index;
  final Uint8List encrypted;
  final Map<String, dynamic> metadata;
  _IndexLoadResult({
    required this.index,
    required this.encrypted,
    required this.metadata,
  });
}
