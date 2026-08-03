import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shonenx/core/utils/extensions.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/discovery/providers/episodes_provider.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/tracking/domain/models/tracked_status.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_type.dart';
import 'package:shonenx/features/tracking/presentation/widgets/tracker_manager_sheet.dart';
import 'package:shonenx/features/tracking/providers/media_tracking_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_link_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_registry.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_server.dart';

/// Actions a title can be launched into, shared by the Home hero and the
/// detail screen so the two cannot drift apart.
abstract final class MediaActions {
  static void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Resumes the part-watched episode if there is one, otherwise starts the
  /// one after the last finished episode, otherwise episode one.
  ///
  /// [serverType] is applied as the player's preference rather than resolved
  /// here: PlayerController already picks a sub or dub server from that
  /// preference, and pre-resolving would run the whole source pipeline on a
  /// screen the user may never play from.
  static Future<void> play(
    BuildContext context,
    WidgetRef ref,
    UnifiedMedia media, {
    ServerType? serverType,
  }) async {
    if (serverType != null) {
      ref.read(playerPrefsProvider.notifier).setDefaultServerType(serverType);
    }

    final args = MediaArgs.fromMedia(media);

    // Hold the chain subscribed for as long as we wait on it.
    //
    // preference -> match -> episodes each watch the next, and none of them is
    // autoDispose, but a one-shot `read(...future)` from a button leaves the
    // chain with no live subscriber: any upstream change restarts it and the
    // future we are holding never settles. The episodes screen watches these
    // providers, which is the only reason Play worked after opening the list
    // once. listenManual gives this path the same subscription for the length
    // of the await.
    final keepAlive = ref.listenManual(episodesListProvider(args), (_, __) {});

    try {
      final state = await ref.read(episodesListProvider(args).future);
      final episodes = state.episodes;
      if (episodes.isEmpty) {
        _toast(context, 'No episodes found for this source.');
        return;
      }

      final history = ref.read(historyEpisodesProvider(media.id)).value ?? [];
      final last = history.firstOrNull;

      UnifiedEpisode? target;
      Duration? startPosition;

      if (last != null) {
        final partway =
            last.positionInMilliseconds > 0 &&
            last.positionInMilliseconds < last.durationInMilliseconds;
        if (partway) {
          target = episodes.firstWhereOrNull(
            (e) => e.number == last.episodeNumber,
          );
          startPosition = Duration(milliseconds: last.positionInMilliseconds);
        } else {
          target = episodes.firstWhereOrNull(
            (e) => e.number == last.episodeNumber + 1,
          );
        }
      }
      target ??= episodes.first;

      if (!context.mounted) return;
      context.push(
        '/player',
        extra: PlayerModeOnline(
          media: media,
          episode: target,
          sourceInfo: state.source,
          startPosition: startPosition,
        ),
      );
    } catch (e) {
      _toast(context, 'Could not start playback: $e');
    } finally {
      keepAlive.close();
    }
  }

  /// Marks the title as planned on the primary tracker. Falls back to the
  /// tracker manager when there is nothing to write against yet -- either the
  /// tracker is not signed in, or this title has no link to one.
  static Future<void> addToWatchList(
    BuildContext context,
    WidgetRef ref,
    UnifiedMedia media,
  ) async {
    final tracker = ref.read(primaryTrackerProvider);

    if (!(await tracker.isAuthenticated)) {
      if (context.mounted) openTrackerManager(context, media);
      return;
    }

    final links = ref.read(trackerLinkProvider(media.id)).value ?? {};
    final trackingId = tracker.type == TrackerType.local
        ? media.id
        : links[tracker.type]?.trackingId;

    if (trackingId == null) {
      if (context.mounted) openTrackerManager(context, media);
      return;
    }

    final existing = ref
        .read(
          mediaTrackingProvider(
            TrackingQuery(tracker.type, media.id, media.type),
          ),
        )
        .value;

    try {
      await tracker.updateListItem(
        media: media,
        trackingId: trackingId,
        status: TrackedStatus.planning,
        progress: existing?.progress ?? 0,
        score: existing?.score ?? 0,
      );
      ref.invalidate(
        mediaTrackingProvider(TrackingQuery(tracker.type, media.id, media.type)),
      );
      _toast(context, 'Added to ${tracker.type.displayName} plan to watch');
    } catch (e) {
      _toast(context, 'Could not add to watch list: $e');
    }
  }

  static void openTrackerManager(BuildContext context, UnifiedMedia media) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => TrackerManagerSheet(media: media),
    );
  }
}
