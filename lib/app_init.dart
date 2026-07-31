import 'dart:async';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/Settings/KvStore.dart';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:isar_community/isar.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shonenx/core/caching/cache_manager.dart';
import 'package:shonenx/core/caching/domain/cache_entry.dart';
import 'package:shonenx/core/network/http_adapter.dart';
import 'package:shonenx/core/network/http_client.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/discovery/domain/media_preference.dart';
import 'package:shonenx/features/discovery/domain/media_source_preference.dart';
import 'package:shonenx/features/history/domain/models/watch_history_entry.dart';
import 'package:shonenx/features/library/domain/models/library_entry.dart';
import 'package:shonenx/features/tracking/domain/isar_tracker_link.dart';

class AppInit {
  static bool isBridgeInitialized = false;

  /// Completes when [setupBridge] has finished, successfully or not.
  ///
  /// The flag alone was not enough to build on. It is set in a `finally`, so
  /// it says "we tried", not "extensions are loaded" -- and anything that
  /// looked at the extension runtime before that point got an exception, fell
  /// back to inbuilt sources, and had no way to hear about it later. Awaiting
  /// this instead means a fast launch waits rather than concluding there are
  /// no extensions. It always completes: [setupBridge] cannot leave it hanging
  /// even when the bridge throws.
  static final Completer<void> _bridgeReady = Completer<void>();
  static Future<void> get bridgeReady => _bridgeReady.future;

  static String? pendingDeepLink;

  late final ScopedLogger _log = AppLogger.scope(AppInit);

  late final CacheManager cacheManager;
  late final Isar isar;

  Future<AppInit> init() async {
    final log = _log.child('init');

    log.section('START');

    // MediaKit is deliberately not initialised here. It dlopens libmpv and
    // its JNI glue -- tens of megabytes mapped into a 1 GB device -- on every
    // cold start, for a first screen that plays no video. videoEngineProvider
    // does it instead, and that is the only route to a Player.
    await _initDatabase();
    log.s('Database initialized');

    // Housekeeping for a directory no build has written since the DSL sources
    // were removed. Nothing waits on it, so it must not sit on the path to the
    // first frame.
    unawaited(_cleanupOldDslProviders());

    log.section('DONE');

    return this;
  }

  Future<void> _cleanupOldDslProviders() async {
    final log = _log.child('_cleanupOldDslProviders');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dslDir = Directory(p.join(dir.path, 'dsl_providers'));

      if (await dslDir.exists()) {
        await dslDir.delete(recursive: true);
        log.i('Deleted old dsl_providers directory');
      }
    } catch (e) {
      log.w('Failed to delete dsl_providers: $e');
    }
  }

  Future<void> _initDatabase() async {
    final log = _log.child('_initDatabase');

    try {
      final dir = await getDatabaseDirectory('ShonenX');

      isar = await Isar.open(
        [
          CacheEntrySchema,
          LibraryEntrySchema,
          MediaSourcePreferenceSchema,
          MediaPreferenceSchema,
          IsarTrackerLinkSchema,
          WatchHistoryEntrySchema,

          // MSourceSchema,
          // SourcePreferenceSchema,
          // SourcePreferenceStringValueSchema,
          // BridgeSettingsSchema,
          KvEntrySchema,
        ],
        directory: dir.path,
        name: 'shonenx_db',
      );

      // Perform migration from MediaSourcePreference to MediaPreference
      final oldPrefsCount = await isar.mediaSourcePreferences.count();
      if (oldPrefsCount > 0) {
        log.i(
          'Migrating $oldPrefsCount MediaSourcePreferences to MediaPreferences...',
        );
        final oldPrefs = await isar.mediaSourcePreferences.where().findAll();

        final newPrefs = oldPrefs
            .map(
              (old) => MediaPreference()
                ..mediaTitle = old.mediaTitle
                ..preferredSourceId = old.preferredSourceId
                ..preferredSourceName = old.preferredSourceName
                ..preferredSourceType = old.preferredSourceType
                ..manualOverrideId = old.manualOverrideId
                ..manualOverrideTitle = old.manualOverrideTitle,
            )
            .toList();

        await isar.writeTxn(() async {
          await isar.mediaPreferences.putAll(newPrefs);
          await isar.mediaSourcePreferences.clear();
        });
        log.s('Migration complete');
      }

      log.s('Isar opened');
    } catch (e, st) {
      log.e('DB INIT FAILED', e, st);
      rethrow;
    }
  }

  static Future<void> setupBridge(WidgetRef ref) async {
    final log = AppLogger.scope('AppInit').child('setupBridge');

    try {
      await AnymeXExtensionBridge.init(
        getDirectory: AnymeXExtensionBridge.defaultGetDirectory(
          baseDirectory: await getDatabaseDirectory('ShonenX'),
        ),
        http: HTTPAdapter(ref.read(httpClientProvider)),
        projectName: "ShonenX",
      );

      // Deliberately no checkAndInitialize() here. Get.find below constructs
      // ExtensionManager (registered with Get.lazyPut), and its onInit already
      // calls it. Calling it here too ran the whole runtime-host load twice on
      // every launch -- the completer inside only dedupes *concurrent* calls,
      // and these were sequential -- which meant unzipping every native
      // library out of the host APK twice before the app was usable.
      final extManager = Get.find<ExtensionManager>();

      // Give the managers a moment to register, but do not sit here for a
      // full five seconds: this runs in the background now, and a caller that
      // needs sources reads them through providers that are invalidated once
      // the bridge reports ready.
      const pollInterval = Duration(milliseconds: 50);
      const maxWait = Duration(seconds: 2);
      var waited = Duration.zero;
      while (extManager.managers.isEmpty && waited < maxWait) {
        await Future.delayed(pollInterval);
        waited += pollInterval;
      }

      log.s(
        'Extension bridge ready '
        '(managers=${extManager.managers.length}, waited=${waited.inMilliseconds}ms)',
      );
    } catch (e, st) {
      log.e('BRIDGE INIT FAILED', e, st);
      rethrow;
    } finally {
      isBridgeInitialized = true;
      if (!_bridgeReady.isCompleted) _bridgeReady.complete();
    }
  }

  static Future<Directory> getDatabaseDirectory(String dirName) async {
    return getApplicationDocumentsDirectory();
  }

  /// Loads libmpv. Idempotent, and called from `videoEngineProvider` rather
  /// than from startup so a session that never opens the player never pays it.
  static void ensureVideoEnginesReady() {
    MediaKit.ensureInitialized();
  }
}
