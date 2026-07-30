import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

enum TvButtonVariant {
  /// Primary action. Red fill, white content.
  filledRed,

  /// Secondary action. White fill, dark content.
  filledWhite,

  /// Neutral action sitting beside a primary one, e.g. a dialog's cancel.
  filledSurface,

  /// Tertiary action. No fill at all -- only the focus ring marks it out.
  bare,
}

/// The action buttons on the detail screen and in dialogs.
///
/// Deliberately not a Material `FilledButton`: those carry an elevation
/// overlay, a ripple and a state-layer wash that all read as noise at 10 feet,
/// and their focus treatment is the ~20%-alpha background the TV work already
/// replaced everywhere else.
class TvButton extends StatelessWidget {
  final String label;

  /// Rendered in bold after [label], as in `Watch **Dubbed**`.
  final String? emphasis;

  final IconData? icon;
  final VoidCallback? onPressed;
  final TvButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Swaps the icon for a spinner and swallows presses. Resolving a stream can
  /// take a couple of seconds, and without this the button looks dead.
  final bool loading;

  /// Null lets the button size to its content, which is what the bare variant
  /// and dialog buttons want.
  final double? width;

  final double height;

  /// Scroll into view on focus. Turn off where the button is known to be in
  /// the first screenful: the default centres it, which on a scrollable page
  /// silently scrolls the heading above it out of sight.
  final bool ensureVisible;

  const TvButton({
    super.key,
    required this.label,
    this.emphasis,
    this.icon,
    this.onPressed,
    this.variant = TvButtonVariant.filledRed,
    this.autofocus = false,
    this.focusNode,
    this.loading = false,
    this.width,
    this.height = 64,
    this.ensureVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (Color background, Color foreground) = switch (variant) {
      TvButtonVariant.filledRed => (cs.primary, Colors.white),
      TvButtonVariant.filledWhite => (Colors.white, ShonenX.bg),
      TvButtonVariant.filledSurface => (cs.surfaceContainer, cs.onSurface),
      TvButtonVariant.bare => (Colors.transparent, cs.onSurface),
    };

    final labelStyle = theme.textTheme.titleMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );

    return TvFocusable(
      onTap: loading ? null : onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      ensureVisible: ensureVisible,
      borderRadius: BorderRadius.circular(8),
      // The ring sits outside the fill, so the button must not also grow --
      // two rows of these would jostle each other.
      scaleOnFocus: false,
      child: Container(
        // The ring is a Border, and a Border takes up its width even when
        // transparent. Deduct it so [width] and [height] describe the box the
        // caller laid out for, not six pixels more.
        width: width == null ? null : width! - TvFocus.ringWidth * 2,
        height: height - TvFocus.ringWidth * 2,
        padding: EdgeInsets.symmetric(
          horizontal: variant == TvButtonVariant.bare ? 12 : 24,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 12),
            ] else if (icon != null) ...[
              Icon(icon, size: 24, color: foreground),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text.rich(
                TextSpan(
                  text: emphasis == null ? label : '$label ',
                  children: emphasis == null
                      ? null
                      : [
                          TextSpan(
                            text: emphasis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                ),
                style: labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
