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
  static String? pendingDeepLink;

  late final ScopedLogger _log = AppLogger.scope(AppInit);

  late final CacheManager cacheManager;
  late final Isar isar;

  Future<AppInit> init() async {
    final log = _log.child('init');

    log.section('START');

    await _initVideoEngines();
    log.s('Video engines initialized');

    await _initDatabase();
    log.s('Database initialized');

    await _cleanupOldDslProviders();
    log.s('Old DSL providers cleaned up');

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

      await AnymeXRuntimeBridge.checkAndInitialize();

      // Give the managers a moment to register, but do not sit here for a
      // full five seconds: this runs in the background now, and a caller that
      // needs sources reads them through providers that are invalidated once
      // the bridge reports ready.
      final extManager = Get.find<ExtensionManager>();
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
    }
  }

  static Future<Directory> getDatabaseDirectory(String dirName) async {
    return getApplicationDocumentsDirectory();
  }

  static Future<void> _initVideoEngines() async {
    final log = AppLogger.scope('AppInit').child('initVideoEngines');

    MediaKit.ensureInitialized();
    log.i('MediaKit initialized');
  }
}
