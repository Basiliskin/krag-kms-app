import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../../utils/logger.dart';

/// Simple code block component for displaying code
class SimpleCodeBlockComponentBuilder extends BlockComponentBuilder {
  SimpleCodeBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return SimpleCodeBlockWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
    );
  }
}

class SimpleCodeBlockWidget extends BlockComponentStatefulWidget {
  const SimpleCodeBlockWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<SimpleCodeBlockWidget> createState() => _SimpleCodeBlockWidgetState();
}

class _SimpleCodeBlockWidgetState extends State<SimpleCodeBlockWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  Widget build(BuildContext context) {
    // Get delta from attributes, not from node.delta
    final deltaAttr = node.attributes['delta'];
    Delta? delta;

    if (deltaAttr != null) {
      if (deltaAttr is Delta) {
        delta = deltaAttr;
      } else if (deltaAttr is List) {
        try {
          delta = Delta.fromJson(List<Map<String, dynamic>>.from(
              deltaAttr.map((e) => Map<String, dynamic>.from(e as Map))));
        } catch (e) {
          KragLogger.error(LogDomain.general, 'Failed to parse delta', e);
        }
      }
    }

    if (delta == null) {
      KragLogger.warn(LogDomain.general,
          '>>> No delta found, attributes: ${node.attributes}');
      return const SizedBox.shrink();
    }

    final language = node.attributes['language'] as String? ?? 'plaintext';
    final text = delta.toPlainText();

    return Container(
      width: double.infinity, // Force full width
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3A3A3A),
          width: 1,
        ),
      ),
      margin:
          const EdgeInsets.symmetric(vertical: 8), // Keep vertical margin only
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              language,
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Code content with horizontal scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: Color(0xFFEDEDED),
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
