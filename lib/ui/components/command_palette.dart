import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krag_app/services/search_service.dart';
import 'package:krag_app/stores/notes_store.dart';
import 'package:krag_app/stores/tabs_store.dart';

// Simple provider for SearchService
final searchServiceProvider = Provider<SearchService>((ref) => SearchService());

class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => const CommandPalette(),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    // Initialize search service if needed
    ref.read(searchServiceProvider).initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await ref.read(searchServiceProvider).search(query);
      if (mounted) {
        setState(() => _results = results);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _selectNote(String noteId) {
    ref.read(notesStoreProvider.notifier).setCurrentNoteId(noteId);
    ref.read(tabsStoreProvider.notifier).addTab(noteId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesStoreProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 100),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A3A3A)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search Input
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _handleSearch,
                  style:
                      const TextStyle(color: Color(0xFFEDEDED), fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search notes...',
                    hintStyle: const TextStyle(color: Color(0xFFA0A0A0)),
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFFA0A0A0)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    suffixIcon: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF3A3A3A)),

                // Results List
                if (_results.isEmpty &&
                    _controller.text.isNotEmpty &&
                    !_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No results found',
                      style: TextStyle(color: Color(0xFFA0A0A0)),
                    ),
                  )
                else if (_results.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final noteId = _results[index];
                        final note = notesState.notes[noteId];
                        final title = note?.title ?? 'Untitled';

                        return InkWell(
                          onTap: () => _selectNote(noteId),
                          hoverColor: const Color(0xFFFF6B00).withOpacity(0.1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.description_outlined,
                                    size: 18, color: Color(0xFFA0A0A0)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      color: Color(0xFFEDEDED),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.keyboard_return,
                                    size: 16, color: Color(0xFF3A3A3A)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Keyboard Listener Wrapper for MainLayout
class CommandPaletteListener extends StatelessWidget {
  final Widget child;

  const CommandPaletteListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            CommandPalette.show(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            CommandPalette.show(context),
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}
