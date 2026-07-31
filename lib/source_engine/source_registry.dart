import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:anymex_extension_runtime_bridge/Services/Mangayomi/MangayomiExtensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    as bridge;
import 'package:shonenx/app_init.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/providers/inbuilt_sources_provider.dart';
import 'package:shonenx/shared/models/unified_media.dart';

final extensionManagerProvider =
    NotifierProvider<ExtensionManagerNotifier, bridge.Extension>(
      ExtensionManagerNotifier.new,
    );

class ExtensionManagerNotifier extends Notifier<bridge.Extension> {
  SharedPreferences get _storage => ref.read(sharedPreferencesProvider);

  static const _key = 'currentManager';

  late final bridge.ExtensionManager _manager =
      Get.find<bridge.ExtensionManager>();

  @override
  bridge.Extension build() {
    final saved = _storage.getString(_key);

    if (saved == 'cloudstream' || saved == 'cloudstream-desktop') {
      final ext = _manager.findById(
        Platform.isAndroid ? 'cloudstream' : 'cloudstream-desktop',
      );
      if (ext != null) return ext;
    }

    if (saved == 'aniyomi' || saved == 'aniyomi-desktop' || saved == null) {
      final ext = _manager.findById(
        Platform.isAndroid ? 'aniyomi' : 'aniyomi-desktop',
      );
      if (ext != null) return ext;
    }

    return _manager.get<MangayomiExtensions>();
  }

  void setManager(String id) {
    String effectiveId = id;
    if (!Platform.isAndroid) {
      if (id == 'aniyomi') effectiveId = 'aniyomi-desktop';
      if (id == 'cloudstream') effectiveId = 'cloudstream-desktop';
    }

    if (state.id == effectiveId) {
      return;
    }

    final ext = _manager.findById(effectiveId);
    if (ext != null) {
      state = ext;
    } else {
      state = _manager.get<MangayomiExtensions>();
    }
    _storage.setString(_key, effectiveId);
  }
}

final enabledExtensionManagersProvider =
    NotifierProvider<EnabledExtensionManagersNotifier, Set<String>>(
      EnabledExtensionManagersNotifier.new,
    );

class EnabledExtensionManagersNotifier extends Notifier<Set<String>> {
  SharedPreferences get _storage => ref.read(sharedPreferencesProvider);
  static const _key = 'enabledExtensionManagers';
  static const _defaultStandalone = {'mangayomi', 'sora'};

  /// Whether the runtime host that backs aniyomi/cloudstream/kotatsu is up.
  ///
  /// Reached defensively: the controller is registered by the bridge, so
  /// touching it before that throws, and a throw here would take the whole
  /// provider -- and every source list built on it -- down with it.
  bool get _runtimeReady {
    try {
      return bridge.AnymeXRuntimeBridge.controller.isReady.value;
    } catch (_) {
      return false;
    }
  }

  @override
  Set<String> build() {
    final saved = _storage.getStringList(_key);
    final Set<String> initial = saved != null
        ? saved.toSet()
        : _defaultStandalone;

    if (_runtimeReady) return initial;

    // The runtime-backed managers are hidden only while the runtime is
    // genuinely missing -- but it is warmed in the background, so at launch it
    // is always missing for a moment. This is a plain Notifier, built once and
    // held for the session, so that moment used to decide the whole run: open
    // the app quickly and those managers were filtered out for good, which is
    // why the player reported no extension and why toggling them by hand was
    // the only way back (the toggle writes state directly, bypassing this).
    //
    // Filter for now, then put the saved set back when the runtime reports in.
    final filtered = initial.where((id) {
      final base = id.replaceAll('-desktop', '');
      return base != 'aniyomi' && base != 'cloudstream' && base != 'kotatsu';
    }).toSet();
    final provisional = filtered.isEmpty ? _defaultStandalone : filtered;

    var disposed = false;
    ref.onDispose(() => disposed = true);

    void restoreSaved() {
      if (disposed || !_runtimeReady) return;
      // Only if nothing has changed it since. A toggle in the meantime is the
      // user's choice and outranks the saved set.
      if (setEquals(state, provisional)) state = initial;
    }

    unawaited(
      AppInit.bridgeReady.then((_) {
        if (disposed) return;
        restoreSaved();
        if (_runtimeReady) return;
        // The bridge is up but the host is still loading. Wait for the flag
        // rather than settling for the filtered set.
        try {
          final worker = ever(
            bridge.AnymeXRuntimeBridge.controller.isReady,
            (_) => restoreSaved(),
          );
          ref.onDispose(worker.dispose);
        } catch (_) {}
      }),
    );

    return provisional;
  }

