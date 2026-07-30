import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/core/utils/extensions.dart';
import 'package:shonenx/features/auth/providers/auth_provider.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/discovery/presentation/widgets/details/detail_media_row.dart';
import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_list_panel.dart';
import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_source_header.dart';
import 'package:shonenx/features/discovery/providers/details_provider.dart';
import 'package:shonenx/features/discovery/providers/episodes_provider.dart';
import 'package:shonenx/features/history/domain/models/watch_history_entry.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/tracking/domain/isar_tracker_link.dart';
import 'package:shonenx/features/tracking/domain/models/tracked_status.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_type.dart';
import 'package:shonenx/features/tracking/engine/remote_tracker.dart';
import 'package:shonenx/features/tracking/presentation/widgets/tracker_manager_sheet.dart';
import 'package:shonenx/features/tracking/providers/media_tracking_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_link_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_registry.dart';
import 'package:shonenx/features/tracking/providers/tracking_prefs_provider.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';
import 'package:shonenx/shared/widgets/tv/tv_badge.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';
import 'package:shonenx/shared/widgets/tv/tv_side_sheet.dart';
import 'package:shonenx/source_engine/utils/media_type_extensions.dart';

/// Single-page detail view.
///
/// The previous version was a collapsing header over About/Episodes tabs.
/// Tabs are an awkward control on a remote -- reaching episode 3 meant
/// scrolling to the bottom of the screen, moving to a tab strip, switching,
/// then scrolling back up -- and the tab strip carried an autofocusing
/// KeyboardListener that stole the screen's first focus. Playback is now one
/// press away and the episode list opens as a side sheet.
class DetailsScreen extends ConsumerStatefulWidget {
  final String tag;
  final MediaType mediaType;
  final UnifiedMedia media;
  final int initialTabIndex;
  final Object? autoPlayMode;

