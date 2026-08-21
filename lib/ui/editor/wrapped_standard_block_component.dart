import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:krag_app/utils/logger.dart';
import 'block_actions_helper.dart';

class WrappedStandardBlockComponentBuilder extends BlockComponentBuilder {
  final BlockComponentBuilder originalBuilder;

  WrappedStandardBlockComponentBuilder({
    required this.originalBuilder,
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    try {
      final innerWidget = originalBuilder.build(blockComponentContext);
      return WrappedStandardBlockWidget(
        key: ValueKey('wrapped_${node.id}'),
        node: node,
        configuration: configuration,
        child: innerWidget,
      );
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.general,
        'Block build error for ${node.type}',
        e,
        stack,
      );
      return _SafeErrorWidget(node: node, configuration: configuration);
    }
  }
}

class _SafeErrorWidget extends BlockComponentStatefulWidget {
  const _SafeErrorWidget({
    required super.node,
    required super.configuration,
  });

  @override
  State<_SafeErrorWidget> createState() => _SafeErrorWidgetState();
}

class _SafeErrorWidgetState extends State<_SafeErrorWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE57373)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE57373), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Error rendering ${node.type} block (ID: ${node.id})',
              style: const TextStyle(color: Color(0xFFE57373), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class WrappedStandardBlockWidget extends BlockComponentStatefulWidget {
  final Widget child;

  const WrappedStandardBlockWidget({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
    required this.child,
  });

  @override
  State<WrappedStandardBlockWidget> createState() =>
      _WrappedStandardBlockWidgetState();
}

class _WrappedStandardBlockWidgetState extends State<WrappedStandardBlockWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  bool _isHovered = false;
  bool _showBlockTypePicker = false;
  BlockActionsHelper? _actionsHelper;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.mounted && _actionsHelper == null) {
      _actionsHelper = BlockActionsHelper(
        context: context,
        node: node,
        onUpdate: () {
          if (mounted) {
            _removeOverlay();
            setState(() {});
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _actionsHelper = null;
    super.dispose();
  }

  void _showMobileActions() {
    if (_actionsHelper == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _actionsHelper!.buildMobileActionSheet(context),
    );
  }

  void _unlockBlock() {
    final editor = _actionsHelper?.editorState;
    if (editor != null) {
      final transaction = editor.transaction;
      transaction.updateNode(node, {'custom_locked': false});
      editor.apply(transaction);
    }
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _showBlockTypePicker = true;
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _showBlockTypePicker = false;
      });
    }
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            width: 200,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 32),
              child: _actionsHelper!.buildBlockTypePicker(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_actionsHelper == null) {
      return widget.child;
    }

    final platform = Theme.of(context).platform;
    final width = MediaQuery.of(context).size.width;
    final isMobile = platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        width < 600;

    final isLocked = node.attributes['custom_locked'] == true;
    final blockPadding = configuration.padding(node);

    if (isLocked) {
      final lockedContent = GestureDetector(
        onTap: _unlockBlock,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          margin: blockPadding,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock, color: Color(0xFFA0A0A0), size: 16),
              SizedBox(width: 8),
              Text(
                'Content Locked',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );

      if (isMobile) {
        return lockedContent;
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 28),
          Expanded(child: lockedContent),
          const SizedBox(width: 28),
        ],
      );
    }

    // Apply the configured padding to the block content
    final paddedChild = Padding(
      padding: blockPadding,
      child: widget.child,
    );

    if (isMobile) {
      return GestureDetector(
        onLongPress: _showMobileActions,
        behavior: HitTestBehavior.translucent,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: paddedChild,
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topRight,
        children: [
          CompositedTransformTarget(
            link: _layerLink,
            child: paddedChild,
          ),
          if (_isHovered || _showBlockTypePicker)
            Positioned(
              right: 0,
              top: -6,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _isHovered || _showBlockTypePicker ? 1.0 : 0.0,
                child: _actionsHelper!.buildCompactFloatingToolbar(
                  onToggleBlockTypePicker: _toggleOverlay,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
