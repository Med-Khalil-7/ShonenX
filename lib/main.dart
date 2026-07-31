import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/app_init.dart';
import 'package:shonenx/shared/providers/database_provider.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:shonenx/shared/providers/theme_prefs_provider.dart';
import 'package:shonenx/shared/providers/ui_prefs_provider.dart';
import 'package:shonenx/core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/remote_config/ui/remote_config_listener.dart';
import 'package:shonenx/core/theme/app_theme.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/core/utils/responsive.dart';
import 'package:shonenx/shared/widgets/global_background.dart';

final _log = AppLogger.scope('Main');
final _riverpodLog = AppLogger.scope('RiverpodObserver');

/// Catches what the try/catch around startup cannot: anything thrown after
/// runApp, from a build, or from an unawaited future.
///
/// Without these the app had no error path at all. A failure during a build
/// showed Flutter's grey box in release, and an async error vanished silently
/// -- indistinguishable, on a slow TV, from the app simply having hung.
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _log.e('FLUTTER ERROR: ${details.exceptionAsString()}', details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _log.e('UNCAUGHT ASYNC: $error', stack);
    return true;
  };

  // The default is a red-on-yellow strip of monospace, unreadable at ten feet
  // and alarming. Fail quietly and legibly instead; the detail is in the log.
  ErrorWidget.builder = (details) => Container(
    color: const Color(0xFF0E1216),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    child: const Text(
      'Something went wrong here.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFFB4BCC6), fontSize: 16),
    ),
  );
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The defaults -- 1000 images, 100 MB of decoded bitmaps -- are sized for a
  // phone with several gigabytes. This runs on 1 GB TV boxes that also have to
  // hold libmpv, so the cache is capped well below what the app would
  // otherwise happily fill. Note this bounds only *unreferenced* images; the
  // ceiling on live ones comes from decoding at display size in the first
  // place (see AppNetworkImage).
  // Defaults are 1000 entries / 100 MB, sized for a 4 GB phone. Trimmed, but
  // not so far that full-screen artwork cannot sit in it: a 1080p backdrop is
  // 8 MB decoded, and the hero crossfade holds two at once. At 32 MB those
  // alone evicted every poster on the screen behind them, so each pass through
  // the carousel re-decoded the lot.
  PaintingBinding.instance.imageCache
    ..maximumSize = 150
    ..maximumSizeBytes = 64 << 20;

  _installErrorHandlers();

  final log = _log.child('main');
  try {
    // Not awaited: it asks the platform for the external storage directory and
    // then creates a file on eMMC, and nothing before the first frame needs
    // the log to be on disk. On a slow box that was pure dead time in front of
    // a blank window.
    unawaited(AppLogger.init());

    log.i('App starting');
    log.i('Args: $args');

    final init = await AppInit().init();
    log.i('AppInit completed');

    final sharedPreference = await SharedPreferences.getInstance();
    log.i('SharedPreferences ready');

    Uri? startupUri;

    for (final arg in args) {
      final uri = Uri.tryParse(arg);
      if (uri != null && uri.scheme.isNotEmpty) {
        startupUri = uri;
        break;
      }
    }

    runApp(
      ProviderScope(
        observers: [RiverpodLogger()],
        overrides: [
          startupUriProvider.overrideWithValue(startupUri),
          databaseProvider.overrideWith((ref) => init.isar),
          sharedPreferencesProvider.overrideWith((ref) => sharedPreference),
        ],
        child: const ShonenXApp(),
      ),
    );
  } catch (e, st) {
    _log.e(e.toString(), st);

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF8B0000),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Initialization Failed:\n\n$e\n\n$st',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShonenXApp extends ConsumerWidget {
  const ShonenXApp({super.key});

  static final _log = AppLogger.scope(ShonenXApp);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = _log.child('build');

    final themePrefs = ref.watch(themePrefsProvider);
    log.d('Theme changed: ${themePrefs.themeMode}');

    final darkTheme = AppTheme.dark(themePrefs, null);
    // Building the light theme costs a whole FlexColorScheme plus a GoogleFonts
    // text theme, and MaterialApp never reads `theme` when the mode is dark.
    // On a TV that is always dark, that was half the theme work wasted on
    // every rebuild.
    final lightTheme = themePrefs.themeMode == ThemeMode.dark
        ? darkTheme
        : AppTheme.light(themePrefs, null);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'ShonenX',
      themeMode: themePrefs.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      scrollBehavior: const _TvScrollBehavior(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        // Both scale knobs stay at 1.0 and all 10-foot sizing lives in the
        // theme. That also neutralises MediaCard's inverse-TextScaler
        // normalisation, which would otherwise cancel any text growth.
        GlobalUI.uiScaleFactor = 1.0;
        GlobalUI.uiRoundness = themePrefs.uiRoundness;

        final scaledChild = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
            // Makes InkWell highlights follow focus rather than hover and
            // stops Slider swallowing left/right, among other D-pad fixes.
            navigationMode: NavigationMode.directional,
          ),
          child: child,
        );

        // ResponsiveHandler is hoisted to the app root so `context.responsive`
        // resolves everywhere. It previously existed only inside
        // ScaffoldWithNavBar, so any lookup from /details, /player or the
        // /settings subtree threw. The nav shell still nests its own handler
        // with custom breakpoints; nested handlers shadow correctly.
        return ResponsiveHandler(
          builder: (context, r) =>
              RemoteConfigListener(child: GlobalBackground(child: scaledChild)),
        );
      },
    );
  }
}

/// Touch dragging is meaningless on a TV, and bouncing overscroll fights the
/// programmatic `Scrollable.ensureVisible` calls that focus movement relies on.
class _TvScrollBehavior extends MaterialScrollBehavior {
  const _TvScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

final class RiverpodLogger extends ProviderObserver {
  static final _log = _riverpodLog;

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    final providerName = context.provider.name ?? 'UnknownProvider';

    if (providerName != 'debug') return;

    final log = _log.child(providerName);

    log.section('State Update');
    log.i('Previous: $previousValue');
    log.i('New: $newValue');
  }
}
