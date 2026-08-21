import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krag_app/constants/index.dart' as constants;
import 'package:krag_app/utils/logger.dart';
import 'providers.dart';
import 'notes_store.dart';

class TabsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _loadLocal();
    _syncRemote();
    return [];
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTabs = prefs.getStringList(constants.StorageKeys.openTabs);
    if (savedTabs != null) {
      state = savedTabs;
      _validateTabs();
    }
  }

  Future<void> _syncRemote() async {
    final serviceAsync = ref.read(driveSyncServiceProvider);

    // Wait for service if loading
    if (serviceAsync.isLoading) {
      // We can't easily await the provider here without watching it,
      // but we don't want to rebuild on every async state change.
      // We'll try to read it if available, or retry shortly?
      // Better: The UI usually triggers initialization.
      // We'll just check if it's ready.
    }

    if (!serviceAsync.hasValue || serviceAsync.value == null) return;

    try {
      final settings = await serviceAsync.value!.loadWorkspaceSettings();
      if (settings.containsKey('openTabs')) {
        final remoteTabs = List<String>.from(settings['openTabs']);
        if (remoteTabs.isNotEmpty) {
          state = remoteTabs;
          _persistLocal(); // Update local cache
          _validateTabs();
        }
      }
    } catch (e) {
      KragLogger.warn(LogDomain.sync, 'Failed to sync tabs from remote: $e');
    }
  }

  Future<void> reloadFromStorage() async {
    await _loadLocal();
  }

  void _validateTabs() {
    final notesState = ref.read(notesStoreProvider);

    // Prevent clearing tabs if notes are still loading
    if (notesState.isLoadingIndex || notesState.notes.isEmpty) {
      return;
    }

    final validTabs =
        state.where((id) => notesState.notes.containsKey(id)).toList();
    if (validTabs.length != state.length) {
      state = validTabs;
      _persist();
    }
  }

  Future<void> _persist() async {
    await _persistLocal();
    await _persistRemote();
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(constants.StorageKeys.openTabs, state);
  }

  Future<void> _persistRemote() async {
    final serviceAsync = ref.read(driveSyncServiceProvider);
    if (serviceAsync.hasValue && serviceAsync.value != null) {
      // Fire and forget
      serviceAsync.value!.updateWorkspaceSettings({'openTabs': state});
    }
  }

  void addTab(String noteId) {
    final notesState = ref.read(notesStoreProvider);
    // Allow adding if notes are loading (optimistic) or if note exists
    if (!state.contains(noteId) &&
        (notesState.isLoadingIndex || notesState.notes.containsKey(noteId))) {
      state = [...state, noteId];
      _persist();
    }
    ref.read(notesStoreProvider.notifier).setCurrentNoteId(noteId);
  }

  void closeTab(String noteId) {
    final notesState = ref.read(notesStoreProvider);
    final wasActive = notesState.currentNoteId == noteId;

    state = state.where((id) => id != noteId).toList();
    _persist();

    if (wasActive) {
      if (state.isNotEmpty) {
        ref.read(notesStoreProvider.notifier).setCurrentNoteId(state.last);
      } else {
        ref.read(notesStoreProvider.notifier).setCurrentNoteId('');
      }
    }
  }

  void ensureCurrentNoteInTabs() {
    final notesState = ref.read(notesStoreProvider);
    final currentId = notesState.currentNoteId;

    if (currentId.isNotEmpty &&
        currentId != constants.AppConstants.defaultNoteId &&
        !state.contains(currentId)) {
      // Only add if it exists or we are loading
      if (notesState.isLoadingIndex ||
          notesState.notes.containsKey(currentId)) {
        state = [...state, currentId];
        _persist();
      }
    }
  }
}

final tabsStoreProvider =
    NotifierProvider<TabsNotifier, List<String>>(TabsNotifier.new);
