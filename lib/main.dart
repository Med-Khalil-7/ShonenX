import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
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
import 'package:shonenx/core/tv/tv_platform.dart';
import 'package:shonenx/core/utils/responsive.dart';
import 'package:shonenx/shared/widgets/global_background.dart';

final _log = AppLogger.scope('Main');
final _riverpodLog = AppLogger.scope('RiverpodObserver');

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = _log.child('main');
  try {
    await AppLogger.init();

    log.i('App starting');
    log.i('Args: $args');

    final init = await AppInit().init(args: args);
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

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightTheme = AppTheme.light(
          themePrefs,
          themePrefs.useDynamic ? lightDynamic : null,
        );
        final darkTheme = AppTheme.dark(
          themePrefs,
          themePrefs.useDynamic ? darkDynamic : null,
        );

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'ShonenX',
          themeMode: themePrefs.themeMode,
          theme: lightTheme,
          darkTheme: darkTheme,
          scrollBehavior: _AppScrollBehavior(isTv: TvPlatform.isTv),
          routerConfig: ref.watch(routerProvider),
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();

            final isTv = TvPlatform.isTv;

            // On TV both scale knobs stay at 1.0 and all 10-foot sizing is done
            // in the theme. That also neutralises MediaCard's inverse-TextScaler
            // normalisation, which would otherwise cancel any text growth.
            GlobalUI.uiScaleFactor = isTv ? 1.0 : themePrefs.uiScaleFactor;
            GlobalUI.uiRoundness = themePrefs.uiRoundness;

            final mq = MediaQuery.of(context);
            final scaledChild = MediaQuery(
              data: mq.copyWith(
                textScaler: isTv
                    ? TextScaler.noScaling
                    : TextScaler.linear(themePrefs.fontScaleFactor),
                // Makes InkWell highlights follow focus rather than hover and
                // stops Slider swallowing left/right, among other D-pad fixes.
                navigationMode: isTv
                    ? NavigationMode.directional
                    : NavigationMode.traditional,
              ),
              child: child,
            );

            // ResponsiveHandler is hoisted to the app root so `context.responsive`
            // resolves everywhere. It previously existed only inside
            // ScaffoldWithNavBar, so any lookup from /details, /player or the
            // /settings subtree threw. The nav shell still nests its own handler
            // with custom breakpoints; nested handlers shadow correctly.
            return ResponsiveHandler(
              builder: (context, r) => RemoteConfigListener(
                child: GlobalBackground(child: scaledChild),
              ),
            );
          },
        );
      },
    );
  }
}

/// Touch dragging is meaningless on a TV, and bouncing overscroll fights the
/// programmatic `Scrollable.ensureVisible` calls that focus movement relies on.
class _AppScrollBehavior extends MaterialScrollBehavior {
  final bool isTv;

  const _AppScrollBehavior({required this.isTv});

  @override
  Set<PointerDeviceKind> get dragDevices => isTv
      ? const {PointerDeviceKind.mouse, PointerDeviceKind.trackpad}
      : const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => isTv
      ? const ClampingScrollPhysics()
      : super.getScrollPhysics(context);
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
