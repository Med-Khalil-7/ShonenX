import 'package:shonenx/shared/models/component_layout.dart';

class GlobalUI {
  static double uiScaleFactor = 1.0;
  static double uiRoundness = 6.0;
}

class LayoutVariants {
  final ComponentLayout normal;
  final ComponentLayout wide;
  final ComponentLayout wideContinue;
  final ComponentLayout continueWatching;

  const LayoutVariants({
    required this.normal,
    ComponentLayout? wide,
    ComponentLayout? wideContinue,
    required this.continueWatching,
  }) : wide = wide ?? const ComponentLayout(width: 340, height: 115),
       wideContinue =
           wideContinue ?? const ComponentLayout(width: 360, height: 120);

  ComponentLayout resolve({
    bool isContinueWatching = false,
    bool isWideMode = false,
  }) {
    if (isWideMode) {
      return isContinueWatching ? wideContinue : wide;
    }
    return isContinueWatching ? continueWatching : normal;
  }
}

enum MediaCardStyle {
  // Two styles only. Nine existed for phone personalisation; on a fixed
  // 10-foot layout the choice is poster or wide, and each extra style is
  // another focus treatment to keep consistent.
  //
  // Dimensions are TV-native. The card lays itself out at these sizes and
  // scales via FittedBox, so they are the real design size rather than a
  // phone size scaled up.
  classic(
    'Poster',
    LayoutVariants(
      normal: ComponentLayout(width: 240, height: 380),
      continueWatching: ComponentLayout(width: 300, height: 260),
    ),
  ),

  cinematic(
    'Wide',
    LayoutVariants(
      normal: ComponentLayout(width: 460, height: 180),
      wide: ComponentLayout(width: 520, height: 190),
      wideContinue: ComponentLayout(width: 540, height: 190),
      continueWatching: ComponentLayout(width: 460, height: 180),
    ),
  );

  final String displayName;
  final LayoutVariants _variants;

  const MediaCardStyle(this.displayName, this._variants);

  ComponentLayout get baseLayout => _variants.normal;
  ComponentLayout get layout => getScaledLayout(GlobalUI.uiScaleFactor);

  ComponentLayout getBaseLayout({
    bool isContinueWatching = false,
    bool isWideMode = false,
  }) {
    return _variants.resolve(
      isContinueWatching: isContinueWatching,
      isWideMode: isWideMode,
    );
  }

  ComponentLayout getLayout({
    bool isContinueWatching = false,
    bool isWideMode = false,
  }) {
    return getScaledLayout(
      GlobalUI.uiScaleFactor,
      isContinueWatching: isContinueWatching,
      isWideMode: isWideMode,
    );
  }

  ComponentLayout getScaledLayout(
    double scale, {
    bool isContinueWatching = false,
    bool isWideMode = false,
  }) {
    final base = getBaseLayout(
      isContinueWatching: isContinueWatching,
      isWideMode: isWideMode,
    );
    return ComponentLayout(
      width: base.width * scale,
      height: base.height * scale,
    );
  }
}

typedef ContinueWatchingStyle = MediaCardStyle;
typedef ContinueReadingStyle = MediaCardStyle;

enum NavBarStyle {
  classic('Classic'),
  minimal('Minimal'),
  frosted('Frosted Glass'),
  material('Material You');

  final String displayName;
  const NavBarStyle(this.displayName);
}
