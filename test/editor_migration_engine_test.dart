import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:krag_app/utils/editor_migration_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Delta getDelta(Node node) {
    final deltaAttr = node.attributes['delta'];
    if (deltaAttr is Delta) return deltaAttr;
    if (deltaAttr is List) return Delta.fromJson(deltaAttr);
    throw Exception('Node ${node.id} has no valid delta attribute');
  }

  group('EditorMigrationEngine HTML Migration', () {
    test('detects and converts simple paragraph with ID', () {
      const html = '<p>Hello World</p>';
      final document = EditorMigrationEngine.migrate(html);

      expect(document.root.children.length, 1);
      final node = document.root.children.first;
      expect(node.type, 'paragraph');
      expect(node.id, isNotNull);
      expect(node.id.length, greaterThan(0));
      expect(getDelta(node).toPlainText(), 'Hello World\n');
    });

    test('converts headings with correct levels and IDs', () {
      const html = '<h1>Title 1</h1><h3>Title 3</h3>';
      final document = EditorMigrationEngine.migrate(html);

      expect(document.root.children.length, 2);

      final h1 = document.root.children[0];
      expect(h1.type, 'heading');
      expect(h1.id, isNotNull);
      expect(h1.attributes['level'], 1);
      expect(getDelta(h1).toPlainText(), 'Title 1\n');

      final h3 = document.root.children[1];
      expect(h3.type, 'heading');
      expect(h3.id, isNotNull);
      expect(h3.attributes['level'], 3);
      expect(getDelta(h3).toPlainText(), 'Title 3\n');
    });

    test('converts inline styles (bold, italic, code, strike)', () {
      const html =
          '<p><b>Bold</b> <i>Italic</i> <code>Code</code> <s>Strike</s></p>';
      final document = EditorMigrationEngine.migrate(html);

      final node = document.root.children.first;
      final delta = getDelta(node);
      final ops = delta.toList();

      // "Bold"
      expect(ops[0].attributes?['bold'], true);
      expect((ops[0] as TextInsert).text, 'Bold');

      // "Italic"
      expect(ops[2].attributes?['italic'], true);
      expect((ops[2] as TextInsert).text, 'Italic');

      // "Code"
      expect(ops[4].attributes?['code'], true);
      expect((ops[4] as TextInsert).text, 'Code');

      // "Strike"
      expect(ops[6].attributes?['strikethrough'], true);
      expect((ops[6] as TextInsert).text, 'Strike');
    });

    test('converts links', () {
      const html = '<p><a href="https://example.com">Link</a></p>';
      final document = EditorMigrationEngine.migrate(html);

      final node = document.root.children.first;
      final op = getDelta(node).toList().first;

      expect(op.attributes?['link'], 'https://example.com');
      expect((op as TextInsert).text, 'Link');
    });

    test('converts unordered lists with nested structure', () {
      const html = '<ul><li>Item 1</li><li>Item 2</li></ul>';
      final document = EditorMigrationEngine.migrate(html);

      expect(document.root.children.length, 1);
      final listNode = document.root.children.first;
      expect(listNode.type, 'list');
      expect(listNode.id, isNotNull);
      expect(listNode.attributes['list_type'], 'bullet');
      expect(listNode.children.length, 2);

      final item1 = listNode.children[0];
      expect(item1.type, 'list_item');
      expect(item1.id, isNotNull);
      expect(item1.children.first.type, 'paragraph');
      expect(getDelta(item1.children.first).toPlainText(), 'Item 1\n');
    });

    test('converts task lists (TipTap format) to todo_list nodes', () {
      const html =
          '<ul data-type="taskList"><li data-checked="true">Done</li><li data-checked="false">Todo</li></ul>';
      final document = EditorMigrationEngine.migrate(html);

      expect(document.root.children.length, 2);

      final task1 = document.root.children[0];
      expect(task1.type, 'todo_list');
      expect(task1.id, isNotNull);
      expect(task1.attributes['checked'], true);
      expect(getDelta(task1).toPlainText(), 'Done\n');

      final task2 = document.root.children[1];
      expect(task2.type, 'todo_list');
      expect(task2.id, isNotNull);
      expect(task2.attributes['checked'], false);
      expect(getDelta(task2).toPlainText(), 'Todo\n');
    });

    test('converts code blocks with language and ID', () {
      const html =
          '<pre><code class="language-dart">void main() {}</code></pre>';
      final document = EditorMigrationEngine.migrate(html);

      final node = document.root.children.first;
      expect(node.type, 'code_block');
      expect(node.id, isNotNull);
      expect(node.attributes['language'], 'dart');
      expect(getDelta(node).toPlainText(), 'void main() {}\n');
    });

    test('handles malformed HTML gracefully', () {
      const html = '<p>Unclosed tag';
      final document = EditorMigrationEngine.migrate(html);

      expect(document.root.children.isNotEmpty, true);
      expect(getDelta(document.root.children.first).toPlainText(),
          contains('Unclosed tag'));
    });

    test('throws on unsupported format (plain text)', () {
      expect(() => EditorMigrationEngine.migrate('Just text'), throwsException);
    });
  });
}
