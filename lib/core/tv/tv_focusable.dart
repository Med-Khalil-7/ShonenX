import 'package:flutter/material.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/core/utils/focus_hover_detector.dart';

/// A focusable surface with a focus ring that is actually visible from a sofa.
///
/// Material's default focus treatment is a ~20%-alpha background wash. It is
/// measurable but effectively invisible at 10 feet, which was the single
/// biggest gap found when driving the app by D-pad. This wraps
/// [FocusHoverDetector] and draws a real outline plus a slight scale-up.
///
/// Cards do not use this -- they already render their own focus state through
/// `CardConfig.isActive`. This is for everything else: rail items, list tiles,
/// chips, player controls, onboarding buttons.
class TvFocusable extends StatelessWidget {
  /// Static content. Omit when supplying a [builder].
  final Widget? child;

  /// Built instead of [child] when focus state should change the content
  /// itself rather than just the frame.
  final Widget Function(BuildContext context, bool isFocused)? builder;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final bool canRequestFocus;
  final bool ensureVisible;
  final double alignment;

  /// Matches the surface being wrapped so the ring hugs its corners.
  final BorderRadius? borderRadius;

  /// Fill the surface when focused. Right for list rows and rail items; wrong
  /// for anything already carrying its own strong colour.
  final bool filledWhenFocused;

  /// Colour of the focus ring. Defaults to white: the accent red reads as
  /// *selected* elsewhere in the UI, so using it for focus too would make the
  /// two states indistinguishable. Pass [Colors.transparent] when the child
  /// signals focus some other way (the player tints its icons instead).
  final Color? ringColor;

  /// Fill colour when [filledWhenFocused]. Defaults to the scheme primary.
  final Color? focusFillColor;

  final bool scaleOnFocus;

  /// Scale applied on focus. Defaults to [TvFocus.scale]; drop to 1.0 inside
  /// tight grids, where a scaled cell clips against its neighbours.
  final double? focusScale;

  final EdgeInsetsGeometry? padding;

  const TvFocusable({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.canRequestFocus = true,
    this.ensureVisible = true,
    this.alignment = 0.5,
    this.borderRadius,
    this.filledWhenFocused = false,
    this.ringColor,
    this.focusFillColor,
    this.scaleOnFocus = true,
    this.focusScale,
    this.padding,
  }) : assert(
         child != null || builder != null,
         'TvFocusable needs either a child or a builder',
       );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius =
        borderRadius ?? BorderRadius.circular(GlobalUiRadius.of(context));

    return FocusHoverDetector(
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      canRequestFocus: canRequestFocus,
      ensureVisible: ensureVisible,
      alignment: alignment,
      onTap: onTap,
      onLongPress: onLongPress,
      // Without these the widget is unreachable by remote: GestureDetector
      // only fires on pointer taps, and DPAD_CENTER arrives as an
      // ActivateIntent that needs an Action to catch it.
      actions: onTap == null
          ? null
          : <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  onTap!();
                  return null;
                },
              ),
              ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
                onInvoke: (_) {
                  onTap!();
                  return null;
                },
              ),
            },
      builder: (context, isFocused, isHovered) {
        final active = isFocused || isHovered;
        final ring = ringColor ?? cs.onSurface;
        final fill = focusFillColor ?? cs.primary;

        Widget content = builder?.call(context, active) ?? child!;
        if (padding != null) {
          content = Padding(padding: padding!, child: content);
        }

        final onFill = ThemeData.estimateBrightnessForColor(fill) ==
                Brightness.dark
            ? Colors.white
            : Colors.black;

        return AnimatedScale(
          scale: active && scaleOnFocus ? (focusScale ?? TvFocus.scale) : 1.0,
          duration: TvFocus.animation,
          curve: TvFocus.curve,
          child: AnimatedContainer(
            duration: TvFocus.animation,
            curve: TvFocus.curve,
            decoration: BoxDecoration(
              color: active && filledWhenFocused ? fill : Colors.transparent,
              borderRadius: radius,
              border: Border.all(
                color: active ? ring : Colors.transparent,
                width: TvFocus.ringWidth,
              ),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: active && filledWhenFocused ? onFill : null,
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: active && filledWhenFocused ? onFill : null,
                ),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reads the app's configured corner radius without every caller having to
/// reach into the theme prefs.
class GlobalUiRadius {
  GlobalUiRadius._();

  static double of(BuildContext context) {
    final shape = Theme.of(context).cardTheme.shape;
    if (shape is RoundedRectangleBorder) {
      final r = shape.borderRadius;
      if (r is BorderRadius) return r.topLeft.x;
    }
    return 12;
  }
}
