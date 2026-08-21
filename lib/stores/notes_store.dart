import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../types/index.dart';
import '../types/normalized.dart';
import 'providers.dart';
import 'package:krag_app/constants/index.dart' as constants;
import 'auth_store.dart';
import '../utils/logger.dart';
import '../utils/editor_migration_engine.dart';

const String _defaultCodeBlockContent =
    '''{"format":"nblock","version":1,"blocks":[{"id":"{{UUID}}","type":"code_block","data":{"language":"plaintext","content":""},"children":[]}]}''';

String _generateDefaultCodeBlockContent() {
  final uuid = const Uuid().v4();
  return _defaultCodeBlockContent.replaceAll('{{UUID}}', uuid);
}

void _validateContentStructure(String id, String content) {
  if (content.trim().isEmpty) {
    KragLogger.warn(
      LogDomain.sync,
      'Note $id content is empty-should contain at least a default code block',
    );
    return;
  }
  try {
    final parsed = jsonDecode(content);
    if (parsed is! Map) return;
    final hasFormat = parsed.containsKey('format');
    final hasVersion = parsed.containsKey('version');
    final hasBlocks = parsed.containsKey('blocks');
    if (hasFormat && hasVersion && hasBlocks) {
      return;
    }
    if (!hasFormat &&
        parsed.containsKey('schema') &&
        parsed['schema'] == 'appflowy') {
      KragLogger.warn(
        LogDomain.sync,
        'Note $id content uses raw AppFlowy format instead of normalized nblock format. '
        'This may cause sync/migration issues. Content should be normalized before save.',
      );
    } else if (!hasFormat &&
        parsed.containsKey('type') &&
        parsed['type'] == 'doc') {
      KragLogger.warn(
        LogDomain.sync,
        'Note $id content uses raw Tiptap format instead of normalized nblock format. '
        'Migration should have occurred before save.',
      );
    } else {
      KragLogger.warn(
        LogDomain.sync,
        'Note $id content has unexpected structure(format=$hasFormat,version=$hasVersion,blocks=$hasBlocks). '
        'Normalization metadata may have been stripped.',
      );
    }
  } catch (e) {
    KragLogger.warn(
      LogDomain.sync,
      'Note $id content validation failed(not valid JSON):$e',
    );
  }
}

class NotesStateData {
  final Map<String, Note> notes;
  final String currentNoteId;
  final bool isLoadingIndex;
  final bool isSyncing;
  final List<String> activeFilterTags;
  final List<String> activeFilterLabels;
  final String? error;
  final Map<String, int> ghostRetryCounts;
  final bool isHydrating;
  final int hydratedCount;
  final int totalToHydrate;
  final bool isReconciling;
  final int orphansFound;
  final int orphansRestored;
  final int orphansDeleted;
  final Set<String> skeletonNoteIds;
  final Set<String> dirtyNoteIds;
  const NotesStateData({
    this.notes = const {},
    this.currentNoteId = constants.AppConstants.defaultNoteId,
    this.isLoadingIndex = false,
    this.isSyncing = false,
    this.activeFilterTags = const [],
    this.activeFilterLabels = const [],
    this.error,
    this.ghostRetryCounts = const {},
    this.isHydrating = false,
    this.hydratedCount = 0,
    this.totalToHydrate = 0,
    this.isReconciling = false,
    this.orphansFound = 0,
    this.orphansRestored = 0,
    this.orphansDeleted = 0,
    this.skeletonNoteIds = const {},
    this.dirtyNoteIds = const {},
  });
  NotesStateData copyWith({
    Map<String, Note>? notes,
    String? currentNoteId,
    bool? isLoadingIndex,
    bool? isSyncing,
    List<String>? activeFilterTags,
    List<String>? activeFilterLabels,
    String? error,
    Map<String, int>? ghostRetryCounts,
    bool? isHydrating,
    int? hydratedCount,
    int? totalToHydrate,
    bool? isReconciling,
    int? orphansFound,
    int? orphansRestored,
    int? orphansDeleted,
    Set<String>? skeletonNoteIds,
    Set<String>? dirtyNoteIds,
  }) {
    return NotesStateData(
      notes: notes ?? this.notes,
      currentNoteId: currentNoteId ?? this.currentNoteId,
      isLoadingIndex: isLoadingIndex ?? this.isLoadingIndex,
      isSyncing: isSyncing ?? this.isSyncing,
      activeFilterTags: activeFilterTags ?? this.activeFilterTags,
      activeFilterLabels: activeFilterLabels ?? this.activeFilterLabels,
      error: error ?? this.error,
      ghostRetryCounts: ghostRetryCounts ?? this.ghostRetryCounts,
      isHydrating: isHydrating ?? this.isHydrating,
      hydratedCount: hydratedCount ?? this.hydratedCount,
      totalToHydrate: totalToHydrate ?? this.totalToHydrate,
      isReconciling: isReconciling ?? this.isReconciling,
      orphansFound: orphansFound ?? this.orphansFound,
      orphansRestored: orphansRestored ?? this.orphansRestored,
      orphansDeleted: orphansDeleted ?? this.orphansDeleted,
      skeletonNoteIds: skeletonNoteIds ?? this.skeletonNoteIds,
      dirtyNoteIds: dirtyNoteIds ?? this.dirtyNoteIds,
    );
  }
}

class NotesNotifier extends Notifier<NotesStateData> {
  bool _hasTriggeredInitialLoad = false;
  @override
  NotesStateData build() {
    final authState = ref.watch(authStoreProvider);
    final syncServiceAsync = ref.watch(driveSyncServiceProvider);
    if (authState.isAuthenticated) {
      syncServiceAsync.when(
        data: (service) {
          if (service != null &&
              state.notes.isEmpty &&
              !state.isLoadingIndex &&
              !_hasTriggeredInitialLoad) {
            _hasTriggeredInitialLoad = true;
            KragLogger.info(
              LogDomain.sync,
              'Triggering initial index load (forcing remote fetch)',
            );
            Future.microtask(() => loadIndex(forceRemote: true));
          } else if (_hasTriggeredInitialLoad && service != null) {
            KragLogger.info(
              LogDomain.sync,
              'Skipping redundant loadIndex trigger-guard flag already set',
            );
          }
        },
        loading: () {},
        error: (e, s) => KragLogger.error(
          LogDomain.sync,
          'Sync service provider error',
          e,
          s,
        ),
      );
    } else {
      if (_hasTriggeredInitialLoad) {
        KragLogger.info(
          LogDomain.sync,
          'User not authenticated-resetting initialization guard flag',
        );
        _hasTriggeredInitialLoad = false;
      }
    }
    return const NotesStateData();
  }

