import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_grid.dart';
import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_source_header.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/utils/media_type_extensions.dart';

/// The episode picker, full screen.
///
/// It used to be a 38%-wide side sheet holding a list. A list is the wrong
/// shape for this on a remote: reaching episode 340 meant holding DOWN, and
/// none of the tiles were focusable anyway. A page gives the grid room for ten
/// columns, which makes every row one decade of episode numbers.
class EpisodesScreen extends ConsumerWidget {
  final UnifiedMedia media;

  /// What to do with the chosen episode.
  ///
  /// Null starts the player, which is what the route does. The player itself
  /// mounts this same screen over its own surface and passes a callback that
  /// switches episode in place -- so the picker is one widget used twice
  /// rather than two that drift apart.
  final void Function(UnifiedEpisode episode, SourceInfo sourceInfo)? onPlay;

  /// The episode to open on, when the caller knows better than history does.
  ///
  /// Opened from the player this is what is actually playing. History only
  /// says where the last *save* landed -- it is written every few seconds, so
  /// straight after switching episode it still names the previous one, and the
  /// grid opened on that episode's range tab instead of the running one's.
  final double? currentEpisodeNumber;

  const EpisodesScreen({
    super.key,
    required this.media,
    this.onPlay,
    this.currentEpisodeNumber,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final m = ShonenXMetrics.of(context);
    final gutter = m.gutter(size);
    final topInset = TvMetrics.verticalOfSize(size);

    final hasSources =
        (ref.watch(media.type.availableSourcesProvider).value ?? []).isNotEmpty;

    // Watched, not read. The details screen used ref.read here, but this is an
    // autoDispose StreamProvider nothing else subscribes to, so the read
    // always came back empty -- which is why resume never worked from the
    // episode list.
    final history = ref.watch(historyEpisodesProvider(media.id)).value ?? [];

    return AppScaffold(
      fullBleed: true,
      body: Padding(
        // Starts at the back arrow's inset, matching the details screen, so
        // the two pages share a left edge.
        padding: EdgeInsets.fromLTRB(m.backArrowInset, topInset + 16, gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BackButton(onPressed: () => context.pop()),
                SizedBox(width: m.body),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Episodes',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: m.heading,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        media.title.availableTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.badge,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: m.body * 0.6),
            if (!hasSources)
              const Expanded(child: NoExtensionsPlaceholder())
            else ...[
              // Source / Fix match: a bad title match is the most common
              // reason a grid comes back empty, so the correction lives on the
              // same screen as the symptom.
              Padding(
                padding: EdgeInsets.only(
                  left: gutter - m.backArrowInset - 16,
                ),
                child: EpisodeSourceHeader(media: media),
              ),
              Expanded(
                child: EpisodeGridView(
                  media: media,
                  currentEpisodeNumber:
                      currentEpisodeNumber ??
                      history.firstOrNull?.episodeNumber,
                  padding: EdgeInsets.only(
                    left: gutter - m.backArrowInset,
                    bottom: m.body * 2,
                  ),
                  onEpisodeTap: (episode, sourceInfo) {
                    final handler = onPlay;
                    if (handler != null) {
                      handler(episode, sourceInfo);
                      return;
                    }

                    final entry = history
                        .where((e) => e.episodeNumber == episode.number)
                        .firstOrNull;
                    final resume =
                        entry != null &&
                        entry.positionInMilliseconds > 0 &&
                        entry.positionInMilliseconds <
                            entry.durationInMilliseconds;

                    // Replace rather than push: the player takes this page's
                    // slot, so BACK out of it lands on details exactly as it
                    // did when this was a sheet.
                    context.pushReplacement(
                      '/player',
                      extra: PlayerModeOnline(
                        media: media,
                        episode: episode,
                        sourceInfo: sourceInfo,
                        startPosition: resume
                            ? Duration(
                                milliseconds: entry.positionInMilliseconds,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = ShonenXMetrics.of(context);

    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      scaleOnFocus: false,
      builder: (context, isFocused) => SizedBox(
        width: m.iconButton * 1.5,
        height: m.iconButton * 1.5,
        child: Icon(
          Icons.arrow_back_rounded,
          size: m.iconButton,
          semanticLabel: 'Back',
          color: isFocused ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
