import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/notes_store.dart';
import '../../types/index.dart';

class HierarchyDialog extends ConsumerStatefulWidget {
  const HierarchyDialog({super.key});

  @override
  ConsumerState<HierarchyDialog> createState() => _HierarchyDialogState();
}

class _HierarchyDialogState extends ConsumerState<HierarchyDialog> {
  String? _draggedNoteId;
  final Map<String, String?> _pendingChanges = {};
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesStoreProvider);
    final originalNotes = notesState.notes;

    // Create effective notes map with pending changes applied
    final effectiveNotes = Map<String, Note>.fromEntries(
      originalNotes.entries.map((entry) {
        if (_pendingChanges.containsKey(entry.key)) {
          return MapEntry(
            entry.key,
            entry.value.copyWith(parentId: _pendingChanges[entry.key]),
          );
        }
        return entry;
      }),
    );

    // Filter root notes (parentId is null)
    final rootNotes =
        effectiveNotes.values.where((n) => n.parentId == null).toList();
    // Sort alphabetically
    rootNotes
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    final isMobile = MediaQuery.of(context).size.width < 600;
    final hasChanges = _pendingChanges.isNotEmpty;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      insetPadding: isMobile
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: isMobile
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isMobile ? MediaQuery.of(context).size.width : 600,
        height: isMobile
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Manage Hierarchy',
                  style: TextStyle(
                    color: Color(0xFFEDEDED),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!isMobile)
                  Row(
                    children: [
                      if (_isSaving)
                        const Padding(
                          padding: EdgeInsets.only(right: 16),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFFFF6B00)),
                          ),
                        ),
                      TextButton(
                        onPressed:
                            _isSaving ? null : () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                              color: const Color(0xFFA0A0A0)
                                  .withOpacity(_isSaving ? 0.5 : 1.0)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed:
                            _isSaving || !hasChanges ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF2A2A2A),
                          disabledForegroundColor: const Color(0xFF6A6A6A),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  )
                else
                  IconButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFFA0A0A0)),
                  ),
              ],
            ),

            // Instructions
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Drag and drop notes to organize them. Changes are saved only when you click "Save".',
                style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
              ),
            ),

            const SizedBox(height: 8),

            // Root Drop Zone
            DragTarget<String>(
              onWillAccept: (data) =>
                  data != null && effectiveNotes[data]?.parentId != null,
              onAccept: (data) {
                HapticFeedback.mediumImpact();
                setState(() {
                  _pendingChanges[data] = null;
                });
              },
              builder: (context, candidateData, rejectedData) {
                final isTargeted = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  decoration: BoxDecoration(
                    color: isTargeted
                        ? const Color(0xFFFF6B00).withOpacity(0.15)
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isTargeted
                          ? const Color(0xFFFF6B00)
                          : const Color(0xFF3A3A3A),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isTargeted
                              ? const Color(0xFFFF6B00).withOpacity(0.2)
                              : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.home_work_outlined,
                          color: isTargeted
                              ? const Color(0xFFFF6B00)
                              : const Color(0xFFA0A0A0),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Workspace Root',
                            style: TextStyle(
                              color: isTargeted
                                  ? const Color(0xFFFF6B00)
                                  : const Color(0xFFEDEDED),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const Text(
                            'Drop here to un-nest',
                            style: TextStyle(
                                color: Color(0xFF6A6A6A), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Tree List
            Expanded(
              child: _isSaving
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFFF6B00)),
                          SizedBox(height: 16),
                          Text('Saving changes...',
                              style: TextStyle(color: Color(0xFFA0A0A0))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: rootNotes.length,
                      itemBuilder: (context, index) {
                        return _HierarchyItem(
                          note: rootNotes[index],
                          allNotes: effectiveNotes,
                          onDragStarted: (id) {
                            HapticFeedback.mediumImpact();
                            setState(() => _draggedNoteId = id);
                          },
                          onDragEnded: () =>
                              setState(() => _draggedNoteId = null),
                          onParentChanged: (childId, newParentId) {
                            setState(() {
                              _pendingChanges[childId] = newParentId;
                            });
                          },
                          draggedNoteId: _draggedNoteId,
                        );
                      },
                    ),
            ),

            // Mobile Action Buttons
            if (isMobile)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed:
                            _isSaving ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: Color(0xFFA0A0A0))),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed:
                            _isSaving || !hasChanges ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF2A2A2A),
                          disabledForegroundColor: const Color(0xFF6A6A6A),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_pendingChanges.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(notesStoreProvider.notifier);
      // Process updates sequentially to ensure data integrity
      for (final entry in _pendingChanges.entries) {
        await notifier.updateNoteParent(entry.key, entry.value);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      // Handle error (could show a snackbar)
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save changes: $e')),
        );
      }
    }
  }
}

class _HierarchyItem extends StatelessWidget {
  final Note note;
  final Map<String, Note> allNotes;
  final Function(String) onDragStarted;
  final VoidCallback onDragEnded;
  final Function(String, String?) onParentChanged;
  final String? draggedNoteId;
  final int depth;

  const _HierarchyItem({
    required this.note,
    required this.allNotes,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onParentChanged,
    this.draggedNoteId,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Find children
    final children =
        allNotes.values.where((n) => n.parentId == note.id).toList();
    children
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    // Logic to prevent circular dependency
    bool canAccept(String? incomingId) {
      if (incomingId == null || incomingId == note.id) return false;

      // Check if we are dragging a parent into its own child/descendant
      String? currentParentId = note.parentId;
      while (currentParentId != null) {
        if (currentParentId == incomingId) return false;
        currentParentId = allNotes[currentParentId]?.parentId;
      }
      return true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Draggable<String>(
          data: note.id,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: const Color(0xFFFF6B00), width: 1),
              ),
              child: Text(
                note.title.isEmpty ? 'Untitled' : note.title,
                style: const TextStyle(
                  color: Color(0xFFEDEDED),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          onDragStarted: () => onDragStarted(note.id),
          onDragEnd: (_) => onDragEnded(),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildItemContent(context, false),
          ),
          child: DragTarget<String>(
            onWillAccept: (data) => canAccept(data),
            onAccept: (data) {
              HapticFeedback.mediumImpact();
              onParentChanged(data, note.id);
            },
            builder: (context, candidateData, rejectedData) {
              return _buildItemContent(context, candidateData.isNotEmpty);
            },
          ),
        ),
        // Recursive children
        ...children.map((child) => _HierarchyItem(
              note: child,
              allNotes: allNotes,
              onDragStarted: onDragStarted,
              onDragEnded: onDragEnded,
              onParentChanged: onParentChanged,
              draggedNoteId: draggedNoteId,
              depth: depth + 1,
            )),
      ],
    );
  }

  Widget _buildItemContent(BuildContext context, bool isTargeted) {
    return Container(
      margin: EdgeInsets.only(left: depth * 20.0, top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isTargeted
            ? const Color(0xFFFF6B00).withOpacity(0.2)
            : const Color(0xFF252525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTargeted ? const Color(0xFFFF6B00) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.drag_indicator,
            size: 18,
            color:
                isTargeted ? const Color(0xFFFF6B00) : const Color(0xFF6A6A6A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note.title.isEmpty ? 'Untitled' : note.title,
              style: TextStyle(
                color: isTargeted
                    ? const Color(0xFFFF6B00)
                    : const Color(0xFFEDEDED),
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