  const DetailsScreen({
    super.key,
    required this.tag,
    required this.mediaType,
    required this.media,
    this.initialTabIndex = 0,
    this.autoPlayMode,
  });

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLinkPrimaryTracker();
      if (!mounted) return;
      if (widget.autoPlayMode is PlayerMode) {
        context.push('/player', extra: widget.autoPlayMode);
      }
    });
  }

  Future<void> _autoLinkPrimaryTracker() async {
    final prefs = ref.read(trackingPrefsProvider);
    if (!prefs.autoTrackPrimary) return;

    final primaryType = prefs.primaryTracker;
    if (primaryType == TrackerType.local) return;

    final media = widget.media;
    // Only tracker-sourced metadata carries an id the tracker will recognise.
    if (media.sourceId != null) return;

    final linksMap = await ref.read(trackerLinkProvider(media.id).future);
    if (linksMap.containsKey(primaryType)) return;

    final mapping = TrackerMapping()
      ..trackerId = primaryType.id
      ..trackingId = media.id
      ..trackingTitle = media.title.availableTitle;

    ref
        .read(trackerLinkProvider(media.id).notifier)
        .saveLink(primaryType, mapping);
  }

  void _toast(String message) {
    if (!mounted) return;
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
  Future<void> _play(UnifiedMedia media, {ServerType? serverType}) async {
    if (_resolving) return;

    if (serverType != null) {
      ref.read(playerPrefsProvider.notifier).setDefaultServerType(serverType);
    }

    setState(() => _resolving = true);
    try {
      final state = await ref.read(
        episodesListProvider(MediaArgs.fromMedia(media)).future,
      );
      final episodes = state.episodes;
      if (episodes.isEmpty) {
        _toast('No episodes found for this source.');
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

      if (!mounted) return;
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
      _toast('Could not start playback: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _openEpisodes(UnifiedMedia media) {
    final history = ref.read(historyEpisodesProvider(media.id)).value ?? [];
    final hasSources =
        (ref.read(media.type.availableSourcesProvider).value ?? []).isNotEmpty;

    TvSideSheet.show(
      context: context,
      label: 'Episodes',
      builder: (sheetContext) => !hasSources
          ? const NoExtensionsPlaceholder()
          : Column(
              children: [
                EpisodeSourceHeader(media: media),
                Expanded(child: _episodeList(sheetContext, media, history)),
              ],
            ),
    );
  }

  Widget _episodeList(
    BuildContext sheetContext,
    UnifiedMedia media,
    List<WatchHistoryEntry> history,
  ) {
    return EpisodeListPanel(
      media: media,
      currentEpisodeNumber: history.firstOrNull?.episodeNumber,
      onEpisodeTap: (episode, sourceInfo) {
        final entry = history
            .where((e) => e.episodeNumber == episode.number)
            .firstOrNull;
        final resume =
            entry != null &&
            entry.positionInMilliseconds > 0 &&
            entry.positionInMilliseconds < entry.durationInMilliseconds;

        Navigator.of(sheetContext).pop();
        context.push(
          '/player',
          extra: PlayerModeOnline(
            media: media,
            episode: episode,
            sourceInfo: sourceInfo,
            startPosition: resume
                ? Duration(milliseconds: entry.positionInMilliseconds)
                : null,
          ),
        );
      },
    );
  }

  Future<void> _addToWatchList(UnifiedMedia media) async {
    final tracker = ref.read(primaryTrackerProvider);
    if (!(await tracker.isAuthenticated)) {
      if (!mounted) return;
      _openTrackerManager(media);
      return;
    }

    final links = ref.read(trackerLinkProvider(media.id)).value ?? {};
    final trackingId = tracker.type == TrackerType.local
        ? media.id
        : links[tracker.type]?.trackingId;

    if (trackingId == null) {
      // Nothing to write against yet; the manager is where a link is made.
      if (!mounted) return;
      _openTrackerManager(media);
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
      _toast('Added to ${tracker.type.displayName} plan to watch');
    } catch (e) {
      _toast('Could not add to watch list: $e');
    }
  }

  void _openTrackerManager(UnifiedMedia media) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => TrackerManagerSheet(media: media),
    );
  }

  void _share(UnifiedMedia media) {
    final providerId = media.providerId ?? 'anilist';
    final url = switch (providerId) {
      'myanimelist' || 'mal' => 'https://myanimelist.net/anime/${media.id}',
      'kitsu' => 'https://kitsu.io/anime/${media.id}',
      _ => 'https://anilist.co/anime/${media.id}',
    };
    SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final gutter = ShonenX.gutter(size);
    final topInset = TvMetrics.verticalOfSize(size);

    final detailsState = ref.watch(
      detailsProvider(
        DetailsArgs(
          widget.media.id,
          widget.mediaType,
          sourceId: widget.media.sourceId,
          trackerId: widget.media.providerId,
        ),
      ),
    );
    final media = detailsState.value?.merge(widget.media) ?? widget.media;

    final relations = media.relations ?? const <UnifiedMedia>[];
    final recommendations = media.recommendations ?? const <UnifiedMedia>[];
    final characters = media.characters ?? const <MediaCharacter>[];

    return AppScaffold(
      fullBleed: true,
      body: Stack(
        children: [
          _Backdrop(url: media.banner ?? media.cover),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    topInset + 16,
                    gutter,
                    40,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconButton(
                        icon: Icons.arrow_back,
                        onPressed: () => context.pop(),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: _buildInfoColumn(media, theme, cs)),
                      const SizedBox(width: 40),
                      _Poster(media: media, tag: widget.tag),
                    ],
                  ),
                ),
              ),
              if (relations.isNotEmpty)
                SliverToBoxAdapter(
                  child: DetailMediaRow(
                    title: 'Related Anime',
                    items: relations,
                    tagPrefix: 'details-rel',
                  ),
                ),
              if (characters.isNotEmpty)
                SliverToBoxAdapter(
                  child: DetailCharacterRow(characters: characters),
                ),
              if (recommendations.isNotEmpty)
                SliverToBoxAdapter(
                  child: DetailMediaRow(
                    title: 'Recommendations',
                    items: recommendations,
                    tagPrefix: 'details-rec',
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: topInset + 40)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(UnifiedMedia media, ThemeData theme, ColorScheme cs) {
    final genres = media.genres ?? const <String>[];
    final description = media.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TvMetaRow(media: media),
            const SizedBox(width: 32),
            _IconButton(
              icon: Icons.share_outlined,
              tooltip: 'Share',
              onPressed: () => _share(media),
            ),
            const SizedBox(width: 12),
            _TrackerButton(
              media: media,
              onOpenManager: () => _openTrackerManager(media),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          media.title.availableTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 22),
        if (description != null && description.isNotEmpty)
          Text(
            _plainText(description),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'Genres: ${genres.join(', ')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvButton(
                    label: 'Play now',
                    icon: Icons.play_arrow_rounded,
                    width: 280,
                    loading: _resolving,
                    // The reason the screen exists. Land here on arrival so
                    // watching something is a single press.
                    autofocus: true,
                    onPressed: () => _play(media),
                  ),
                  const SizedBox(width: 16),
                  TvButton(
                    label: 'More episodes',
                    icon: Icons.layers_outlined,
                    width: 280,
                    variant: TvButtonVariant.filledWhite,
                    onPressed: () => _openEpisodes(media),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TvButton(
                        label: 'Watch',
                        emphasis: 'Dubbed',
                        icon: Icons.mic_none_rounded,
                        height: 52,
                        variant: TvButtonVariant.bare,
                        onPressed: () =>
                            _play(media, serverType: ServerType.dub),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TvButton(
                    label: 'Add to watch list',
                    icon: Icons.add_circle_outline,
                    height: 52,
                    variant: TvButtonVariant.bare,
                    onPressed: () => _addToWatchList(media),
                  ),
                ],
              ),
              TvButton(
                label: 'Watch',
                emphasis: 'Subbed',
                icon: Icons.closed_caption_off_rounded,
                height: 52,
                variant: TvButtonVariant.bare,
                onPressed: () => _play(media, serverType: ServerType.sub),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Descriptions arrive as fragments of HTML from every tracker.
  static String _plainText(String raw) => raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _Backdrop extends StatelessWidget {
  final String? url;

  const _Backdrop({required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url == null || url!.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
          // Heavy enough that white body text stays legible over any artwork.
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final UnifiedMedia media;
  final String tag;

  const _Poster({required this.media, required this.tag});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = media.cover ?? media.banner;

    // Not focusable: it is an illustration, and a focus stop here would sit
    // between the action buttons and the rows below for no gain.
    return SizedBox(
      width: ShonenX.detailPosterWidth,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ShonenX.posterRadius),
          child: Hero(
            tag: tag,
            child: (url == null || url.isEmpty)
                ? Container(color: cs.surfaceContainer)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: cs.surfaceContainer),
                    errorWidget: (_, __, ___) =>
                        Container(color: cs.surfaceContainer),
                  ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _IconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      scaleOnFocus: false,
      builder: (context, isFocused) => SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          size: 28,
          semanticLabel: tooltip,
          color: isFocused ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Tracker state as a single icon.
///
/// The old version was a labelled button whose only route to editing an entry
/// was a long-press -- a gesture no remote can produce. Everything now goes
/// through the manager sheet.
class _TrackerButton extends ConsumerWidget {
  final UnifiedMedia media;
  final VoidCallback onOpenManager;

  const _TrackerButton({required this.media, required this.onOpenManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTrackers = ref.watch(activeTrackersProvider(media.type));
    if (activeTrackers.isEmpty) return const SizedBox.shrink();

    final tracker = ref.watch(primaryTrackerProvider);
    final links = ref.watch(trackerLinkProvider(media.id)).value ?? {};
    final trackingState = ref.watch(
      mediaTrackingProvider(TrackingQuery(tracker.type, media.id, media.type)),
    );

    final isAuthenticated = tracker.type.isAuthenticated(ref);
    final isLinked =
        links.containsKey(tracker.type) || tracker.type == TrackerType.local;

    final IconData icon;
    final String tooltip;
    if (!isAuthenticated) {
      icon = Icons.login;
      tooltip = 'Log in to ${tracker.type.displayName}';
    } else if (isLinked && trackingState.value != null) {
      icon = Icons.bookmark_added;
      tooltip =
          'Ep ${trackingState.value!.progress.toInt()} • '
          '${trackingState.value!.status.getLabelForMedia(media.type)}';
    } else {
      icon = Icons.bookmark_add_outlined;
      tooltip = 'Add to ${tracker.type.displayName}';
    }

    return _IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: () {
        if (tracker is RemoteTracker && !isAuthenticated) {
          ref.read(authTokensProvider.notifier).login(tracker);
          return;
        }
        onOpenManager();
      },
    );
  }
}
