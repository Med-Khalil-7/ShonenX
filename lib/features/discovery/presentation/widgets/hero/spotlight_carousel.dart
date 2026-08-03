import 'dart:async';

import 'package:shonenx/shared/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/tv/tv_badge.dart';

/// Full-bleed spotlight at the top of Home.
///
/// The strip of artwork thumbnails along the bottom is both the page indicator
/// and the control: each is a focus stop, moving along it previews that title
/// in the panel above, and OK opens it.
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

  /// Invoked when focus returns to the hero from below. Its thumbnails opt out
  /// of `ensureVisible` so that moving along the strip cannot scroll the page,
  /// which also means nothing scrolls the page back up on the way in.
  final VoidCallback? onEnter;

  /// Used for the first thumbnail, so the page can hand focus back into the
  /// hero from below without reaching into this widget's state.
  final FocusNode? entryFocus;

  const SpotlightCarousel({
    super.key,
    required this.data,
    this.tagPrefix = 'spotlight',
    this.autofocus = true,
    this.onEscapeUp,
    this.onEnter,
    this.entryFocus,
  });

  @override
  ConsumerState<SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends ConsumerState<SpotlightCarousel> {
  static const _maxItems = 10;
  static const _advanceInterval = Duration(seconds: 8);

  /// Height reserved for the header buttons, as a fraction of the hero.
  static const _headerBandFraction = 0.16;

  /// One per slide. The thumbnail strip is both the indicator and the
  /// control: moving along it previews each title above, and OK opens it.
  final List<FocusNode> _thumbFocus = [];

  int _index = 0;
  bool _focused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final node in _thumbFocus) {
      // The entry node is owned by the page.
      if (node != widget.entryFocus) node.dispose();
    }
    super.dispose();
  }

  /// Grown lazily: the slide count is not known until the feed resolves.
  FocusNode _focusFor(int index) {
    while (_thumbFocus.length <= index) {
      final i = _thumbFocus.length;
      // The first thumbnail borrows the page's node so the page can focus it.
      final node = i == 0 && widget.entryFocus != null
          ? widget.entryFocus!
          : FocusNode(debugLabel: 'heroThumb$i');
      node.addListener(() {
        if (!mounted) return;
        if (node.hasFocus) _select(i);
        _onFocusChanged();
      });
      _thumbFocus.add(node);
    }
    return _thumbFocus[index];
  }

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
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
    final hasFocus = _thumbFocus.any((n) => n.hasFocus);
    if (_focused == hasFocus) return;
    setState(() => _focused = hasFocus);
    // Auto-advance while the user is reading a slide would move the target out
    // from under the OK press.
    if (hasFocus) {
      _timer?.cancel();
      widget.onEnter?.call();
    } else {
      _restartTimer();
    }
  }

  /// The hero no longer advances on its own.
  ///
  /// Each tick cross-faded two full-screen banners through an AnimatedSwitcher,
  /// which is a full-viewport saveLayer for the length of the transition --
  /// every eight seconds, forever, including while the user is on another
  /// screen with home still alive in the shell. The slide strip is a D-pad
  /// control and nothing on a TV needs a carousel that moves by itself.
  void _restartTimer() {
    _timer?.cancel();
  }

  /// Up escapes to the header, which is drawn over the hero and is therefore
  /// invisible to geometric traversal. Right wraps; left does not.
  ///
  /// Right off the end returns to the first slide, so browsing forward never
  /// dead-ends. Left off the first slide is deliberately *not* a wrap: it falls
  /// through so the shell can hand focus to the navigation rail, which is the
  /// only way to reach the rail from the hero. Wrapping both ways cost the user
  /// that route.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp && widget.onEscapeUp != null) {
      widget.onEscapeUp!();
      return KeyEventResult.handled;
    }

    final step = switch (key) {
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowLeft => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;

    final count = _items.length;
    if (count == 0) return KeyEventResult.ignored;

    final from = _thumbFocus.indexWhere((n) => n.hasFocus);
    if (from < 0) return KeyEventResult.ignored;

    // Leaving on the left edge is the shell's business, not ours.
    if (step < 0 && from == 0) return KeyEventResult.ignored;

    // Stop at the ends; do not wrap.
    //
    // This was modulo, so holding right ran round the strip forever -- the
    // slide, its backdrop and its poster changing on every key repeat, for as
    // long as the button was held. A strip of ten titles is a list, not a
    // carousel: the last one is the end of it.
    final to = from + step;
    if (to < 0 || to >= count || to >= _thumbFocus.length) {
      return KeyEventResult.handled;
    }
    _thumbFocus[to].requestFocus();
    return KeyEventResult.handled;
  }

  void _openDetails(UnifiedMedia media) {
    context.push(
      '/details/${media.type.id}?tag=${widget.tagPrefix}-${media.id}',
      extra: media,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final m = ShonenXMetrics.of(context);

    // Snapped to a whole device pixel. A fraction of a pixel left the bottom
    // row only partly covered by the scrim that hides the backdrop, so a
    // hairline of the artwork showed along the hero's bottom edge -- one bright
    // line across the full width, right where the hero meets the first row.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final height =
        (size.height * ShonenX.heroHeightFraction * dpr).roundToDouble() / dpr;
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
              // Lifts the slide strip off the hero's bottom edge, where the
              // artwork now runs down to.
              bottom: m.body * 2.6,
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
                          items: items,
                          index: _index,
                          focusFor: _focusFor,
                          autofocus: widget.autofocus,
                          onOpen: _openDetails,
                        ),
                      ),
                      SizedBox(width: m.shellGutter(size) * 2),
                      _Poster(media: media, height: posterHeight),
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

