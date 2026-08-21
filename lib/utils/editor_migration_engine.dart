import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:uuid/uuid.dart';
import '../types/normalized.dart';
import '../utils/delta_insert_utils.dart';

const _uuid = Uuid();

class EditorMigrationEngine {
  static const currentSchemaVersion = 1;
  static bool debug = true;

  static void _log(String message) {
    if (!debug) return;
    // In a real app, use a proper logger
    // print('[MigrationEngine] $message');
  }

  static Document migrate(dynamic input) {
    final detected = _detectFormat(input);
    _log('Detected format: $detected');

    Document document;
    switch (detected) {
      case _Format.nblock:
        _log('Loading Normalized Block format');
        document = _loadNormalized(input);
        break;
      case _Format.appflowy:
        _log('Loading AppFlowy JSON');
        document = _loadAppFlowy(input);
        break;
      case _Format.tiptap:
        _log('Converting from Tiptap JSON to Normalized -> AppFlowy');
        final normalized = tiptapToNormalized(input);
        document = normalizedToAppFlowy(normalized);
        break;
      case _Format.html:
        _log('Converting from HTML');
        document = LegacyHtmlConverter.htmlToAppFlowy(input);
        break;
      case _Format.markdown:
        _log('Converting from Markdown');
        document = markdownToAppFlowy(input.toString());
        break;
      default:
        _log('Unknown format, falling back to Markdown/Text');
        document = markdownToAppFlowy(input.toString());
    }

    _sanitizeDocument(document);
    return document;
  }

  static void _sanitizeDocument(Document document) {
    for (final node in document.root.children) {
      _sanitizeNode(node);
    }
  }

  static void _sanitizeNode(Node node) {
    if (_requiresDelta(node.type)) {
      final attributes = node.attributes;

      // 1. Ensure 'delta' attribute exists
      if (!attributes.containsKey('delta') || attributes['delta'] == null) {
        attributes['delta'] = getDeltaNewLine();
      } else {
        // 2. Validate existing 'delta'
        final dynamic raw = attributes['delta'];
        if (raw is! Delta) {
          try {
            if (raw is List) {
              // Try parsing as JSON list of operations
              attributes['delta'] = Delta.fromJson(
                List<Map<String, dynamic>>.from(
                  raw.map((e) => Map<String, dynamic>.from(e as Map)),
                ),
              );
            } else {
              // Fallback to parsing as data/text
              attributes['delta'] = _parseDataToDelta(raw);
            }
          } catch (e) {
            _log(
                'Failed to sanitize delta for node ${node.id} (${node.type}): $e');
            // Ultimate fallback
            attributes['delta'] = _parseDataToDelta(raw);
          }
        }
      }

      // 3. Ensure Delta is not empty (must contain at least a newline for block editors)
      final delta = attributes['delta'] as Delta;
      if (delta.isEmpty) {
        attributes['delta'] = getDeltaNewLine();
      } else {
        // Optional: Check if it ends with newline.
        // Most editors enforce this, but we can be defensive.
        final text = delta.toPlainText();
        if (!text.endsWith('\n')) {
          delta.insert('\n');
        }
      }
    }

    for (final child in node.children) {
      _sanitizeNode(child);
    }
  }

  static bool _requiresDelta(String type) {
    // const textTypes = {
    //   // Legacy / Normalized types (from BlockTypes)
    //   BlockTypes.paragraph,
    //   BlockTypes.heading,
    //   BlockTypes.bulletList, // 'bullet_list'
    //   BlockTypes.orderedList, // 'ordered_list'
    //   BlockTypes.taskList, // 'task_list'
    //   BlockTypes.listItem, // 'list_item'
    //   BlockTypes.taskItem, // 'task_item'
    //   BlockTypes.codeBlock, // 'code_block'
    //   BlockTypes.quote,
    // };
    // return textTypes.contains(type);
    return false;
  }

  static Map<String, dynamic> serialize(Document document) {
    return {
      'schema': 'appflowy',
      'version': currentSchemaVersion,
      'document': document.toJson(),
    };
  }

  static Document deserialize(Map<String, dynamic> json) {
    final doc = Document.fromJson(Map<String, dynamic>.from(json['document']));
    _sanitizeDocument(doc);
    return doc;
  }

