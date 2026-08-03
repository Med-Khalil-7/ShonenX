import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/utils/extensions.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/discovery/providers/media_preference_provider.dart';
import 'package:shonenx/source_engine/source_engine_provider.dart';
import 'package:shonenx/source_engine/matchmaker/match_service.dart';
import 'package:shonenx/source_engine/utils/media_type_extensions.dart';

class MatchedMedia {
  final String id;
  final String title;

  const MatchedMedia({required this.id, required this.title});
}

class MatchedMediaState {
  final MatchedMedia? matchedMedia;
  final bool isLoading;
  final String? error;

  const MatchedMediaState({
    this.matchedMedia,
    this.isLoading = false,
    this.error,
  });

  MatchedMediaState copyWith({
    MatchedMedia? matchedMedia,
    bool? isLoading,
    String? error,
  }) {
    return MatchedMediaState(
      matchedMedia: matchedMedia ?? this.matchedMedia,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final matchedMediaProvider =
    AsyncNotifierProvider.family<
      MediaMatchNotifier,
      MatchedMediaState,
      MediaArgs
    >(MediaMatchNotifier.new);

class MediaMatchNotifier extends AsyncNotifier<MatchedMediaState> {
  late final MediaArgs args;

  MediaMatchNotifier(this.args);

  @override
  Future<MatchedMediaState> build() async {
    // No `state = const AsyncLoading()` here.
    //
    // Riverpod already reports loading for as long as this build's future is
    // pending; assigning state from inside build publishes a second, manual
    // loading value that the build's own future never resolves. A widget that
    // watches this as an AsyncValue never notices -- it just rebuilds when the
    // data lands, which is why the episodes screen always worked. A one-shot
    // `await ref.read(...future)` latches onto that manual value and waits
    // forever, which is what left the player spinning on a black screen for
    // any title whose episode list had not been opened yet. Opening the list
    // first "fixed" it only because the match was then already cached.
    final prefs = await ref.watch(mediaPreferenceProvider(args).future);

    if (args.sourceId != null && args.providerId != null) {
      final availableSources = await ref.watch(
        args.type.availableSourcesProvider.future,
      );

      final sourceInfo =
          availableSources.firstWhereOrNull((s) => s.id == args.sourceId) ??
          prefs.sourceInfo;

      if (prefs.sourceInfo.id != sourceInfo.id ||
          prefs.matchedMediaId != args.providerId ||
          prefs.matchedMediaTitle != args.mediaTitle) {
        Future.microtask(() {
          ref
              .read(mediaPreferenceProvider(args).notifier)
              .updatePrefs(sourceInfo, args.providerId!, args.mediaTitle);
        });
      }

      return MatchedMediaState(
        matchedMedia: MatchedMedia(
          id: args.providerId!,
          title: args.mediaTitle,
        ),
      );
    }

    if (prefs.matchedMediaId != null && prefs.matchedMediaTitle != null) {
      return MatchedMediaState(
        matchedMedia: MatchedMedia(
          id: prefs.matchedMediaId!,
          title: prefs.matchedMediaTitle!,
        ),
      );
    }

    final sourceImpl = ref.read(animeSourceProvider(prefs.sourceInfo));

    final result = await MediaMatchService(
      sourceImpl,
      args.type,
    ).findBestMatch(args.mediaTitle);

    if (result == null) {
      return const MatchedMediaState();
    }

    // Cache the match in Isar DB to bypass matchmaker on next launch
    Future.microtask(() {
      ref
          .read(mediaPreferenceProvider(args).notifier)
          .saveAutoMatch(result.id, result.title.availableTitle);
    });

    return MatchedMediaState(
      matchedMedia: MatchedMedia(
        id: result.id,
        title: result.title.availableTitle,
      ),
    );
  }
}
