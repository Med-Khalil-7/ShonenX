import 'dart:math' as math;

import 'package:shonenx/shared/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/features/auth/providers/auth_provider.dart';
import 'package:shonenx/features/discovery/domain/media_actions.dart';
import 'package:shonenx/features/discovery/presentation/widgets/details/detail_media_row.dart';
import 'package:shonenx/features/discovery/providers/details_provider.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/features/tracking/domain/isar_tracker_link.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_type.dart';
import 'package:shonenx/features/tracking/engine/remote_tracker.dart';
import 'package:shonenx/features/tracking/providers/media_tracking_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_link_provider.dart';
import 'package:shonenx/features/tracking/providers/tracker_registry.dart';
import 'package:shonenx/features/tracking/providers/tracking_prefs_provider.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';
import 'package:shonenx/shared/widgets/tv/tv_badge.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';

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

  /// One scope per row below the header, so left and right stay inside the row
  /// the user is on.
  ///
  /// The rows are already FocusTraversalGroups internally, but as bare
  /// siblings in one scope a press at either end of a row escaped into the
  /// next one -- the home screen does not have that problem because it wraps
  /// each row like this and owns up/down itself. Same shape here.
  final List<FocusScopeNode> _rowScopes = [];

  /// Scopes above the content rows: the meta icons, then the two lines of
  /// action buttons. Each is its own left/right chain, so walking the primary
  /// buttons never wanders into the line below or the icons above.
  static const _headerScopes = 2;
  static const _iconScope = 0;
  static const _actionScope = 1;

  /// Where up from the first row goes back to: the Play button.
  final FocusNode _headerFocus = FocusNode(debugLabel: 'detailsHeader');

  void _ensureRowScopes(int count) {
    while (_rowScopes.length < count) {
      _rowScopes.add(
        FocusScopeNode(debugLabel: 'detailsRow${_rowScopes.length}'),
      );
    }
  }

  /// The innermost scope holding focus.
  ///
  /// lastIndexWhere, not indexWhere: the action buttons sit inside the header
  /// row's scope, so both report hasFocus when a button is selected and the
  /// first match would always say "header".
  int get _focusedRow => _rowScopes.lastIndexWhere((s) => s.hasFocus);

  /// Where focus should land in scope [index]: where it was left, or its first
  /// control.
  ///
  /// The remembered child is the point of this -- stepping past a row and back
  /// should return to the card you were on, not restart the row.
  ///
  /// The exclusion matters as much. The header row's scope *contains* the
  /// action buttons, because the back arrow and the meta icons sit on either
  /// side of the column those buttons are in. Without skipping deeper scopes,
  /// asking the header where focus should go answered "the action buttons" --
  /// so pressing up from Play now put focus straight back on Play now and the
  /// top row was unreachable.
  FocusNode? _targetIn(int index) {
    final scope = _rowScopes[index];

    bool inDeeperScope(FocusNode node) {
      for (var i = index + 1; i < _rowScopes.length; i++) {
        final deeper = _rowScopes[i];
        if (identical(node, deeper) || node.ancestors.contains(deeper)) {
          return true;
        }
      }
      return false;
    }

    final remembered = scope.focusedChild;
    if (remembered != null &&
        remembered.canRequestFocus &&
        !inDeeperScope(remembered)) {
      return remembered;
    }
    for (final node in scope.traversalDescendants) {
      if (node.canRequestFocus &&
          !node.skipTraversal &&
          !inDeeperScope(node)) {
        return node;
      }
    }
    return null;
  }

  bool _focusRow(int index) {
    if (index < 0 || index >= _rowScopes.length) return false;
    final target = _targetIn(index);
    if (target == null) return false;
    target.requestFocus();
    return true;
  }

  /// Left and right walk the action buttons in order, wrapping round.
  ///
  /// Arrow keys are geometric: WidgetOrderTraversalPolicy sets tab order but
  /// inDirection still searches by position, so with the Wrap folded onto two
  /// lines there was nothing to the right of "Watch Dubbed" and the second
  /// line could not be reached sideways -- and Down was taken by the vertical
  /// stepper to leave for the cards, so "Add to watch list" and "Watch Subbed"
  /// could not be reached at all. Walking the list by index ignores where the
  /// line happened to break.
  KeyEventResult _cycleActions(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // Down goes to the button under this one, if the Wrap put one there.
    //
    // Only once there is nothing below does the press fall through to the
    // vertical stepper and leave for the cards -- pressing down on "Play now"
    // should reach "Add to watch list", not skip the line entirely. The group
    // confines directional traversal, so this can never wander out on its own.
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    if (down || up) {
      final focused = FocusManager.instance.primaryFocus;
      final moved =
          focused?.focusInDirection(
            down ? TraversalDirection.down : TraversalDirection.up,
          ) ??
          false;
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    final forward = key == LogicalKeyboardKey.arrowRight;
    final back = key == LogicalKeyboardKey.arrowLeft;
    if (!forward && !back) return KeyEventResult.ignored;

    final nodes = _rowScopes[_actionScope].traversalDescendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .toList();
    if (nodes.length < 2) return KeyEventResult.ignored;

    final current = nodes.indexWhere((n) => n.hasPrimaryFocus);
    if (current == -1) return KeyEventResult.ignored;

    final next = forward
        ? (current + 1) % nodes.length
        : (current - 1 + nodes.length) % nodes.length;
    nodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  /// Up and down step between the header and the rows; everything else is left
  /// to the row that has focus.
  KeyEventResult _handleVertical(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;

    final current = _focusedRow;

    if (down) {
      for (var i = current + 1; i < _rowScopes.length; i++) {
        if (_focusRow(i)) return KeyEventResult.handled;
      }
      // Nothing below; stay put rather than dropping focus into the page.
      return current == -1 ? KeyEventResult.ignored : KeyEventResult.handled;
    }

    if (current > 0) {
      for (var i = current - 1; i >= 0; i--) {
        if (_focusRow(i)) return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    for (final scope in _rowScopes) {
      scope.dispose();
    }
    _headerFocus.dispose();
    super.dispose();
  }

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

  /// Resumes the part-watched episode if there is one, otherwise starts the
  /// one after the last finished episode, otherwise episode one.
  ///
  /// [serverType] is applied as the player's preference rather than resolved
  /// here: PlayerController already picks a sub or dub server from that
  /// preference, and pre-resolving would run the whole source pipeline on a
  /// screen the user may never play from.
  Future<void> _play(UnifiedMedia media, {ServerType? serverType}) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      await MediaActions.play(context, ref, media, serverType: serverType);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Episodes live on their own page now. A remote needs the whole screen to
  /// show a hundred numbered squares; a 38%-wide sheet showed a list.
  void _openEpisodes(UnifiedMedia media) =>
      context.push('/episodes', extra: media);

  Future<void> _addToWatchList(UnifiedMedia media) =>
      MediaActions.addToWatchList(context, ref, media);

  void _openTrackerManager(UnifiedMedia media) =>
      MediaActions.openTrackerManager(context, media);

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
    final m = ShonenXMetrics.of(context);
    final gutter = m.gutter(size);
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

    _ensureRowScopes(_headerScopes);

    // Where the title and description start.
    //
    // The header indents past the back arrow, so the rows below have to use
    // the same edge or they hang to the left of the text they sit under. Kept
    // as one expression here rather than duplicated per row: the header builds
    // its offset from these same three pieces.
    final contentLeft =
        m.backArrowInset +
        math.max(gutter - m.backArrowInset, m.iconButton * 1.5) +
        m.backArrowGap;

    return AppScaffold(
      fullBleed: true,
      body: Stack(
        children: [
          _Backdrop(url: media.banner ?? media.cover),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _handleVertical,
            child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  // Starts at the back arrow's inset, not the content gutter:
                  // the arrow lives in the margin to the left of the text
                  // column, so it must not push the column inward.
                  padding: EdgeInsets.fromLTRB(
                    m.backArrowInset,
                    topInset + 16,
                    gutter,
                    m.body * 3,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Every dimension here is derived, not fixed. Devices
                      // report very different logical widths for the same
                      // panel, and a hardcoded poster plus two hardcoded
                      // buttons overflow the narrow ones.
                      final posterWidth = math.min(
                        m.detailPoster,
                        size.height * 0.72 * ShonenX.posterAspect,
                      );
                      // The back arrow shares a scope with the meta icons
                      // on its line: they read as one row of controls, so
                      // left and right should walk between them. The action
                      // buttons nest their own scope inside this one, which
                      // is why _focusedRow takes the innermost match.
                      return FocusScope(
                        node: _rowScopes[_iconScope],
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The margin between the arrow's inset and the
                          // content gutter is narrower than the button itself,
                          // so the slot has to be the larger of the two --
                          // sizing it to the margin alone squashed the icon.
                          SizedBox(
                            width: math.max(
                              gutter - m.backArrowInset,
                              m.iconButton * 1.5,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _IconButton(
                                icon: Icons.arrow_back,
                                onPressed: () => context.pop(),
                                tooltip: 'Back',
                              ),
                            ),
                          ),
                          // Clear space, so the arrow does not read as the
                          // first item of the metadata line next to it.
                          SizedBox(width: m.backArrowGap),
                          Expanded(child: _buildInfoColumn(media, theme, cs)),
                          SizedBox(width: gutter * 0.5),
                          _Poster(
                            media: media,
                            tag: widget.tag,
                            width: posterWidth,
                            height: posterWidth / ShonenX.posterAspect,
                          ),
                        ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Each row in its own scope, numbered by how many rows this
              // title actually has -- a series with no relations must not
              // leave an empty scope for up/down to step into.
              ...() {
                final rows = <Widget>[
                  if (relations.isNotEmpty)
                    DetailMediaRow(
                      title: 'Related Anime',
                      items: relations,
                      tagPrefix: 'details-rel',
                      edgeInset: contentLeft,
                    ),
                  if (characters.isNotEmpty)
                    DetailCharacterRow(
                      characters: characters,
                      edgeInset: contentLeft,
                    ),
                  if (recommendations.isNotEmpty)
                    DetailMediaRow(
                      title: 'Recommendations',
                      items: recommendations,
                      tagPrefix: 'details-rec',
                      edgeInset: contentLeft,
                    ),
                ];
                _ensureRowScopes(_headerScopes + rows.length);
                return [
                  for (var i = 0; i < rows.length; i++)
                    SliverToBoxAdapter(
                      child: FocusScope(
                        node: _rowScopes[_headerScopes + i],
                        child: rows[i],
                      ),
                    ),
                ];
              }(),
              SliverToBoxAdapter(child: SizedBox(height: topInset + 40)),
            ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(UnifiedMedia media, ThemeData theme, ColorScheme cs) {
    final genres = media.genres ?? const <String>[];
    final description = media.description;
    final m = ShonenXMetrics.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, not a Row: on a narrow viewport the badges and the two
        // action icons cannot share a line, and a Row would just clip them.
        Wrap(
          spacing: m.meta * 1.6,
          runSpacing: m.meta * 0.5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TvMetaRow(media: media),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconButton(
                  icon: Icons.share_outlined,
                  tooltip: 'Share',
                  onPressed: () => _share(media),
                ),
                SizedBox(width: m.meta),
                _TrackerButton(
                  media: media,
                  onOpenManager: () => _openTrackerManager(media),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: m.titlePage * 0.6),
        Text(
          media.title.availableTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: m.titlePage,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        SizedBox(height: m.titlePage * 0.7),
        if (description != null && description.isNotEmpty)
          Text(
            _plainText(description),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: m.body,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        SizedBox(height: m.body * 1.6),
        Text(
          'Genres: ${genres.join(', ')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: m.body,
            color: cs.onSurfaceVariant,
          ),
        ),
        SizedBox(height: m.body * 2.6),
        // All five in one group, deliberately.
        //
        // The Wrap breaks them onto two lines when the column is narrow, but
        // they are one set of things you can do with this title, so left and
        // right walk the whole set and wrap round -- reaching "Watch Subbed"
        // must not depend on which line it happened to land on. What they do
        // not do is leak into the icons above or the rows below; those have
        // scopes of their own and up/down is what moves between them.
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _cycleActions,
          child: FocusScope(
          node: _rowScopes[_actionScope],
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Wrap(
              spacing: m.label * 1.3,
              runSpacing: m.label,
              children: [
                TvButton(
                  label: 'Play now',
                  icon: Icons.play_arrow_rounded,
                  height: m.buttonHeight,
                  loading: _resolving,
                  ensureVisible: false,
                  focusNode: _headerFocus,
                  // The reason the screen exists. Land here on arrival so
                  // watching something is a single press.
                  autofocus: true,
                  onPressed: () => _play(media),
                ),
                TvButton(
                  label: 'More episodes',
                  icon: Icons.layers_outlined,
                  height: m.buttonHeight,
                  variant: TvButtonVariant.filledWhite,
                  ensureVisible: false,
                  onPressed: () => _openEpisodes(media),
                ),
                TvButton(
                  label: 'Watch',
                  emphasis: 'Dubbed',
                  icon: Icons.mic_none_rounded,
                  height: m.buttonHeight * 0.9,
                  variant: TvButtonVariant.bare,
                  ensureVisible: false,
                  onPressed: () => _play(media, serverType: ServerType.dub),
                ),
                TvButton(
                  label: 'Add to watch list',
                  icon: Icons.add_circle_outline,
                  height: m.buttonHeight * 0.9,
                  variant: TvButtonVariant.bare,
                  ensureVisible: false,
                  onPressed: () => _addToWatchList(media),
                ),
                TvButton(
                  label: 'Watch',
                  emphasis: 'Subbed',
                  icon: Icons.closed_caption_off_rounded,
                  height: m.buttonHeight * 0.9,
                  variant: TvButtonVariant.bare,
                  ensureVisible: false,
                  onPressed: () => _play(media, serverType: ServerType.sub),
                ),
              ],
            ),
          ),
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
          AppNetworkImage(
            url: url,
            alignment: Alignment.topCenter,
            placeholder: const SizedBox.shrink(),
            error: const SizedBox.shrink(),
          ),
          // Heavy enough that white body text stays legible over any artwork.
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.94),
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
  final double width;
  final double height;

  const _Poster({
    required this.media,
    required this.tag,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = media.cover ?? media.banner;

    // Not focusable: it is an illustration, and a focus stop here would sit
    // between the action buttons and the rows below for no gain.
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShonenX.posterRadius),
        child: Hero(
          tag: tag,
          child: (url == null || url.isEmpty)
              ? ColoredBox(color: cs.surfaceContainer)
              : AppNetworkImage(
                  url: url,
                  width: width,
                  placeholder: ColoredBox(color: cs.surfaceContainer),
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
    final m = ShonenXMetrics.of(context);

    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      scaleOnFocus: false,
      // Same treatment as the player's back arrow: over a backdrop image a
      // white ring competes with whatever is behind it, so focus tints the
      // glyph instead. It also keeps the arrow reading as a bare icon rather
      // than as a boxed button.
      ringColor: Colors.transparent,
      builder: (context, isFocused) => SizedBox(
        width: m.iconButton * 1.5,
        height: m.iconButton * 1.5,
        child: Icon(
          icon,
          size: m.iconButton,
          semanticLabel: tooltip,
          color: isFocused ? cs.primary : cs.onSurfaceVariant,
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