  static _Format _detectFormat(dynamic input) {
    if (input is String) {
      try {
        final trimmed = input.trim();
        if (trimmed.startsWith('{')) {
          final decoded = jsonDecode(input);
          if (decoded is Map) {
            final map = Map<String, dynamic>.from(decoded);
            if (isNormalizedDocument(map)) return _Format.nblock;
            if (map['schema'] == 'appflowy') return _Format.appflowy;
            if (map['type'] == 'doc') return _Format.tiptap;
          }
        }
      } catch (_) {}

      final trimmed = input.trim();
      if (trimmed.startsWith('<')) {
        final hasHtmlTags = RegExp(
          r'<(p|div|h[1-6]|ul|ol|li|br|span|b|i|strong|em|code|pre|blockquote|table|tr|td|th|a|del|s|strike|hr)\b',
          caseSensitive: false,
        ).hasMatch(trimmed);

        if (hasHtmlTags ||
            trimmed.toLowerCase().startsWith('<!doctype html>') ||
            trimmed.toLowerCase().startsWith('<html>')) {
          return _Format.html;
        }
      }
      return _Format.markdown;
    }
    if (input is Map) {
      final map = Map<String, dynamic>.from(input);
      if (isNormalizedDocument(map)) return _Format.nblock;
      if (map['schema'] == 'appflowy') return _Format.appflowy;
      if (map['type'] == 'doc') return _Format.tiptap;
    }
    return _Format.unknown;
  }

  static Document _loadNormalized(dynamic input) {
    final Map<String, dynamic> json = input is String
        ? Map<String, dynamic>.from(jsonDecode(input))
        : Map<String, dynamic>.from(input);
    final normalizedDoc = NormalizedDocument.fromJson(json);
    return normalizedToAppFlowy(normalizedDoc);
  }

  static Document _loadAppFlowy(Map<String, dynamic> input) {
    return Document.fromJson(Map<String, dynamic>.from(input['document']));
  }

  static Document normalizedToAppFlowy(NormalizedDocument doc) {
    final List<Node> nodes = [];
    for (final block in doc.blocks) {
      nodes.addAll(_convertNormalizedBlock(block));
    }
    if (nodes.isEmpty) {
      nodes.add(paragraphNode()..id = _uuid.v4());
    }
    return Document(root: Node(type: 'page', id: _uuid.v4(), children: nodes));
  }

  static String _normalizeLanguage(String? lang) {
    if (lang == null || lang.trim().isEmpty) return 'plaintext';
    final lower = lang.trim().toLowerCase();
    if (lower == 'plain_text' ||
        lower == 'plaintext' ||
        lower == 'none' ||
        lower == 'txt') {
      return 'plaintext';
    }
    if (lower == 'c++') return 'cpp';
    if (lower == 'c#') return 'csharp';
    return lower;
  }

  static List<Node> _convertNormalizedBlock(NormalizedBlock block) {
    final delta = _parseDataToDelta(block.data);
    _log('Converting block type: ${block.type}, delta length: ${delta.length}');

    switch (block.type) {
      case BlockTypes.paragraph:
        return [paragraphNode(delta: delta)..id = _uuid.v4()];
      case BlockTypes.heading:
        return [
          headingNode(
            level: block.attributes?.level ?? 1,
            delta: delta,
          )..id = _uuid.v4()
        ];
      case BlockTypes.codeBlock:
        final language = _normalizeLanguage(block.attributes?.language);
        var plainText = delta.toPlainText();
        // if (!plainText.endsWith('\n')) {
        //   plainText += '\n';
        // }
        return [
          Node(
            type: 'code',
            id: _uuid.v4(),
            attributes: {
              'language': language,
              'delta': Delta()..insert(plainText),
            },
          )
        ];
      case BlockTypes.blockquote:
        return [quoteNode(delta: delta)..id = _uuid.v4()];
      case BlockTypes.bulletList:
        return _buildListItems(block, 'bulleted_list');
      case BlockTypes.orderedList:
        return _buildListItems(block, 'numbered_list');
      case BlockTypes.taskList:
        return _buildListItems(block, 'todo_list');
      case BlockTypes.horizontalRule:
        return [
          Node(
            type: 'divider',
            id: _uuid.v4(),
            attributes: {'lineType': 'solid'},
          )
        ];
      case BlockTypes.listItem:
      case BlockTypes.taskItem:
        return [paragraphNode(delta: delta)..id = _uuid.v4()];
      default:
        _log('Unknown block type: ${block.type}, falling back to paragraph');
        return [paragraphNode(delta: delta)..id = _uuid.v4()];
    }
  }

