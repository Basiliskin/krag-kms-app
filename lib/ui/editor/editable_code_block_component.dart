import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart' hide Node;
import 'package:highlight/languages/all.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import '../../utils/logger.dart';

class EditableCodeBlockComponentBuilder extends BlockComponentBuilder {
  EditableCodeBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return EditableCodeBlockWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }
}

class EditableCodeBlockWidget extends BlockComponentStatefulWidget {
  const EditableCodeBlockWidget({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<EditableCodeBlockWidget> createState() =>
      _EditableCodeBlockWidgetState();
}

class _EditableCodeBlockWidgetState extends State<EditableCodeBlockWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late CodeController _codeController;
  String _currentLanguage = 'plaintext';
  String _placeholder = 'Enter code here...';
  bool _showLanguagePicker = false;
  EditorState? _editorState;

  @override
  void initState() {
    super.initState();
    _currentLanguage = node.attributes['language'] as String? ?? 'plaintext';
    _placeholder =
        node.attributes['placeholder'] as String? ?? 'Enter code here...';
    _codeController = CodeController(
      text: _getCodeText(),
      language: _getLanguageMode(_currentLanguage),
    );
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_editorState == null && mounted) {
      context.visitAncestorElements((element) {
        final w = element.widget;
        if (w is AppFlowyEditor) {
          _editorState = w.editorState;
          return false;
        }
        return true;
      });
    }
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    final newText = _codeController.text;
    final oldText = _getCodeText();

    if (newText != oldText) {
      final editor = _editorState;
      if (editor != null) {
        // Use a transaction to update the node. This ensures the change is
        // captured by the EditorState's transactionStream and triggers persistence.
        final transaction = editor.transaction;
        transaction.updateNode(node, {
          'delta': Delta()..insert(newText),
        });
        editor.apply(transaction);
      } else {
        // Fallback if editor state is not found yet (should not happen after build)
        node.updateAttributes({
          'delta': Delta()..insert(newText),
        });
      }
    }
  }

  @override
  void didUpdateWidget(EditableCodeBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      final newText = _getCodeText();
      if (_codeController.text != newText) {
        _codeController.removeListener(_onCodeChanged);
        _codeController.text = newText;
        _codeController.addListener(_onCodeChanged);
      }

      final newLang = node.attributes['language'] as String? ?? 'plaintext';
      if (_currentLanguage != newLang) {
        setState(() {
          _currentLanguage = newLang;
          _codeController.language = _getLanguageMode(newLang);
        });
      }

      final newPlaceholder =
          node.attributes['placeholder'] as String? ?? 'Enter code here...';
      if (_placeholder != newPlaceholder) {
        setState(() {
          _placeholder = newPlaceholder;
        });
      }
    }
  }

  Mode _getLanguageMode(String language) {
    return builtinLanguages[language] ??
        builtinLanguages['plaintext'] ??
        Mode();
  }

  String _getCodeText() {
    final deltaAttr = node.attributes['delta'];
    Delta? delta;
    if (deltaAttr != null) {
      if (deltaAttr is Delta) {
        delta = deltaAttr;
      } else if (deltaAttr is List) {
        try {
          delta = Delta.fromJson(
            List<Map<String, dynamic>>.from(
              deltaAttr.map((e) => Map<String, dynamic>.from(e as Map)),
            ),
          );
        } catch (e) {
          KragLogger.error(LogDomain.general, 'Failed to parse delta', e);
        }
      }
    }
    return delta?.toPlainText() ?? '';
  }

  void _updateLanguage(String newLanguage) {
    final editor = _editorState;
    if (editor != null) {
      final transaction = editor.transaction;
      transaction.updateNode(node, {
        'language': newLanguage,
      });
      editor.apply(transaction);
    } else {
      node.updateAttributes({
        'language': newLanguage,
      });
    }

    setState(() {
      _currentLanguage = newLanguage;
      _codeController.language = _getLanguageMode(newLanguage);
      _showLanguagePicker = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: configuration.padding(node),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF3A3A3A),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_showLanguagePicker) _buildLanguagePicker(),
            _buildCodeContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF3A3A3A),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showLanguagePicker = !_showLanguagePicker;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _showLanguagePicker
                      ? const Color(0xFFFF6B00)
                      : const Color(0xFF3A3A3A),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentLanguage,
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _showLanguagePicker
                        ? Icons.arrow_drop_up
                        : Icons.arrow_drop_down,
                    size: 16,
                    color: const Color(0xFFA0A0A0),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePicker() {
    final languages = [
      'plaintext',
      'dart',
      'javascript',
      'typescript',
      'python',
      'java',
      'kotlin',
      'swift',
      'rust',
      'go',
      'cpp',
      'c',
      'csharp',
      'ruby',
      'php',
      'html',
      'css',
      'scss',
      'json',
      'yaml',
      'xml',
      'sql',
      'bash',
      'shell',
      'markdown',
    ];
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: ListView.builder(
        itemCount: languages.length,
        itemBuilder: (context, index) {
          final language = languages[index];
          final isSelected = language == _currentLanguage;
          return InkWell(
            onTap: () => _updateLanguage(language),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: isSelected ? const Color(0xFF2A2A2A) : Colors.transparent,
              child: Text(
                language,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF6B00)
                      : const Color(0xFFEDEDED),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCodeContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: CodeField(
              controller: _codeController,
              gutterStyle: GutterStyle.none,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: Color(0xFFEDEDED),
                height: 1.5,
                letterSpacing: 0.2,
              ),
              maxLines: null,
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _codeController,
            builder: (context, value, child) {
              if (value.text.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _placeholder,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: Color(0xFF5A5A5A),
                      height: 1.5,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
