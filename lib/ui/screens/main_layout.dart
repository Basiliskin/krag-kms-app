import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/auth_store.dart';
import '../../stores/notes_store.dart';
import '../../stores/tabs_store.dart';
import '../components/tag_sidebar.dart';
import '../components/tab_bar.dart';
import '../components/hierarchy_dialog.dart';
import '../components/filter_dialog.dart';
import '../editor/block_editor.dart';
import 'vault_entry_screen.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  final bool _isSidebarOpen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tabsStoreProvider.notifier).ensureCurrentNoteInTabs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStoreProvider);
    final notesState = ref.watch(notesStoreProvider);
    final openTabs = ref.watch(tabsStoreProvider);

    if (!authState.isAuthenticated) {
      return const VaultEntryScreen();
    }

    if (notesState.isLoadingIndex) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF6B00)),
              SizedBox(height: 16),
              Text(
                'Loading Vault...',
                style: TextStyle(color: Color(0xFFA0A0A0)),
              ),
            ],
          ),
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 768;
    final showSidebar = _isSidebarOpen && !isMobile;
    final hasActiveFilters = notesState.activeFilterTags.isNotEmpty ||
        notesState.activeFilterLabels.isNotEmpty;

    // Determine if we have a valid note to display in the editor.
    // We show the editor ONLY if:
    // 1. There is a current note ID.
    // 2. That note actually exists in our local state.
    // 3. That note is currently open in a tab.
    final currentNoteId = notesState.currentNoteId;
    final hasValidNote = currentNoteId.isNotEmpty &&
        notesState.notes.containsKey(currentNoteId) &&
        openTabs.contains(currentNoteId);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: false,
      drawer: isMobile ? const Drawer(child: TagSidebar()) : null,
      appBar: isMobile
          ? AppBar(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                'Krag',
                style: TextStyle(color: Color(0xFFEDEDED)),
              ),
              iconTheme: const IconThemeData(color: Color(0xFFA0A0A0)),
              actions: [
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const FilterDialog(),
                    );
                  },
                  icon: Icon(
                    Icons.filter_list,
                    color: hasActiveFilters
                        ? const Color(0xFFFF6B00)
                        : const Color(0xFFA0A0A0),
                  ),
                  tooltip: 'Filter Notes',
                ),
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const HierarchyDialog(),
                    );
                  },
                  icon: const Icon(Icons.account_tree_outlined),
                  tooltip: 'Manage Hierarchy',
                ),
              ],
            )
          : null,
      body: Row(
        children: [
          if (showSidebar)
            const SizedBox(
              width: 250,
              child: TagSidebar(),
            ),
          Expanded(
            child: Column(
              children: [
                const AppTabBar(),
                Expanded(
                  child: Container(
                    color: const Color(0xFF121212),
                    child: !hasValidNote
                        ? _buildEmptyState()
                        : BlockEditor(noteId: currentNoteId),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.note_add,
            size: 64,
            color: Color(0xFF2A2A2A),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notes found',
            style: TextStyle(
              color: Color(0xFFA0A0A0),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref.read(notesStoreProvider.notifier).createNote();
              ref.read(tabsStoreProvider.notifier).ensureCurrentNoteInTabs();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B00),
              foregroundColor: Colors.white,
            ),
            child: const Text('Create First Note'),
          ),
        ],
      ),
    );
  }
}
