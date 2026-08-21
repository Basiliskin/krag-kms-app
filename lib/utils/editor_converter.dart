import 'package:appflowy_editor/appflowy_editor.dart';
import 'logger.dart';
import 'editor_migration_engine.dart';

class EditorConverter {
  /// Converts Tiptap HTML content to an AppFlowy Document.
  static Document htmlToAppFlowy(String html) {
    EditorMigrationEngine.debug = true;

    KragLogger.info(
      LogDomain.general,
      'Converting HTML to AppFlowy (Length: ${html.length})',
    );

    final document = EditorMigrationEngine.migrate(html);

    for (final node in document.root.children) {
      final delta = node.attributes['delta'] as Delta;
      KragLogger.info(
        LogDomain.general,
        'Final delta: "${delta.toPlainText().replaceAll("\n", "\\n")}"',
      );
    }

    return document;
  }

  /// Converts an AppFlowy EditorState to Tiptap HTML.
  static String appFlowyToHtml(EditorState editorState) {
    final payload =
        EditorMigrationEngine.appFlowyToMarkdown(editorState.document);
    return payload;
  }
}