  static List<Node> _buildListItems(NormalizedBlock block, String type) {
    final nodes = <Node>[];
    if (block.data is List) {
      for (final child in block.data as List) {
        if (child is NormalizedBlock) {
          final delta = _parseDataToDelta(child.data);
          Node node;
          if (type == 'todo_list') {
            node = todoListNode(
              checked: child.attributes?.checked ?? false,
              delta: delta,
            );
          } else if (type == 'bulleted_list') {
            node = bulletedListNode(delta: delta);
          } else {
            node = numberedListNode(delta: delta);
          }
          node.id = _uuid.v4();
          nodes.add(node);

          if (child.data is List) {
            final nested = child.data as List;
            if (nested.isNotEmpty && nested.first is NormalizedBlock) {
              for (final n in nested.cast<NormalizedBlock>()) {
                nodes.addAll(_convertNormalizedBlock(n));
              }
            }
          }
        }
      }
    }
    return nodes;
  }

  static Delta _parseDataToDelta(dynamic data) {
    if (data == null) return getDeltaNewLine();

    dynamic decoded;
    if (data is String) {
      try {
        final trimmed = data.trim();
        if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) {
          return Delta()..insert('$data\n');
        }
        decoded = jsonDecode(data);
      } catch (e) {
        _log('JSON parse failed for data block, treating as text: $e');
        return Delta()..insert('$data\n');
      }
    } else {
      decoded = data;
    }

    if (decoded is List) {
      final delta = Delta();
      for (final op in decoded) {
        if (op is Map) {
          if (op['type'] == 'text') {
            final attrs = <String, dynamic>{};
            final rawMarks = op['marks'];
            List<dynamic>? marks;
            if (rawMarks is List) {
              marks = rawMarks;
            } else if (rawMarks is String) {
              try {
                final decodedMarks = jsonDecode(rawMarks);
                if (decodedMarks is List) marks = decodedMarks;
              } catch (_) {}
            }

            if (marks != null) {
              for (final mark in marks) {
                if (mark is Map) {
                  final type = mark['type'];
                  if (type == 'bold') attrs['bold'] = true;
                  if (type == 'italic') attrs['italic'] = true;
                  if (type == 'underline') attrs['underline'] = true;
                  if (type == 'strike') attrs['strikethrough'] = true;
                  if (type == 'code') attrs['code'] = true;
                  if (type == 'link') {
                    final linkAttrs = mark['attrs'];
                    if (linkAttrs is Map) {
                      attrs['link'] = linkAttrs['href'];
                    }
                  }
                }
              }
            }

            final text = op['text']?.toString() ?? '';
            if (text.isNotEmpty) {
              delta.insert(text, attributes: attrs.isNotEmpty ? attrs : null);
            }
          }
        }
      }
      if (delta.isEmpty) {
        delta.insert('\n');
      } else if (!delta.toPlainText().endsWith('\n')) {
        delta.insert('\n');
      }
      return delta;
    }

