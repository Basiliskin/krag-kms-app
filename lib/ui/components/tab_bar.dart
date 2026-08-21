import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/notes_store.dart';
import '../../stores/tabs_store.dart';

class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openTabIds = ref.watch(tabsStoreProvider);
    final notesState = ref.watch(notesStoreProvider);
    final currentNoteId = notesState.currentNoteId;

    if (openTabIds.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: openTabIds.length,
              itemBuilder: (context, index) {
                final noteId = openTabIds[index];
                final note = notesState.notes[noteId];

                // A tab should show a skeleton if:
                // 1. The note is explicitly in the skeleton set
                // 2. The note object hasn't been loaded into the map yet (null)
                // 3. The store is currently performing initial hydration
                // 4. The store is still loading the initial index
                final isSkeleton =
                    notesState.skeletonNoteIds.contains(noteId) ||
                        note == null ||
                        notesState.isHydrating ||
                        notesState.isLoadingIndex;

                final isActive = noteId == currentNoteId;

                return InkWell(
                  onTap: () {
                    ref
                        .read(notesStoreProvider.notifier)
                        .setCurrentNoteId(noteId);
                  },
                  child: Container(
                    width: 160,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF2A2A2A)
                          : Colors.transparent,
                      border: const Border(
                        right: BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: isSkeleton
                              ? Center(
                                  child: Container(
                                    height: 12,
                                    width: 80,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3A3A3A),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                )
                              : Text(
                                  note.title.isNotEmpty == true
                                      ? note.title
                                      : 'Untitled',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFFEDEDED)
                                        : const Color(0xFFA0A0A0),
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            ref
                                .read(tabsStoreProvider.notifier)
                                .closeTab(noteId);
                          },
                          borderRadius: BorderRadius.circular(4),
                          hoverColor: const Color(0xFF3A3A3A),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: isActive
                                  ? const Color(0xFFEDEDED)
                                  : const Color(0xFFA0A0A0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          InkWell(
            onTap: () {
              ref.read(notesStoreProvider.notifier).createNote();
              Future.microtask(() => ref
                  .read(tabsStoreProvider.notifier)
                  .ensureCurrentNoteInTabs());
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF2A2A2A)),
                ),
              ),
              child: const Icon(
                Icons.add,
                color: Color(0xFFA0A0A0),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