/// The left column: metadata, title, synopsis and the slide strip.
class _Details extends StatelessWidget {
  final UnifiedMedia? media;
  final ShonenXMetrics metrics;
  final List<UnifiedMedia> items;
  final int index;
  final FocusNode Function(int) focusFor;
  final bool autofocus;
  final ValueChanged<UnifiedMedia> onOpen;

  const _Details({
    required this.media,
    required this.metrics,
    required this.items,
    required this.index,
    required this.focusFor,
    required this.autofocus,
    required this.onOpen,
  });

  /// Line counts and line heights the reserved boxes are built from. Kept as
  /// constants so the box and the Text it holds can never disagree.
  static const _titleLines = 2;
  static const _synopsisLines = 3;
  static const _titleHeight = 1.1;
  static const _bodyHeight = 1.5;

  double get _titleLineHeight => metrics.titleHero * _titleHeight;
  double get _bodyLineHeight => metrics.body * _bodyHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = metrics;

    if (media == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Genres ride in the metadata row rather than getting a line of their
        // own, which is what keeps the strip below on screen.
        TvMetaRow(media: media!, showGenres: true),
        SizedBox(height: m.body * 0.8),
        // Title and synopsis occupy their full line count whether or not the
        // slide fills it. Sized to content, a one-line title or a title with
        // no synopsis behind it made the whole column shorter, and the strip
        // below jumped up the screen as the carousel advanced -- a page
        // indicator that will not hold still is worse than no indicator.
        SizedBox(
          height: _titleLineHeight * _titleLines,
          child: Text(
            media!.title.availableTitle,
            maxLines: _titleLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: m.titleHero,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              height: _titleHeight,
            ),
          ),
        ),
        SizedBox(height: m.body),
        SizedBox(
          height: _bodyLineHeight * _synopsisLines,
          child: Text(
            plainSynopsis(media!.description ?? ''),
            maxLines: _synopsisLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: m.body,
              color: cs.onSurfaceVariant,
              height: _bodyHeight,
            ),
          ),
        ),
        // The strip hugs the foot of the hero. With the block above at a fixed
        // height that is a fixed position, so it neither drifts between slides
        // nor sits adrift in the middle of the screen -- the hero's own height
        // is what places it, and that is tuned to land just under the text.
        const Spacer(),
        if (items.isNotEmpty)
          _SlideStrip(
            items: items,
            index: index,
            metrics: m,
            focusFor: focusFor,
            autofocus: autofocus,
            onOpen: onOpen,
          ),
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

/// Artwork thumbnails for every slide: the page indicator and the control in
/// one. Moving along it previews each title above; OK opens the one shown.
///
/// This replaces a dot indicator plus a pair of action buttons. Dots say which
/// slide you are on but not what is on it, and the buttons duplicated what the
/// detail screen already does one press later.
class _SlideStrip extends StatefulWidget {
  final List<UnifiedMedia> items;
  final int index;
  final ShonenXMetrics metrics;
  final FocusNode Function(int) focusFor;
  final bool autofocus;
  final ValueChanged<UnifiedMedia> onOpen;

  const _SlideStrip({
    required this.items,
    required this.index,
    required this.metrics,
    required this.focusFor,
    required this.autofocus,
    required this.onOpen,
  });

  @override
  State<_SlideStrip> createState() => _SlideStripState();
}

class _SlideStripState extends State<_SlideStrip> {
  final ScrollController _controller = ScrollController();

  double get _itemExtent =>
      widget.metrics.heroThumb * 1.22; // thumbnail plus separator

  @override
  void didUpdateWidget(covariant _SlideStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _revealSelected();
  }

