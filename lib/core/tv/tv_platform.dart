import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/core/utils/device_info.dart';

/// How TV mode is decided.
///
/// [auto] trusts device detection. The two explicit values exist so the TV
/// layout can be driven from a desktop build (or forced off on a real TV)
/// without rebuilding.
enum TvModeOverride { auto, forceOn, forceOff }

/// Whether the app should present its 10-foot, D-pad-driven UI.
///
/// This has to be a resolved static rather than something read per-build:
/// `ResponsiveData.from` is synchronous and runs inside `build`, while the
/// underlying platform check is async. [resolve] is therefore called once
/// during `AppInit`, before `runApp`.
class TvPlatform {
  TvPlatform._();

  static final _log = AppLogger.scope('TvPlatform');

  static bool _detected = false;
  static TvModeOverride _override = TvModeOverride.auto;
  static bool _resolved = false;

  /// What the device actually reports, ignoring any override.
  static bool get detected => _detected;

  static TvModeOverride get override => _override;

  static bool get isTv => switch (_override) {
    TvModeOverride.forceOn => true,
    TvModeOverride.forceOff => false,
    TvModeOverride.auto => _detected,
  };

  /// Resolves device detection once. Safe to call again; later calls are no-ops
  /// unless [force] is set.
  ///
  /// [args] are the process arguments, so a desktop run can pass `--tv` (or
  /// `--no-tv`) to exercise the TV layout without a TV.
  static Future<void> resolve({
    List<String> args = const [],
    bool force = false,
  }) async {
    if (_resolved && !force) return;

    if (args.contains('--tv')) {
      _override = TvModeOverride.forceOn;
    } else if (args.contains('--no-tv')) {
      _override = TvModeOverride.forceOff;
    }

    _detected = await DeviceInfo.isTelevision();
    _resolved = true;

    _log
        .child('resolve')
        .i('detected=$_detected override=${_override.name} isTv=$isTv');
  }

  /// Used by the settings toggle so the layout can be switched at runtime.
  static void setOverride(TvModeOverride value) {
    _override = value;
    _log.child('setOverride').i('override=${value.name} isTv=$isTv');
  }
}
