import 'package:flutter/material.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

typedef InteractionStateBuilder =
    Widget Function(BuildContext context, bool isFocused, bool isHovered);

/// Focusable wrapper used by every interactive surface.
///
/// Kept as the single wrapper (rather than adding a parallel TV widget)
/// because `MediaCard` and the continue-watching cards already build on it and
/// every card style already consumes the resulting `isActive` flag.
class FocusHoverDetector extends StatefulWidget {
  final Widget Function(BuildContext context, bool isFocused, bool isHovered)
  builder;

  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;

  final Map<Type, Action<Intent>>? actions;

  final MouseCursor cursor;

  /// Supply one to drive focus programmatically (row/grid controllers).
  final FocusNode? focusNode;

  final bool autofocus;

  final ValueChanged<bool>? onFocusChange;

  final bool canRequestFocus;

  /// Scroll this widget into view when it gains focus. Essential on TV: focus
  /// routinely lands on an item that is off-screen.
  final bool ensureVisible;

  /// 0.5 centres the item in the viewport, which reads best for carousels.
  final double alignment;

  /// Treat the whole widget as one focus stop rather than letting inner
  /// buttons collect focus of their own.
  final bool descendantsAreFocusable;

  const FocusHoverDetector({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.actions,
    this.cursor = SystemMouseCursors.click,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.canRequestFocus = true,
    this.ensureVisible = true,
    this.alignment = 0.5,
    this.descendantsAreFocusable = false,
  });

  @override
  State<FocusHoverDetector> createState() => _FocusHoverDetectorState();
}

class _FocusHoverDetectorState extends State<FocusHoverDetector> {
  bool _isFocused = false;
  bool _isHovered = false;

  void _setFocused(bool value) {
    if (_isFocused == value) return;
    // NOTE: focus and hover used to clear each other. That meant a stray mouse
    // hover silently killed the D-pad focus ring. They are independent now;
    // callers already OR them together.
    setState(() => _isFocused = value);
    widget.onFocusChange?.call(value);

    if (value && widget.ensureVisible) {
      // Post-frame so the scrollable has settled before we measure.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = context;
        if (!ctx.mounted) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: widget.alignment,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: TvFocus.animation,
          curve: TvFocus.curve,
        );
      });
    }
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.canRequestFocus,
      descendantsAreFocusable: widget.descendantsAreFocusable,
      onShowFocusHighlight: _setFocused,
      onShowHoverHighlight: _setHovered,
      mouseCursor: widget.cursor,
      actions: widget.actions,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(context, _isFocused, _isHovered),
      ),
    );
  }
}
