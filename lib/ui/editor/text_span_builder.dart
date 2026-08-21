import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

TextSpan buildTextSpanFromNode(Node node, TextStyle defaultStyle) {
  final delta = node.delta;
  if (delta == null) return TextSpan(text: '', style: defaultStyle);

  final children = <InlineSpan>[];

  for (final op in delta.toList()) {
    // Check if the operation is a TextInsert to access the .text property
    if (op is TextInsert) {
      final text = op.text;
      final attributes = op.attributes;

      TextStyle style = defaultStyle;

      if (attributes != null) {
        if (attributes['bold'] == true) {
          style = style.copyWith(fontWeight: FontWeight.bold);
        }
        if (attributes['italic'] == true) {
          style = style.copyWith(fontStyle: FontStyle.italic);
        }
        if (attributes['underline'] == true) {
          style = style.copyWith(decoration: TextDecoration.underline);
        }
        if (attributes['strikethrough'] == true) {
          style = style.copyWith(decoration: TextDecoration.lineThrough);
        }
        if (attributes['code'] == true) {
          style = style.copyWith(
            fontFamily: 'Monospace',
            backgroundColor: Colors.grey.withOpacity(0.2),
          );
        }
        // Add color handling if needed
        if (attributes['color'] != null) {
          try {
            // Assuming color is stored as hex string
            final colorHex = attributes['color'] as String;
            final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
            style = style.copyWith(color: color);
          } catch (_) {}
        }
      }

      children.add(TextSpan(text: text, style: style));
    }
    // Handle other operation types (Embeds, etc.) if necessary
  }

  return TextSpan(children: children);
}
