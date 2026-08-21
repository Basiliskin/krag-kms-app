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

/// Manages orphan file reconciliation operations
///
/// Follows Single Responsibility Principle by handling only orphan detection and cleanup
/// Uses Dependency Injection for testability
///
/// Orphan Reconciliation Strategy:
/// 1. Identify local files not present in index
/// 2. Verify existence on Google Drive
/// 3. If exists on Drive: restore to index with metadata
/// 4. If not on Drive: delete from local cache
/// 5. Safety guards prevent mass deletion
class OrphanReconciliationService implements IOrphanReconciliationService {
  final IDriveAdapter _driveAdapter;
  final ICryptoService _cryptoService;
  final IIndexManager _indexManager;
  final IFileHydrationService _hydrationService;

  SecretKey? _dataMasterKey;

  static const String _localNotePrefix = 'krag_cached_note_';
  static const double _safetyThreshold =
      0.3; // Don't delete if >30% are orphans

  OrphanReconciliationService(
    this._driveAdapter,
    this._cryptoService,
    this._indexManager,
    this._hydrationService,
  );

  /// Initialize the orphan reconciliation service with encryption key
  void initialize(SecretKey dataMasterKey) {
    _dataMasterKey = dataMasterKey;
    KragLogger.info(LogDomain.sync, 'OrphanReconciliationService initialized');
  }