  void toggleManager(String managerId, bool enabled) {
    final next = Set<String>.from(state);
    final baseId = managerId.replaceAll('-desktop', '');
    final desktopId = '$baseId-desktop';

    if (enabled) {
      next.add(baseId);
      next.add(desktopId);
    } else {
      next.remove(baseId);
      next.remove(desktopId);
    }
    state = next;
    _storage.setStringList(_key, next.toList());
  }

  void disableAll(List<String> managers) {
    final next = Set<String>.from(state);
    for (var manager in managers) {
      next.remove(manager);
      next.remove('$manager-desktop');
    }
    state = next;
    _storage.setStringList(_key, next.toList());
  }

  void enableAll(List<String> managers) {
    final next = Set<String>.from(state);
    next.addAll(managers);
    state = next;
    _storage.setStringList(_key, next.toList());
  }

  void setAll(Set<String> managers) {
    state = managers;
    _storage.setStringList(_key, managers.toList());
  }
}

final availableAnimeSourcesProvider = FutureProvider<List<SourceInfo>>(
  retry: (retryCount, error) => null,
  (ref) async {
    final inbuilt = ref
        .read(inbuiltAnimeSourcesProvider)
        .map(
          (s) => SourceInfo(
            id: s.sourceInfo.id,
            name: s.sourceInfo.name,
            type: SourceType.inbuilt,
            mediaType: MediaType.ANIME,
            iconUrl: s.sourceInfo.iconUrl,
          ),
        )
        .toList();

    // Wait for the extension runtime before deciding what exists.
    //
    // Get.find throws until AnymeXExtensionBridge.init has registered the
    // manager, and the bridge is warmed in the background so that a launch
    // straight into an episode loses the race. Throwing landed in the catch
    // below, which returns the inbuilt list -- but the `ever` workers that
    // re-run this provider when extensions register are set up *after* the
    // find, so they never got attached and the empty answer stood for the
    // rest of the session. That is why extensions only came back after being
    // toggled: the toggle changes enabledExtensionManagersProvider, which
    // invalidates this provider and runs it again once the bridge is up.
    //
    // The timeout is a backstop for a bridge that never reports in; the
    // fallback is the same inbuilt list as before, not a hang.
    if (!AppInit.isBridgeInitialized) {
      await AppInit.bridgeReady.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
    }

    try {
      final enabledManagers = ref.watch(enabledExtensionManagersProvider);
      final bridgeManager = Get.find<bridge.ExtensionManager>();
      final worker1 = ever(bridgeManager.installedAnimeExtensions, (_) {
        ref.invalidateSelf();
      });
      final worker2 = ever(bridgeManager.availableAnimeExtensions, (_) {
        ref.invalidateSelf();
      });
      ref.onDispose(() {
        worker1.dispose();
        worker2.dispose();
      });
      final extensionsRaw = bridgeManager.installedAnimeExtensions.where((ext) {
        final mId = (ext.managerId ?? bridge.getSourceManager(ext).id)
            .replaceAll('-desktop', '');
        return enabledManagers.contains(mId) ||
            enabledManagers.contains(
              ext.managerId ?? bridge.getSourceManager(ext).id,
            );
      }).toList();

      final extensions = extensionsRaw
          .map(
            (ext) => SourceInfo(
              id: ext.id ?? "Unknown",
              name: ext.name ?? "Unknown",
              type: SourceType.extension,
              mediaType: MediaType.ANIME,
              iconUrl: ext.iconUrl,
              lang: ext.lang,
              isNsfw: ext.isNsfw ?? false,
            ),
          )
          .toList();

      final allSources = [...inbuilt, ...extensions];
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final order = prefs.getStringList('source_order_ANIME') ?? [];
        if (order.isNotEmpty) {
          final orderMap = {for (int i = 0; i < order.length; i++) order[i]: i};
          allSources.sort((a, b) {
            final indexA = orderMap[a.id] ?? 9999;
            final indexB = orderMap[b.id] ?? 9999;
            return indexA.compareTo(indexB);
          });
        }
      } catch (_) {}
      return allSources;
    } catch (e) {
      return inbuilt;
    }
  },
  name: 'availableAnimeSourcesProvider',
);

final allAvailableSourcesProvider = FutureProvider<List<SourceInfo>>((
  ref,
) async {
  return ref.watch(availableAnimeSourcesProvider.future);
}, name: 'allAvailableSourcesProvider');
