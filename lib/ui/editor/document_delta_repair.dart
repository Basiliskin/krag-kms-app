import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:krag_app/utils/logger.dart';

const Set<String> _textTypes = {
  'paragraph',
  'heading',
  'bulleted_list',
  'numbered_list',
  'todo_list',
  'quote',
  'code',
  'code_block',
};

void repairDocumentDeltas(Document document) {
  _repairNodeRecursive(document.root);
}

void _repairNodeRecursive(Node node) {
  final children = node.children;
  // Use standard for-loop for better performance on large documents
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    if (child.type == 'lock') {
      // final delta = _extractDeltaFromNode(child);
      final paragraph = paragraphNode() //delta: delta
        ..id = child.id
        ..attributes['custom_locked'] = true;

      // Replace the lock node with the paragraph node
      children[i] = paragraph;
      KragLogger.info(LogDomain.general,
          'PRELOAD: Migrated lock block to paragraph+locked');

      // Recurse on the new node
      _repairNodeRecursive(paragraph);
    } else {
      _repairNodeRecursive(child);
    }
  }
  _repairNode(node);
}

void _repairNode(Node node) {
  if (!_textTypes.contains(node.type)) {
    return;
  }

  // node.attributes['delta'] = safeDelta;

  // Ensure required attributes exist
  switch (node.type) {
    case 'heading':
      node.attributes.putIfAbsent('level', () => 1);
      break;
    case 'todo_list':
      node.attributes.putIfAbsent('checked', () => false);
      break;
    case 'code':
    case 'code_block':
      node.attributes.putIfAbsent('language', () => 'plaintext');
      break;
  }
}
