//** File: lib/types/index.dart**
// Ported from src/types/index.ts and src/types/filters.ts
class Note {
  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final List<String> labels;
  final String? parentId;
  final String? modifiedTime;
  final int? v; // Version

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const [],
    this.labels = const [],
    this.parentId,
    this.modifiedTime,
    this.v,
  });

  // Helper to create a copy with modified fields
  Note copyWith({
    String? title,
    String? content,
    List<String>? tags,
    List<String>? labels,
    String? parentId,
    String? modifiedTime,
    int? v,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      labels: labels ?? this.labels,
      parentId: parentId ?? this.parentId,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      v: v ?? this.v,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'tags': tags,
      'labels': labels,
      'parentId': parentId,
      'modifiedTime': modifiedTime,
      '_v': v,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      labels: (json['labels'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      parentId: json['parentId'] as String?,
      modifiedTime: json['modifiedTime'] as String?,
      v: json['_v'] as int?,
    );
  }
}

// In Dart, we use Map<String, Note> instead of a specific NotesState type alias usually,
// but we can define it for clarity.
typedef NotesState = Map<String, Note>;

class SearchResult {
  final String id;
  final String title;

  SearchResult({required this.id, required this.title});
}

class GraphNode {
  final String id;
  final String name;
  final double? x;
  final double? y;
  final String? color;

  GraphNode({required this.id, required this.name, this.x, this.y, this.color});
}

class GraphLink {
  final String source;
  final String target;

  GraphLink({required this.source, required this.target});
}

class GraphData {
  final List<GraphNode> nodes;
  final List<GraphLink> links;

  GraphData({required this.nodes, required this.links});
}

class DriveFileMetadata {
  final String id;
  final String name;
  final String createdTime;
  final String modifiedTime;
  final int? v;

  DriveFileMetadata({
    required this.id,
    required this.name,
    required this.createdTime,
    required this.modifiedTime,
    this.v,
  });
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdTime': createdTime,
      'modifiedTime': modifiedTime,
      'v': v,
    };
  }
}

class NoteFilters {
  final List<String> tags;
  final List<String> labels;

  const NoteFilters({this.tags = const [], this.labels = const []});

  static const NoteFilters empty = NoteFilters();

  bool get isEmpty => tags.isEmpty && labels.isEmpty;
}