  void _markNoteDirty(String noteId) {
    final updatedDirtyIds = Set<String>.from(state.dirtyNoteIds);
    if (!updatedDirtyIds.contains(noteId)) {
      updatedDirtyIds.add(noteId);
      state = state.copyWith(dirtyNoteIds: updatedDirtyIds);
      KragLogger.info(
        LogDomain.sync,
        'Note $noteId marked as DIRTY. Total dirty notes:${updatedDirtyIds.length}',
      );
    }
  }

  void _clearNoteDirty(String noteId) {
    final updatedDirtyIds = Set<String>.from(state.dirtyNoteIds);
    if (updatedDirtyIds.contains(noteId)) {
      updatedDirtyIds.remove(noteId);
      state = state.copyWith(dirtyNoteIds: updatedDirtyIds);
      KragLogger.info(
        LogDomain.sync,
        'Note $noteId marked as CLEAN. Remaining dirty notes:${updatedDirtyIds.length}',
      );
    }
  }

  List<Note> getDirtyNotes() {
    return state.dirtyNoteIds
        .where((id) => state.notes.containsKey(id))
        .map((id) => state.notes[id]!)
        .toList();
  }

  Future<void> syncAllDirty() async {
    if (state.dirtyNoteIds.isEmpty) {
      KragLogger.info(
        LogDomain.sync,
        'No dirty notes to sync.',
      );
      return;
    }
    final dirtyIds = List<String>.from(state.dirtyNoteIds);
    KragLogger.info(
      LogDomain.sync,
      'Starting batch sync for ${dirtyIds.length}dirty notes:${dirtyIds.join(",")}',
    );
    state = state.copyWith(isSyncing: true);
    int successCount = 0;
    int failureCount = 0;
    try {
      for (final noteId in dirtyIds) {
        try {
          await saveNote(noteId);
          successCount++;
        } catch (e, stack) {
          failureCount++;
          KragLogger.error(
            LogDomain.sync,
            'Failed to sync dirty note $noteId during batch operation',
            e,
            stack,
          );
        }
      }
      KragLogger.info(
        LogDomain.sync,
        'Batch sync completed:$successCount succeeded,$failureCount failed',
      );
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  bool isNoteDirty(String noteId) {
    return state.dirtyNoteIds.contains(noteId);
  }

  Future<void> loadIndex(
      {bool showLoading = true, bool forceRemote = false}) async {
    final serviceAsync = ref.read(driveSyncServiceProvider);
    if (!serviceAsync.hasValue || serviceAsync.value == null) {
      KragLogger.warn(
        LogDomain.sync,
        'Cannot load index:Sync service not ready',
      );
      return;
    }
    final syncService = serviceAsync.value!;
    if (showLoading) {
      state = state.copyWith(isLoadingIndex: true);
    }
    KragLogger.info(
      LogDomain.sync,
      'Starting complete sync cycle:index load → local cache population → hydration → orphan reconciliation',
    );
    try {
      final indexEntries =
          await syncService.loadIndex(forceRemote: forceRemote);
      KragLogger.info(
        LogDomain.sync,
        'Raw index entries found:${indexEntries.length}',
      );
      final newNotes = <String, Note>{};
      final skeletonIds = <String>{};
      final versionDriftWarnings = <String>[];
      int cacheHits = 0;
      int cacheMisses = 0;
      for (var entry in indexEntries) {
        final id = entry['id'] as String;
        final version = entry['_v'] as int?;
        if (version == null || version < 0) {
          versionDriftWarnings.add(id);
          KragLogger.warn(
            LogDomain.sync,
            'Version drift detected for note $id:_v=$version(expected non-negative integer)',
          );
        }
        Note? cachedNote;
        try {
          cachedNote = await syncService.getCachedNote(id);
        } catch (e) {
          KragLogger.warn(
            LogDomain.sync,
            'Cache retrieval error for note $id:$e',
          );
        }
        if (cachedNote != null) {
          newNotes[id] = Note(
            id: id,
            title: cachedNote.title,
            content: cachedNote.content,
            tags: (entry['tags'] as List?)?.cast<String>() ?? [],
            labels: (entry['labels'] as List?)?.cast<String>() ?? [],
            modifiedTime: entry['modifiedTime'],
            parentId: entry['parentId'],
            v: version,
          );
          cacheHits++;
          KragLogger.info(
            LogDomain.sync,
            'Note $id loaded from cache(title:"${cachedNote.title}",content:${cachedNote.content.length}bytes)',
          );
        } else {
          newNotes[id] = Note(
            id: id,
            title: entry['title'] ?? 'Untitled',
            content: '',
            tags: (entry['tags'] as List?)?.cast<String>() ?? [],
            labels: (entry['labels'] as List?)?.cast<String>() ?? [],
            modifiedTime: entry['modifiedTime'],
            parentId: entry['parentId'],
            v: version,
          );
          skeletonIds.add(id);
          cacheMisses++;
          KragLogger.info(
            LogDomain.sync,
            'Note $id not in cache-marked as skeleton for hydration',
          );
        }
      }
      KragLogger.info(
        LogDomain.sync,
        'Local cache loading complete:$cacheHits hits,$cacheMisses misses out of ${indexEntries.length}total notes',
      );
      List<String> loadedTags = [];
      List<String> loadedLabels = [];
      String? loadedCurrentId;
      Map<String, dynamic> settings = {};
      try {
        settings = await syncService.loadWorkspaceSettings();
        if (settings.containsKey('activeFilterTags')) {
          loadedTags = List<String>.from(settings['activeFilterTags']);
        }
        if (settings.containsKey('activeFilterLabels')) {
          loadedLabels = List<String>.from(settings['activeFilterLabels']);
        }
        if (settings.containsKey('currentNoteId')) {
          loadedCurrentId = settings['currentNoteId'];
        }
        final prefs = await SharedPreferences.getInstance();
        if (loadedCurrentId != null) {
          await prefs.setString(
            constants.StorageKeys.currentNoteId,
            loadedCurrentId,
          );
        }
        await prefs.setString(
          constants.StorageKeys.noteFilters,
          jsonEncode({
            'tags': loadedTags,
            'labels': loadedLabels,
          }),
        );
      } catch (e) {
        KragLogger.warn(
          LogDomain.sync,
          'Failed to load workspace settings:$e',
        );
      }
      final actualCount = newNotes.length;
      if (settings.containsKey('noteCount')) {
        final expectedCount = settings['noteCount'] as int?;
        if (expectedCount != null && expectedCount != actualCount) {
          KragLogger.warn(
            LogDomain.sync,
            'Workspace settings count mismatch:expected $expectedCount,actual $actualCount. Triggering settings sync.',
          );
          Future.microtask(() {
            _syncWorkspaceSettingsWithActualCount(actualCount);
          });
        }
      } else {
        Future.microtask(() {
          _syncWorkspaceSettingsWithActualCount(actualCount);
        });
      }
      var currentId = loadedCurrentId ?? state.currentNoteId;
      if (newNotes.isNotEmpty && !newNotes.containsKey(currentId)) {
        currentId = newNotes.keys.first;
        KragLogger.info(
          LogDomain.general,
          'Current note ID updated to:$currentId',
        );
      }
      state = state.copyWith(
        notes: newNotes,
        currentNoteId: currentId,
        activeFilterTags: loadedTags,
        activeFilterLabels: loadedLabels,
        isLoadingIndex: false,
        isHydrating: skeletonIds.isNotEmpty,
        skeletonNoteIds: skeletonIds,
        dirtyNoteIds: const {},
        error: null,
      );
      KragLogger.info(
        LogDomain.sync,
        'State updated:${newNotes.length}notes loaded,${skeletonIds.length}in skeleton state,dirty flags cleared',
      );
      await _verifyAndHydrateNotes(indexEntries, newNotes);
      await _reconcileOrphanFiles(indexEntries);
      if (state.notes.isEmpty) {
        KragLogger.info(
          LogDomain.sync,
          'Index empty after sync,creating default note',
        );
        createNote();
      }
      KragLogger.info(
        LogDomain.sync,
        'Complete sync cycle finished successfully. Final note count:${state.notes.length},skeleton count:${state.skeletonNoteIds.length}',
      );
    } on Exception catch (e, stack) {
      final errorMessage = e.toString();
      KragLogger.error(
        LogDomain.sync,
        'Failed to load index',
        e,
        stack,
      );
      if (errorMessage.contains('Session expired')) {
        KragLogger.warn(
          LogDomain.auth,
          'Session expired detected during loadIndex. Triggering logout...',
        );
        await _handleSessionExpired();
      }
      state = state.copyWith(
        isLoadingIndex: false,
        isHydrating: false,
        error: errorMessage.contains('Session expired')
            ? 'Session expired. Please sign in again.'
            : null,
      );
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to load index',
        e,
        stack,
      );
      state = state.copyWith(
        isLoadingIndex: false,
        isHydrating: false,
      );
    }
  }

  Future<void> _verifyAndHydrateNotes(
    List<dynamic> indexEntries,
    Map<String, Note> currentNotes,
  ) async {
    final hydrationServiceAsync = ref.read(fileHydrationServiceProvider);
    if (!hydrationServiceAsync.hasValue ||
        hydrationServiceAsync.value == null) {
      KragLogger.warn(
        LogDomain.sync,
        'FileHydrationService not available. Clearing skeleton state without hydration.',
      );
      state = state.copyWith(
        skeletonNoteIds: const {},
        isHydrating: false,
      );
      return;
    }
    final hydrationService = hydrationServiceAsync.value!;
    KragLogger.info(
      LogDomain.sync,
      'Starting automatic verification and hydration for ${indexEntries.length}notes',
    );
    state = state.copyWith(
      isHydrating: true,
      hydratedCount: 0,
      totalToHydrate: 0,
    );
    try {
      final needsHydration = <String, Map<String, dynamic>>{};
      for (final entry in indexEntries) {
        final noteId = entry['id'] as String;
        final indexEntry = entry as Map<String, dynamic>;
        final checkResult = await hydrationService.checkNeedHydration(
          noteId,
          indexEntry,
        );
        if (checkResult.needsHydration) {
          needsHydration[noteId] = indexEntry;
          KragLogger.info(
            LogDomain.sync,
            'Note $noteId needs hydration:${checkResult.reason}'
            '(local:v${checkResult.localVersion},index:v${checkResult.indexVersion})',
          );
        }
      }
      if (needsHydration.isEmpty) {
        KragLogger.info(
          LogDomain.sync,
          'All ${indexEntries.length}notes are up-to-date. No hydration needed.',
        );
        state = state.copyWith(
          isHydrating: false,
          skeletonNoteIds: const {},
        );
        return;
      }
      KragLogger.info(
        LogDomain.sync,
        'Found ${needsHydration.length}/${indexEntries.length}notes requiring hydration',
      );
      state = state.copyWith(totalToHydrate: needsHydration.length);
      final batchSize = 10;
      final noteIds = needsHydration.keys.toList();
      int hydratedCount = 0;
      int failedCount = 0;
      int skippedDueToEquality = 0;
      for (var i = 0; i < noteIds.length; i += batchSize) {
        final end =
            (i + batchSize < noteIds.length) ? i + batchSize : noteIds.length;
        final batch = noteIds.sublist(i, end);
        KragLogger.info(
          LogDomain.sync,
          'Hydrating batch ${(i / batchSize).floor() + 1}:notes ${i + 1}-$end of ${noteIds.length}',
        );
        final index = indexEntries.cast<Map<String, dynamic>>();
        final results = await hydrationService.hydrateNotes(batch, index);
        final updatedNotes = Map<String, Note>.from(state.notes);
        final updatedSkeletonIds = Set<String>.from(state.skeletonNoteIds);
        for (final entry in results.entries) {
          final noteId = entry.key;
          final hydratedNote = entry.value;
          if (hydratedNote != null) {
            String finalContent = hydratedNote.content;
            bool migrationNeeded = false;
            try {
              if (finalContent.trim().isNotEmpty) {
                final parsed = jsonDecode(finalContent);
                if (!isNormalizedDocument(parsed)) {
                  final normalized =
                      EditorMigrationEngine.tiptapToNormalized(parsed);
                  finalContent = jsonEncode(normalized.toJson());
                  migrationNeeded = true;
                  KragLogger.info(
                    LogDomain.sync,
                    'Content migration applied during hydration for $noteId',
                  );
                }
              }
            } catch (e) {
              KragLogger.warn(
                LogDomain.sync,
                'Migration check failed for $noteId during hydration:$e',
              );
            }
            final finalNote = migrationNeeded
                ? hydratedNote.copyWith(
                    content: finalContent,
                    v: (hydratedNote.v ?? 0) + 1,
                    modifiedTime: DateTime.now().toIso8601String(),
                  )
                : hydratedNote;
            final existingNote = updatedNotes[noteId];
            bool shouldUpdate = false;
            if (existingNote == null) {
              shouldUpdate = true;
            } else if (existingNote.content != finalNote.content) {
              shouldUpdate = true;
              KragLogger.info(
                LogDomain.sync,
                'Content changed for $noteId during hydration(${existingNote.content.length}→ ${finalNote.content.length}bytes)',
              );
            } else if (existingNote.title != finalNote.title) {
              shouldUpdate = true;
              KragLogger.info(
                LogDomain.sync,
                'Title changed for $noteId during hydration',
              );
            } else {
              skippedDueToEquality++;
              KragLogger.info(
                LogDomain.sync,
                'Skipping update for $noteId-content identical(prevents UI flicker)',
              );
            }
            if (shouldUpdate) {
              updatedNotes[noteId] = finalNote;
              hydratedCount++;
              KragLogger.info(
                LogDomain.sync,
                'Successfully hydrated $noteId(v${finalNote.v},${finalNote.content.length}bytes content)',
              );
            }
            if (updatedSkeletonIds.contains(noteId)) {
              updatedSkeletonIds.remove(noteId);
              KragLogger.info(
                LogDomain.sync,
                'Removed $noteId from skeleton state',
              );
            }
          } else {
            failedCount++;
            KragLogger.warn(
              LogDomain.sync,
              'Failed to hydrate note:$noteId',
            );
          }
        }
        state = state.copyWith(
          notes: updatedNotes,
          skeletonNoteIds: updatedSkeletonIds,
          hydratedCount: hydratedCount,
        );
        if (i + batchSize < noteIds.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      KragLogger.info(
        LogDomain.sync,
        'Hydration completed:$hydratedCount hydrated,$failedCount failed,$skippedDueToEquality skipped(identical content)',
      );
      state = state.copyWith(isHydrating: false);
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Error during verification and hydration',
        e,
        stack,
      );
      state = state.copyWith(isHydrating: false);
    }
  }

  Future<void> _reconcileOrphanFiles(List<dynamic> indexEntries) async {
    final reconciliationServiceAsync =
        ref.read(orphanReconciliationServiceProvider);
    if (!reconciliationServiceAsync.hasValue ||
        reconciliationServiceAsync.value == null) {
      KragLogger.warn(
        LogDomain.sync,
        'OrphanReconciliationService not available. Skipping orphan reconciliation.',
      );
      return;
    }
    final reconciliationService = reconciliationServiceAsync.value!;
    KragLogger.info(
      LogDomain.sync,
      'Starting orphan file reconciliation...',
    );
    state = state.copyWith(
      isReconciling: true,
      orphansFound: 0,
      orphansRestored: 0,
      orphansDeleted: 0,
    );
    try {
      final summary = await reconciliationService.performCleanup(indexEntries);
      KragLogger.info(
        LogDomain.sync,
        'Orphan reconciliation summary:$summary',
      );
      state = state.copyWith(
        orphansFound: summary.totalOrphans,
        orphansRestored: summary.restored,
        orphansDeleted: summary.deleted,
      );
      if (summary.restoredIds.isNotEmpty) {
        KragLogger.info(
          LogDomain.sync,
          'Adding ${summary.restoredIds.length}restored notes to state',
        );
        final updatedNotes = Map<String, Note>.from(state.notes);
        final serviceAsync = ref.read(driveSyncServiceProvider);
        if (serviceAsync.hasValue && serviceAsync.value != null) {
          final freshIndex =
              await serviceAsync.value!.loadIndex(checkMismatch: false);
          for (final noteId in summary.restoredIds) {
            final indexEntry =
                freshIndex.cast<Map<String, dynamic>>().firstWhere(
                      (e) => e['id'] == noteId,
                      orElse: () => {},
                    );
            if (indexEntry.isNotEmpty) {
              updatedNotes[noteId] = Note(
                id: noteId,
                title: indexEntry['title'] ?? 'Untitled',
                content: '',
                tags: (indexEntry['tags'] as List?)?.cast<String>() ?? [],
                labels: (indexEntry['labels'] as List?)?.cast<String>() ?? [],
                modifiedTime: indexEntry['modifiedTime'],
                parentId: indexEntry['parentId'],
                v: indexEntry['_v'] as int?,
              );
              KragLogger.info(
                LogDomain.sync,
                'Added restored note $noteId to state',
              );
            }
          }
          state = state.copyWith(notes: updatedNotes);
        }
        await _syncWorkspaceSettingsWithActualCount(state.notes.length);
      }
      if (summary.totalOrphans > 0) {
        KragLogger.info(
          LogDomain.sync,
          'Orphan reconciliation completed:${summary.restored}restored,${summary.deleted}deleted,'
          '${summary.skipped}skipped,${summary.errors}errors',
        );
      } else {
        KragLogger.info(
          LogDomain.sync,
          'No orphan files found. Storage is clean.',
        );
      }
      state = state.copyWith(isReconciling: false);
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Error during orphan reconciliation',
        e,
        stack,
      );
      state = state.copyWith(isReconciling: false);
    }
  }

  Future<void> forceRepair() async {
    final serviceAsync = ref.read(driveSyncServiceProvider);
    if (!serviceAsync.hasValue || serviceAsync.value == null) return;
    state = state.copyWith(isLoadingIndex: true);
    KragLogger.info(
      LogDomain.sync,
      'Force repair triggered by user',
    );
    try {
      await serviceAsync.value!.rebuildIndex();
      await loadIndex();
    } on Exception catch (e, stack) {
      final errorMessage = e.toString();
      KragLogger.error(
        LogDomain.sync,
        'Force repair failed',
        e,
        stack,
      );
      if (errorMessage.contains('Session expired')) {
        KragLogger.warn(
          LogDomain.auth,
          'Session expired detected during forceRepair. Triggering logout...',
        );
        await _handleSessionExpired();
      }
      state = state.copyWith(
        isLoadingIndex: false,
        error: errorMessage.contains('Session expired')
            ? 'Session expired. Please sign in again.'
            : null,
      );
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Force repair failed',
        e,
        stack,
      );
      state = state.copyWith(isLoadingIndex: false);
    }
  }

