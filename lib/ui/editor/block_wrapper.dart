import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class BlockWrapper extends StatefulWidget {
  final Widget child;
  final EditorState editorState;
  final Node node;

  const BlockWrapper({
    super.key,
    required this.child,
    required this.editorState,
    required this.node,
  });

  @override
  State<BlockWrapper> createState() => _BlockWrapperState();
}

class _BlockWrapperState extends State<BlockWrapper> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // On mobile, we might always show handles or use a different interaction model.
    // For this implementation, we'll stick to the desktop/web hover pattern
    // but ensure it's usable on touch via long-press or always-visible options if needed.
    // The React app uses hover for desktop and specific touch handles for mobile.

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        color: _isHovered ? const Color(0xFF1E1E1E) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle (Left)
            Opacity(
              opacity: _isHovered ? 1.0 : 0.0,
              child: GestureDetector(
                onTap: () {
                  // Could open block menu here
                },
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 4),
                  child: const Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: Color(0xFFA0A0A0),
                  ),
                ),
              ),
            ),

            // Content
            Expanded(child: widget.child),

            // Delete/Options (Right) - mimicking React's delete on hover
            if (_isHovered)
              GestureDetector(
                onTap: () {
                  final transaction = widget.editorState.transaction;
                  transaction.deleteNode(widget.node);
                  widget.editorState.apply(transaction);
                },
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(left: 4),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Color(0xFFA0A0A0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
