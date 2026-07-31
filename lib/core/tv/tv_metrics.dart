import 'package:flutter/widgets.dart';
import 'package:shonenx/core/utils/responsive.dart';

/// Layout constants for the 10-foot UI.
class TvMetrics {
  TvMetrics._();

  /// Fraction of each edge treated as unsafe.
  ///
  /// TVs overscan: a slice of the framebuffer around the border may not be
  /// visible on the physical panel. Android's guidance is a 5% total safe-area
  /// inset, i.e. 2.5% per edge -- 48px horizontally and 27px vertically at
  /// 1080p, scaling automatically at 4K.
  static const double overscanFraction = 0.025;

  static EdgeInsets of(ResponsiveData r) => EdgeInsets.symmetric(
    horizontal: r.width * overscanFraction,
    vertical: r.height * overscanFraction,
  );

  static double horizontalOf(ResponsiveData r) => r.width * overscanFraction;

  static double verticalOf(ResponsiveData r) => r.height * overscanFraction;

  /// Same insets from a raw [Size], for widgets that sit outside the
  /// `ResponsiveHandler` (the player runs on its own route) or that only need
  /// one edge and would rather not pull in the whole responsive model.
  static EdgeInsets ofSize(Size size) => EdgeInsets.symmetric(
    horizontal: size.width * overscanFraction,
    vertical: size.height * overscanFraction,
  );

  static double horizontalOfSize(Size size) => size.width * overscanFraction;

  static double verticalOfSize(Size size) => size.height * overscanFraction;
}

/// Focus treatment shared by every focusable surface, so cards, rail items,
/// list tiles and player buttons all read as one language.
class TvFocus {
  TvFocus._();

  static const double ringWidth = 3.0;
  static const double scale = 1.06;
  static const Duration animation = Duration(milliseconds: 160);
  static const Curve curve = Curves.easeOutCubic;
}
