import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../../services/block_encryption_service.dart';
import '../../services/crypto_service.dart';
import '../../services/session_service.dart';
import 'block_wrapper.dart';

// This widget wraps any block content to provide encryption capabilities
class EncryptedBlockWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final Node node;
  final EditorState editorState;

  const EncryptedBlockWrapper({
    super.key,
    required this.child,
    required this.node,
    required this.editorState,
  });

  @override
  ConsumerState<EncryptedBlockWrapper> createState() =>
      _EncryptedBlockWrapperState();
}

class _EncryptedBlockWrapperState extends ConsumerState<EncryptedBlockWrapper> {
  late BlockEncryptionService _encryptionService;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _encryptionService =
        BlockEncryptionService(CryptoService(), SessionService());
  }

  bool get _isLocked {
    return widget.node.attributes['locked'] == true;
  }

  // TODO: Add UI for locking/unlocking blocks
  Future<void> _lockBlock() async {
    setState(() => _isProcessing = true);
    try {
      // Serialize the whole node to JSON to preserve content/attributes
      final contentJson = jsonEncode(widget.node.toJson());

      // Encrypt
      final result = await _encryptionService.encryptBlockContent(contentJson);

      final transaction = widget.editorState.transaction;

      // Update attributes to store encryption data
      transaction.updateNode(widget.node, {
        'locked': true,
        'encryptedData': result['encryptedData'],
        'iv': result['iv'],
      });

      widget.editorState.apply(transaction);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to lock block: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _unlockBlock() async {
    setState(() => _isProcessing = true);
    try {
      final iv = widget.node.attributes['iv'] as String?;
      final encryptedData = widget.node.attributes['encryptedData'] as String?;

      if (iv == null || encryptedData == null) {
        throw Exception('Missing encryption data');
      }

      // Decrypt (verification step)
      await _encryptionService.decryptBlockContent(iv, encryptedData);

      final transaction = widget.editorState.transaction;
      transaction.updateNode(widget.node, {
        'locked': false,
        'encryptedData': null,
        'iv': null,
      });
      widget.editorState.apply(transaction);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unlock block: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return BlockWrapper(
        editorState: widget.editorState,
        node: widget.node,
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock, color: Color(0xFFA0A0A0), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Locked Content',
                  style: const TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (_isProcessing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: _unlockBlock,
                  child: const Text('Unlock'),
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        widget.child,
      ],
    );
  }
}

// Helper to wrap standard builders
// Explicitly using Widget Function(BlockComponentContext) to ensure it's treated as a callable
encryptedBuilder(
  EditorState editorState,
  Widget Function(BlockComponentContext) originalBuilder,
) {
  return (BlockComponentContext context) {
    final child = originalBuilder(context);
    return EncryptedBlockWrapper(
      node: context.node,
      editorState: editorState,
      child: child,
    );
  };
}
