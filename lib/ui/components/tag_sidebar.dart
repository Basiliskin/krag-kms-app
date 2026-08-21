import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/notes_store.dart';
import '../../stores/tabs_store.dart';
import '../../types/index.dart';
import 'drive_connect_button.dart';
import 'hierarchy_dialog.dart';
import 'filter_dialog.dart';

class TagSidebar extends ConsumerStatefulWidget {
  const TagSidebar({super.key});
  @override
  ConsumerState<TagSidebar> createState() => _TagSidebarState();
}

class _TagSidebarState extends ConsumerState<TagSidebar> {
  Set<String> _getVisibleNoteIds(Map<String, Note> notes,
      List<String> filterTags, List<String> filterLabels) {
    if (filterTags.isEmpty && filterLabels.isEmpty) {
      return notes.keys.toSet();
    }
    final visibleIds = <String>{};
    for (final note in notes.values) {
      bool noteMatches = false;
      if (filterTags.isNotEmpty &&
          note.tags.any((t) => filterTags.contains(t))) {
        noteMatches = true;
      }
      if (filterLabels.isNotEmpty &&
          note.labels.any((l) => filterLabels.contains(l))) {
        noteMatches = true;
      }
      if (noteMatches) {
        String? currentId = note.id;
        while (currentId != null && !visibleIds.contains(currentId)) {
          visibleIds.add(currentId);
          currentId = notes[currentId]?.parentId;
        }
      }
    }
    return visibleIds;
  }

  List<Note> _buildNoteTree(Map<String, Note> notes, Set<String> visibleIds) {
    final noteList =
        notes.values.where((n) => visibleIds.contains(n.id)).toList();
    noteList
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final rootNotes = noteList.where((n) => n.parentId == null).toList();
    return rootNotes;
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesStoreProvider);
    final notes = notesState.notes;
    final currentNoteId = notesState.currentNoteId;
    final visibleIds = _getVisibleNoteIds(
      notes,
      notesState.activeFilterTags,
      notesState.activeFilterLabels,
    );
    final rootNotes = _buildNoteTree(notes, visibleIds);
    final hasActiveFilters = notesState.activeFilterTags.isNotEmpty ||
        notesState.activeFilterLabels.isNotEmpty;
    return Container(
      width: 250,
      color: const Color(0xFF121212),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_special,
                    color: Color(0xFFEDEDED), size: 24),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Workspace',
                      style: TextStyle(
                        color: Color(0xFFEDEDED),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Notes & Tags',
                      style: TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
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
                    size: 20,
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
                  icon: const Icon(Icons.account_tree_outlined,
                      color: Color(0xFFA0A0A0), size: 20),
                  tooltip: 'Manage Hierarchy',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: rootNotes.length,
              itemBuilder: (context, index) {
                final note = rootNotes[index];
                return _NoteTreeItem(
                  key: ValueKey(note.id),
                  note: note,
                  allNotes: notes,
                  visibleIds: visibleIds,
                  currentNoteId: currentNoteId,
                  onTap: (id) {
                    ref.read(notesStoreProvider.notifier).setCurrentNoteId(id);
                    ref.read(tabsStoreProvider.notifier).addTab(id);
                  },
                  onCreateChild: (parentId) {
                    final newId = ref
                        .read(notesStoreProvider.notifier)
                        .createNote(parentId: parentId);
                    ref.read(tabsStoreProvider.notifier).addTab(newId);
                  },
                  onDelete: (id) {
                    _confirmDelete(context, ref, id);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
            ),
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notesState.isSyncing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: const [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Syncing...',
                              style: TextStyle(
                                  color: Color(0xFFA0A0A0), fontSize: 12)),
                        ],
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: notesState.isSyncing
                        ? null
                        : () async {
                            try {
                              await ref
                                  .read(notesStoreProvider.notifier)
                                  .saveCurrentNote();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sync completed'),
                                    backgroundColor: Color(0xFF4CAF50),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Sync failed: $e'),
                                    backgroundColor: const Color(0xFFE57373),
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      foregroundColor: const Color(0xFFEDEDED),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Now'),
                  ),
                  const SizedBox(height: 12),
                  const DriveConnectButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String noteId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Note?',
            style: TextStyle(color: Color(0xFFEDEDED))),
        content: const Text('Are you sure you want to delete this note?',
            style: TextStyle(color: Color(0xFFA0A0A0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFFA0A0A0))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(notesStoreProvider.notifier).deleteNote(noteId);
              ref.read(tabsStoreProvider.notifier).closeTab(noteId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _NoteTreeItem extends StatefulWidget {
  final Note note;
  final Map<String, Note> allNotes;
  final Set<String> visibleIds;
  final String currentNoteId;
  final Function(String) onTap;
  final Function(String) onCreateChild;
  final Function(String) onDelete;
  final int depth;
  const _NoteTreeItem({
    super.key,
    required this.note,
    required this.allNotes,
    required this.visibleIds,
    required this.currentNoteId,
    required this.onTap,
    required this.onCreateChild,
    required this.onDelete,
    this.depth = 0,
  });
  @override
  State<_NoteTreeItem> createState() => _NoteTreeItemState();
}

class _NoteTreeItemState extends State<_NoteTreeItem> {
  bool _isExpanded = false;
  @override
  Widget build(BuildContext context) {
    final children = widget.allNotes.values
        .where((n) =>
            n.parentId == widget.note.id && widget.visibleIds.contains(n.id))
        .toList();
    children
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final isSelected = widget.note.id == widget.currentNoteId;
    final hasChildren = children.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2A2A2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(width: widget.depth * 16.0),
              SizedBox(
                width: 24,
                height: 24,
                child: hasChildren
                    ? InkWell(
                        onTap: () => setState(() => _isExpanded = !_isExpanded),
                        borderRadius: BorderRadius.circular(4),
                        child: Icon(
                          _isExpanded
                              ? Icons.arrow_drop_down
                              : Icons.arrow_right,
                          color: const Color(0xFFA0A0A0),
                          size: 20,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: InkWell(
                  onTap: () => widget.onTap(widget.note.id),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final notesState = ref.watch(notesStoreProvider);
                        final isSkeleton =
                            notesState.skeletonNoteIds.contains(widget.note.id);
                        if (isSkeleton) {
                          return Container(
                            height: 14,
                            width: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }
                        return Text(
                          widget.note.title.isEmpty
                              ? 'Untitled'
                              : widget.note.title,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFEDEDED)
                                : const Color(0xFFA0A0A0),
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_horiz,
                    size: 16,
                    color: isSelected
                        ? const Color(0xFFEDEDED)
                        : const Color(0xFF6A6A6A),
                  ),
                  color: const Color(0xFF1E1E1E),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'add_child',
                      child: Text('Add Child Note',
                          style: TextStyle(color: Color(0xFFEDEDED))),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'add_child') {
                      widget.onCreateChild(widget.note.id);
                      setState(() => _isExpanded = true);
                    }
                    if (value == 'delete') widget.onDelete(widget.note.id);
                  },
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (_isExpanded && hasChildren)
          ...children.map((child) => _NoteTreeItem(
                key: ValueKey(child.id),
                note: child,
                allNotes: widget.allNotes,
                visibleIds: widget.visibleIds,
                currentNoteId: widget.currentNoteId,
                onTap: widget.onTap,
                onCreateChild: widget.onCreateChild,
                onDelete: widget.onDelete,
                depth: widget.depth + 1,
              )),
      ],
    );
  }
}