  /// Keeps the selected thumbnail on screen by scrolling *this* list only.
  ///
  /// `Scrollable.ensureVisible` -- which is what TvFocusable does by default --
  /// walks up and scrolls every enclosing scrollable, so letting it handle the
  /// strip dragged the whole page down a little on each step.
  void _revealSelected() {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final target =
        widget.index * _itemExtent - (viewport - _itemExtent) / 2;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: TvFocus.animation,
      curve: TvFocus.curve,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    return SizedBox(
      height: m.heroThumb / ShonenX.thumbAspect + TvFocus.ringWidth * 2,
      child: FocusTraversalGroup(
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          // Directional traversal only reaches nodes that have been built.
          cacheExtent: 700,
          itemCount: widget.items.length,
          separatorBuilder: (_, __) => SizedBox(width: m.heroThumb * 0.13),
          itemBuilder: (context, i) => _Thumb(
            media: widget.items[i],
            metrics: m,
            selected: i == widget.index,
            focusNode: widget.focusFor(i),
            autofocus: widget.autofocus && i == 0,
            onTap: () => widget.onOpen(widget.items[i]),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final UnifiedMedia media;
  final ShonenXMetrics metrics;
  final bool selected;
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onTap;

  const _Thumb({
    required this.media,
    required this.metrics,
    required this.selected,
    required this.focusNode,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = metrics;
    final radius = BorderRadius.circular(m.heroThumb * 0.12);
    final url = media.banner ?? media.cover;

    return TvFocusable(
      onTap: onTap,
      focusNode: focusNode,
      autofocus: autofocus,
      borderRadius: radius,
      scaleOnFocus: false,
      // The strip scrolls itself -- see _SlideStripState._revealSelected.
      ensureVisible: false,
      // The ring already marks the selection; a second highlight would be
      // saying the same thing twice.
      ringColor: cs.onSurface,
      builder: (context, isFocused) => AnimatedOpacity(
        duration: TvFocus.animation,
        // Unselected slides sit back so the current one reads first.
        opacity: selected ? 1.0 : 0.45,
        child: SizedBox(
          width: m.heroThumb,
          height: m.heroThumb / ShonenX.thumbAspect,
          child: ClipRRect(
            borderRadius: radius,
            child: (url == null || url.isEmpty)
                ? ColoredBox(color: cs.surfaceContainer)
                : AppNetworkImage(
                    url: url,
                    // A wide banner cropped into a tall tile: width is the
                    // short edge here, so budgeting from it would blur the
                    // part actually on screen.
                    fromHeight: true,
                    height: m.heroThumb / ShonenX.thumbAspect,
                    placeholder: ColoredBox(color: cs.surfaceContainer),
                  ),
          ),
        ),
      ),
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
                : AppNetworkImage(
                    url: url,
                    alignment: Alignment.topCenter,
                    // Fills the hero edge to edge (cover is the default).
                    //
                    // AniList banners are a wide strip, about 1900x400, and
                    // the hero is 1920x605 on a 1080p panel, so filling it
                    // costs a 1.5x upscale and crops the sides. That is the
                    // source's limit, not a setting -- there is no larger
                    // banner to ask for. What is in our hands is the decode,
                    // which is now at the size it is drawn: this used to run
                    // at half resolution for the crossfade, making it a 960px
                    // bitmap stretched across the whole screen, three times
                    // its own size and the softest thing in the app.
                    placeholder: ColoredBox(color: cs.surface),
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
              colors: [cs.surface, cs.surface.withValues(alpha: 0.0)],
              // Measured from the bottom edge up, and it starts fading from
              // zero: no solid band at all. This was [0, 0.12, 0.6] -- opaque
              // for the bottom eighth and not clear until past halfway, so the
              // artwork died around the middle of the hero and everything
              // below it was flat background.
              stops: const [0.0, 0.34],
            ),
          ),
        ),
      ],
    );
  }
}

/// The slide's artwork. Display only.
///
/// It used to grow a ring while the hero held focus, echoing the strip below
/// it. Nothing about it is selectable, so the ring claimed a focus that lived
/// on the thumbnails -- two things wearing the same highlight, only one of
/// which answers to a keypress.
class _Poster extends StatelessWidget {
  final UnifiedMedia? media;
  final double height;

  const _Poster({required this.media, required this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ShonenX.posterRadius);
    final url = media?.cover ?? media?.banner;

    return SizedBox(
      width: height * ShonenX.posterAspect,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: SizedBox.expand(
            key: ValueKey(url ?? 'empty'),
            child: (url == null || url.isEmpty)
                ? ColoredBox(color: cs.surfaceContainer)
                : AppNetworkImage(
                    url: url,
                    width: height * ShonenX.posterAspect,
                    placeholder: ColoredBox(color: cs.surfaceContainer),
                  ),
          ),
        ),
      ),
    );
  }
}
