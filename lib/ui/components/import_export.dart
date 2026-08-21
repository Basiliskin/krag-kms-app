import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:archive/archive.dart';
import '../../stores/notes_store.dart';
import '../../types/index.dart';

class ImportExportDialog extends ConsumerWidget {
  const ImportExportDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Import / Export',
          style: TextStyle(color: Color(0xFFEDEDED))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file, color: Color(0xFFA0A0A0)),
            title: const Text('Import Markdown',
                style: TextStyle(color: Color(0xFFEDEDED))),
            subtitle: const Text('Coming soon',
                style: TextStyle(color: Color(0xFF6A6A6A))),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Import not implemented in this version')),
              );
            },
          ),
          const Divider(color: Color(0xFF3A3A3A)),
          ListTile(
            leading: const Icon(Icons.download, color: Color(0xFFA0A0A0)),
            title: const Text('Export All Notes',
                style: TextStyle(color: Color(0xFFEDEDED))),
            subtitle: const Text('Download as ZIP',
                style: TextStyle(color: Color(0xFF6A6A6A))),
            onTap: () async {
              Navigator.pop(context);
              await _handleExport(context, ref);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleExport(BuildContext context, WidgetRef ref) async {
    final notesState = ref.read(notesStoreProvider);
    final notes = notesState.notes.values.toList();

    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No notes to export')),
      );
      return;
    }

    try {
      final archive = Archive();

      for (final note in notes) {
        final content = _generateMarkdown(note);
        final filename = '${_sanitizeFilename(note.title)}.md';
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(filename, bytes.length, bytes));
      }

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      if (zipData != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Exported ${notes.length} notes to ZIP (${zipData.length} bytes)')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  String _generateMarkdown(Note note) {
    final sb = StringBuffer();
    sb.writeln('---');
    sb.writeln('title: "${note.title}"');
    if (note.tags.isNotEmpty) {
      sb.writeln('tags: [${note.tags.map((t) => '"$t"').join(', ')}]');
    }
    if (note.labels.isNotEmpty) {
      sb.writeln('labels: [${note.labels.map((l) => '"$l"').join(', ')}]');
    }
    sb.writeln('---');
    sb.writeln();
    sb.write(note.content);
    return sb.toString();
  }

  String _sanitizeFilename(String title) {
    return title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }
}
