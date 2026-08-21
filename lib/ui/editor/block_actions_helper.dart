import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../../utils/logger.dart';
import 'package:uuid/uuid.dart';
import '../../utils/delta_insert_utils.dart';

class BlockActionsHelper {
  final BuildContext context;
  final Node node;
  final VoidCallback onUpdate;
  EditorState? _cachedEditorState;

  BlockActionsHelper({
    required this.context,
    required this.node,
    required this.onUpdate,
  }) {
    _cacheEditorState();
    _cacheBlockEditorState();
  }

  void _cacheEditorState() {
    if (!context.mounted) return;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is AppFlowyEditor) {
        _cachedEditorState = widget.editorState;
        return false;
      }
      return true;
    });
  }

  void _cacheBlockEditorState() {
    if (!context.mounted) return;
    context.visitAncestorElements((element) {
      if (element.widget.runtimeType.toString().contains('BlockEditor')) {
        return false;
      }
      return true;
    });
  }

  EditorState? get editorState {
    try {
      if (_cachedEditorState != null) {
        return _cachedEditorState;
      }
      if (!context.mounted) return null;
      EditorState? result;
      try {
        context.visitAncestorElements((element) {
          final widget = element.widget;
          if (widget is AppFlowyEditor) {
            result = widget.editorState;
            _cachedEditorState = result;
            return false;
          }
          return true;
        });
      } catch (e) {
        return _cachedEditorState;
      }
      return result ?? _cachedEditorState;
    } catch (e) {
      KragLogger.error(LogDomain.general, 'Error getting editor state', e);
      return null;
    }
  }

  List<Map<String, dynamic>> get blockTypes {
    final isLocked = node.attributes['custom_locked'] == true;
    return [
      // Code block FIRST - default/preferred block type
      {'type': 'code', 'icon': Icons.code, 'label': 'Code Block'},
      {'type': 'paragraph', 'icon': Icons.text_fields, 'label': 'Paragraph'},
      {
        'type': 'heading',
        'icon': Icons.title,
        'label': 'Heading 1',
        'level': 1
      },
      {
        'type': 'heading',
        'icon': Icons.title,
        'label': 'Heading 2',
        'level': 2
      },
      {
        'type': 'heading',
        'icon': Icons.title,
        'label': 'Heading 3',
        'level': 3
      },
      {
        'type': 'bulleted_list',
        'icon': Icons.format_list_bulleted,
        'label': 'Bullet List'
      },
      {
        'type': 'numbered_list',
        'icon': Icons.format_list_numbered,
        'label': 'Numbered List'
      },
      {'type': 'todo_list', 'icon': Icons.check_box, 'label': 'Todo List'},
      {'type': 'quote', 'icon': Icons.format_quote, 'label': 'Quote'},
      {'type': 'divider', 'icon': Icons.horizontal_rule, 'label': 'Divider'},
      {
        'type': 'lock',
        'icon': isLocked ? Icons.lock_open : Icons.lock,
        'label': isLocked ? 'Unlock Block' : 'Lock Block',
      },
    ];
  }

  Widget buildActionButtons({
    required bool isHovered,
    required bool showBlockTypePicker,
    required VoidCallback onToggleBlockTypePicker,
  }) {
    if (!isHovered) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: Icons.add,
          tooltip: 'Add code block below',
          onPressed: addBlockBelow,
        ),
        const SizedBox(height: 4),
        _buildActionButton(
          icon: Icons.more_horiz,
          tooltip: 'Change block type',
          onPressed: onToggleBlockTypePicker,
        ),
      ],
    );
  }

  Widget buildDragHandle() {
    return _buildDragHandle();
  }

  Widget buildBlockTypePicker() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: Colors.transparent,
      child: Container(
        width: 200,
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: blockTypes.length,
          itemBuilder: (context, index) {
            final blockType = blockTypes[index];
            return InkWell(
              onTap: () {
                changeBlockType(
                  blockType['type'] as String,
                  level: blockType['level'] as int?,
                );
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      blockType['icon'] as IconData,
                      size: 18,
                      color: const Color(0xFFA0A0A0),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      blockType['label'] as String,
                      style: const TextStyle(
                        color: Color(0xFFEDEDED),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

// FIX: Add Copy button to mobile action sheet
// Replace the buildMobileActionSheet method in your BlockActionsHelper class with this:

  Widget buildMobileActionSheet(BuildContext sheetContext) {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Changed from Row to Wrap to accommodate 5 buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceEvenly,
            children: [
              _buildMobileActionButton(
                icon: Icons.add,
                label: 'Add Code',
                onTap: () {
                  addBlockBelow();
                  Navigator.pop(sheetContext);
                },
              ),
              _buildMobileActionButton(
                icon: Icons.reorder,
                label: 'Reorder',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReorderPanel();
                },
              ),
              // NEW: Copy button added here
              _buildMobileActionButton(
                icon: Icons.copy,
                label: 'Copy',
                onTap: () {
                  copyBlockContent();
                  Navigator.pop(sheetContext);
                },
              ),
              _buildMobileActionButton(
                icon: Icons.more_horiz,
                label: 'Convert',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showBlockTypeSheet(sheetContext);
                },
              ),
              _buildMobileActionButton(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: const Color(0xFFE57373),
                onTap: () {
                  deleteBlock();
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBlockTypeSheet(BuildContext originalContext) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Convert to',
              style: TextStyle(
                color: Color(0xFFEDEDED),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: blockTypes.length,
                itemBuilder: (context, index) {
                  final type = blockTypes[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        type['icon'] as IconData,
                        color: const Color(0xFFA0A0A0),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      type['label'] as String,
                      style: const TextStyle(color: Color(0xFFEDEDED)),
                    ),
                    onTap: () {
                      changeBlockType(
                        type['type'] as String,
                        level: type['level'] as int?,
                      );
                      Navigator.pop(sheetContext);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReorderPanel() {
    final editor = editorState;
    if (editor == null) {
      KragLogger.warn(LogDomain.general, 'Reorder panel: Editor state is null');
      return;
    }
    if (!context.mounted) return;

    KragLogger.info(LogDomain.general,
        'Opening reorder panel. Total blocks: ${editor.document.root.children.length}');

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reorder',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(dialogContext).size.width * 0.85,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: _ReorderPanelWidget(
                editor: editor,
                selectedNodeId: node.id,
                onUpdate: onUpdate,
                onClose: () {
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    );
  }

  Widget _buildMobileActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child:
                  Icon(icon, color: color ?? const Color(0xFFEDEDED), size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color ?? const Color(0xFFA0A0A0),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(icon, color: const Color(0xFFA0A0A0)),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: const Icon(Icons.reorder, color: Color(0xFFA0A0A0)),
        tooltip: 'Reorder blocks',
        onPressed: _showReorderPanel,
      ),
    );
  }

  Widget buildDeleteButton() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: const Icon(Icons.delete_outline, color: Color(0xFFE57373)),
        tooltip: 'Delete block',
        onPressed: deleteBlock,
      ),
    );
  }

  Widget buildRightActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildDragHandle(),
        const SizedBox(height: 4),
        buildDeleteButton(),
      ],
    );
  }

  /// Copy current block content (plain text) to clipboard. Works for any block
  /// with text (paragraph, heading, code, list, etc.).
  void copyBlockContent() {
    final text = _extractTextFromNode(node).trim();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Block copied to clipboard'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF2A2A2A),
        ),
      );
    }
  }

  /// Single-row compact toolbar for floating overlay (desktop). Does not affect
  /// block layout height; used in Stack/Positioned so blocks stay compact.
  /// Includes Copy for all blocks (replaces code block's own copy button).
  Widget buildCompactFloatingToolbar({
    required VoidCallback onToggleBlockTypePicker,
  }) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(6),
      color: const Color(0xFF1E1E1E),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              icon: Icons.add,
              tooltip: 'Add code block below',
              onPressed: addBlockBelow,
            ),
            const SizedBox(width: 2),
            _buildActionButton(
              icon: Icons.more_horiz,
              tooltip: 'Change block type',
              onPressed: onToggleBlockTypePicker,
            ),
            const SizedBox(width: 2),
            _buildActionButton(
              icon: Icons.copy,
              tooltip: 'Copy block',
              onPressed: copyBlockContent,
            ),
            const SizedBox(width: 2),
            _buildDragHandle(),
            const SizedBox(width: 2),
            buildDeleteButton(),
          ],
        ),
      ),
    );
  }

  void addBlockBelow() {
    try {
      final editor = editorState;
      if (editor == null) {
        KragLogger.warn(
            LogDomain.general, 'Cannot add block: editor state is null');
        return;
      }

      // ✅ INSERT CODE BLOCK INSTEAD OF PARAGRAPH
      final transaction = editor.transaction;
      final path = node.path;

      // Create code block with minimum height ensured by newline character
      final newNode = Node(
        type: 'code',
        id: const Uuid().v4(),
        // attributes: {'language': 'plaintext', 'delta': getDeltaNewLine()},
      );

      transaction.insertNode(path.next, newNode);
      editor.apply(transaction);

      // Position cursor at start of new code block (after newline)
      editor.updateSelectionWithReason(
        Selection.single(
          path: path.next,
          startOffset: 1, // Position after the newline character
        ),
        reason: SelectionUpdateReason.transaction,
      );

      onUpdate();
      KragLogger.info(
          LogDomain.general, 'Added code block below node ${node.id}');
    } catch (e) {
      KragLogger.error(LogDomain.general, 'Error adding code block below', e);
      throw e;
    }
  }

  void moveBlockUp() {
    final editor = editorState;
    if (editor == null) return;
    final path = node.path;
    if (path.last == 0) return;
    final transaction = editor.transaction;
    final prevPath = path.previous;
    final prevNode = editor.document.nodeAtPath(prevPath);
    if (prevNode == null) return;
    transaction.moveNode(path, prevNode);
    editor.apply(transaction);
    onUpdate();
  }

  void moveBlockDown() {
    final editor = editorState;
    if (editor == null) return;
    final path = node.path;
    final parent = node.parent;
    if (parent == null) return;
    if (path.last >= parent.children.length - 1) return;
    final transaction = editor.transaction;
    final nextPath = path.next;
    final nextNode = editor.document.nodeAtPath(nextPath);
    if (nextNode == null) return;
    transaction.moveNode(nextPath, node);
    editor.apply(transaction);
    onUpdate();
  }

  void deleteBlock() {
    final editor = editorState;
    if (editor == null) {
      KragLogger.warn(
          LogDomain.general, 'Cannot change block type: editor state is null');
      return;
    }
    final transaction = editor.transaction;
    transaction.deleteNode(node);
    editor.apply(transaction);
    onUpdate();
  }

  void changeBlockType(String newType, {int? level}) {
    final editor = editorState;
    if (editor == null) return;

    // Lock/Unlock: toggle custom_locked attribute instead of changing block type.
    // AppFlowy has no builder for type='lock', so we use the attribute approach
    // which WrappedStandardBlockWidget already handles.
    if (newType == 'lock') {
      final isLocked = node.attributes['custom_locked'] == true;
      final transaction = editor.transaction;
      transaction.updateNode(node, {'custom_locked': !isLocked});
      editor.apply(transaction);
      onUpdate();
      return;
    }

    final path = node.path;
    final transaction = editor.transaction;

    String textContent = _extractTextFromNode(node);
    // if (!textContent.endsWith('\n')) textContent += '\n';

    final deltaObj = Delta()..insert(textContent);
    final List<dynamic> deltaList = deltaObj.toJson();

    final attributes = <String, dynamic>{
      'delta': deltaList,
      if (level != null) 'level': level,
      if (newType == TodoListBlockKeys.type) 'checked': false,
      if (newType == 'code' || newType == 'code_block') 'language': 'plaintext',
    };

    final newNode = Node(type: newType, attributes: attributes);
    transaction.deleteNode(node);
    transaction.insertNode(path, newNode);
    transaction.afterSelection = Selection.single(
      path: path,
      startOffset: 0,
    );
    editor.apply(transaction);
    onUpdate();
  }

  String _extractTextFromNode(Node node) {
    try {
      final deltaAttr = node.attributes['delta'];
      if (deltaAttr == null) {
        return '';
      }
      if (deltaAttr is Delta) {
        return deltaAttr.toPlainText();
      }
      if (deltaAttr is List) {
        final buffer = StringBuffer();
        for (final op in deltaAttr) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String) {
              buffer.write(insert);
            }
          }
        }
        return buffer.toString();
      }
      return '';
    } catch (e) {
      KragLogger.error(
          LogDomain.general, 'Failed to extract text from node', e);
      return '';
    }
  }
}

