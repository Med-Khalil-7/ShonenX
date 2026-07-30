import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/shared/models/unified_media.dart';

/// Full-bleed spotlight at the top of Home.
///
/// A single focus stop rather than one per slide: on a remote, left/right
/// paging the hero is the expected gesture, and making each slide focusable
/// would mean the user has to traverse ten dead entries to reach the row
/// underneath.
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

  late final FocusNode _node = FocusNode(
    debugLabel: 'spotlight',
    onKeyEvent: _handleKey,
  );

  int _index = 0;
  bool _focused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _node.removeListener(_onFocusChanged);
    _node.dispose();
    super.dispose();
  }

  List<UnifiedMedia> get _items {
    final all = widget.data.value ?? const <UnifiedMedia>[];
    return all.length > _maxItems ? all.sublist(0, _maxItems) : all;
  }

  void _onFocusChanged() {
    if (_focused == _node.hasFocus) return;
    setState(() => _focused = _node.hasFocus);
    // Auto-advance while the user is reading a slide would move the target out
    // from under the OK press.
    if (_focused) {
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        // Not handled at the first slide: falling through lets the shell's
        // handler open the navigation rail, which is what a left press at the
        // left edge of the screen should do.
        if (_index == 0) return KeyEventResult.ignored;
        _step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (widget.onEscapeUp == null) return KeyEventResult.ignored;
        widget.onEscapeUp!();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() {
    final items = _items;
    if (items.isEmpty) return;
    final media = items[_index % items.length];
    context.push(
      '/details/${media.type.id}?tag=${widget.tagPrefix}-${media.id}',
      extra: media,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = size.height * ShonenX.heroHeightFraction;
    final insets = TvMetrics.ofSize(size);
    final items = _items;

    final media = items.isEmpty ? null : items[_index % items.length];

    return SizedBox(
      height: height,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onFocusChange: (_) {},
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _open();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: _open,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Backdrop(media: media),
                Positioned(
                  left: ShonenX.contentPadH,
                  right: ShonenX.contentPadH,
                  top: insets.top + 24,
                  bottom: 24,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _Title(media: media)),
                      const SizedBox(width: 40),
                      _Poster(
                        media: media,
                        focused: _focused,
                        tagPrefix: widget.tagPrefix,
                      ),
                    ],
                  ),
                ),
              ],
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
          child: (url == null || url.isEmpty)
              ? Container(key: const ValueKey('empty'), color: cs.surface)
              : CachedNetworkImage(
                  key: ValueKey(url),
                  imageUrl: url,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  placeholder: (_, __) => Container(color: cs.surface),
                  errorWidget: (_, __, ___) => Container(color: cs.surface),
                ),
        ),
        // Two scrims: one so the title stays legible over bright artwork, one
        // so the poster row below reads as part of the same surface rather
        // than a hard cut.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                cs.surface,
                cs.surface.withValues(alpha: 0.85),
                cs.surface.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.35, 0.75],
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
                cs.surface.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.45],
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  final UnifiedMedia? media;

  const _Title({required this.media});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (media == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        media!.title.availableTitle,
        key: ValueKey(media!.id),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
          height: 1.1,
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final UnifiedMedia? media;
  final bool focused;
  final String tagPrefix;

  const _Poster({
    required this.media,
    required this.focused,
    required this.tagPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ShonenX.posterRadius);
    final url = media?.cover ?? media?.banner;

    // The hero is too large to ring as a whole -- an outline round the entire
    // top of the screen reads as a rendering fault, not as focus. The poster
    // carries the focus state instead.
    return AnimatedScale(
      scale: focused ? 1.04 : 1.0,
      duration: TvFocus.animation,
      curve: TvFocus.curve,
      child: AnimatedContainer(
        duration: TvFocus.animation,
        curve: TvFocus.curve,
        width: ShonenX.heroPosterWidth,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: focused ? ShonenX.ringColor : Colors.transparent,
            width: TvFocus.ringWidth,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: radius,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: (url == null || url.isEmpty)
                  ? Container(key: const ValueKey('empty'), color: cs.surfaceContainer)
                  : CachedNetworkImage(
                      key: ValueKey(url),
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
      ),
    );
  }
}