  @override
  Future<List<String>> findOrphanFiles(List<dynamic> index) async {
    KragLogger.info(
        LogDomain.sync, 'Searching for orphan files in local cache...');

    final indexIds = index.map((e) => e['id'] as String).toSet();
    final orphans = <String>[];

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_localNotePrefix)) {
          final noteId = key.substring(_localNotePrefix.length);

          // Check if this note ID is in the index
          if (!indexIds.contains(noteId)) {
            orphans.add(noteId);
            KragLogger.info(
              LogDomain.sync,
              'Orphan file detected: $noteId (in cache but not in index)',
            );
          }
        }
      }

      KragLogger.info(
        LogDomain.sync,
        'Found ${orphans.length} orphan files out of ${indexIds.length} indexed notes',
      );

      return orphans;
    } catch (e, stack) {
      KragLogger.error(
          LogDomain.sync, 'Failed to search for orphan files', e, stack);
      return [];
    }
  }

  @override
  Future<OrphanReconciliationResult> reconcileOrphan(
    String noteId,
    List<dynamic> index,
  ) async {
    KragLogger.info(LogDomain.sync, 'Reconciling orphan file: $noteId');

    final fileName = '$noteId.bin';

    // Step 1: Check if file exists on Drive
    try {
      final files = await _driveAdapter.listFiles(
        constants.FolderPaths.docs,
        useCache: false,
      );

      final driveFile = files.where((f) => f.name == fileName).firstOrNull;

      if (driveFile != null) {
        // File exists on Drive - restore to index
        KragLogger.info(
          LogDomain.sync,
          'Orphan $noteId found on Drive (${driveFile.id}). Restoring to index...',
        );

        return await _restoreOrphanToIndex(noteId, driveFile, index);
      } else {
        // File not on Drive - delete from local cache
        KragLogger.info(
          LogDomain.sync,
          'Orphan $noteId not found on Drive. Removing from local cache...',
        );

        return await _deleteOrphanFromCache(noteId);
      }
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Error reconciling orphan $noteId',
        e,
        stack,
      );

      return OrphanReconciliationResult(
        noteId: noteId,
        action: OrphanAction.error,
        reason: e.toString(),
      );
    }
  }

  @override
  Future<Map<String, OrphanReconciliationResult>> reconcileAllOrphans(
    List<dynamic> index,
  ) async {
    final orphans = await findOrphanFiles(index);
    final results = <String, OrphanReconciliationResult>{};

    if (orphans.isEmpty) {
      KragLogger.info(LogDomain.sync, 'No orphan files found');
      return results;
    }

    KragLogger.info(
      LogDomain.sync,
      'Reconciling ${orphans.length} orphan files...',
    );

    for (final noteId in orphans) {
      final result = await reconcileOrphan(noteId, index);
      results[noteId] = result;
    }

    return results;
  }

  @override
  Future<OrphanReconciliationSummary> performCleanup(
      List<dynamic> index) async {
    KragLogger.info(LogDomain.sync, 'Starting orphan cleanup cycle...');

    // Step 1: Find all orphans
    final orphans = await findOrphanFiles(index);

    if (orphans.isEmpty) {
      KragLogger.info(
          LogDomain.sync, 'No orphan files found. Cleanup not needed.');
      return OrphanReconciliationSummary(
        totalOrphans: 0,
        restored: 0,
        deleted: 0,
        skipped: 0,
        errors: 0,
        restoredIds: [],
        deletedIds: [],
      );
    }

    // Step 2: Safety guard - prevent mass deletion
    final orphanPercentage = orphans.length / (index.length + orphans.length);

    if (orphanPercentage > _safetyThreshold) {
      KragLogger.error(
        LogDomain.sync,
        'SAFETY GUARD TRIGGERED: ${orphans.length} orphans (${(orphanPercentage * 100).toStringAsFixed(1)}%) exceeds safety threshold (${(_safetyThreshold * 100).toStringAsFixed(1)}%). '
        'Aborting orphan cleanup to prevent potential data loss.',
      );

      return OrphanReconciliationSummary(
        totalOrphans: orphans.length,
        restored: 0,
        deleted: 0,
        skipped: orphans.length,
        errors: 0,
        restoredIds: [],
        deletedIds: [],
      );
    }

    // Step 3: Reconcile each orphan
    int restored = 0;
    int deleted = 0;
    int skipped = 0;
    int errors = 0;
    final restoredIds = <String>[];
    final deletedIds = <String>[];

    for (final noteId in orphans) {
      try {
        final result = await reconcileOrphan(noteId, index);

        switch (result.action) {
          case OrphanAction.restored:
            restored++;
            restoredIds.add(noteId);

            // Update index with restored note
            if (result.restoredNote != null && result.driveId != null) {
              await _indexManager.updateIndexEntry(
                result.restoredNote!,
                driveId: result.driveId,
              );
              KragLogger.info(
                LogDomain.sync,
                'Restored orphan $noteId to index with driveId ${result.driveId}',
              );
            }
            break;

          case OrphanAction.deleted:
            deleted++;
            deletedIds.add(noteId);
            break;

          case OrphanAction.skipped:
            skipped++;
            break;

          case OrphanAction.error:
            errors++;
            break;
        }
      } catch (e, stack) {
        KragLogger.error(
          LogDomain.sync,
          'Unexpected error reconciling orphan $noteId',
          e,
          stack,
        );
        errors++;
      }
    }

    final summary = OrphanReconciliationSummary(
      totalOrphans: orphans.length,
      restored: restored,
      deleted: deleted,
      skipped: skipped,
      errors: errors,
      restoredIds: restoredIds,
      deletedIds: deletedIds,
    );

    KragLogger.info(LogDomain.sync, 'Orphan cleanup completed: $summary');

    return summary;
  }

  // Private helper methods

  Future<OrphanReconciliationResult> _restoreOrphanToIndex(
    String noteId,
    DriveFileMetadata driveFile,
    List<dynamic> index,
  ) async {
    try {
      // Download and decrypt file to get full metadata
      final fileData = await _driveAdapter.getFile(driveFile.id);

      if (fileData.isEmpty) {
        KragLogger.warn(
            LogDomain.sync, 'Orphan $noteId file is empty on Drive');
        return OrphanReconciliationResult(
          noteId: noteId,
          action: OrphanAction.error,
          driveId: driveFile.id,
          reason: 'File is empty on Drive',
        );
      }

      final noteMap = await _decryptData<Map<String, dynamic>>(fileData);
      final note = Note.fromJson(noteMap);

      // Update note with Drive metadata
      final restoredNote = note.copyWith(
        modifiedTime: driveFile.modifiedTime,
        v: driveFile.v ?? note.v,
      );

      KragLogger.info(
        LogDomain.sync,
        'Successfully restored orphan $noteId (v${restoredNote.v}, driveId: ${driveFile.id})',
      );

      return OrphanReconciliationResult(
        noteId: noteId,
        action: OrphanAction.restored,
        driveId: driveFile.id,
        restoredNote: restoredNote,
      );
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to restore orphan $noteId',
        e,
        stack,
      );

      return OrphanReconciliationResult(
        noteId: noteId,
        action: OrphanAction.error,
        driveId: driveFile.id,
        reason: e.toString(),
      );
    }
  }

  Future<OrphanReconciliationResult> _deleteOrphanFromCache(
      String noteId) async {
    try {
      await _hydrationService.clearCache(noteId);

      KragLogger.info(
        LogDomain.sync,
        'Successfully deleted orphan $noteId from local cache',
      );

      return OrphanReconciliationResult(
        noteId: noteId,
        action: OrphanAction.deleted,
      );
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to delete orphan $noteId from cache',
        e,
        stack,
      );

      return OrphanReconciliationResult(
        noteId: noteId,
        action: OrphanAction.error,
        reason: e.toString(),
      );
    }
  }

  Future<T> _decryptData<T>(Uint8List data) async {
    if (_dataMasterKey == null) throw Exception('Data master key not set');
    if (data.length < 12) throw Exception('Data too short');

    try {
      final iv = data.sublist(0, 12);
      final encrypted = data.sublist(12);

      var decryptedBytes = await _cryptoService.decryptBinary(
        _dataMasterKey!,
        iv,
        encrypted,
      );

      // Handle GZIP compression
      if (decryptedBytes.length > 2 &&
          decryptedBytes[0] == 0x1F &&
          decryptedBytes[1] == 0x8B) {
        try {
          final decompressed = GZipDecoder().decodeBytes(decryptedBytes);
          decryptedBytes = Uint8List.fromList(decompressed);
        } catch (e) {
          KragLogger.warn(
            LogDomain.crypto,
            'Failed to decompress GZIP data, attempting raw decode: $e',
          );
        }
      }

      final jsonString = bytesToString(decryptedBytes);
      return jsonDecode(jsonString) as T;
    } catch (e, stack) {
      KragLogger.error(LogDomain.crypto, 'Decryption failed', e, stack);
      rethrow;
    }
  }
}

extension ListFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