class _ReorderPanelWidget extends StatefulWidget {
  final EditorState editor;
  final String selectedNodeId;
  final VoidCallback onUpdate;
  final VoidCallback onClose;

  const _ReorderPanelWidget({
    required this.editor,
    required this.selectedNodeId,
    required this.onUpdate,
    required this.onClose,
  });

  @override
  State<_ReorderPanelWidget> createState() => _ReorderPanelWidgetState();
}

class _ReorderPanelWidgetState extends State<_ReorderPanelWidget> {
  late String _selectedContentHash;
  String? _draggingContentHash;

  @override
  void initState() {
    super.initState();
    _selectedContentHash = _getNodeHash(
      widget.editor.document.root.children.firstWhere(
        (n) => n.id == widget.selectedNodeId,
        orElse: () => widget.editor.document.root.children.first,
      ),
    );
  }

  String _getNodeHash(Node node) {
    final preview = _getBlockPreview(node);
    final type = _getBlockType(node);
    return '$type:$preview'.hashCode.toString();
  }

  void _handleReorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    KragLogger.info(
        LogDomain.general, 'Reorder requested: $oldIndex -> $newIndex');

    final blocks = widget.editor.document.root.children;
    final nodeToMove = blocks[oldIndex];
    final contentHash = _getNodeHash(nodeToMove);

