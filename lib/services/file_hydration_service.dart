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

class FileHydrationService implements IFileHydrationService {
  final IDriveAdapter _driveAdapter;
  final ICryptoService _cryptoService;
  final IIndexManager _indexManager;
  SecretKey? _dataMasterKey;

  static const String _localNotePrefix = 'krag_cached_note_';
  static const String _localVersionPrefix = 'krag_cached_version_';

  FileHydrationService(
    this._driveAdapter,
    this._cryptoService,
    this._indexManager,
  );

  void initialize(SecretKey dataMasterKey) {
    _dataMasterKey = dataMasterKey;
    KragLogger.info(LogDomain.sync, 'FileHydrationService initialized');
  }

  @override
  Future<HydrationCheckResult> checkNeedHydration(
    String noteId,
    Map<String, dynamic> indexEntry,
  ) async {
    final indexVersion = indexEntry['_v'] as int? ?? 0;
    final hasCache = await hasLocalCache(noteId);

    if (!hasCache) {
      KragLogger.info(
          LogDomain.sync, 'Hydration check: Note $noteId missing from cache.');
      return HydrationCheckResult(
        noteId: noteId,
        needsHydration: true,
        reason: HydrationReason.missingFromCache,
        indexVersion: indexVersion,
      );
    }

    final localVersion = await _getLocalVersion(noteId);
    if (localVersion == null || indexVersion > localVersion) {
      KragLogger.info(
        LogDomain.sync,
        'Hydration check: Note $noteId version mismatch. Local: $localVersion, Index: $indexVersion',
      );
      return HydrationCheckResult(
        noteId: noteId,
        needsHydration: true,
        reason: localVersion == null
            ? HydrationReason.missingFromCache
            : HydrationReason.versionMismatch,
        localVersion: localVersion,
        indexVersion: indexVersion,
      );
    }

    try {
      final cachedData = await getCachedData(noteId);
      if (cachedData == null || cachedData.isEmpty) {
        return HydrationCheckResult(
          noteId: noteId,
          needsHydration: true,
          reason: HydrationReason.emptyContent,
          localVersion: localVersion,
          indexVersion: indexVersion,
        );
      }
      await _decryptData<Map<String, dynamic>>(cachedData);
    } catch (e) {
      KragLogger.warn(
          LogDomain.sync, 'Hydration check: Note $noteId cache corrupted: $e');
      return HydrationCheckResult(
        noteId: noteId,
        needsHydration: true,
        reason: HydrationReason.corruptedCache,
        localVersion: localVersion,
        indexVersion: indexVersion,
      );
    }

    return HydrationCheckResult(
      noteId: noteId,
      needsHydration: false,
      localVersion: localVersion,
      indexVersion: indexVersion,
    );
  }

  @override
  Future<Note?> hydrateNote(
      String noteId, Map<String, dynamic> indexEntry) async {
    KragLogger.info(LogDomain.sync, 'Hydrating note:$noteId');
    Uint8List? fileData;
    DriveFileMetadata? metadata;
    String? driveId = indexEntry['driveId'] as String?;
    try {
      if (driveId != null) {
        fileData = await _driveAdapter.getFile(driveId);
        metadata = await _driveAdapter.getFileMetadata(driveId);
      }
    } catch (e) {
      KragLogger.warn(
          LogDomain.sync, 'Hydration via driveId failed for $noteId:$e');
    }
    if (fileData == null || fileData.isEmpty) {
      try {
        final fileName = '$noteId.bin';
        final files = await _driveAdapter.listFiles(
          constants.FolderPaths.docs,
          useCache: false,
        );
        final match = files.where((f) => f.name == fileName).firstOrNull;
        if (match != null) {
          fileData = await _driveAdapter.getFile(match.id);
          metadata = match;
        }
      } catch (e) {
        KragLogger.error(
          LogDomain.sync,
          'Hydration fallback search failed for $noteId',
          e,
        );
      }
    }
    if (fileData == null || fileData.isEmpty) return null;
    try {
      final noteMap = await _decryptData<Map<String, dynamic>>(fileData);
      final note = Note.fromJson(noteMap);
      final hydratedNote = note.copyWith(
        modifiedTime: metadata?.modifiedTime ?? note.modifiedTime,
        v: metadata?.v ?? note.v,
      );
      await _cacheNoteData(noteId, fileData, hydratedNote.v ?? 0);
      return hydratedNote;
    } catch (e) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to decrypt hydrated note $noteId',
        e,
      );
      return null;
    }
  }

  @override
  Future<Map<String, Note?>> hydrateNotes(
    List<String> noteIds,
    List<dynamic> index,
  ) async {
    final results = <String, Note?>{};
    for (final id in noteIds) {
      final entry = _indexManager.getIndexEntry(index, id);
      if (entry != null) {
        results[id] = await hydrateNote(id, entry);
      }
    }
    return results;
  }

  @override
  Future<List<String>> verifyAndHydrateAll(List<dynamic> index) async {
    final hydratedIds = <String>[];
    for (final entry in index) {
      final noteId = entry['id'] as String;
      final check =
          await checkNeedHydration(noteId, entry as Map<String, dynamic>);
      if (check.needsHydration) {
        final note = await hydrateNote(noteId, entry);
        if (note != null) hydratedIds.add(noteId);
      }
    }
    return hydratedIds;
  }

  @override
  Future<bool> hasLocalCache(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_localNotePrefix$noteId');
  }

  @override
  Future<Uint8List?> getCachedData(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final base64 = prefs.getString('$_localNotePrefix$noteId');
    return base64 != null ? base64ToUint8Array(base64) : null;
  }

  @override
  Future<void> clearCache(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_localNotePrefix$noteId');
    await prefs.remove('$_localVersionPrefix$noteId');
  }

  Future<int?> _getLocalVersion(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_localVersionPrefix$noteId');
  }

  Future<void> _cacheNoteData(
      String noteId, Uint8List data, int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_localNotePrefix$noteId', uint8ArrayToBase64(data));
    await prefs.setInt('$_localVersionPrefix$noteId', version);
  }

  Future<T> _decryptData<T>(Uint8List data) async {
    if (_dataMasterKey == null) throw Exception('Key not set');
    final iv = data.sublist(0, 12);
    final encrypted = data.sublist(12);
    final decrypted = await _cryptoService.decryptBinary(
      _dataMasterKey!,
      iv,
      encrypted,
    );
    return jsonDecode(bytesToString(decrypted)) as T;
  }
}
