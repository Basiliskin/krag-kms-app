import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:uuid/uuid.dart';

Delta deltaFromInline(List inline) {
  final delta = Delta();
  for (final span in inline) {
    final attrs = <String, dynamic>{};

    for (final mark in span['marks']) {
      if (mark is String) attrs[mark] = true;
      if (mark is Map && mark['type'] == 'link') {
        attrs['link'] = mark['href'];
      }
    }

    delta.insert(span['text'], attributes: attrs.isEmpty ? null : attrs);
  }
  return delta;
}

Node blockToNode(Map block) {
  switch (block['type']) {
    case 'paragraph':
      return Node(
        type: 'paragraph',
        id: const Uuid().v4(),
        attributes: {'delta': deltaFromInline(block['content'])},
      );

    case 'heading':
      return Node(
        type: 'heading',
        id: const Uuid().v4(),
        attributes: {
          'level': block['level'],
          'delta': deltaFromInline(block['content']),
        },
      );

    case 'list':
      return Node(
        type: 'list',
        id: const Uuid().v4(),
        attributes: {'list_type': block['listType']},
        children: block['items'].map<Node>((item) {
          return Node(
            type: 'list_item',
            id: const Uuid().v4(),
            children: [
              Node(
                type: 'paragraph',
                id: const Uuid().v4(),
                attributes: {'delta': deltaFromInline(item)},
              )
            ],
          );
        }).toList(),
      );

    case 'table':
      return Node(
        type: 'table',
        id: const Uuid().v4(),
        children: block['rows'].map<Node>((row) {
          return Node(
            type: 'table_row',
            id: const Uuid().v4(),
            children: row.map<Node>((cell) {
              return Node(
                type: 'table_cell',
                id: const Uuid().v4(),
                children: [
                  Node(
                    type: 'paragraph',
                    id: const Uuid().v4(),
                    attributes: {'delta': deltaFromInline(cell)},
                  )
                ],
              );
            }).toList(),
          );
        }).toList(),
      );
  }

  throw UnsupportedError(block['type']);
}

List inlineFromDelta(Delta delta) {
  return delta.toJson().map((op) {
    final marks = <dynamic>[];
    final attrs = op['attributes'] ?? {};

    attrs.forEach((k, v) {
      if (k == 'link') {
        marks.add({'type': 'link', 'href': v});
      } else if (v == true) {
        marks.add(k);
      }
    });

    return {
      'text': op['insert'],
      'marks': marks,
    };
  }).toList();
}
