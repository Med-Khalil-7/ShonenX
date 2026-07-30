import 'package:flutter/widgets.dart';

/// Design tokens for the 10-foot UI.
///
/// These are the raw values the TV screens are laid out against. The colours
/// are also plumbed into the `shonenx` colour scheme (see `exclusive_schemes`
/// and `AppTheme._buildTheme`) so generic Material widgets land on the same
/// palette. Reach for `Theme.of(context).colorScheme` where a widget is
/// scheme-driven, and for these constants where an exact measurement is being
/// reproduced.
abstract final class ShonenX {
  /// Scheme key. The screens still render on any other scheme, they just stop
  /// being pixel-exact.
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

  // --- Rail ---------------------------------------------------------------

  static const railWidth = 120.0;
  static const railLogoSize = 56.0;
  static const railLogoRadius = 14.0;
  static const railItemSize = 64.0;
  static const railIconSize = 32.0;
  static const railIndicator = Size(5, 36);

  // --- Content ------------------------------------------------------------

  /// Gutter between the rail and the content column.
  static const contentPadH = 56.0;

  static const posterRadius = 8.0;

  /// Home row posters.
  static const rowPosterWidth = 170.0;
  static const rowPosterHeight = 255.0;
  static const rowGap = 24.0;

  /// The hero takes most of the first screenful; the row below peeks in.
  static const heroHeightFraction = 0.62;
  static const heroPosterWidth = 300.0;

  /// Detail screen poster.
  static const detailPosterWidth = 340.0;

  // --- Search -------------------------------------------------------------

  static const searchColumnWidth = 437.0;
  static const searchFieldHeight = 66.0;
  static const searchFieldRadius = 16.0;
  static const keyboardRadius = 6.0;
  static const keyboardColumns = 6;
  static const keyHeight = 62.0;
  static const resultThumbWidth = 92.0;
  static const resultThumbHeight = 132.0;

  // --- Player -------------------------------------------------------------

  static const playerIconSize = 36.0;
  static const playerTopIconGap = 40.0;
  static const transportIconSize = 40.0;
  static const transportGap = 44.0;
  static const seekTrackHeight = 4.0;
  static const seekThumbRadius = 6.0;
  static const seekThumbRadiusFocused = 8.0;
  static const centerIndicatorSize = 120.0;
}
