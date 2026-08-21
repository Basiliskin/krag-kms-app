class BlockTypes {
  static const String paragraph = 'paragraph';
  static const String heading = 'heading';
  static const String bulletList = 'bullet_list';
  static const String orderedList = 'ordered_list';
  static const String taskList = 'task_list';
  static const String listItem = 'list_item';
  static const String taskItem = 'task_item';
  static const String blockquote = 'blockquote';
  static const String codeBlock = 'code_block';
  static const String quote = 'quote';
  static const String image = 'image';
  static const String horizontalRule = 'horizontal_rule';
}

class BlockAttributes {
  final int? level; // For headings (1, 2, 3)
  final String? language; // For code blocks
  final bool? checked; // For task items
  final bool? locked; // For Notion-style locking
  final String? encryptedData; // Base64 encrypted content
  final String? iv; // Initialization vector for encryption

  BlockAttributes({
    this.level,
    this.language,
    this.checked,
    this.locked,
    this.encryptedData,
    this.iv,
  });

  factory BlockAttributes.fromJson(Map<String, dynamic> json) {
    return BlockAttributes(
      level: json['level'] as int?,
      language: json['language'] as String?,
      checked: json['checked'] as bool?,
      locked: json['locked'] as bool?,
      encryptedData: json['encryptedData'] as String?,
      iv: json['iv'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (level != null) data['level'] = level;
    if (language != null) data['language'] = language;
    if (checked != null) data['checked'] = checked;
    if (locked != null) data['locked'] = locked;
    if (encryptedData != null) data['encryptedData'] = encryptedData;
    if (iv != null) data['iv'] = iv;
    return data;
  }
}

class NormalizedBlock {
  final String id;
  final String type;
  final BlockAttributes? attributes;

  final dynamic data;

  NormalizedBlock({
    required this.id,
    required this.type,
    this.attributes,
    this.data,
  });

  factory NormalizedBlock.fromJson(Map<String, dynamic> json) {
    dynamic rawData = json['data'];
    dynamic parsedData;

    if (rawData is String) {
      parsedData = rawData;
    } else if (rawData is List) {
      // We need to determine if this is a list of blocks or a list of Tiptap text nodes.
      // In the Normalized format, nested blocks are List<NormalizedBlock>.
      // Tiptap text nodes are usually serialized into a JSON string in 'data'.
      // However, if they arrive as a raw List, we check the first element.
      if (rawData.isNotEmpty &&
          rawData.first is Map &&
          (rawData.first as Map).containsKey('id')) {
        parsedData = rawData
            .map((e) =>
                NormalizedBlock.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } else {
        // It's likely a list of text nodes or marks, keep as is or stringify
        parsedData = rawData;
      }
    }

    return NormalizedBlock(
      id: json['id'] as String,
      type: json['type'] as String,
      attributes: json['attributes'] != null
          ? BlockAttributes.fromJson(
              Map<String, dynamic>.from(json['attributes'] as Map))
          : null,
      data: parsedData,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'id': id,
      'type': type,
    };

    if (attributes != null) {
      json['attributes'] = attributes!.toJson();
    }

    if (data != null) {
      if (data is List<NormalizedBlock>) {
        json['data'] =
            (data as List<NormalizedBlock>).map((e) => e.toJson()).toList();
      } else {
        json['data'] = data;
      }
    }

    return json;
  }
}

class NormalizedDocument {
  final String format;
  final int version;
  final List<NormalizedBlock> blocks;

  static const String formatName = 'nblock';

  NormalizedDocument({
    this.format = formatName,
    required this.version,
    required this.blocks,
  });

  factory NormalizedDocument.fromJson(Map<String, dynamic> json) {
    return NormalizedDocument(
      format: json['format'] as String? ?? formatName,
      version: json['version'] as int? ?? 1,
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((e) =>
                  NormalizedBlock.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'format': format,
      'version': version,
      'blocks': blocks.map((e) => e.toJson()).toList(),
    };
  }
}

/// Helper to check if a JSON object is a NormalizedDocument.
bool isNormalizedDocument(dynamic json) {
  if (json is! Map) return false;
  return json['format'] == NormalizedDocument.formatName &&
      json['version'] is int &&
      json['blocks'] is List;
}
