import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/shared/providers/ui_prefs_provider.dart';
import 'package:shonenx/shared/widgets/app_network_image.dart';
import 'package:shonenx/features/discovery/presentation/widgets/continue/continue_media_mixin.dart';
import 'package:shonenx/features/history/domain/models/watch_history_entry.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/features/discovery/providers/episodes_provider.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/history/providers/continue_watching_resolver.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/source_engine/source_registry.dart';
import 'continue_card_layout.dart';

class ContinueWatchingItem extends ConsumerStatefulWidget {
  final WatchHistoryEntry entry;
  final double progress;
  final ContinueWatchingStyle style;

  /// Multiplier on the style's own size, so a row can bring the card down to
  /// the height of whatever sits beside it. 1 leaves the style untouched.
  final double scale;

  const ContinueWatchingItem({
    super.key,
    required this.entry,
    required this.progress,
    required this.style,
    this.scale = 1,
  });

  @override
  ConsumerState<ContinueWatchingItem> createState() =>
      _ContinueWatchingItemState();
}

class _ContinueWatchingItemState extends ConsumerState<ContinueWatchingItem>
    with ContinueMediaMixin {
  bool _isFocused = false;
  bool _isHovered = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        _resumeEpisode();
        return null;
      },
    ),
  };

  /// Resolves the source, then opens the player on it.
  ///
  /// The resolve happens here rather than inside the player. It is a search
  /// against the source and it can fail -- wrong match, source down, no
  /// episodes -- and the place to say so is the screen the user is still
  /// looking at, where handleResumeMedia can offer to pick another source.
  /// Done inside the player there is nothing behind the failure but a black
  /// screen, and nowhere to go back to.
  ///
  /// It goes to the player directly, not through the detail screen with an
  /// autoplay flag: this card already says which episode and how far in.
  Future<void> _resumeEpisode() async {
    await handleResumeMedia(
      resolveAndPlay: () async {
        // Same reason as MediaActions.play: the resolver walks the preference
        // -> match -> episodes chain, and it needs a live subscriber for the
        // length of the walk or an upstream change restarts it under us.
        final keepAlive = ref.listenManual(
          episodesListProvider(
            MediaArgs(mediaTitle: widget.entry.animeTitle, type: MediaType.ANIME),
          ),
          (_, __) {},
        );
        try {
          final result = await ref
              .read(continueWatchingResolverProvider)
              .resolve(widget.entry);
          if (!mounted) return;
          context.push('/player', extra: result.mode);
        } finally {
          keepAlive.close();
        }
      },
      mediaType: MediaType.ANIME,
      mediaTitle: widget.entry.animeTitle,
      availableSourcesProvider: availableAnimeSourcesProvider,
    );
  }

  void _showContextMenu(Offset position) {
    showItemContextMenu(
      position: position,
      mediaType: MediaType.ANIME,
      mediaTitle: widget.entry.animeTitle,
      onViewDetails: () {
        context.push(
          '/details/anime',
          extra: UnifiedMedia(
            id: widget.entry.animeId,
            title: MediaTitle(english: widget.entry.animeTitle),
            type: MediaType.ANIME,
            cover: widget.entry.cover ?? widget.entry.thumbnailUrl,
            banner: widget.entry.banner,
          ),
        );
      },
      onRemoveHistory: () =>
          ref.read(watchHistoryRepositoryProvider).deleteEntry(widget.entry.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = _isFocused || _isHovered;

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _isFocused = v),
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _resumeEpisode();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        onSecondaryTapDown: (details) {
          _showContextMenu(details.globalPosition);
        },
        onLongPressStart: (details) {
          _showContextMenu(details.globalPosition);
        },
        child: _buildStyledContent(widget.style, theme, isActive),
      ),
    );
  }

  Widget _buildStyledContent(
    ContinueWatchingStyle style,
    ThemeData theme,
    bool isActive,
  ) {
    final epNum = widget.entry.episodeNumber;
    final cleanNum = epNum.toString().contains('.0') ? epNum.toInt() : epNum;
    final epTitle = widget.entry.episodeTitle;
    final subtitleText = 'EP $cleanNum${epTitle != null ? ' • $epTitle' : ''}';

    final isWideMode = ref.watch(
      uiPrefsProvider.select((s) => s.isContinueWatchingWide(style.name)),
    );
    final baseLayout = style.getBaseLayout(
      isContinueWatching: true,
      isWideMode: isWideMode,
    );
    final layout = style.getLayout(
      isContinueWatching: true,
      isWideMode: isWideMode,
    );

    final card = ContinueCardLayout(
      variant: style.name,
      width: baseLayout.width,
      height: baseLayout.height,
      isActive: isActive,
      isLoading: isLoading,
      isWideMode: isWideMode,
      title: widget.entry.animeTitle,
      subtitle: style == ContinueWatchingStyle.cinematic
          ? (widget.entry.episodeTitle ?? 'Continue watching')
          : subtitleText,
      progress: widget.progress,
      progressText: _formatTimeRemaining(),
      badgeText: 'EP ${widget.entry.episodeNumber.toInt()}',
      thumbnailBuilder: (context, cs) =>
          _buildThumbnail(widget.entry.thumbnailUrl, cs),
      fallbackIcon: Icons.play_circle_outline_rounded,
      badgeType: 'WATCHING',
    );

    final currentTextScale = MediaQuery.of(context).textScaler.scale(1.0);
    final scaleFactor = (layout.width * widget.scale) / baseLayout.width;
    final normalizedCard = MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(currentTextScale / scaleFactor)),
      child: card,
    );

    final width = layout.width * widget.scale;
    final height = layout.height * widget.scale;

    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: baseLayout.width,
          height: baseLayout.height,
          child: normalizedCard,
        ),
      ),
    );
  }

  String _formatTimeRemaining() {
    final remainingMs =
        widget.entry.durationInMilliseconds -
        widget.entry.positionInMilliseconds;
    if (remainingMs <= 0) return 'Watched';

    final remainingMins = (remainingMs / 60000).ceil();
    return '$remainingMins min left';
  }

  /// Decoded frames, keyed by the base64 they came from.
  ///
  /// `base64Decode` used to run inside `build`, which minted a fresh list every
  /// frame. `MemoryImage` keys its cache entry on the list's *identity*, so no
  /// two builds ever hit the cache and a full-resolution screenshot was decoded
  /// from scratch on every rebuild of the card.
  static final _frames = <String, Uint8List>{};
  static const _maxFrames = 12;

  static Uint8List _frameBytes(String base64) {
    final hit = _frames[base64];
    if (hit != null) return hit;
    final bytes = base64Decode(base64);
    if (_frames.length >= _maxFrames) {
      _frames.remove(_frames.keys.first);
    }
    return _frames[base64] = bytes;
  }

  Widget _buildThumbnail(String? thumbnail, ColorScheme cs) {
    if (thumbnail == null || thumbnail.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.movie_creation_outlined, color: cs.onSurfaceVariant),
      );
    }

    final broken = Container(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.broken_image_rounded, color: cs.onSurfaceVariant),
    );

    try {
      if (thumbnail.startsWith('http')) {
        return AppNetworkImage(url: thumbnail, error: broken);
      }

      // A screenshot straight off the video, so it is frame-sized: 1920x1080
      // is 8 MB decoded for a card a couple of hundred pixels wide.
      return LayoutBuilder(
        builder: (context, constraints) => Image.memory(
          _frameBytes(thumbnail),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: constraints.hasBoundedWidth
              ? AppNetworkImage.decodeBudget(context, constraints.maxWidth)
              : null,
          errorBuilder: (_, __, ___) => broken,
        ),
      );
    } catch (_) {
      return broken;
    }
  }
}
