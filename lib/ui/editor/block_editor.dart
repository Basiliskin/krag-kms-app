import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../../stores/notes_store.dart';
import '../../stores/tabs_store.dart';
import '../../types/index.dart';
import '../../utils/logger.dart';
import '../../utils/editor_migration_engine.dart';
import 'editable_code_block_component.dart';
import 'lock_block_component.dart';
import 'wrapped_standard_block_component.dart';
import 'package:krag_app/ui/editor/document_delta_repair.dart';

CommandShortcutEvent _buildKragPasteCommand() {
  return CommandShortcutEvent(
    key: 'paste the content',
    getDescription: () => 'paste content',
    command: 'ctrl+v',
    macOSCommand: 'cmd+v',
    handler: (EditorState editorState) {
      final selection = editorState.selection?.normalized;
      if (selection == null) return KeyEventResult.ignored;
      () async {
        final data = await AppFlowyClipboard.getData();
        final text = data.text?.trim();
        if (text == null || text.isEmpty) return;
        try {
          final parsed = EditorMigrationEngine.markdownToAppFlowy(text);
          if (parsed.root.children.isEmpty) return;
          var path = selection.end.path.next;
          final node = editorState.document.nodeAtPath(selection.end.path);
          final delta = node?.delta;
          if (delta != null && delta.toPlainText().trim().isEmpty) {
            path = selection.end.path;
          }
          final transaction = editorState.transaction;
          var afterPath = path;
          for (var i = 0; i < parsed.root.children.length - 1; i++) {
            afterPath = afterPath.next;
          }
          final offset = parsed.root.children.lastOrNull?.delta?.length ?? 0;
          transaction
            ..insertNodes(path, parsed.root.children)
            ..afterSelection = Selection.collapsed(
              Position(path: afterPath, offset: offset),
            );
          editorState.apply(transaction);
          repairDocumentDeltas(editorState.document);
        } catch (e) {
          KragLogger.error(LogDomain.general, 'Paste markdown failed', e);
        }
      }();
      return KeyEventResult.handled;
    },
  );
}

EditorState _createDefaultCodeBlockEditorState() {
  final codeNode = Node(
    type: 'code',
    id: const Uuid().v4(),
    attributes: {
      'language': 'plaintext',
    },
  );
  final document = Document(
    root: Node(
      type: 'page',
      id: const Uuid().v4(),
      children: [codeNode],
    ),
  );
  return EditorState(document: document);
}

List<CommandShortcutEvent> _buildCustomCommandShortcuts() {
  return [
    ...standardCommandShortcutEvents.where(
      (e) => e.key != 'paste the content' && e.key != 'insert new line',
    ),
    _buildKragPasteCommand(),
    CommandShortcutEvent(
      key: 'insert new line',
      getDescription: () => 'insert new line(code block)',
      command: 'enter',
      macOSCommand: 'enter',
      handler: (EditorState editorState) {
        final selection = editorState.selection?.normalized;
        if (selection == null) return KeyEventResult.ignored;
        final node = editorState.document.nodeAtPath(selection.end.path);
        if (node == null) return KeyEventResult.ignored;
        if (node.type == 'code') {
          final delta = node.delta;
          if (delta != null && selection.end.offset >= delta.length - 1) {
            final transaction = editorState.transaction;
            editorState.apply(transaction);
            return KeyEventResult.handled;
          }
        }
        final transaction = editorState.transaction;
        final newPath = selection.end.path.next;
        final newCodeBlock = Node(
          type: 'code',
          id: const Uuid().v4(),
          attributes: {
            'language': 'plaintext',
          },
        );
        transaction
          ..insertNode(newPath, newCodeBlock)
          ..afterSelection = Selection.collapsed(
            Position(path: newPath, offset: 1),
          );
        editorState.apply(transaction);
        return KeyEventResult.handled;
      },
    ),
  ];
}

