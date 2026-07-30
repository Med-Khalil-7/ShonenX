import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

/// Colour and shape tokens for the 10-foot UI.
///
/// The colours are also plumbed into the `shonenx` colour scheme (see
/// `exclusive_schemes` and `AppTheme._buildTheme`) so generic Material widgets
/// land on the same palette. Reach for `Theme.of(context).colorScheme` where a
/// widget is scheme-driven and for these where an exact value is wanted.
///
/// Sizes do **not** live here -- see [ShonenXMetrics].
abstract final class ShonenX {
  /// Scheme key. The screens still render on any other scheme, they just stop
  /// matching the design.
  static const schemeKey = 'shonenx';

  // --- Colour -------------------------------------------------------------

  static const bg = Color(0xFF0E1216);
  static const surface = Color(0xFF171C22);
  static const surfaceContainer = Color(0xFF1E242B);

  /// Keyboard keys, dialog cards, raised rows.
  static const surfaceHigh = Color(0xFF262D36);

  static const outline = Color(0xFF39414B);

  /// Play now, the exit dialog's confirm button, the rail's active indicator,
  /// and the focused player transport icons.
  static const red = Color(0xFFE8352C);

  static const onSurface = Color(0xFFFFFFFF);
  static const onSurfaceVariant = Color(0xFFB4BCC6);

  // --- Focus --------------------------------------------------------------

  /// Surfaces get a white ring. Red is reserved for *selected* state, with the
  /// single exception of the player transport row, which tints its icons red
  /// instead of ringing them.
  static const ringColor = Color(0xFFFFFFFF);

  // --- Shape --------------------------------------------------------------

  static const posterRadius = 8.0;
  static const railLogoRadius = 14.0;
  static const searchFieldRadius = 16.0;
  static const keyboardRadius = 6.0;
  static const keyboardColumns = 6;

  /// Posters are 2:3 everywhere. Height is always derived from width so the
  /// two can never drift apart.
  static const posterAspect = 2 / 3;

  /// The hero carries metadata, a synopsis, two buttons and a page indicator,
  /// so it needs most of the screen; the first row still peeks in below.
  static const heroHeightFraction = 0.72;
}

/// Every size in the TV design, as a fraction of the viewport width.
///
/// These were measured off the reference captures, which are ~1920px wide. The
/// first attempt hardcoded those numbers as logical pixels, which is wrong:
/// Android TV at 1080p reports a 960x540 logical viewport, so every constant
/// rendered at roughly double its intended size. Expressing them as fractions
/// makes the design density-independent and resolution-independent, and makes
/// "does this match the reference?" a question that can be measured rather
/// than eyeballed.
///
/// Type sizes are here for the same reason, and are applied as explicit
/// `fontSize` values: the replica screens must not inherit Material's scale
/// *and* the 1.2x TV multiplier in `AppTheme._tvSizing` on top of it.
class ShonenXMetrics {
  /// Viewport width in logical pixels.
  final double w;

  const ShonenXMetrics(this.w);

  factory ShonenXMetrics.of(BuildContext context) =>
      ShonenXMetrics(MediaQuery.sizeOf(context).width);

  // --- Layout -------------------------------------------------------------

  double get railWidth => w * 0.095;
  double get railIcon => w * 0.028;
  double get railLogo => w * 0.045;
  double get railItem => w * 0.062;
  Size get railIndicator => Size(w * 0.0045, w * 0.030);

  /// The left edge every screen aligns to.
  ///
  /// Margins deliberately do not scale with the rest: growing them only steals
  /// width from the content they frame.
  double gutter(Size size) =>
      math.max(w * 0.091, TvMetrics.horizontalOfSize(size));

  double get backArrowInset => w * 0.061;

  /// Gutter for content that already sits inside the navigation rail's
  /// padding. The rail has consumed part of the margin, so only the remainder
  /// is added -- otherwise the two stack and the column starts twice as far in
  /// as the design calls for.
  double shellGutter(Size size) =>
      math.max(gutter(size) - railWidth, w * 0.020);

  double get heroPoster => w * 0.26;
  double get rowPoster => w * 0.14;
  double get rowGap => w * 0.008;
  double get detailPoster => w * 0.25;

  double get buttonWidth => w * 0.21;
  double get buttonHeight => w * 0.052;
  double get iconButton => w * 0.036;

  // --- Search -------------------------------------------------------------

  double get searchColumn => w * 0.30;
  double get searchField => w * 0.050;
  double get keyHeight => w * 0.046;
  double get resultThumb => w * 0.070;

  // --- Type ---------------------------------------------------------------

  double get titleHero => w * 0.033;
  double get titlePage => w * 0.030;
  double get heading => w * 0.024;
  double get meta => w * 0.018;
  double get label => w * 0.018;
  double get body => w * 0.015;
  double get badge => w * 0.013;

  // --- Player -------------------------------------------------------------

  double get playerIcon => w * 0.027;
  double get playerIconGap => w * 0.075;
  double get transportIcon => w * 0.030;
  double get transportGap => w * 0.100;
  double get seekTrack => w * 0.003;
  double get seekThumb => w * 0.005;
  double get centerIndicator => w * 0.090;
  double get dialogWidth => w * 0.400;

  // --- Hero ---------------------------------------------------------------

  double get heroDot => w * 0.006;
  double get heroDotActive => w * 0.020;
}
