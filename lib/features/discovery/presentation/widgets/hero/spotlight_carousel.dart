import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/features/discovery/domain/media_actions.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/tv/tv_badge.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';

/// Full-bleed spotlight at the top of Home.
///
/// The two action buttons are the focus stops. Paging happens by pressing past
/// them: left from the first button steps back a slide, right from the last
/// steps forward, and in between the presses move between the buttons. That
/// keeps the buttons genuinely usable while still letting the whole hero be
/// driven with nothing but a D-pad.
class SpotlightCarousel extends ConsumerStatefulWidget {
  final AsyncValue<List<UnifiedMedia>> data;

  /// Namespaces the Hero tags so they cannot collide with the row below, which
  /// may well be showing the same titles.
  final String tagPrefix;

  final bool autofocus;

  /// Invoked on a press that would leave the hero upwards. The hero is the
  /// topmost content, so nothing is above it geometrically and the default
  /// traversal has nowhere to go; the header buttons are drawn *over* the hero
  /// and have to be handed focus explicitly.
  final VoidCallback? onEscapeUp;

  const SpotlightCarousel({
    super.key,
    required this.data,
    this.tagPrefix = 'spotlight',
    this.autofocus = true,
    this.onEscapeUp,
  });

  @override
  ConsumerState<SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends ConsumerState<SpotlightCarousel> {
  static const _maxItems = 10;
  static const _advanceInterval = Duration(seconds: 8);

  /// Height reserved for the header buttons, as a fraction of the hero.
  static const _headerBandFraction = 0.16;

  final FocusNode _playFocus = FocusNode(debugLabel: 'heroPlay');
  final FocusNode _listFocus = FocusNode(debugLabel: 'heroList');

  int _index = 0;
  bool _focused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _playFocus.addListener(_onFocusChanged);
    _listFocus.addListener(_onFocusChanged);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playFocus.removeListener(_onFocusChanged);
    _listFocus.removeListener(_onFocusChanged);
    _playFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  List<UnifiedMedia> get _items {
    final all = widget.data.value ?? const <UnifiedMedia>[];
    return all.length > _maxItems ? all.sublist(0, _maxItems) : all;
  }

  UnifiedMedia? get _current {
    final items = _items;
    return items.isEmpty ? null : items[_index % items.length];
  }

  void _onFocusChanged() {
    final hasFocus = _playFocus.hasFocus || _listFocus.hasFocus;
    if (_focused == hasFocus) return;
    setState(() => _focused = hasFocus);
    // Auto-advance while the user is reading a slide would move the target out
    // from under the OK press.
    if (hasFocus) {
      _timer?.cancel();
    } else {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_advanceInterval, (_) {
      if (!mounted || _items.length < 2) return;
      setState(() => _index = (_index + 1) % _items.length);
    });
  }

  void _step(int delta) {
    final items = _items;
    if (items.isEmpty) return;
    setState(() => _index = (_index + delta) % items.length);
  }

  /// Claims left/right only at the ends of the button row, so traversal still
  /// moves between the two buttons in the middle.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (widget.onEscapeUp == null) return KeyEventResult.ignored;
      widget.onEscapeUp!();
      return KeyEventResult.handled;
    }

