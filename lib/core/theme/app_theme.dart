import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shonenx/shared/providers/theme_prefs_provider.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/theme/exclusive_schemes.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

typedef ThemeModifier =
    ThemeData Function(ThemeData theme, ThemePrefsState prefs);

class AppTheme {
  AppTheme._();

  /// Minimum hit target for a D-pad-driven UI.
  static const _tvButtonMinSize = Size(88, 44);

  static ThemeData light(ThemePrefsState prefs, ColorScheme? colorScheme) {
    return _buildTheme(
      brightness: Brightness.light,
      prefs: prefs,
      colorScheme: colorScheme,
    );
  }

  static ThemeData dark(ThemePrefsState prefs, ColorScheme? colorScheme) {
    return _buildTheme(
      brightness: Brightness.dark,
      prefs: prefs,
      colorScheme: colorScheme,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ThemePrefsState prefs,
    required ColorScheme? colorScheme,
  }) {
    final isDark = brightness == Brightness.dark;

    final exclusive = prefs.exclusiveScheme != null
        ? exclusiveSchemes[prefs.exclusiveScheme]
        : null;

    ColorScheme? effectiveColorScheme = colorScheme;
    if (effectiveColorScheme == null &&
        prefs.useImageColors &&
        prefs.wallpaperSettings?.imageColorSeed != null) {
      effectiveColorScheme = ColorScheme.fromSeed(
        seedColor: Color(prefs.wallpaperSettings!.imageColorSeed!),
        brightness: brightness,
      );
    } else if (effectiveColorScheme == null && prefs.colorSeed != null) {
      effectiveColorScheme = ColorScheme.fromSeed(
        seedColor: Color(prefs.colorSeed!),
        brightness: brightness,
      );
    }

    FlexSchemeColor? customColors;
    if (prefs.primaryColor != null && effectiveColorScheme == null) {
      final primary = Color(prefs.primaryColor!);
      final secondary = prefs.secondaryColor != null
          ? Color(prefs.secondaryColor!)
          : FlexSchemeColor.from(
              primary: primary,
              brightness: brightness,
            ).secondary;
      final tertiary = prefs.tertiaryColor != null
          ? Color(prefs.tertiaryColor!)
          : FlexSchemeColor.from(
              primary: primary,
              brightness: brightness,
            ).tertiary;

      customColors = FlexSchemeColor(
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
      );
    } else if (effectiveColorScheme == null && exclusive != null) {
      customColors = isDark ? exclusive.dark : exclusive.light;
    }

    final baseTheme = isDark
        ? FlexThemeData.dark(
            scheme:
                (customColors == null &&
                    effectiveColorScheme == null &&
                    exclusive == null)
                ? prefs.flexScheme
                : FlexScheme.custom,
            colors: customColors,
            colorScheme: effectiveColorScheme,
            keyColors: prefs.themeVariant == AppThemeVariant.classic
                ? null
                : const FlexKeyColors(
                    useKeyColors: true,
                    keepPrimary: true,
                    keepSecondary: true,
                    keepTertiary: true,
                    keepError: true,
                  ),
            variant: prefs.themeVariant.flexVariant,
            surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
            blendLevel: prefs.blendLevel,
            swapColors: prefs.swapColors,
            appBarStyle: FlexAppBarStyle.surface,
            appBarOpacity: prefs.useAmoled ? 1.0 : 0.90,
            transparentStatusBar: true,
            darkIsTrueBlack: prefs.useAmoled,
            textTheme: GoogleFonts.montserratTextTheme(),
            useMaterial3: true,
            swapLegacyOnMaterial3: true,
            visualDensity: FlexColorScheme.comfortablePlatformDensity,
            pageTransitionsTheme: _pageTransitionsTheme,
            subThemesData: _subThemesData(prefs),
          )
        : FlexThemeData.light(
            scheme:
                (customColors == null &&
                    effectiveColorScheme == null &&
                    exclusive == null)
                ? prefs.flexScheme
                : FlexScheme.custom,
            colors: customColors,
            colorScheme: effectiveColorScheme,
            keyColors: prefs.themeVariant == AppThemeVariant.classic
                ? null
                : const FlexKeyColors(useExpressiveOnContainerColors: true),
            variant: prefs.themeVariant.flexVariant,
            surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
            blendLevel: prefs.blendLevel,
            swapColors: prefs.swapColors,
            appBarStyle: FlexAppBarStyle.surface,
            appBarOpacity: 0.95,
            transparentStatusBar: true,
            textTheme: GoogleFonts.montserratTextTheme(),
            useMaterial3: true,
            swapLegacyOnMaterial3: true,
            visualDensity: FlexColorScheme.comfortablePlatformDensity,
            pageTransitionsTheme: _pageTransitionsTheme,
            subThemesData: _subThemesData(prefs),
          );

    ThemeData result = baseTheme;
    if (isDark && prefs.exclusiveScheme == ShonenX.schemeKey) {
      // FlexColorScheme derives surfaces by blending the primary into a
      // neutral. The TV design needs exact values, so pin them after the fact
      // rather than hunting for a blend that happens to land on them.
      result = result.copyWith(
        scaffoldBackgroundColor: ShonenX.bg,
        canvasColor: ShonenX.bg,
        colorScheme: result.colorScheme.copyWith(
          surface: ShonenX.bg,
          surfaceContainerLowest: ShonenX.bg,
          surfaceContainerLow: ShonenX.surface,
          surfaceContainer: ShonenX.surfaceContainer,
          surfaceContainerHigh: ShonenX.surfaceHigh,
          surfaceContainerHighest: ShonenX.surfaceHigh,
          outline: ShonenX.outline,
          outlineVariant: ShonenX.outline,
          onSurface: ShonenX.onSurface,
          onSurfaceVariant: ShonenX.onSurfaceVariant,
        ),
      );
    } else if (isDark && prefs.useAmoled) {
      result = result.copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: result.colorScheme.copyWith(
          surface: const Color(0xFF000000),
        ),
      );
    } else if (prefs.surfaceColor != null) {
      final sCol = Color(prefs.surfaceColor!);
      result = result.copyWith(
        scaffoldBackgroundColor: sCol,
        colorScheme: result.colorScheme.copyWith(surface: sCol),
      );
    }