  void setCurrentNoteId(String id) {
    state = state.copyWith(currentNoteId: id);
    _persistNavigation(id);
  }

  void updateFilters({List<String>? tags, List<String>? labels}) {
    final newTags = tags ?? state.activeFilterTags;
    final newLabels = labels ?? state.activeFilterLabels;
    state = state.copyWith(
      activeFilterTags: newTags,
      activeFilterLabels: newLabels,
    );
    _persistFilters(newTags, newLabels);
  }

  Future<void> _persistNavigation(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(constants.StorageKeys.currentNoteId, id);
      final serviceAsync = ref.read(driveSyncServiceProvider);
      if (serviceAsync.hasValue && serviceAsync.value != null) {
        serviceAsync.value!.updateWorkspaceSettings({'currentNoteId': id});
      }
    } catch (e) {
      KragLogger.warn(
        LogDomain.general,
        'Failed to persist navigation:$e',
      );
    }
  }

  Future<void> _persistFilters(List<String> tags, List<String> labels) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filterData = jsonEncode({
        'tags': tags,
        'labels': labels,
      });
      await prefs.setString(constants.StorageKeys.noteFilters, filterData);
      final serviceAsync = ref.read(driveSyncServiceProvider);
      if (serviceAsync.hasValue && serviceAsync.value != null) {
        serviceAsync.value!.updateWorkspaceSettings({
          'activeFilterTags': tags,
          'activeFilterLabels': labels,
        });
      }
    } catch (e) {
      KragLogger.warn(
        LogDomain.general,
        'Failed to persist filters:$e',
      );
    }
  }

  Future<void> fetchNoteContent(String id) async {
    KragLogger.info(
      LogDomain.sync,
      '[fetchNoteContent]',
    );
    final serviceAsync = ref.read(driveSyncServiceProvider);
    if (!serviceAsync.hasValue || serviceAsync.value == null) {
      KragLogger.warn(
        LogDomain.sync,
        'Cannot fetch note content:Sync service not ready',
      );
      return;
    }
    final syncService = serviceAsync.value!;
    try {
      Note? fetchedNote;
      bool usedCache = false;

      fetchedNote = await syncService.loadNote(id);
      if (fetchedNote != null) {
        KragLogger.info(
          LogDomain.sync,
          'Note $id content fetched from remote(${fetchedNote.content.length}bytes)',
        );
      }

      if (fetchedNote != null) {
        if (state.ghostRetryCounts.containsKey(id)) {
          final newRetryCounts = Map<String, int>.from(state.ghostRetryCounts);
          newRetryCounts.remove(id);
          state = state.copyWith(ghostRetryCounts: newRetryCounts);
        }
        String finalContent = fetchedNote.content;
        bool migrationNeeded = false;
        KragLogger.info(
          LogDomain.sync,
          '[fetchNoteContent] :\r\n$finalContent',
        );
        try {
          if (finalContent.trim().isNotEmpty) {
            final parsed = jsonDecode(finalContent);
            if (!isNormalizedDocument(parsed)) {
              final normalized =
                  EditorMigrationEngine.tiptapToNormalized(parsed);
              finalContent = jsonEncode(normalized.toJson());
              migrationNeeded = true;
              KragLogger.info(
                LogDomain.sync,
                'Content migration applied for $id',
              );
            }
          }
        } catch (e) {
          KragLogger.warn(
            LogDomain.sync,
            'Migration check failed for $id:$e',
          );
        }
        final noteToUpdate = migrationNeeded
            ? fetchedNote.copyWith(
                content: finalContent,
                v: (fetchedNote.v ?? 0) + 1,
                modifiedTime: DateTime.now().toIso8601String(),
              )
            : fetchedNote;
        final newNotes = Map<String, Note>.from(state.notes);
        newNotes[id] = noteToUpdate;
        final updatedSkeletonIds = Set<String>.from(state.skeletonNoteIds);
        if (updatedSkeletonIds.contains(id)) {
          updatedSkeletonIds.remove(id);
          KragLogger.info(
            LogDomain.sync,
            'Removed $id from skeleton state after fetch',
          );
        }
        state = state.copyWith(
          notes: newNotes,
          skeletonNoteIds: updatedSkeletonIds,
        );
        KragLogger.info(
          LogDomain.sync,
          'Note $id successfully updated(source:${usedCache ? "cache" : "remote"})',
        );
      } else {
        final currentRetries = state.ghostRetryCounts[id] ?? 0;
        if (currentRetries < 3) {
          final newRetryCounts = Map<String, int>.from(state.ghostRetryCounts);
          newRetryCounts[id] = currentRetries + 1;
          state = state.copyWith(ghostRetryCounts: newRetryCounts);
          KragLogger.warn(
            LogDomain.sync,
            'Fetch failed for note $id. Retry attempt ${currentRetries + 1}/3. Postponing pruning.',
          );
        } else {
          KragLogger.error(
            LogDomain.sync,
            'Ghost note confirmed after 3 attempts:$id. Content not found on remote or cache. Pruning...',
          );
          final newRetryCounts = Map<String, int>.from(state.ghostRetryCounts);
          newRetryCounts.remove(id);
          state = state.copyWith(ghostRetryCounts: newRetryCounts);
          _removeGhostNoteFromState(id);
          _queueGhostNoteCleanup(id);
        }
      }
    } on Exception catch (e, stack) {
      final errorMessage = e.toString();
      KragLogger.error(
        LogDomain.sync,
        'Failed to fetch note content:$id',
        e,
        stack,
      );
      if (errorMessage.contains('Session expired')) {
        KragLogger.warn(
          LogDomain.auth,
          'Session expired detected during fetchNoteContent. Triggering logout...',
        );
        await _handleSessionExpired();
      }
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to fetch note content:$id',
        e,
        stack,
      );
    }
  }

  void _removeGhostNoteFromState(String noteId) {
    final newNotes = Map<String, Note>.from(state.notes);
    newNotes.remove(noteId);
    final newRetryCounts = Map<String, int>.from(state.ghostRetryCounts);
    newRetryCounts.remove(noteId);
    final updatedSkeletonIds = Set<String>.from(state.skeletonNoteIds);
    updatedSkeletonIds.remove(noteId);
    final updatedDirtyIds = Set<String>.from(state.dirtyNoteIds);
    updatedDirtyIds.remove(noteId);
    String newCurrentId = state.currentNoteId;
    if (newCurrentId == noteId) {
      newCurrentId = newNotes.isNotEmpty
          ? newNotes.keys.first
          : constants.AppConstants.defaultNoteId;
      KragLogger.info(
        LogDomain.sync,
        'Ghost note was current note. Switching to:$newCurrentId',
      );
    }
    state = state.copyWith(
      notes: newNotes,
      currentNoteId: newCurrentId,
      ghostRetryCounts: newRetryCounts,
      skeletonNoteIds: updatedSkeletonIds,
      dirtyNoteIds: updatedDirtyIds,
    );
    KragLogger.info(
      LogDomain.sync,
      'Ghost note $noteId removed from local state,skeleton set,and dirty flags',
    );
  }

  Future<void> _queueGhostNoteCleanup(String noteId) async {
    try {
      final serviceAsync = ref.read(driveSyncServiceProvider);
      if (!serviceAsync.hasValue || serviceAsync.value == null) {
        KragLogger.warn(
          LogDomain.sync,
          'Cannot clean up ghost note:Sync service not ready',
        );
        return;
      }
      final syncService = serviceAsync.value!;
      KragLogger.info(
        LogDomain.sync,
        'Performing final verification for ghost note:$noteId',
      );
      try {
        final verifyNote = await syncService.loadNote(noteId);
        if (verifyNote != null) {
          KragLogger.warn(
            LogDomain.sync,
            'Verification failed:Note $noteId actually exists on Drive. Aborting cleanup.',
          );
          if (!state.notes.containsKey(noteId)) {
            final newNotes = Map<String, Note>.from(state.notes);
            newNotes[noteId] = verifyNote;
            state = state.copyWith(notes: newNotes);
            KragLogger.info(
              LogDomain.sync,
              'Restored note $noteId to local state after verification.',
            );
          }
          return;
        }
      } catch (e) {
        KragLogger.error(
          LogDomain.sync,
          'Verification error for $noteId during cleanup. Aborting to be safe.',
          e,
        );
        return;
      }
      final currentIndex = await syncService.loadIndex();
      final ghostEntryIndex =
          currentIndex.indexWhere((entry) => entry['id'] == noteId);
      if (ghostEntryIndex != -1) {
        KragLogger.info(
          LogDomain.sync,
          'Ghost note $noteId confirmed missing. Removing from remote index...',
        );
        currentIndex.removeAt(ghostEntryIndex);
        await syncService.saveIndex(currentIndex);
        KragLogger.info(
          LogDomain.sync,
          'Ghost note $noteId successfully removed from remote index',
        );
        final actualCount = currentIndex.length;
        await _syncWorkspaceSettingsWithActualCount(actualCount);
      } else {
        KragLogger.info(
          LogDomain.sync,
          'Ghost note $noteId not found in index(already cleaned up)',
        );
      }
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to clean up ghost note $noteId from index',
        e,
        stack,
      );
    }
  }

  Future<void> _syncWorkspaceSettingsWithActualCount(int actualCount) async {
    try {
      final serviceAsync = ref.read(driveSyncServiceProvider);
      if (serviceAsync.hasValue && serviceAsync.value != null) {
        final currentSettings =
            await serviceAsync.value!.loadWorkspaceSettings();
        final updatedSettings = {
          ...currentSettings,
          'noteCount': actualCount,
          'lastSyncedAt': DateTime.now().toIso8601String(),
        };
        await serviceAsync.value!.updateWorkspaceSettings(updatedSettings);
        KragLogger.info(
          LogDomain.sync,
          'Workspace settings synced with actual note count:$actualCount',
        );
      }
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to sync workspace settings count',
        e,
        stack,
      );
    }
  }

  Future<void> saveCurrentNote() async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true);
    try {
      KragLogger.info(LogDomain.sync,
          'Initiating save for current note: ${state.currentNoteId}');
      await saveNote(state.currentNoteId);
      // Refresh index to ensure remote state is reflected locally
      await loadIndex(showLoading: false, forceRemote: true);
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  String createNote({String? parentId}) {
    final id = const Uuid().v4();
    final defaultContent = _generateDefaultCodeBlockContent();
    final newNote = Note(
      id: id,
      title: 'Untitled',
      content: defaultContent,
      modifiedTime: DateTime.now().toIso8601String(),
      parentId: parentId,
    );
    final newNotes = Map<String, Note>.from(state.notes);
    newNotes[id] = newNote;
    final updatedDirtyIds = Set<String>.from(state.dirtyNoteIds);
    updatedDirtyIds.add(id);
    state = state.copyWith(
      notes: newNotes,
      currentNoteId: id,
      dirtyNoteIds: updatedDirtyIds,
    );
    Future.microtask(() {
      _syncWorkspaceSettingsWithActualCount(newNotes.length);
    });
    KragLogger.info(
      LogDomain.general,
      'Created new note with default code block:$id(marked as dirty)',
    );
    return id;
  }

  Future<void> updateNoteTitle(String id, String title) async {
    KragLogger.info(
      LogDomain.general,
      '[updateNoteTitle] : $id, $title',
    );
    if (state.notes.containsKey(id)) {
      final updatedNote = state.notes[id]!.copyWith(
        title: title,
        modifiedTime: DateTime.now().toIso8601String(),
      );
      final newNotes = Map<String, Note>.from(state.notes);
      newNotes[id] = updatedNote;
      state = state.copyWith(notes: newNotes);
      _markNoteDirty(id);
    }
  }

  Future<void> updateNoteContent(String id, String content) async {
    _validateContentStructure(id, content);
    KragLogger.info(
      LogDomain.general,
      'NotesStore:Updating local content for $id. Size:${content.length}',
    );
    if (state.notes.containsKey(id)) {
      final updatedNote = state.notes[id]!.copyWith(
        content: content,
        modifiedTime: DateTime.now().toIso8601String(),
      );
      final newNotes = Map<String, Note>.from(state.notes);
      newNotes[id] = updatedNote;
      final updatedSkeletonIds = Set<String>.from(state.skeletonNoteIds);
      if (updatedSkeletonIds.contains(id)) {
        updatedSkeletonIds.remove(id);
      }
      state = state.copyWith(
        notes: newNotes,
        skeletonNoteIds: updatedSkeletonIds,
      );
      _markNoteDirty(id);
    } else {
      KragLogger.warn(
        LogDomain.general,
        'NotesStore:Attempted to update content for missing note $id',
      );
    }
  }

  Future<void> updateNoteTags(String id, List<String> tags) async {
    if (state.notes.containsKey(id)) {
      final updatedNote = state.notes[id]!.copyWith(
        tags: tags,
        modifiedTime: DateTime.now().toIso8601String(),
      );
      final newNotes = Map<String, Note>.from(state.notes);
      newNotes[id] = updatedNote;
      state = state.copyWith(notes: newNotes);
      _markNoteDirty(id);
    }
  }

  Future<void> updateNoteLabels(String id, List<String> labels) async {
    if (state.notes.containsKey(id)) {
      final updatedNote = state.notes[id]!.copyWith(
        labels: labels,
        modifiedTime: DateTime.now().toIso8601String(),
      );
      final newNotes = Map<String, Note>.from(state.notes);
      newNotes[id] = updatedNote;
      state = state.copyWith(notes: newNotes);
      _markNoteDirty(id);
    }
  }

  Future<void> saveNote(String id) async {
    KragLogger.info(
      LogDomain.sync,
      '[saveNote]',
    );
    final localNote = state.notes[id];
    if (localNote == null) return;
    final serviceAsync = ref.read(driveSyncServiceProvider);
    if (!serviceAsync.hasValue || serviceAsync.value == null) {
      throw Exception('Sync service not ready');
    }
    try {
      final syncService = serviceAsync.value!;
      final localVersion = localNote.v ?? 0;

      final localNoteContent = jsonEncode(localNote);
      KragLogger.info(
        LogDomain.sync,
        '[saveNote] :\r\n$localNoteContent',
      );

      // OPTIMIZATION: Use index lookup instead of loadNote to avoid cache pollution
      int remoteVersion = 0;
      try {
        final index = await syncService.loadIndex(checkMismatch: false);
        final remoteEntry = index.cast<Map<String, dynamic>>().firstWhere(
              (e) => e['id'] == id,
              orElse: () => <String, dynamic>{},
            );
        if (remoteEntry.isNotEmpty) {
          remoteVersion = remoteEntry['_v'] as int? ?? 0;
        }
      } catch (e) {
        KragLogger.warn(LogDomain.sync,
            'Failed to fetch remote version from index for $id: $e');
      }

      if (remoteVersion > localVersion) {
        KragLogger.warn(
          LogDomain.sync,
          'Version drift detected for note $id:Local v$localVersion<Remote v$remoteVersion. '
          'Attempting reconciliation...',
        );
        try {
          // Bump local note to remote version before saving to ensure it becomes the new head
          final reconciledNote = localNote.copyWith(
            v: remoteVersion,
          );
          final savedNote = await syncService.saveNote(reconciledNote);

          final newNotes = Map<String, Note>.from(state.notes);
          newNotes[id] = savedNote;
          state = state.copyWith(notes: newNotes);
          _clearNoteDirty(id);

          KragLogger.info(
            LogDomain.sync,
            'Reconciliation successful for $id. Saved as v${savedNote.v}. '
            'Local metadata preserved,remote content adopted.',
          );
          return;
        } catch (reconcileError) {
          KragLogger.error(
            LogDomain.sync,
            'Reconciliation failed for $id',
            reconcileError,
          );
          rethrow;
        }
      } else if (remoteVersion == localVersion && localVersion > 0) {
        KragLogger.warn(
          LogDomain.sync,
          'Version stagnation detected for note $id:Local v$localVersion==Remote v$remoteVersion. '
          'Incrementing version to force update.',
        );
      }

      final savedNote = await syncService.saveNote(localNote);
      final savedVersion = savedNote.v ?? 0;

      // Atomic check: Ensure version actually increased
      if (savedVersion <= localVersion && localVersion > 0) {
        final diagnostic = '''
Version Integrity Violation for note $id:
- Local version before save: $localVersion
- Remote version before save: $remoteVersion
- Saved version returned: $savedVersion
- Expected: > $localVersion
- Note title: "${localNote.title}"''';
        KragLogger.error(LogDomain.sync, 'Integrity Error: $diagnostic');

        try {
          final recoveredNote = await syncService.loadNote(id);
          if (recoveredNote != null) {
            final newNotes = Map<String, Note>.from(state.notes);
            newNotes[id] = recoveredNote;
            state = state.copyWith(notes: newNotes);
            KragLogger.info(LogDomain.sync,
                'Recovered note $id from remote after version violation');
            return;
          }
        } catch (recoveryError) {
          KragLogger.warn(LogDomain.sync,
              'Failed to recover note $id after version violation: $recoveryError');
        }
        throw Exception(
            'Integrity Error: Version regression or stagnation detected.');
      }

      final currentNote = state.notes[id];
      if (currentNote != null) {
        final updatedNote = currentNote.copyWith(
          v: savedNote.v,
          modifiedTime: savedNote.modifiedTime,
        );
        final newNotes = Map<String, Note>.from(state.notes);
        newNotes[id] = updatedNote;
        state = state.copyWith(notes: newNotes);
      }

      _clearNoteDirty(id);
      KragLogger.info(
        LogDomain.sync,
        'Note $id saved successfully (v$localVersion -> v$savedVersion)',
      );
    } on Exception catch (e, stack) {
      final errorMessage = e.toString();
      KragLogger.error(
        LogDomain.sync,
        'Failed to save note:$id',
        e,
        stack,
      );
      if (errorMessage.contains('Session expired')) {
        KragLogger.warn(
          LogDomain.auth,
          'Session expired detected during saveNote. Triggering logout...',
        );
        await _handleSessionExpired();
      }
      rethrow;
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to save note:$id',
        e,
        stack,
      );
      rethrow;
    }
  }

  Future<void> deleteNote(String id) async {
    final newNotes = Map<String, Note>.from(state.notes);
    final removedNote = newNotes.remove(id);
    if (removedNote == null) {
      KragLogger.warn(
        LogDomain.general,
        'Attempted to delete non-existent note locally:$id',
      );
      return;
    }
    final updatedSkeletonIds = Set<String>.from(state.skeletonNoteIds);
    updatedSkeletonIds.remove(id);
    final updatedDirtyIds = Set<String>.from(state.dirtyNoteIds);
    updatedDirtyIds.remove(id);
    String newCurrentId = state.currentNoteId;
    if (newCurrentId == id) {
      newCurrentId = newNotes.isNotEmpty
          ? newNotes.keys.first
          : constants.AppConstants.defaultNoteId;
    }
    state = state.copyWith(
      notes: newNotes,
      currentNoteId: newCurrentId,
      skeletonNoteIds: updatedSkeletonIds,
      dirtyNoteIds: updatedDirtyIds,
    );
    KragLogger.info(
      LogDomain.general,
      'Local note deleted:$id. New count:${newNotes.length}',
    );
    try {
      final serviceAsync = ref.read(driveSyncServiceProvider);
      if (serviceAsync.hasValue && serviceAsync.value != null) {
        KragLogger.info(
          LogDomain.sync,
          'Initiating remote deletion for note:$id',
        );
        await serviceAsync.value!.deleteNote(id);
        KragLogger.info(
          LogDomain.sync,
          'Updating workspace settings note count to:${newNotes.length}',
        );
        await _syncWorkspaceSettingsWithActualCount(newNotes.length);
      } else {
        KragLogger.warn(
          LogDomain.sync,
          'Sync service not ready. Remote deletion queued/skipped.',
        );
      }
    } on Exception catch (e, stack) {
      final errorMessage = e.toString();
      KragLogger.error(
        LogDomain.sync,
        'Failed to delete note remotely:$id',
        e,
        stack,
      );
      if (errorMessage.contains('Session expired')) {
        KragLogger.warn(
          LogDomain.auth,
          'Session expired detected during deleteNote. Triggering logout...',
        );
        await _handleSessionExpired();
      }
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Failed to delete note remotely:$id',
        e,
        stack,
      );
    }
  }

  Future<void> updateNoteParent(String id, String? parentId) async {
    if (state.notes.containsKey(id)) {
      final updatedNote = state.notes[id]!.copyWith(
        parentId: parentId,
        modifiedTime: DateTime.now().toIso8601String(),
      );
      final newNotes = Map<String, Note>.from(state.notes);
      newNotes[id] = updatedNote;
      state = state.copyWith(notes: newNotes);
      _markNoteDirty(id);
    }
  }

  Future<void> reorderBlocks(String noteId, int oldIndex, int newIndex) async {
    final note = state.notes[noteId];
    if (note == null || note.content.isEmpty) return;
    try {
      final contentJson = jsonDecode(note.content);
      if (contentJson is Map &&
          contentJson['format'] == 'nblock' &&
          contentJson['blocks'] is List) {
        final blocks = List<Map<String, dynamic>>.from(
          (contentJson['blocks'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        if (oldIndex < 0 || oldIndex >= blocks.length) return;
        if (newIndex < 0 || newIndex >= blocks.length) return;
        if (oldIndex == newIndex) return;
        final movedBlock = blocks.removeAt(oldIndex);
        blocks.insert(newIndex, movedBlock);
        final newContent = jsonEncode({
          'format': contentJson['format'],
          'version': contentJson['version'] ?? 1,
          'blocks': blocks,
        });
        final updatedNote = note.copyWith(
          content: newContent,
          modifiedTime: DateTime.now().toIso8601String(),
        );
        final newNotes = Map<String, Note>.from(state.notes);
        newNotes[noteId] = updatedNote;
        state = state.copyWith(notes: newNotes);
        _markNoteDirty(noteId);
        KragLogger.info(
          LogDomain.general,
          'Blocks reordered:$oldIndex → $newIndex',
        );
      } else if (contentJson is Map &&
          contentJson['type'] == 'page' &&
          contentJson['children'] is List) {
        final blocks = List<Map<String, dynamic>>.from(
          (contentJson['children'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        if (oldIndex < 0 || oldIndex >= blocks.length) return;
        if (newIndex < 0 || newIndex >= blocks.length) return;
        if (oldIndex == newIndex) return;
        final movedBlock = blocks.removeAt(oldIndex);
        blocks.insert(newIndex, movedBlock);
        final newContent = jsonEncode({
          'type': contentJson['type'] ?? 'page',
          'children': blocks,
        });
        final updatedNote = note.copyWith(
          content: newContent,
          modifiedTime: DateTime.now().toIso8601String(),
        );
        final newNotes = Map<String, Note>.from(state.notes);
        newNotes[noteId] = updatedNote;
        state = state.copyWith(notes: newNotes);
        _markNoteDirty(noteId);
        KragLogger.info(
          LogDomain.general,
          'Blocks reordered:$oldIndex → $newIndex',
        );
      } else {
        KragLogger.warn(
          LogDomain.general,
          'Invalid content structure for reorder:${contentJson.runtimeType}',
        );
      }
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.general,
        'Failed to reorder blocks',
        e,
        stack,
      );
    }
  }

  Future<void> _handleSessionExpired() async {
    try {
      _hasTriggeredInitialLoad = false;
      KragLogger.info(
        LogDomain.auth,
        'Resetting initialization guard flag due to session expiration',
      );
      await ref.read(authStoreProvider.notifier).handleLogout();
      state = state.copyWith(
        notes: const {},
        currentNoteId: constants.AppConstants.defaultNoteId,
        isLoadingIndex: false,
        isSyncing: false,
        activeFilterTags: const [],
        activeFilterLabels: const [],
        ghostRetryCounts: const {},
        isHydrating: false,
        hydratedCount: 0,
        totalToHydrate: 0,
        isReconciling: false,
        orphansFound: 0,
        orphansRestored: 0,
        orphansDeleted: 0,
        skeletonNoteIds: const {},
        dirtyNoteIds: const {},
      );
      KragLogger.info(
        LogDomain.auth,
        'Session expiration handled. User logged out and state cleared.',
      );
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.auth,
        'Failed to handle session expired',
        e,
        stack,
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final notesStoreProvider = NotifierProvider<NotesNotifier, NotesStateData>(
  NotesNotifier.new,
);