    final onFirst = _playFocus.hasFocus;
    final onLast = _listFocus.hasFocus;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight && onLast) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && onFirst) {
      // At the first slide, fall through so the shell's handler opens the
      // navigation rail -- which is what a left press at the left edge of the
      // screen should do.
      if (_index == 0) return KeyEventResult.ignored;
      _step(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _play() async {
    final media = _current;
    if (media == null) return;
    await MediaActions.play(context, ref, media);
  }

  void _openDetails() {
    final media = _current;
    if (media == null) return;
    context.push(
      '/details/${media.type.id}?tag=${widget.tagPrefix}-${media.id}',
      extra: media,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final m = ShonenXMetrics.of(context);
    final height = size.height * ShonenX.heroHeightFraction;
    final insets = TvMetrics.ofSize(size);
    final items = _items;
    final media = _current;

    return SizedBox(
      height: height,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Backdrop(media: media),
            Positioned(
              left: m.shellGutter(size),
              right: m.shellGutter(size),
              // Leaves a band at the top for the header buttons, which are
              // drawn over this and would otherwise land on the poster.
              top: insets.top + height * _headerBandFraction,
              bottom: m.body,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final posterHeight = constraints.maxHeight.clamp(
                    0.0,
                    m.heroPoster / ShonenX.posterAspect,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Details(
                          media: media,
                          metrics: m,
                          slideCount: items.length,
                          index: _index,
                          playFocus: _playFocus,
                          listFocus: _listFocus,
                          autofocus: widget.autofocus,
                          onPlay: _play,
                          onMoreInfo: _openDetails,
                        ),
                      ),
                      SizedBox(width: m.shellGutter(size) * 2),
                      _Poster(
                        media: media,
                        focused: _focused,
                        height: posterHeight,
                        borderColor: cs.onSurface,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The left column: metadata, title, synopsis, actions and the page indicator.
class _Details extends StatelessWidget {
  final UnifiedMedia? media;
  final ShonenXMetrics metrics;
  final int slideCount;
  final int index;
  final FocusNode playFocus;
  final FocusNode listFocus;
  final bool autofocus;
  final VoidCallback onPlay;
  final VoidCallback onMoreInfo;

  const _Details({
    required this.media,
    required this.metrics,
    required this.slideCount,
    required this.index,
    required this.playFocus,
    required this.listFocus,
    required this.autofocus,
    required this.onPlay,
    required this.onMoreInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = metrics;

    if (media == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        TvMetaRow(media: media!),
        SizedBox(height: m.body * 0.8),
        Text(
          media!.title.availableTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: m.titleHero,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            height: 1.1,
          ),
        ),
        if (media!.description != null && media!.description!.isNotEmpty) ...[
          SizedBox(height: m.body),
          Text(
            plainSynopsis(media!.description!),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: m.body,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
        SizedBox(height: m.body * 1.4),
        Row(
          children: [
            TvButton(
              label: 'Play now',
              icon: Icons.play_arrow_rounded,
              // No fixed width: these sit next to each other under a long
              // title and read better sized to their own labels.
              height: m.buttonHeight,
              focusNode: playFocus,
              autofocus: autofocus,
              // The hero is at the top of the page; centring it on focus would
              // scroll the header buttons out of sight.
              ensureVisible: false,
              onPressed: onPlay,
            ),
            SizedBox(width: m.label),
            TvButton(
              label: 'More info',
              icon: Icons.info_outline_rounded,
              height: m.buttonHeight,
              variant: TvButtonVariant.filledWhite,
              focusNode: listFocus,
              ensureVisible: false,
              onPressed: onMoreInfo,
            ),
          ],
        ),
        const Spacer(),
        if (slideCount > 1)
          _PageDots(count: slideCount, index: index, metrics: m),
      ],
    );
  }

  /// Descriptions arrive as fragments of HTML from every tracker.
  static String plainSynopsis(String raw) => raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Which slide of how many. The active dot stretches into a bar rather than
/// just brightening -- at 10 feet a change of shape reads where a change of
/// opacity does not.
class _PageDots extends StatelessWidget {
  final int count;
  final int index;
  final ShonenXMetrics metrics;

  const _PageDots({
    required this.count,
    required this.index,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = metrics.heroDot;

    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: TvFocus.animation,
            curve: TvFocus.curve,
            margin: EdgeInsets.only(right: size * 0.8),
            width: i == index ? metrics.heroDotActive : size,
            height: size,
            decoration: BoxDecoration(
              color: i == index
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(size),
            ),
          ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  final UnifiedMedia? media;

  const _Backdrop({required this.media});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = media?.banner ?? media?.cover;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          // SizedBox.expand is load-bearing: AnimatedSwitcher lays its children
          // out in a loose Stack, so an image inside it sizes to the source
          // bitmap and sits centred instead of covering the box.
          child: SizedBox.expand(
            key: ValueKey(url ?? 'empty'),
            child: (url == null || url.isEmpty)
                ? ColoredBox(color: cs.surface)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (_, __) => ColoredBox(color: cs.surface),
                    errorWidget: (_, __, ___) => ColoredBox(color: cs.surface),
                  ),
          ),
        ),
        // Two scrims: one so the text column stays legible over bright
        // artwork, one so the poster row below reads as part of the same
        // surface rather than a hard cut.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                cs.surface,
                cs.surface.withValues(alpha: 0.88),
                cs.surface.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.42, 0.82],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                cs.surface,
                cs.surface,
                cs.surface.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.12, 0.6],
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final UnifiedMedia? media;
  final bool focused;
  final double height;
  final Color borderColor;

  const _Poster({
    required this.media,
    required this.focused,
    required this.height,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ShonenX.posterRadius);
    final url = media?.cover ?? media?.banner;

    // Not a focus stop -- the buttons are. The border only echoes that the
    // hero as a whole is active.
    return AnimatedContainer(
      duration: TvFocus.animation,
      curve: TvFocus.curve,
      width: height * ShonenX.posterAspect,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: focused ? borderColor : Colors.transparent,
          width: TvFocus.ringWidth,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: SizedBox.expand(
            key: ValueKey(url ?? 'empty'),
            child: (url == null || url.isEmpty)
                ? ColoredBox(color: cs.surfaceContainer)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        ColoredBox(color: cs.surfaceContainer),
                    errorWidget: (_, __, ___) =>
                        ColoredBox(color: cs.surfaceContainer),
                  ),
          ),
        ),
      ),
    );
  }
}