    return _themeModifiers.fold(
      result,
      (theme, modifier) => modifier(theme, prefs),
    );
  }

  static final List<ThemeModifier> _themeModifiers = [
    _widgets,
    _shadows,
    _tvSizing,
  ];

  static ThemeData _widgets(ThemeData theme, ThemePrefsState prefs) {
    final cs = theme.colorScheme;

    return theme.copyWith(
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: cs.surfaceContainerHigh,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(prefs.uiRoundness),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: cs.primary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(prefs.uiRoundness),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(prefs.uiRoundness),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(prefs.uiRoundness),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(prefs.uiRoundness),
          ),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        filled: true,
      ),
    );
  }

  static ThemeData _shadows(ThemeData theme, ThemePrefsState prefs) {
    return theme.copyWith(shadowColor: Colors.transparent);
  }

  /// Type multiplier for the Material-styled screens.
  ///
  /// Settings, extensions, history and the sheets are not in the design
  /// reference and inherit Material's scale rather than [ShonenXMetrics]. When
  /// the replica screens were rescaled to the reference they came down by
  /// ~0.75 on type and ~0.67 on boxes, and a 1.2x multiplier here left these
  /// screens visibly larger than everything they sit next to.
  static const double _tvTextScale = 0.9;

  /// Undoes [_tvSizing]'s type scale for a subtree.
  ///
  /// Media cards lay themselves out against fixed pixel dimensions and then
  /// scale the whole card with a FittedBox, so their internal typography is
  /// already sized for the design. Letting the global 10-foot scale through
  /// makes the title overflow the card by a few pixels instead of making it
  /// bigger.
  static TextTheme cardTextTheme(TextTheme scaled) => TextTheme(
    displayLarge: _descale(scaled.displayLarge),
    displayMedium: _descale(scaled.displayMedium),
    displaySmall: _descale(scaled.displaySmall),
    headlineLarge: _descale(scaled.headlineLarge),
    headlineMedium: _descale(scaled.headlineMedium),
    headlineSmall: _descale(scaled.headlineSmall),
    titleLarge: _descale(scaled.titleLarge),
    titleMedium: _descale(scaled.titleMedium),
    titleSmall: _descale(scaled.titleSmall),
    bodyLarge: _descale(scaled.bodyLarge),
    bodyMedium: _descale(scaled.bodyMedium),
    bodySmall: _descale(scaled.bodySmall),
    labelLarge: _descale(scaled.labelLarge),
    labelMedium: _descale(scaled.labelMedium),
    labelSmall: _descale(scaled.labelSmall),
  );

  static TextStyle? _descale(TextStyle? s) => s?.fontSize == null
      ? s
      : s!.copyWith(fontSize: s.fontSize! / _tvTextScale);

  /// Material's stock focus treatment is a ~20%-alpha wash, which measures as
  /// a real repaint but is invisible from a sofa. Every Material button gets a
  /// hard outline instead, so focus is unmistakable without wrapping each call
  /// site. The colour is deliberately high-contrast rather than the primary
  /// tone, so it also reads on top of an already-primary-filled button.
  static WidgetStateProperty<BorderSide?> _focusRing(ColorScheme cs) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: cs.onSurface, width: TvFocus.ringWidth);
        }
        return null;
      });

  static WidgetStateProperty<Color?> _focusOverlay(ColorScheme cs) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return cs.onSurface.withValues(alpha: 0.14);
        }
        return null;
      });

  /// Material 3 default sizes, used as the base when a slot leaves `fontSize`
  /// null. GoogleFonts text themes do exactly that for several slots, and
  /// `TextTheme.apply(fontSizeFactor:)` asserts on a null fontSize -- so the
  /// scaling has to be done per slot rather than with `apply`.
  static const Map<String, double> _m3TextSizes = {
    'displayLarge': 57,
    'displayMedium': 45,
    'displaySmall': 36,
    'headlineLarge': 32,
    'headlineMedium': 28,
    'headlineSmall': 24,
    'titleLarge': 22,
    'titleMedium': 16,
    'titleSmall': 14,
    'bodyLarge': 16,
    'bodyMedium': 14,
    'bodySmall': 12,
    'labelLarge': 14,
    'labelMedium': 12,
    'labelSmall': 11,
  };

  static TextStyle? _scale(TextStyle? style, String slot) {
    final base = style?.fontSize ?? _m3TextSizes[slot]!;
    return (style ?? const TextStyle()).copyWith(
      fontSize: base * _tvTextScale,
    );
  }

  static TextTheme _scaleTextTheme(TextTheme t) => TextTheme(
    displayLarge: _scale(t.displayLarge, 'displayLarge'),
    displayMedium: _scale(t.displayMedium, 'displayMedium'),
    displaySmall: _scale(t.displaySmall, 'displaySmall'),
    headlineLarge: _scale(t.headlineLarge, 'headlineLarge'),
    headlineMedium: _scale(t.headlineMedium, 'headlineMedium'),
    headlineSmall: _scale(t.headlineSmall, 'headlineSmall'),
    titleLarge: _scale(t.titleLarge, 'titleLarge'),
    titleMedium: _scale(t.titleMedium, 'titleMedium'),
    titleSmall: _scale(t.titleSmall, 'titleSmall'),
    bodyLarge: _scale(t.bodyLarge, 'bodyLarge'),
    bodyMedium: _scale(t.bodyMedium, 'bodyMedium'),
    bodySmall: _scale(t.bodySmall, 'bodySmall'),
    labelLarge: _scale(t.labelLarge, 'labelLarge'),
    labelMedium: _scale(t.labelMedium, 'labelMedium'),
    labelSmall: _scale(t.labelSmall, 'labelSmall'),
  );

  /// 10-foot sizing.
  ///
  /// All TV typography and hit-target growth happens here rather than through
  /// `GlobalUI.uiScaleFactor` or a global `TextScaler`. Both of those are
  /// pinned to 1.0 in main.dart precisely so this is the single place that
  /// decides size -- MediaCard cancels an outer TextScaler against its own
  /// layout scale, so scaling from the outside would silently do nothing to
  /// card text.
  static ThemeData _tvSizing(ThemeData theme, ThemePrefsState prefs) {
    final cs = theme.colorScheme;

    return theme.copyWith(
      // FlexColorScheme picks `compact` on desktop-class platforms; a TV
      // wants room to breathe.
      visualDensity: VisualDensity.comfortable,
      textTheme: _scaleTextTheme(theme.textTheme),
      primaryTextTheme: _scaleTextTheme(theme.primaryTextTheme),
      iconTheme: theme.iconTheme.copyWith(size: 22),
      // ListTile and bare InkWells fall back to this; the stock 20%-alpha
      // wash is invisible at 10 feet, so it is much stronger here.
      focusColor: cs.primary.withValues(alpha: 0.34),
      listTileTheme: theme.listTileTheme.copyWith(
        minTileHeight: 52,
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 6,
        ),
      ),
      // Merge rather than replace: _widgets already set the rounded shape.
      iconButtonTheme: IconButtonThemeData(
        style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(42, 42)),
          iconSize: const WidgetStatePropertyAll(21),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: _tvButtonMinSize,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        ).copyWith(side: _focusRing(cs), overlayColor: _focusOverlay(cs)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: _tvButtonMinSize,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        ).copyWith(side: _focusRing(cs), overlayColor: _focusOverlay(cs)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: _tvButtonMinSize,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ).copyWith(side: _focusRing(cs), overlayColor: _focusOverlay(cs)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: _tvButtonMinSize,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        ).copyWith(side: _focusRing(cs), overlayColor: _focusOverlay(cs)),
      ),
      chipTheme: theme.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(
        labelPadding: const EdgeInsets.symmetric(horizontal: 24),
      ),
      // Tooltips need a hover or a long-press; a remote can do neither.
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(days: 1),
        triggerMode: TooltipTriggerMode.manual,
      ),
    );
  }

  static FlexSubThemesData _subThemesData(ThemePrefsState prefs) {
    return FlexSubThemesData(
      blendOnLevel: prefs.blendLevel,
      defaultRadius: prefs.uiRoundness,
      blendOnColors: true,
      useMaterial3Typography: true,
      buttonMinSize: _tvButtonMinSize,
      fabUseShape: true,
      fabAlwaysCircular: false,
      interactionEffects: true,
      tintedDisabledControls: true,
      unselectedToggleIsColored: true,
      sliderValueTinted: true,
      switchThumbFixedSize: true,
    );
  }

  static const _pageTransitionsTheme = PageTransitionsTheme(
    builders: {TargetPlatform.android: AppPageTransition()},
  );
}

class AppPageTransition extends PageTransitionsBuilder {
  const AppPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enterCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    final exitCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    final slideIn = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(enterCurve);

    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1, 0),
    ).animate(exitCurve);

    return SlideTransition(
      position: slideOut,
      child: SlideTransition(position: slideIn, child: child),
    );
  }
}
