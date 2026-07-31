import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/utils/formatting.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_number_cell.dart';
import 'package:shonenx/features/discovery/providers/episodes_provider.dart';
import 'package:shonenx/features/discovery/providers/matched_media_provider.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/features/tracking/providers/media_tracking_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_registry.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';
import 'package:shonenx/source_engine/models/source_info.dart';

/// One page of the grid: at most 100 episodes, plus the label for its tab.
class _EpisodeRange {
  final String label;
  final List<UnifiedEpisode> episodes;

  const _EpisodeRange(this.label, this.episodes);
}

/// The episode picker: a grid of numbered squares with range tabs above it.
///
/// Mounted full-screen by `EpisodesScreen` and inside the player's side sheet.
/// It measures its own constraints rather than the screen's, so the same
/// widget lays out at ten columns on a page and five in a 38%-wide sheet.
class EpisodeGridView extends ConsumerStatefulWidget {
  final UnifiedMedia media;

  /// Episode the user would resume. Gets initial focus and the accent fill.
  final double? currentEpisodeNumber;

  /// Overrides the tracker/history-derived progress when non-zero.
  final double watchedProgress;

  final void Function(UnifiedEpisode episode, SourceInfo sourceInfo)
  onEpisodeTap;

  final EdgeInsets padding;

  const EpisodeGridView({
    super.key,
    required this.media,
    required this.onEpisodeTap,
    this.currentEpisodeNumber,
    this.watchedProgress = 0,
    this.padding = EdgeInsets.zero,
  });

  @override
  ConsumerState<EpisodeGridView> createState() => _EpisodeGridViewState();
}

class _EpisodeGridViewState extends ConsumerState<EpisodeGridView> {
  static const _pageSize = 100;

  int _rangeIndex = 0;
  List<FocusNode> _tabNodes = const [];

  /// Held by cell 0 so the tab strip can hand focus to a known place rather
  /// than letting geometry pick whichever cell happens to sit under the tab.
  final _firstCellFocus = FocusNode(debugLabel: 'epCell0');

  /// Index of the focused cell within the current range. A plain field, never
  /// `setState` -- rebuilding the whole grid on every D-pad press would undo
  /// the point of building it non-lazily.
  int? _focusedIndex;