class BlockEditor extends ConsumerStatefulWidget {
  final String noteId;
  const BlockEditor({super.key, required this.noteId});
  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<BlockEditor> {
  EditorState? _editorState;
  StreamSubscription? _subscription;
  Timer? _debounceTimer;
  bool _isLoading = true;
  bool _isInitializing = false;
  String? _lastInitializedContent;
  String? _lastSentContent;
  late final Map<String, BlockComponentBuilder> _blockComponentBuilders;
  @override
  void initState() {
    super.initState();
    _blockComponentBuilders = _buildBlockComponentBuilders();
    _initializeEditor();
  }

  @override
  void didUpdateWidget(covariant BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _disposeEditor(saveToNoteId: oldWidget.noteId);
      setState(() {
        _isLoading = true;
      });
      _initializeEditor();
    }
  }

  @override
  void dispose() {
    _disposeEditor(saveToNoteId: widget.noteId);
    super.dispose();
  }

  void _disposeEditor({String? saveToNoteId}) {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      if (saveToNoteId != null) {
        _performSave(saveToNoteId);
      }
    }
    _subscription?.cancel();
    _editorState?.dispose();
    _editorState = null;
    _subscription = null;
    _debounceTimer = null;
    _lastInitializedContent = null;
    _lastSentContent = null;
    _isInitializing = false;
  }

  void _performSave(String targetNoteId) {
    if (_editorState == null) return;
    KragLogger.info(LogDomain.general, '[_performSave] : $targetNoteId');

    try {
      final content =
          EditorMigrationEngine.appFlowyToMarkdown(_editorState!.document);
      if (content == _lastSentContent) return;
      _lastSentContent = content;
      ref
          .read(notesStoreProvider.notifier)
          .updateNoteContent(targetNoteId, content);
    } catch (err) {
      KragLogger.error(LogDomain.general, 'Failed to save editor content', err);
    }
  }

  Future<void> _initializeEditor() async {
    final targetNoteId = widget.noteId;
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    KragLogger.info(LogDomain.general, '[_initializeEditor]: $targetNoteId');

    if (!mounted) return;
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }

    try {
      await ref
          .read(notesStoreProvider.notifier)
          .fetchNoteContent(targetNoteId);
      if (!mounted || widget.noteId != targetNoteId) {
        KragLogger.warn(
          LogDomain.general,
          'BlockEditor:Aborting init for $targetNoteId-switched or unmounted',
        );
        return;
      }
      final updatedNote = ref.read(notesStoreProvider).notes[targetNoteId];
      if (updatedNote != null && updatedNote.content.isNotEmpty) {
        _initEditorWithContent(updatedNote.content);
      } else {
        _editorState = _createDefaultCodeBlockEditorState();
        _setupSubscription();
      }
    } catch (e) {
      KragLogger.error(
        LogDomain.general,
        'BlockEditor:Initialization error for $targetNoteId',
        e,
      );
      _editorState = _createDefaultCodeBlockEditorState();
      _setupSubscription();
    } finally {
      if (mounted && widget.noteId == targetNoteId) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupSubscription() {
    if (_editorState != null && _subscription == null && !_isInitializing) {
      _subscription = _editorState!.transactionStream.listen((event) {
        _onDocumentChange();
      });
    }
  }

  void _initEditorWithContent(String content) {
    if (_lastInitializedContent == content && _editorState != null) {
      return;
    }
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _isInitializing = true;
    _lastInitializedContent = content;
    _lastSentContent = content;
    try {
      if (content.trim().isEmpty) {
        _editorState = _createDefaultCodeBlockEditorState();
        _setupSubscription();
        return;
      }
      final document = EditorMigrationEngine.migrate(content);
      repairDocumentDeltas(document);
      if (document.root.children.isEmpty) {
        KragLogger.warn(
          LogDomain.general,
          'Parsed document has no children,adding default code block',
        );
        final defaultCodeBlock = Node(
          type: 'code',
          id: const Uuid().v4(),
          attributes: {
            'language': 'plaintext',
          },
        );
        document.root.children.add(defaultCodeBlock);
      }
      _editorState = EditorState(document: document);
      _setupSubscription();
    } catch (e) {
      KragLogger.error(
          LogDomain.general, 'Failed to initialize editor content', e);
      _editorState = _createDefaultCodeBlockEditorState();
      if (content.isNotEmpty) {
        try {
          final plainText = content.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
          final textToInsert = plainText.isNotEmpty ? plainText : content;
          final transaction = _editorState!.transaction;
          transaction.insertText(
            _editorState!.document.root.children.first,
            0,
            textToInsert,
          );
          _editorState!.apply(transaction);
        } catch (_) {}
      }
      _setupSubscription();
    } finally {
      _isInitializing = false;
    }
  }

  void _onDocumentChange() {
    if (_editorState == null) return;
    if (_isInitializing) return;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _performSave(widget.noteId);
    });
  }

  Map<String, BlockComponentBuilder> _buildBlockComponentBuilders() {
    try {
      final builders = Map<String, BlockComponentBuilder>.from(
          standardBlockComponentBuilderMap);
      final typesToWrap = [
        'paragraph',
        'heading',
        'bulleted_list',
        'numbered_list',
        'todo_list',
        'quote',
        'code',
        'code_block',
      ];
      builders['code'] = EditableCodeBlockComponentBuilder(
        configuration: BlockComponentConfiguration(
          padding: (node) => const EdgeInsets.symmetric(vertical: 0),
        ),
      );
      builders['code_block'] = EditableCodeBlockComponentBuilder(
        configuration: BlockComponentConfiguration(
          padding: (node) => const EdgeInsets.symmetric(vertical: 0),
        ),
      );
      builders['lock'] = LockBlockComponentBuilder(
        configuration: BlockComponentConfiguration(
          padding: (node) => const EdgeInsets.symmetric(vertical: 0),
        ),
      );
      for (final type in typesToWrap) {
        if (builders.containsKey(type)) {
          final bool hasInternalPadding =
              type == 'code' || type == 'code_block' || type == 'lock';
          builders[type] = WrappedStandardBlockComponentBuilder(
            originalBuilder: builders[type]!,
            configuration: const BlockComponentConfiguration().copyWith(
              padding: (node) => EdgeInsets.symmetric(
                vertical: hasInternalPadding ? 0 : 2,
              ),
            ),
          );
        }
      }
      return builders;
    } catch (e) {
      KragLogger.error(
        LogDomain.general,
        'Failed to build block component builders',
        e,
      );
      return standardBlockComponentBuilderMap;
    }
  }

  void reloadWithContent(String content) {
    _lastInitializedContent = content;
    _initEditorWithContent(content);
  }

  String _getCurrentEditorContent() {
    if (_editorState == null) return '';
    try {
      return EditorMigrationEngine.appFlowyToMarkdown(_editorState!.document);
    } catch (e) {
      return '';
    }
  }

  Future<void> _copyNoteAsMarkdown() async {
    final markdown = _getCurrentEditorContent();
    if (markdown.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note is empty')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: markdown));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied note as Markdown')),
      );
    }
  }

  Future<void> _pasteMarkdownToNote() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
      return;
    }
    if (_editorState == null) return;
    try {
      final parsed = EditorMigrationEngine.markdownToAppFlowy(text);
      if (parsed.root.children.isEmpty) return;
      final transaction = _editorState!.transaction;
      final root = _editorState!.document.root;
      int index = root.children.length;
      for (final node in parsed.root.children) {
        transaction.insertNode([index], node);
        index++;
      }
      _editorState!.apply(transaction);
      repairDocumentDeltas(_editorState!.document);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pasted Markdown as blocks')),
        );
      }
    } catch (e) {
      KragLogger.error(LogDomain.general, 'Paste markdown failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paste failed:${e.toString()}')),
        );
      }
    }
  }

  void _clearEditorContent() {
    if (_editorState == null) return;
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    setState(() {
      _editorState = _createDefaultCodeBlockEditorState();
      try {
        final content =
            EditorMigrationEngine.appFlowyToMarkdown(_editorState!.document);
        _lastInitializedContent = content;
        _lastSentContent = content;
      } catch (e) {
        KragLogger.error(
          LogDomain.general,
          'Failed to calculate cleared content hash',
          e,
        );
      }
      _setupSubscription();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note content cleared locally'),
          backgroundColor: Color(0xFF3A3A3A),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleManualSave() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      KragLogger.info(LogDomain.general,
          '[_handleManualSave] : ${_debounceTimer?.isActive}');
      if (_debounceTimer?.isActive ?? false) {
        _debounceTimer!.cancel();
      }
      _performSave(widget.noteId);
      await ref.read(notesStoreProvider.notifier).saveCurrentNote();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Note saved successfully'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to save:$e'),
            backgroundColor: const Color(0xFFE57373),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notesStoreProvider, (previous, next) {
      final nextNote = next.notes[widget.noteId];
      if (nextNote == null) return;
      if (_isInitializing) return;

      final previousNote = previous?.notes[widget.noteId];
      bool isRemoteUpdate = false;

      // 1. Check for version increase (strong signal of remote update)
      if (previousNote != null) {
        final versionIncreased = (nextNote.v ?? 0) > (previousNote.v ?? 0);
        if (versionIncreased) {
          isRemoteUpdate = true;
        }
      }

      // 2. Check for content mismatch that isn't what we just sent
      final currentEditorContent = _getCurrentEditorContent();
      if (nextNote.content != currentEditorContent &&
          nextNote.content != _lastSentContent) {
        isRemoteUpdate = true;
      }

      if (isRemoteUpdate) {
        KragLogger.info(
          LogDomain.general,
          'BlockEditor:Remote content update detected for ${widget.noteId} (v${nextNote.v}). Re-initializing.',
        );
        _initEditorWithContent(nextNote.content);
        setState(() {});
      } else if (nextNote.content == currentEditorContent) {
        // Ensure tracking variables are in sync if content matches
        _lastInitializedContent = nextNote.content;
        _lastSentContent = nextNote.content;
      }
    });
    final notesState = ref.watch(notesStoreProvider);
    final isSkeleton = notesState.skeletonNoteIds.contains(widget.noteId);
    final showSkeleton = _isLoading ||
        isSkeleton ||
        notesState.isHydrating ||
        _editorState == null;
    if (showSkeleton) {
      return Column(
        children: [
          _buildHeader(isSkeleton: true),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SkeletonLine(width: double.infinity, height: 20),
                  const SizedBox(height: 16),
                  const _SkeletonLine(width: double.infinity, height: 16),
                  _SkeletonLine(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: 16,
                  ),
                  _SkeletonLine(
                    width: MediaQuery.of(context).size.width * 0.6,
                    height: 16,
                  ),
                  const SizedBox(height: 16),
                  const _SkeletonLine(width: double.infinity, height: 16),
                  _SkeletonLine(
                    width: MediaQuery.of(context).size.width * 0.9,
                    height: 16,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading content...',
                        style:
                            TextStyle(color: Color(0xFF6A6A6A), fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _buildBottomToolbar(),
        ],
      );
    }
    if (_editorState!.document.root.children.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B00)));
    }
    final commandShortcutEvents = _buildCustomCommandShortcuts();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(isSkeleton: false),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: AppFlowyEditor(
                  key: ValueKey('editor_${widget.noteId}'),
                  editorState: _editorState!,
                  editable: true,
                  autoFocus: false,
                  commandShortcutEvents: commandShortcutEvents,
                  editorStyle: EditorStyle.mobile(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 48 + 16),
                    cursorColor: const Color(0xFFFF6B00),
                    selectionColor: const Color.fromRGBO(255, 107, 0, 0.3),
                  ).copyWith(
                    padding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                    textStyleConfiguration: const TextStyleConfiguration(
                      text: TextStyle(color: Color(0xFFEDEDED), fontSize: 16),
                      bold: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEDEDED),
                      ),
                      code: TextStyle(
                        fontFamily: 'monospace',
                        backgroundColor: Color(0xFF2A2A2A),
                        color: Color(0xFFEDEDED),
                      ),
                    ),
                  ),
                  blockComponentBuilders: _blockComponentBuilders,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: _buildBottomToolbar(),
        ),
      ],
    );
  }

  Widget _buildHeader({required bool isSkeleton}) {
    final notesStore = ref.watch(notesStoreProvider);
    final note = notesStore.notes[widget.noteId];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetadataBadges(note),
          const SizedBox(height: 8),
          if (isSkeleton)
            Container(
              height: 40,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
            )
          else
            TextFormField(
              key: ValueKey('title_${widget.noteId}_${note?.v ?? 0}'),
              initialValue: note?.title,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEDEDED),
              ),
              decoration: const InputDecoration(
                hintText: 'Untitled',
                hintStyle: TextStyle(color: Color(0xFF3A3A3A)),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                ref
                    .read(notesStoreProvider.notifier)
                    .updateNoteTitle(widget.noteId, value);
              },
            ),
          const Divider(color: Color(0xFF2A2A2A), height: 32),
        ],
      ),
    );
  }

  Widget _buildMetadataBadges(Note? note) {
    final tags = note?.tags ?? [];
    final labels = note?.labels ?? [];
    final hasMetadata = tags.isNotEmpty || labels.isNotEmpty;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!hasMetadata)
            _buildBadge(
              label: 'Settings',
              icon: Icons.settings,
              backgroundColor: const Color(0xFF2A2A2A),
              onTap: () => _showMetadataManagementDialog(context),
            )
          else ...[
            ...tags.map(
              (tag) => _buildBadge(
                label: tag,
                icon: Icons.tag,
                color: const Color(0xFFFF6B00),
                onTap: () => _showMetadataManagementDialog(context),
              ),
            ),
            ...labels.map(
              (label) => _buildBadge(
                label: label,
                icon: Icons.label_outline,
                color: const Color(0xFFFF6B00),
                onTap: () => _showMetadataManagementDialog(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required IconData icon,
    Color? color,
    Color backgroundColor = const Color(0xFF2A2A2A),
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: color != null
              ? Border.all(color: color.withOpacity(0.3))
              : Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color ?? const Color(0xFFA0A0A0)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? const Color(0xFFEDEDED),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMetadataManagementDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => _MetadataManagementDialog(noteId: widget.noteId));
  }

  Widget _buildBottomToolbar() {
    final notesState = ref.watch(notesStoreProvider);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () {
                  ref.read(notesStoreProvider.notifier).createNote();
                  ref
                      .read(tabsStoreProvider.notifier)
                      .ensureCurrentNoteInTabs();
                },
                icon: const Icon(Icons.add),
                color: const Color.fromARGB(255, 75, 208, 18),
                tooltip: 'New Note',
              ),
              IconButton(
                onPressed: _copyNoteAsMarkdown,
                icon: const Icon(Icons.copy),
                color: const Color.fromARGB(255, 223, 202, 9),
                tooltip: 'Copy Markdown',
              ),
              IconButton(
                onPressed: _pasteMarkdownToNote,
                icon: const Icon(Icons.content_paste),
                color: const Color.fromARGB(255, 9, 222, 254),
                tooltip: 'Paste Markdown',
              ),
              IconButton(
                onPressed: _editorState == null ? null : _clearEditorContent,
                icon: const Icon(Icons.layers_clear),
                color: const Color(0xFFE57373),
                tooltip: 'Clear Content(Local Only)',
              ),
              if (notesState.isSyncing)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color.fromARGB(255, 7, 117, 190),
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: _handleManualSave,
                  icon: const Icon(Icons.save),
                  color: const Color.fromARGB(255, 21, 238, 5),
                  tooltip: 'Save',
                ),
              IconButton(
                onPressed: _editorState == null
                    ? null
                    : () => _editorState!.undoManager.undo(),
                icon: const Icon(Icons.undo),
                color: const Color(0xFFA0A0A0),
                disabledColor: const Color(0xFF505050),
                tooltip: 'Undo',
              ),
              IconButton(
                onPressed: _editorState == null
                    ? null
                    : () => _editorState!.undoManager.redo(),
                icon: const Icon(Icons.redo),
                color: const Color(0xFFA0A0A0),
                disabledColor: const Color(0xFF505050),
                tooltip: 'Redo',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataManagementDialog extends ConsumerStatefulWidget {
  final String noteId;
  const _MetadataManagementDialog({required this.noteId});
  @override
  ConsumerState<_MetadataManagementDialog> createState() =>
      _MetadataManagementDialogState();
}

class _MetadataManagementDialogState
    extends ConsumerState<_MetadataManagementDialog> {
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();
  @override
  void dispose() {
    _tagController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty) return;
    final note = ref.read(notesStoreProvider).notes[widget.noteId];
    if (note == null) return;
    if (!note.tags.contains(tag)) {
      final updatedTags = [...note.tags, tag];
      ref
          .read(notesStoreProvider.notifier)
          .updateNoteTags(widget.noteId, updatedTags);
    }
    _tagController.clear();
  }

  void _removeTag(String tag) {
    final note = ref.read(notesStoreProvider).notes[widget.noteId];
    if (note == null) return;
    final updatedTags = note.tags.where((t) => t != tag).toList();
    ref
        .read(notesStoreProvider.notifier)
        .updateNoteTags(widget.noteId, updatedTags);
  }

  void _addLabel(String value) {
    final label = value.trim();
    if (label.isEmpty) return;
    final note = ref.read(notesStoreProvider).notes[widget.noteId];
    if (note == null) return;
    if (!note.labels.contains(label)) {
      final updatedLabels = [...note.labels, label];
      ref
          .read(notesStoreProvider.notifier)
          .updateNoteLabels(widget.noteId, updatedLabels);
    }
    _labelController.clear();
  }

  void _removeLabel(String label) {
    final note = ref.read(notesStoreProvider).notes[widget.noteId];
    if (note == null) return;
    final updatedLabels = note.labels.where((l) => l != label).toList();
    ref
        .read(notesStoreProvider.notifier)
        .updateNoteLabels(widget.noteId, updatedLabels);
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(notesStoreProvider).notes[widget.noteId];
    if (note == null) return const SizedBox.shrink();
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Manage Metadata',
                  style: TextStyle(
                    color: Color(0xFFEDEDED),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFFA0A0A0)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: 'Tags',
              icon: Icons.tag,
              items: note.tags,
              controller: _tagController,
              onAdd: _addTag,
              onRemove: _removeTag,
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: 'Labels',
              icon: Icons.label_outline,
              items: note.labels,
              controller: _labelController,
              onAdd: _addLabel,
              onRemove: _removeLabel,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<String> items,
    required TextEditingController controller,
    required Function(String) onAdd,
    required Function(String) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFFFF6B00)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Add $title...',
            hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
            filled: true,
            fillColor: const Color(0xFF121212),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 1),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add, color: Color(0xFFFF6B00)),
              onPressed: () => onAdd(controller.text),
            ),
          ),
          onSubmitted: onAdd,
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map(
                  (item) => Chip(
                    label: Text(
                      item,
                      style: const TextStyle(
                          color: Color(0xFFEDEDED), fontSize: 12),
                    ),
                    backgroundColor: const Color(0xFF2A2A2A),
                    deleteIcon: const Icon(Icons.close,
                        size: 14, color: Color(0xFFA0A0A0)),
                    onDeleted: () => onRemove(item),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  const _SkeletonLine({required this.width, required this.height});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
