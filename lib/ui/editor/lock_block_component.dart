import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// Renders legacy type='lock' blocks (migrated on load, but fallback for edge cases).
/// Tap to convert to paragraph and unlock.
class LockBlockComponentBuilder extends BlockComponentBuilder {
  LockBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return _LockBlockWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }
}

class _LockBlockWidget extends BlockComponentStatefulWidget {
  const _LockBlockWidget({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<_LockBlockWidget> createState() => _LockBlockWidgetState();
}

class _LockBlockWidgetState extends State<_LockBlockWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  EditorState? _editorState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_editorState == null && mounted) {
      context.visitAncestorElements((element) {
        final w = element.widget;
        if (w is AppFlowyEditor) {
          _editorState = w.editorState;
          return false;
        }
        return true;
      });
    }
  }

  void _unlockAndConvertToParagraph() {
    final editor = _editorState;
    if (editor == null) return;

    final path = node.path;
    final transaction = editor.transaction;
    transaction.deleteNode(node);
    transaction.insertNode(
      path,
      paragraphNode()
        ..attributes['custom_locked'] = false
        ..id = node.id,
    );
    transaction.afterSelection = Selection.single(path: path, startOffset: 0);
    editor.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _unlockAndConvertToParagraph,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: configuration.padding(node),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, color: Color(0xFFA0A0A0), size: 16),
            SizedBox(width: 8),
            Text(
              'Content Locked (tap to unlock)',
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
