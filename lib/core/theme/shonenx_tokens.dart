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
  static const searchFieldRadius = 16.0;
  static const keyboardRadius = 6.0;
  static const keyboardColumns = 6;

  /// Posters are 2:3 everywhere. Height is always derived from width so the
  /// two can never drift apart.
  static const posterAspect = 2 / 3;

  /// Slide-strip thumbnails are slightly taller than wide.
  static const thumbAspect = 0.85;

  /// The hero carries metadata, a synopsis and the slide strip, and the first
  /// row peeks in below it.
  ///
  /// Cut from 0.72 once the strip moved up to sit under the synopsis: the
  /// hero's content ended well before its box did, so the extra height was
  /// pure empty space between the strip and the first row.
  static const heroHeightFraction = 0.56;
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
///
/// ## How these numbers were arrived at
///
/// The reference grab `Screenshot from 2026-07-30 20-23-22.png` is 1897x845
/// with the screen spanning x 14..1894, so ~1881px of real width. Measuring
/// the same elements there and in a device capture gives the ratio directly:
///
/// | element | reference | before | ratio |
/// |---|---|---|---|
/// | row poster (pitch 184.5, gap 8) | 0.094 | 0.140 | 0.67 |
/// | detail poster | 0.186 | 0.248 | 0.75 |
/// | Play now height, incl. ring | 0.034 | 0.050 | 0.68 |
/// | detail title ink | 0.0175 | 0.0234 | 0.75 |
/// | synopsis ink | 0.0101 | 0.0135 | 0.75 |
///
/// Two groups fall out: **boxes shrink ~0.67, type shrinks ~0.75**. Text
/// holding relatively larger than the boxes around it is right for a 10-foot
/// UI, and the same 0.75 comes out of two independent text measurements, so it
/// is the design rather than measurement noise. Anything measurable is set to
/// its measured value; everything else follows its group's factor.
///
/// The player overlay is deliberately **not** on this scale -- see the player
/// group at the bottom.
class ShonenXMetrics {
  /// Viewport width in logical pixels.
  final double w;

  const ShonenXMetrics(this.w);

  factory ShonenXMetrics.of(BuildContext context) =>
      ShonenXMetrics(MediaQuery.sizeOf(context).width);

  // --- Layout -------------------------------------------------------------

  double get railWidth => w * 0.064;
  double get railIcon => w * 0.019;

  /// Above the reference scale, like the hero thumbnails: the mark is the only
  /// thing on the rail that says which app this is, and at the icon sizes
  /// around it there was nothing to recognise.
  double get railLogo => w * 0.046;
  double get railItem => w * 0.042;
  Size get railIndicator => Size(w * 0.003, w * 0.020);

  /// Width the rail grows to when it takes focus.
  ///
  /// Drawn over the content rather than pushing it, so this width costs
  /// nothing below it -- see `TvSideRail`.
  double get railExpandedWidth => w * 0.235;

  /// Left inset of the rail's icons, held constant across the expansion so the
  /// icons stay put and only the labels arrive.
  double get railItemInset => w * 0.011;

  /// The left edge every screen aligns to.
  ///
  /// Margins deliberately do not scale with the rest: growing them only steals
  /// width from the content they frame.
  double gutter(Size size) =>
      math.max(w * 0.061, TvMetrics.horizontalOfSize(size));

  /// Where the detail screen's back arrow sits.
  ///
  /// The content column lands at `backArrowInset + arrow slot + backArrowGap`,
  /// which the reference puts at 0.073W with the arrow itself around 0.040W.
  /// These two are chosen so that sum comes out right -- changing either moves
  /// the column, not just the arrow.
  double get backArrowInset => w * 0.026;

  /// Clear space between the back arrow and the text beside it. Without it the
  /// arrow reads as part of the metadata line rather than as its own control.
  double get backArrowGap => w * 0.016;

  /// Gutter for content that already sits inside the navigation rail's
  /// padding. The rail has consumed part of the margin, so only the remainder
  /// is added -- otherwise the two stack and the column starts twice as far in
  /// as the design calls for.
  ///
  /// At the reference scale the rail is wider than the plain gutter, so this
  /// is the floor in practice: `railWidth + 0.025` puts shell content at
  /// ~0.089W, which is where the reference home starts its rows.
  double shellGutter(Size size) =>
      math.max(gutter(size) - railWidth, w * 0.025);

  double get heroPoster => w * 0.180;
  double get rowPoster => w * 0.094;
  double get rowGap => w * 0.0045;
  double get detailPoster => w * 0.186;

  double get buttonWidth => w * 0.140;

  /// Slightly taller than the reference's 0.030: measured against the capture
  /// the labels sat tight to the top and bottom edges, and the extra reads as
  /// deliberate padding rather than as a bigger button.
  double get buttonHeight => w * 0.042;
  double get iconButton => w * 0.024;

  // --- Search -------------------------------------------------------------

  /// The search column runs a notch larger than the reference scale would put
  /// it. Everywhere else the user is reading; here they are aiming a D-pad at
  /// 38 individual keys, and the keys have to stay comfortable targets.
  double get searchColumn => w * 0.231;
  double get searchField => w * 0.039;
  double get keyHeight => w * 0.036;
  double get resultThumb => w * 0.054;

  // --- Type ---------------------------------------------------------------

  double get titleHero => w * 0.0248;
  double get titlePage => w * 0.0225;
  double get heading => w * 0.0180;
  double get meta => w * 0.0135;
  double get label => w * 0.0135;
  double get body => w * 0.0113;
  double get badge => w * 0.0098;

  // --- Player -------------------------------------------------------------

  /// The player overlay is held at the scale it was tuned to on a device and
  /// is **not** part of the reference rescale: it was reviewed and accepted as
  /// it stands, and the transport row in particular is read from across a room
  /// while the video plays behind it.
  ///
  /// Its side surfaces -- the audio panel, the settings panel, the exit dialog
  /// -- are ordinary app chrome and use the shared metrics above, so they do
  /// come down with everything else.

  double get playerIcon => w * 0.027;
  double get playerIconGap => w * 0.075;
  double get transportIcon => w * 0.030;
  double get transportGap => w * 0.100;
  double get seekTrack => w * 0.003;
  double get seekThumb => w * 0.005;
  double get centerIndicator => w * 0.090;

  /// Width of the scrub preview card. 16:9, so its height follows.
  double get seekPreview => w * 0.22;

  /// Type and button sizes for the overlay.
  ///
  /// These are what [heading], [meta] and [buttonHeight] were before the
  /// rescale. They are separate getters rather than shared ones so the overlay
  /// keeps its size when the app scale moves again -- borrowing the app's type
  /// is exactly how it would have been shrunk by accident.
  double get playerHeading => w * 0.024;
  double get playerLabel => w * 0.018;
  double get playerButtonHeight => w * 0.052;

  double get dialogWidth => w * 0.320;

  // --- Hero ---------------------------------------------------------------

  /// Width of one artwork thumbnail in the slide strip.
  ///
  /// Above the reference scale on purpose: these double as the carousel's
  /// page indicator, so they have to be identifiable as artwork at a glance
  /// and not just as dots.
  double get heroThumb => w * 0.047;
}