    setState(() {
      _draggingContentHash = contentHash;
    });

    await _applyReorderToEditor(oldIndex, newIndex, contentHash);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _draggingContentHash = null;
        });
      }
    });
  }

  Future<void> _applyReorderToEditor(
      int oldIndex, int newIndex, String contentHash) async {
    final sourcePath = [oldIndex];
    final nodeToMove = widget.editor.document.nodeAtPath(sourcePath);

    if (nodeToMove == null) {
      KragLogger.warn(LogDomain.general, 'Node to move not found at $oldIndex');
      return;
    }

    int finalIndex = newIndex;
    if (oldIndex < newIndex) {
      finalIndex = newIndex;
    }

    final transaction = widget.editor.transaction;
    final targetPath = [finalIndex];

    KragLogger.info(LogDomain.general,
        'Moving node ${nodeToMove.id} from $sourcePath to $targetPath');

    try {
      transaction.deleteNode(nodeToMove);
      transaction.insertNode(targetPath, nodeToMove);
      transaction.afterSelection = Selection.collapsed(
        Position(path: targetPath),
      );

      await widget.editor.apply(transaction);
      widget.onUpdate();

      setState(() {
        _selectedContentHash = contentHash;
      });

      KragLogger.info(LogDomain.general, 'Reorder complete.');
    } catch (e, stack) {
      KragLogger.error(
          LogDomain.general, 'Error applying reorder transaction', e, stack);
    }
  }

  String _getBlockPreview(Node block) {
    final deltaAttr = block.attributes['delta'];
    if (deltaAttr != null) {
      try {
        Delta? delta;
        if (deltaAttr is Delta) {
          delta = deltaAttr;
        } else if (deltaAttr is List) {
          delta = Delta.fromJson(
            List<Map<String, dynamic>>.from(
              deltaAttr.map((e) => Map<String, dynamic>.from(e as Map)),
            ),
          );
        }
        final text = delta?.toPlainText() ?? '';
        if (text.trim().isNotEmpty) {
          return text.trim();
        }
      } catch (_) {}
    }

    final type = block.attributes['type'] ?? 'paragraph';
    return type == 'divider' ? '────────────' : 'Empty $type';
  }

  String _getBlockType(Node block) {
    final type = block.attributes['type'] ?? 'paragraph';
    final level = block.attributes['level'];

    switch (type) {
      case 'heading':
        return 'Heading ${level ?? 1}';
      case 'bulleted_list':
        return 'Bullet List';
      case 'numbered_list':
        return 'Numbered List';
      case 'todo_list':
        return 'Todo List';
      case 'code':
      case 'code_block':
        return 'Code Block';
      default:
        return type[0].toUpperCase() + type.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.editor.document.root.children;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFEDEDED)),
                onPressed: widget.onClose,
              ),
              const Text(
                'Reorder Blocks',
                style: TextStyle(
                  color: Color(0xFFEDEDED),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: blocks.length,
            onReorder: _handleReorder,
            proxyDecorator: (child, index, animation) {
              return child;
            },
            itemBuilder: (context, index) {
              final block = blocks[index];
              final blockHash = _getNodeHash(block);
              final isCurrentBlock = blockHash == _selectedContentHash ||
                  blockHash == _draggingContentHash;

              return Container(
                key: ValueKey(block.id),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isCurrentBlock
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrentBlock
                        ? const Color(0xFFFF6B00)
                        : const Color(0xFF3A3A3A),
                    width: isCurrentBlock ? 2 : 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Icon(
                      Icons.drag_handle,
                      color: isCurrentBlock
                          ? const Color(0xFFFF6B00)
                          : const Color(0xFFA0A0A0),
                    ),
                    title: Text(
                      _getBlockPreview(block),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrentBlock
                            ? const Color(0xFFFF6B00)
                            : const Color(0xFFEDEDED),
                        fontWeight: isCurrentBlock
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      _getBlockType(block),
                      style: TextStyle(
                        color: isCurrentBlock
                            ? const Color(0xFFFF9B50)
                            : const Color(0xFF7A7A7A),
                        fontSize: 12,
                      ),
                    ),
                    trailing: isCurrentBlock
                        ? const Icon(Icons.my_location,
                            color: Color(0xFFFF6B00), size: 20)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