  bool _didAutofocus = false;
  bool _isRetrying = false;

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    _firstCellFocus.dispose();
    super.dispose();
  }

  void _syncTabNodes(int count) {
    if (_tabNodes.length == count) return;
    for (final n in _tabNodes) {
      n.dispose();
    }
    _tabNodes = List.generate(count, (_) => FocusNode(debugLabel: 'epRange'));
  }

  void _triggerRetry(MediaArgs matchArgs) {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    ref.invalidate(matchedMediaProvider(matchArgs));
    ref.invalidate(episodesListProvider(matchArgs));
    if (widget.media.sourceId != null) {
      ref.invalidate(
        sourceEpisodesProvider((
          providerId: widget.media.providerId ?? widget.media.id,
          sourceId: widget.media.sourceId!,
          type: widget.media.type,
        )),
      );
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isRetrying = false);
    });
  }

  /// Season grouping folded into the page split.
  ///
  /// Seasons cannot simply be flattened: the source lists restart numbering
  /// each season, so deduplicating by episode number across a whole series
  /// would silently drop S2E1 in favour of S1E1. Grouping by season first and
  /// only then slicing into pages keeps every episode while still leaving the
  /// common single-season case with plain "1 - 100" tabs.
  List<_EpisodeRange> _buildRanges(List<UnifiedEpisode> all) {
    final seasons = all.map((e) => e.season).toSet().toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1; // specials and extras last
        if (b == null) return -1;
        return a.compareTo(b);
      });

    final ranges = <_EpisodeRange>[];

    for (final season in seasons) {
      final deduped = <double, UnifiedEpisode>{};
      for (final e in all.where((e) => e.season == season)) {
        deduped.putIfAbsent(e.number, () => e);
      }
      final episodes = deduped.values.toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      if (episodes.isEmpty) continue;

      final prefix = seasons.length > 1
          ? (season == null ? 'Specials · ' : 'S$season · ')
          : '';

      for (var i = 0; i < episodes.length; i += _pageSize) {
        final page = episodes.sublist(
          i,
          (i + _pageSize).clamp(0, episodes.length),
        );
        final first = formatEpisodeNumber(page.first.number) ?? '';
        final last = formatEpisodeNumber(page.last.number) ?? '';
        final span = page.length == 1 ? first : '$first – $last';
        ranges.add(_EpisodeRange('$prefix$span', page));
      }
    }

    return ranges;
  }

  @override
  Widget build(BuildContext context) {
    final matchArgs = MediaArgs.fromMedia(widget.media);
    final episodesAsync = ref.watch(episodesListProvider(matchArgs));
    final isBusy =
        _isRetrying || episodesAsync.isRefreshing || episodesAsync.isLoading;

    // Watched state, unchanged from the list panel this replaces: the tracker's
    // progress marks everything below it, and the local history covers episodes
    // played without a tracker linked.
    final primaryTracker = ref.watch(primaryTrackerProvider);
    final trackingState = ref.watch(
      mediaTrackingProvider(
        TrackingQuery(primaryTracker.type, widget.media.id, widget.media.type),
      ),
    );
    final trackedProgress = trackingState.value?.progress.toDouble() ?? 0;

    final historyWatchedSet =
        (ref.watch(historyEpisodesProvider(widget.media.id)).value ?? [])
            .map((e) => e.episodeNumber)
            .toSet();

    final maxHistoryEp = historyWatchedSet.fold<double>(
      0.0,
      (max, epNum) => epNum > max ? epNum : max,
    );

    final watched = widget.watchedProgress > 0
        ? widget.watchedProgress
        : (trackedProgress > 0 ? trackedProgress : maxHistoryEp);

    return episodesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(
        icon: Icons.error_outline_rounded,
        iconColor: Theme.of(context).colorScheme.error,
        title: e.toString().contains('Cloudflare')
            ? 'Cloudflare verification failed.'
            : 'Failed to fetch episodes',
        detail: e.toString().contains('Cloudflare')
            ? 'Try turning off "In-app Cloudflare Bypass" in settings to use the proxy, or fix the match manually.'
            : '$e',
        busy: isBusy,
        onRetry: () => _triggerRetry(matchArgs),
      ),
      data: (state) {
        if (state.episodes.isEmpty) {
          return _Message(
            icon: Icons.folder_open_rounded,
            title: 'No episodes found for this source.',
            detail:
                'The provider may still be indexing, or the match might need to be retried.',
            busy: isBusy,
            onRetry: () => _triggerRetry(matchArgs),
          );
        }

        final ranges = _buildRanges(state.episodes);
        if (ranges.isEmpty) {
          return _Message(
            icon: Icons.folder_open_rounded,
            title: 'No episodes found for this source.',
            busy: isBusy,
            onRetry: () => _triggerRetry(matchArgs),
          );
        }

        _syncTabNodes(ranges.length);

        // Open on the page holding the resume episode, so a 900-episode series
        // does not land the user on episode 1 every time.
        if (!_didAutofocus && widget.currentEpisodeNumber != null) {
          final i = ranges.indexWhere(
            (r) => r.episodes.any(
              (e) => e.number == widget.currentEpisodeNumber,
            ),
          );
          if (i >= 0) _rangeIndex = i;
        }
        if (_rangeIndex >= ranges.length) _rangeIndex = 0;

        final range = ranges[_rangeIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ranges.length > 1)
              Padding(
                padding: EdgeInsets.only(
                  left: widget.padding.left,
                  right: widget.padding.right,
                  bottom: ShonenXMetrics.of(context).rowGap,
                ),
                child: _RangeTabStrip(
                  ranges: [for (final r in ranges) r.label],
                  selected: _rangeIndex,
                  nodes: _tabNodes,
                  onSelected: (i) => setState(() => _rangeIndex = i),
                  onEnterGrid: _firstCellFocus.requestFocus,
                ),
              ),
            Expanded(
              child: _Grid(
                key: ValueKey(_rangeIndex),
                episodes: range.episodes,
                firstCellFocus: _firstCellFocus,
                padding: widget.padding,
                watchedProgress: watched,
                historyWatchedSet: historyWatchedSet,
                currentEpisodeNumber: widget.currentEpisodeNumber,
                // Only the very first grid we show takes focus. Switching
                // ranges later must leave focus on the tab the user pressed.
                autofocus: !_didAutofocus,
                onAutofocused: () => _didAutofocus = true,
                onFocusedIndexChanged: (i) => _focusedIndex = i,
                focusedIndex: () => _focusedIndex,
                onEscapeUp: _tabNodes.isEmpty || ranges.length < 2
                    ? null
                    : () => _tabNodes[_rangeIndex].requestFocus(),
                onTap: (episode) =>
                    widget.onEpisodeTap(episode, state.source),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The squares.
///
/// Built eagerly into a Column of Rows rather than a GridView. Directional
/// traversal can only reach focus nodes that already exist, and a sliver only
/// mounts what is inside the viewport plus its cache extent -- so a lazy grid
/// dead-ends partway down. That is fatal here rather than merely awkward,
/// because `_TvScrollBehavior` removes drag scrolling: a cell focus cannot
/// reach is a cell that cannot be reached at all. A hundred cells is a cheap
/// build; this is the same shape `TvOnScreenKeyboard` uses for its keys.
class _Grid extends StatelessWidget {
  final List<UnifiedEpisode> episodes;
  final FocusNode firstCellFocus;

  final EdgeInsets padding;
  final double watchedProgress;
  final Set<double> historyWatchedSet;
  final double? currentEpisodeNumber;
  final bool autofocus;
  final VoidCallback onAutofocused;
  final ValueChanged<int?> onFocusedIndexChanged;
  final int? Function() focusedIndex;
  final VoidCallback? onEscapeUp;
  final void Function(UnifiedEpisode) onTap;

  const _Grid({
    super.key,
    required this.episodes,
    required this.firstCellFocus,
    required this.padding,
    required this.watchedProgress,
    required this.historyWatchedSet,
    required this.currentEpisodeNumber,
    required this.autofocus,
    required this.onAutofocused,
    required this.onFocusedIndexChanged,
    required this.focusedIndex,
    required this.onEscapeUp,
    required this.onTap,
  });

  /// Grid geometry: how many columns, and how big a cell is.
  ///
  /// Derived purely from the panel's own box -- never from how many episodes
  /// this title has. That is the point: the grid is the same control for a
  /// twelve-episode season and a thousand-episode one, so nothing re-flows
  /// when you move between two shows. It still scales with the panel, so
  /// 720p, 1080p and 4K each get cells in proportion, and the player's narrow
  /// side sheet gets its own smaller constant.
  ///
  /// Cells are rectangles, not squares: the columns divide the width and the
  /// rows divide the height, so the grid fills the screen exactly instead of
  /// leaving a band of dead space under the last row.
  static (int, double, double) _geometry({
    required double width,
    required double height,
    required double gap,
    required ShonenXMetrics m,
  }) {
    // Target sizes, as a fraction of the viewport like every other measure in
    // the design. Rounding to the nearest whole cell is what makes the count
    // stable across titles.
    final columns = math.max(4, ((width + gap) / (m.body * 5.0 + gap)).round());
    final cellW = (width - gap * (columns - 1)) / columns;

    if (!height.isFinite) return (columns, cellW, cellW);

    final rows = math.max(3, ((height + gap) / (m.body * 4.2 + gap)).floor());
    final cellH = (height - gap * (rows - 1)) / rows;

    return (columns, cellW, cellH);
  }

  @override
  Widget build(BuildContext context) {
    final m = ShonenXMetrics.of(context);
    final gap = m.rowGap;

    return LayoutBuilder(
      builder: (context, constraints) {
        final innerW = constraints.maxWidth - padding.horizontal;
        final innerH = constraints.maxHeight.isFinite
            ? constraints.maxHeight - padding.vertical
            : double.infinity;

        final (columns, cellW, cellH) = _geometry(
          width: innerW,
          height: innerH,
          gap: gap,
          m: m,
        );

        // Index of the cell that should claim focus on first build.
        var focusTarget = 0;
        if (currentEpisodeNumber != null) {
          final i = episodes.indexWhere(
            (e) => e.number == currentEpisodeNumber,
          );
          if (i >= 0) focusTarget = i;
        }
        if (autofocus) onAutofocused();

        final rows = <List<int>>[];
        for (var i = 0; i < episodes.length; i += columns) {
          rows.add([
            for (var c = i; c < i + columns && c < episodes.length; c++) c,
          ]);
        }

        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) =>
              _onKey(event, columns, episodes.length),
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: gap,
              children: [
                for (final row in rows)
                  Row(
                    spacing: gap,
                    // Fixed boxes rather than Expanded: the height half of
                    // the geometry has to survive, and Expanded only governs
                    // width.
                    children: [
                      for (final i in row)
                        SizedBox(
                          width: cellW,
                          height: cellH,
                          child: _cell(i, math.min(cellW, cellH), focusTarget),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(int index, double size, int focusTarget) {
    final ep = episodes[index];
    final isCurrent = currentEpisodeNumber == ep.number;
    final isWatched =
        watchedProgress >= ep.number || historyWatchedSet.contains(ep.number);

    return EpisodeNumberCell(
      episode: ep,
      focusNode: index == 0 ? firstCellFocus : null,
      size: size,
      isFiller: ep.isFiller,
      state: isCurrent
          ? EpisodeCellState.current
          : isWatched
          ? EpisodeCellState.watched
          : EpisodeCellState.unwatched,
      autofocus: autofocus && index == focusTarget,
      onFocusChange: (has) => onFocusedIndexChanged(has ? index : null),
      onTap: () => onTap(ep),
    );
  }

  KeyEventResult _onKey(KeyEvent event, int columns, int count) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final i = focusedIndex();
    if (i == null) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Nothing sits left of column 0, but the back arrow in the header is
    // further left than the grid's own gutter, so geometry would happily jump
    // there from any row. Swallow instead.
    if (key == LogicalKeyboardKey.arrowLeft && i % columns == 0) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        (i % columns == columns - 1 || i == count - 1)) {
      return KeyEventResult.handled;
    }
    // UP out of the top row returns to the tab the user came from. Left to
    // geometry it would pick whichever tab happens to sit above that column,
    // which for a short strip and a right-hand column is nothing at all.
    if (key == LogicalKeyboardKey.arrowUp && i < columns) {
      final escape = onEscapeUp;
      if (escape != null) {
        escape();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

/// "1 – 100", "101 – 200", …
///
/// OK switches the range and leaves focus on the tab; DOWN enters the grid and
/// UP comes back. One job per direction -- if OK also dived into the grid there
/// would be no way to tell whether a press meant "select" or "select and go".
class _RangeTabStrip extends StatefulWidget {
  final List<String> ranges;
  final int selected;
  final List<FocusNode> nodes;
  final ValueChanged<int> onSelected;
  final VoidCallback onEnterGrid;

  const _RangeTabStrip({
    required this.ranges,
    required this.selected,
    required this.nodes,
    required this.onSelected,
    required this.onEnterGrid,
  });

  @override
  State<_RangeTabStrip> createState() => _RangeTabStripState();
}

class _RangeTabStripState extends State<_RangeTabStrip> {
  final _scroll = ScrollController();
  bool _atStart = true;
  bool _atEnd = true;

  List<String> get ranges => widget.ranges;
  int get selected => widget.selected;
  List<FocusNode> get nodes => widget.nodes;
  ValueChanged<int> get onSelected => widget.onSelected;
  VoidCallback get onEnterGrid => widget.onEnterGrid;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _scroll.removeListener(_sync);
    _scroll.dispose();
    super.dispose();
  }

  /// Which edges still have tabs beyond them.
  void _sync() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final atStart = p.pixels <= p.minScrollExtent + 1;
    final atEnd = p.pixels >= p.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = ShonenXMetrics.of(context);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // DOWN always enters at the first episode of the range. Geometry would
      // otherwise drop focus onto whichever cell sits under the tab, so
      // picking "103 - 148" and pressing DOWN landed on 105.
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onEnterGrid();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _buildStrip(context, cs, m),
    );
  }

  Widget _buildStrip(BuildContext context, ColorScheme cs, ShonenXMetrics m) {
    // Always scrolls, and the tabs are sized for a sofa rather than sized to
    // fit. Dividing the width between them made each one narrower the more
    // ranges a series had -- exactly backwards, since a long series is when
    // the strip matters most.
    final strip = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: m.rowGap,
        children: [
          for (var i = 0; i < ranges.length; i++) _tab(context, cs, m, i),
        ],
      ),
    );

    final fadeStart = !_atStart;
    final fadeEnd = !_atEnd;
    if (!fadeStart && !fadeEnd) return strip;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Fades where the row continues, so a tab cut off at the edge reads as
        // "there is more" rather than as a clipping bug.
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              if (fadeStart) Colors.transparent else Colors.white,
              Colors.white,
              Colors.white,
              if (fadeEnd) Colors.transparent else Colors.white,
            ],
            stops: const [0.0, 0.06, 0.94, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: strip,
        ),
        if (fadeStart)
          Positioned(left: 0, child: _edgeArrow(cs, m, Icons.chevron_left_rounded)),
        if (fadeEnd)
          Positioned(right: 0, child: _edgeArrow(cs, m, Icons.chevron_right_rounded)),
      ],
    );
  }

  /// A hint, not a control: the D-pad already moves along the strip, and an
  /// extra focus stop at each end would sit between the tabs and the grid.
  Widget _edgeArrow(ColorScheme cs, ShonenXMetrics m, IconData icon) {
    return IgnorePointer(
      child: Icon(icon, size: m.body * 1.5, color: cs.onSurfaceVariant),
    );
  }

  Widget _tab(BuildContext context, ColorScheme cs, ShonenXMetrics m, int i) {
    return TvFocusable(
      focusNode: i < nodes.length ? nodes[i] : null,
      onTap: () => onSelected(i),
      borderRadius: BorderRadius.circular(m.body * 1.2),
      scaleOnFocus: false,
      builder: (context, isFocused) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.body * 1.5,
          vertical: m.body * 0.7,
        ),
        decoration: BoxDecoration(
          color: i == selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(m.body * 1.2),
        ),
        child: Text(
          ranges[i],
          maxLines: 1,
          style: TextStyle(
            fontSize: m.body,
            height: 1.2,
            color: i == selected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: i == selected || isFocused
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Shared empty / error state, with the retry the old panel had.
class _Message extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? detail;
  final bool busy;
  final VoidCallback onRetry;

  const _Message({
    required this.icon,
    required this.title,
    required this.busy,
    required this.onRetry,
    this.iconColor,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(m.body * 1.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: m.heading * 2,
              color: iconColor ?? cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            SizedBox(height: m.body),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: m.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              SizedBox(height: m.body * 0.4),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: m.badge, color: cs.onSurfaceVariant),
              ),
            ],
            SizedBox(height: m.body * 1.2),
            TvButton(
              label: busy ? 'Fetching…' : 'Retry',
              icon: Icons.refresh_rounded,
              variant: TvButtonVariant.filledSurface,
              height: m.buttonHeight,
              loading: busy,
              autofocus: true,
              onPressed: busy ? null : onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