    return getDeltaNewLine();
  }

  static NormalizedDocument tiptapToNormalized(dynamic tiptapJson) {
    if (tiptapJson == null) {
      return NormalizedDocument(version: 1, blocks: []);
    }

    List<dynamic> content = [];
    if (tiptapJson is Map && tiptapJson['type'] == 'doc') {
      content = tiptapJson['content'] ?? [];
    } else if (tiptapJson is List) {
      content = tiptapJson;
    } else if (tiptapJson is Map) {
      content = [tiptapJson];
    }

    final blocks = content.map((node) => _convertTiptapNode(node)).toList();
    return NormalizedDocument(version: 1, blocks: blocks);
  }

  static NormalizedBlock _convertTiptapNode(dynamic node) {
    final map = node as Map;
    final type = _mapTiptapType(map['type']);
    BlockAttributes? attributes;

    if (map.containsKey('attrs')) {
      final attrs = map['attrs'] as Map;
      attributes = BlockAttributes(
        level: attrs['level'],
        language: attrs['language'],
        checked: attrs['checked'],
      );
    }

    dynamic data;
    final hasNestedBlocks =
        (map['content'] as List?)?.any((child) => child['type'] != 'text') ??
            false;

    if (hasNestedBlocks) {
      data =
          (map['content'] as List).map((c) => _convertTiptapNode(c)).toList();
    } else if (map.containsKey('content')) {
      data = jsonEncode(map['content']);
    } else if (map.containsKey('text')) {
      data = jsonEncode([
        {'type': 'text', 'text': map['text']},
      ]);
    }

    return NormalizedBlock(
      id: _uuid.v4(),
      type: type,
      attributes: attributes,
      data: data,
    );
  }

  static String _mapTiptapType(String tiptapType) {
    switch (tiptapType) {
      case 'paragraph':
        return BlockTypes.paragraph;
      case 'heading':
        return BlockTypes.heading;
      case 'bulletList':
        return BlockTypes.bulletList;
      case 'orderedList':
        return BlockTypes.orderedList;
      case 'listItem':
        return BlockTypes.listItem;
      case 'taskList':
        return BlockTypes.taskList;
      case 'taskItem':
        return BlockTypes.taskItem;
      case 'blockquote':
        return BlockTypes.blockquote;
      case 'codeBlock':
        return BlockTypes.codeBlock;
      case 'horizontalRule':
        return BlockTypes.horizontalRule;
      default:
        return BlockTypes.paragraph;
    }
  }

  static Document markdownToAppFlowy(String markdown) {
    final lines = markdown.split('\n');
    final nodes = <Node>[];
    bool inCodeBlock = false;
    String? codeLanguage;
    StringBuffer codeBuffer = StringBuffer();
    // Accumulate consecutive non-blank lines into one paragraph (markdown style).
    // Blank lines flush the paragraph and are not turned into empty blocks.
    StringBuffer? paragraphBuffer;

    void flushParagraph() {
      if (paragraphBuffer != null && paragraphBuffer!.isNotEmpty) {
        final text = paragraphBuffer.toString().trimRight();
        if (text.isNotEmpty) {
          nodes.add(paragraphNode(delta: Delta()..insert('$text\n'))
            ..id = _uuid.v4());
        }
        paragraphBuffer = null;
      }
    }

    for (final line in lines) {
      if (line.trim().startsWith('```')) {
        flushParagraph();
        if (inCodeBlock) {
          nodes.add(Node(
            type: 'code',
            id: _uuid.v4(),
            attributes: {
              'language': codeLanguage ?? 'plaintext',
              'delta': Delta()..insert(codeBuffer.toString()),
            },
          ));
          codeBuffer.clear();
          inCodeBlock = false;
          codeLanguage = null;
        } else {
          inCodeBlock = true;
          codeLanguage = line.trim().substring(3).trim();
          if (codeLanguage.isEmpty) codeLanguage = 'plaintext';
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.writeln(line);
        continue;
      }

      if (line.startsWith('#')) {
        flushParagraph();
        final level = line.indexOf(' ');
        if (level > 0 && level <= 6) {
          nodes.add(headingNode(
            level: level,
            delta: Delta()..insert('${line.substring(level + 1)}\n'),
          )..id = _uuid.v4());
          continue;
        }
      }

      if (line.startsWith('- []') || line.startsWith('- [x]')) {
        flushParagraph();
        final checked = line.startsWith('- [x]');
        nodes.add(todoListNode(
          checked: checked,
          delta: Delta()..insert('${line.substring(6)}\n'),
        )..id = _uuid.v4());
        continue;
      }

      if (line.startsWith('- ')) {
        flushParagraph();
        nodes.add(bulletedListNode(
          delta: Delta()..insert('${line.substring(2)}\n'),
        )..id = _uuid.v4());
        continue;
      }

      if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        flushParagraph();
        final dotIndex = line.indexOf('.');
        nodes.add(numberedListNode(
          delta: Delta()..insert('${line.substring(dotIndex + 2)}\n'),
        )..id = _uuid.v4());
        continue;
      }

      if (line.startsWith('> ')) {
        flushParagraph();
        nodes.add(quoteNode(
          delta: Delta()..insert('${line.substring(2)}\n'),
        )..id = _uuid.v4());
        continue;
      }

      if (line.trim() == '---') {
        flushParagraph();
        nodes.add(Node(
          type: 'divider',
          id: _uuid.v4(),
          attributes: {'lineType': 'solid'},
        ));
        continue;
      }

      // Blank line: paragraph separator only, no extra block
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      // Normal line: add to current paragraph (merge consecutive lines)
      paragraphBuffer ??= StringBuffer();
      if (paragraphBuffer!.length > 0) paragraphBuffer!.write('\n');
      paragraphBuffer!.write(line);
    }
    flushParagraph();

    if (inCodeBlock && codeBuffer.isNotEmpty) {
      nodes.add(Node(
        type: 'code',
        id: _uuid.v4(),
        attributes: {
          'language': codeLanguage ?? 'plaintext',
          'delta': Delta()..insert(codeBuffer.toString()),
        },
      ));
    }

    if (nodes.isEmpty) {
      nodes.add(paragraphNode()..id = _uuid.v4());
    }

    return Document(root: Node(type: 'page', id: _uuid.v4(), children: nodes));
  }

  static String appFlowyToMarkdown(Document doc) {
    final buffer = StringBuffer();

    Delta? getDelta(dynamic deltaAttr) {
      if (deltaAttr == null) return null;
      if (deltaAttr is Delta) return deltaAttr;
      try {
        final List<dynamic> list;
        if (deltaAttr is List) {
          list = deltaAttr;
        } else {
          list = List<dynamic>.from(deltaAttr);
        }
        final List<Map<String, dynamic>> operations = list.map((op) {
          if (op is Map<String, dynamic>) {
            return op;
          } else if (op is Map) {
            return Map<String, dynamic>.from(op);
          } else {
            return Map<String, dynamic>.from(op as Map);
          }
        }).toList();
        return Delta.fromJson(operations);
      } catch (e) {
        _log('Failed to parse delta: $e (type: ${deltaAttr.runtimeType})');
        return null;
      }
    }

    String getText(dynamic deltaAttr) {
      final delta = getDelta(deltaAttr);
      return delta?.toPlainText().trim() ?? '';
    }

    String getRawText(dynamic deltaAttr) {
      final delta = getDelta(deltaAttr);
      return delta?.toPlainText() ?? '';
    }

    for (final node in doc.root.children) {
      final text = getText(node.attributes['delta']);
      switch (node.type) {
        case 'heading':
          final level = node.attributes['level'] ?? 1;
          buffer.writeln('${'#' * level} $text');
          break;
        case 'paragraph':
          buffer.writeln(text);
          break;
        case 'bulleted_list':
          buffer.writeln('- $text');
          break;
        case 'numbered_list':
          buffer.writeln('1. $text');
          break;
        case 'todo_list':
          final checked = node.attributes['checked'] == true;
          buffer.writeln('- [${checked ? 'x' : ' '}] $text');
          break;
        case 'quote':
          buffer.writeln('> $text');
          break;
        case 'divider':
          buffer.writeln('---');
          break;
        case 'code':
        case 'code_block':
          final lang = node.attributes['language'] ?? '';
          final codeContent = getRawText(node.attributes['delta']).trimRight();
          buffer.writeln('```$lang\n$codeContent\n```');
          break;
        default:
          buffer.writeln(text);
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}

class LegacyHtmlConverter {
  static Document htmlToAppFlowy(String html) {
    try {
      final document = html_parser.parse(html);
      final body = document.body;
      if (body == null) {
        return _createEmptyDocument();
      }

      final nodes = <Node>[];
      for (final node in body.nodes) {
        nodes.addAll(_convertDomNode(node));
      }

      if (nodes.isEmpty) {
        return _createEmptyDocument();
      }

      return Document(
          root: Node(type: 'page', id: _uuid.v4(), children: nodes));
    } catch (e) {
      EditorMigrationEngine._log('HTML Parsing failed: $e');
      return _createEmptyDocument();
    }
  }

  static Document _createEmptyDocument() {
    return Document(
      root: Node(
        type: 'page',
        id: _uuid.v4(),
        children: [paragraphNode()..id = _uuid.v4()],
      ),
    );
  }

  static List<Node> _convertDomNode(dom.Node node) {
    EditorMigrationEngine._log(
        'Processing DOM node: ${node.nodeType} (${node.nodeType == dom.Node.ELEMENT_NODE ? (node as dom.Element).localName : "text"})');

    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text?.trim();
      if (text != null && text.isNotEmpty) {
        return [
          paragraphNode(delta: Delta()..insert('$text\n'))..id = _uuid.v4()
        ];
      }
      return [];
    }

    if (node.nodeType == dom.Node.ELEMENT_NODE) {
      return _convertElement(node as dom.Element);
    }

    return [];
  }

  static List<Node> _convertElement(dom.Element element) {
    final tagName = element.localName?.toLowerCase();
    EditorMigrationEngine._log('Converting Element: <$tagName>');

    switch (tagName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return [_createHeading(element, tagName!)];
      case 'p':
      case 'div':
        return [_createParagraph(element)];
      case 'ul':
      case 'ol':
        return _createList(element);
      case 'pre':
        return [_createCodeBlock(element)];
      case 'blockquote':
        return [_createParagraph(element)];
      case 'hr':
        return [
          Node(
            type: 'divider',
            id: _uuid.v4(),
            attributes: {'lineType': 'solid'},
          )
        ];
      case 'br':
        return [];
      default:
        if (element.text.trim().isNotEmpty) {
          EditorMigrationEngine._log(
              'Unknown tag <$tagName> with content, converting to paragraph');
          return [_createParagraph(element)];
        }
        EditorMigrationEngine._log('Skipping unknown/empty tag <$tagName>');
        return [];
    }
  }

  static Node _createHeading(dom.Element element, String tagName) {
    final level = int.tryParse(tagName.substring(1)) ?? 1;
    return headingNode(
      level: level,
      delta: _buildDeltaFromElement(element),
    )..id = _uuid.v4();
  }

  static Node _createParagraph(dom.Element element) {
    return paragraphNode(delta: _buildDeltaFromElement(element))
      ..id = _uuid.v4();
  }

  static List<Node> _createList(dom.Element element) {
    final isTaskList = element.attributes['data-type'] == 'taskList';

    if (isTaskList) {
      final nodes = <Node>[];
      for (final child in element.children) {
        if (child.localName?.toLowerCase() == 'li') {
          final checked = child.attributes['data-checked'] == 'true';
          nodes.add(
            todoListNode(
              checked: checked,
              delta: _buildDeltaFromElement(child),
            )..id = _uuid.v4(),
          );
        }
      }
      return nodes;
    } else {
      final listType =
          element.localName == 'ol' ? 'numbered_list' : 'bulleted_list';
      final listItems = <Node>[];

      for (final child in element.children) {
        if (child.localName?.toLowerCase() == 'li') {
          final delta = _buildDeltaFromElement(child);
          Node node;
          if (listType == 'bulleted_list') {
            node = bulletedListNode(delta: delta);
          } else {
            node = numberedListNode(delta: delta);
          }
          node.id = _uuid.v4();
          listItems.add(node);

          for (final nested in child.children
              .where((c) => ['ul', 'ol'].contains(c.localName))) {
            listItems.addAll(_createList(nested));
          }
        }
      }
      return listItems;
    }
  }

  static Node _createCodeBlock(dom.Element element) {
    final codeElement = element.querySelector('code');
    final target = codeElement ?? element;

    String? language;
    final classNames = target.classes;
    for (final cls in classNames) {
      if (cls.startsWith('language-')) {
        language = cls.substring(9);
        break;
      }
    }
    language = EditorMigrationEngine._normalizeLanguage(language);

    var text = target.text;
    if (!text.endsWith('\n')) {
      text += '\n';
    }

    return Node(
      type: 'code',
      id: _uuid.v4(),
      attributes: {
        'language': language,
        'delta': (Delta()..insert(text)),
      },
    );
  }

  static Delta _buildDeltaFromElement(dom.Element element) {
    return _buildDeltaFromNodes(element.nodes);
  }

  static Delta _buildDeltaFromNodes(List<dom.Node> nodes) {
    final delta = Delta();
    for (final node in nodes) {
      _recursiveDeltaBuild(node, {}, delta);
    }
    if (!delta.toPlainText().endsWith('\n')) {
      delta.insert('\n');
    }
    return delta;
  }

  static void _recursiveDeltaBuild(
    dom.Node node,
    Map<String, dynamic> currentAttrs,
    Delta delta,
  ) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text != null && text.isNotEmpty) {
        delta.insert(
          text,
          attributes: currentAttrs.isEmpty ? null : Map.from(currentAttrs),
        );
      }
      return;
    }

    if (node.nodeType == dom.Node.ELEMENT_NODE) {
      final element = node as dom.Element;
      final newAttrs = Map<String, dynamic>.from(currentAttrs);

      switch (element.localName?.toLowerCase()) {
        case 'strong':
        case 'b':
          newAttrs['bold'] = true;
          break;
        case 'em':
        case 'i':
          newAttrs['italic'] = true;
          break;
        case 'u':
          newAttrs['underline'] = true;
          break;
        case 's':
        case 'del':
        case 'strike':
          newAttrs['strikethrough'] = true;
          break;
        case 'code':
          newAttrs['code'] = true;
          break;
        case 'a':
          if (element.attributes.containsKey('href')) {
            newAttrs['link'] = element.attributes['href'];
          }
          break;
        case 'br':
          delta.insert('\n');
          return;
      }

      for (final child in element.nodes) {
        _recursiveDeltaBuild(child, newAttrs, delta);
      }
    }
  }
}

enum _Format { html, tiptap, appflowy, nblock, markdown, unknown }
