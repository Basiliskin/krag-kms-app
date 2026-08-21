import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/notes_store.dart';

class FilterDialog extends ConsumerStatefulWidget {
  const FilterDialog({super.key});

  @override
  ConsumerState<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends ConsumerState<FilterDialog> {
  late List<String> _selectedTags;
  late List<String> _selectedLabels;
  String _tagSearch = '';
  String _labelSearch = '';

  @override
  void initState() {
    super.initState();
    final state = ref.read(notesStoreProvider);
    _selectedTags = List.from(state.activeFilterTags);
    _selectedLabels = List.from(state.activeFilterLabels);
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesStoreProvider).notes;

    // Aggregate unique tags and labels from all notes
    final allTags = notes.values.expand((n) => n.tags).toSet().toList()..sort();
    final allLabels = notes.values.expand((n) => n.labels).toSet().toList()
      ..sort();

    final filteredTags = allTags
        .where((t) => t.toLowerCase().contains(_tagSearch.toLowerCase()))
        .toList();
    final filteredLabels = allLabels
        .where((l) => l.toLowerCase().contains(_labelSearch.toLowerCase()))
        .toList();

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      insetPadding: isMobile
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: isMobile
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isMobile ? MediaQuery.of(context).size.width : 500,
        height: isMobile
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter Notes',
                  style: TextStyle(
                    color: Color(0xFFEDEDED),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFFA0A0A0)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  _buildSectionHeader('Tags'),
                  _buildSearchField('Search tags...',
                      (val) => setState(() => _tagSearch = val)),
                  const SizedBox(height: 12),
                  _buildChipList(filteredTags, _selectedTags, (tag) {
                    setState(() {
                      if (_selectedTags.contains(tag)) {
                        _selectedTags.remove(tag);
                      } else {
                        _selectedTags.add(tag);
                      }
                    });
                  }),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Labels'),
                  _buildSearchField('Search labels...',
                      (val) => setState(() => _labelSearch = val)),
                  const SizedBox(height: 12),
                  _buildChipList(filteredLabels, _selectedLabels, (label) {
                    setState(() {
                      if (_selectedLabels.contains(label)) {
                        _selectedLabels.remove(label);
                      } else {
                        _selectedLabels.add(label);
                      }
                    });
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedTags.clear();
                        _selectedLabels.clear();
                      });
                    },
                    child: const Text(
                      'Reset All',
                      style: TextStyle(color: Color(0xFFA0A0A0)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(notesStoreProvider.notifier).updateFilters(
                            tags: _selectedTags,
                            labels: _selectedLabels,
                          );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFEDEDED),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSearchField(String hint, ValueChanged<String> onChanged) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6A6A6A)),
        prefixIcon:
            const Icon(Icons.search, color: Color(0xFF6A6A6A), size: 20),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildChipList(List<String> items, List<String> selectedItems,
      ValueChanged<String> onToggle) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No items found',
          style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 14),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final isSelected = selectedItems.contains(item);
        return FilterChip(
          label: Text(item),
          selected: isSelected,
          onSelected: (_) => onToggle(item),
          backgroundColor: const Color(0xFF2A2A2A),
          selectedColor: const Color(0xFFFF6B00).withOpacity(0.2),
          checkmarkColor: const Color(0xFFFF6B00),
          labelStyle: TextStyle(
            color:
                isSelected ? const Color(0xFFFF6B00) : const Color(0xFFA0A0A0),
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFFFF6B00)
                  : const Color(0xFF3A3A3A),
            ),
          ),
        );
      }).toList(),
    );
  }
}
