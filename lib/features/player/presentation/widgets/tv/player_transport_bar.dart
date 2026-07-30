import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/features/player/domain/aniskip_prefs.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/presentation/widgets/progress_bar.dart';
import 'package:shonenx/features/player/providers/aniskip_prefs_provider.dart';
import 'package:shonenx/features/player/providers/aniskip_provider.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';

String formatPlaybackTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = two(d.inMinutes.remainder(60));
  final seconds = two(d.inSeconds.remainder(60));
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}

/// Seek bar and transport controls at the foot of the player.
class PlayerTransportBar extends ConsumerStatefulWidget {
  final bool visible;
  final VideoEngine engine;
  final PlayerController controller;
  final AniSkipArgs? aniskipArgs;
  final FocusNode playPauseFocus;

  /// Any interaction restarts the auto-hide countdown.
  final VoidCallback onInteraction;

  const PlayerTransportBar({
    super.key,
    required this.visible,
    required this.engine,
    required this.controller,
    required this.aniskipArgs,
    required this.playPauseFocus,
    required this.onInteraction,
  });

  @override
  ConsumerState<PlayerTransportBar> createState() =>
      _PlayerTransportBarState();
}

class _PlayerTransportBarState extends ConsumerState<PlayerTransportBar> {
  bool _hasTriggeredAutoNext = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = TvMetrics.ofSize(MediaQuery.sizeOf(context));
    final aniSkips = ref.watch(aniSkipProvider(widget.aniskipArgs));

    ref.listen(videoEngineStateProvider.select((s) => s.position), (_, current) {
      if (current.inSeconds > 0) {
        widget.controller.setupAutoSkipListener(widget.aniskipArgs);
      }
    });

    return AnimatedPositioned(
      duration: Durations.medium2,
      curve: Curves.fastEaseInToSlowEaseOut,
      bottom: widget.visible ? 0 : -260,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: Durations.short4,
        opacity: widget.visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              insets.left,
              48,
              insets.right,
              insets.bottom + 16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black26, Colors.black],
              ),
            ),
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SkipAction(
                      engine: widget.engine,
                      controller: widget.controller,
                      aniSkips: aniSkips.value ?? const [],
                      hasTriggeredAutoNext: _hasTriggeredAutoNext,
                      onAutoNextTriggered: () =>
                          _hasTriggeredAutoNext = true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SeekRow(
                    engine: widget.engine,
                    aniSkips: aniSkips.value ?? const [],
                    onInteraction: widget.onInteraction,
                  ),
                  const SizedBox(height: 8),
                  _ControlRow(
                    engine: widget.engine,
                    controller: widget.controller,
                    playPauseFocus: widget.playPauseFocus,
                    onInteraction: widget.onInteraction,
                    theme: theme,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The seek bar is a focus stop of its own so left/right can scrub.
///
/// Presses accumulate into a pending position and commit once the user stops,
/// rather than issuing a seek per press: holding the key on a remote produces
/// a fast repeat, and seeking on every one of those makes the decoder thrash.
class _SeekRow extends ConsumerStatefulWidget {
  final VideoEngine engine;
  final List<AniSkipStamp> aniSkips;
  final VoidCallback onInteraction;

  const _SeekRow({
    required this.engine,
    required this.aniSkips,
    required this.onInteraction,
  });

  @override
  ConsumerState<_SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends ConsumerState<_SeekRow> {
  static const _step = Duration(seconds: 10);
  static const _commitAfter = Duration(milliseconds: 400);

  late final FocusNode _node = FocusNode(
    debugLabel: 'seekBar',
    onKeyEvent: _handleKey,
  );

  Duration? _pending;
  Timer? _commitTimer;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted && _focused != _node.hasFocus) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => _step,
      LogicalKeyboardKey.arrowLeft => -_step,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;

    widget.onInteraction();
    final duration = ref.read(videoEngineStateProvider).duration;
    final base = _pending ?? ref.read(videoEngineStateProvider).position;
    final next = base + delta;

    setState(() {
      _pending = next < Duration.zero
          ? Duration.zero
          : (next > duration ? duration : next);
    });

    _commitTimer?.cancel();
    _commitTimer = Timer(_commitAfter, () async {
      final target = _pending;
      if (target == null) return;
      await widget.engine.seekTo(target);
      if (mounted) setState(() => _pending = null);
    });

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final position = ref.watch(
      videoEngineStateProvider.select((s) => s.position),
    );
    final duration = ref.watch(
      videoEngineStateProvider.select((s) => s.duration),
    );
    final buffer = ref.watch(videoEngineStateProvider.select((s) => s.buffer));

    final shown = _pending ?? position;
    final timeStyle = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white70,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(formatPlaybackTime(shown), style: timeStyle),
        ),
        Expanded(
          child: Focus(
            focusNode: _node,
            child: SizedBox(
              height: 40,
              child: CustomPaint(
                size: const Size(double.infinity, 40),
                painter: ProgressBarPainter(
                  skipStamps: widget.aniSkips,
                  totalDuration: duration.inMilliseconds / 1000.0,
                  progress: shown.inMilliseconds / 1000.0,
                  buffer: buffer.inMilliseconds / 1000.0,
                  barHeight: _focused
                      ? ShonenX.seekTrackHeight + 2
                      : ShonenX.seekTrackHeight,
                  thumbWidth: _focused
                      ? ShonenX.seekThumbRadiusFocused * 2
                      : ShonenX.seekThumbRadius * 2,
                  thumbHeight: _focused
                      ? ShonenX.seekThumbRadiusFocused * 2
                      : ShonenX.seekThumbRadius * 2,
                  thumbRadius: Radius.circular(
                    _focused
                        ? ShonenX.seekThumbRadiusFocused
                        : ShonenX.seekThumbRadius,
                  ),
                  // Red while scrubbing so it is obvious the bar has focus and
                  // that the position shown is not where playback is yet.
                  thumbColor: _focused ? cs.primary : Colors.white,
                  progressColor: Colors.white,
                  bufferColor: Colors.white38,
                  baseColor: Colors.white24,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 110,
          child: Text(
            formatPlaybackTime(duration),
            style: timeStyle,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _ControlRow extends ConsumerWidget {
  final VideoEngine engine;
  final PlayerController controller;
  final FocusNode playPauseFocus;
  final VoidCallback onInteraction;
  final ThemeData theme;

  const _ControlRow({
    required this.engine,
    required this.controller,
    required this.playPauseFocus,
    required this.onInteraction,
    required this.theme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(
      videoEngineStateProvider.select((s) => s.isPlaying),
    );
    final skipDuration = ref.watch(
      playerPrefsProvider.select((p) => p.skipDuration),
    );

    return Row(
      children: [
        _TransportButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: isPlaying ? 'Pause' : 'Play',
          focusNode: playPauseFocus,
          onPressed: () {
            onInteraction();
            isPlaying ? engine.pause() : engine.play();
          },
        ),
        const SizedBox(width: ShonenX.transportGap),
        _TransportButton(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          onPressed: () {
            onInteraction();
            engine.seekRelative(const Duration(seconds: -10));
          },
        ),
        const SizedBox(width: ShonenX.transportGap),
        _TransportButton(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          onPressed: () {
            onInteraction();
            engine.seekRelative(const Duration(seconds: 10));
          },
        ),
        const Spacer(),
        if (controller.hasNextEpisode)
          _TransportButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next episode',
            label: 'Next Episode',
            onPressed: () {
              onInteraction();
              controller.skipEpisode();
            },
          )
        else
          _TransportButton(
            icon: Icons.fast_forward_rounded,
            tooltip: 'Skip forward',
            label: '+${skipDuration}s',
            onPressed: () {
              onInteraction();
              engine.seekRelative(Duration(seconds: skipDuration));
            },
          ),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TvFocusable(
      onTap: onPressed,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(8),
      scaleOnFocus: false,
      // See PlayerTopBar: over video, tinting beats ringing.
      ringColor: Colors.transparent,
      builder: (context, isFocused) {
        final color = isFocused ? theme.colorScheme.primary : Colors.white;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) ...[
                Text(
                  label!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Icon(
                icon,
                size: ShonenX.transportIconSize,
                semanticLabel: tooltip,
                color: color,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Skip Opening / Skip Ending while inside an AniSkip stamp, and the auto-next
/// countdown as the episode runs out.
class _SkipAction extends ConsumerWidget {
  final VideoEngine engine;
  final PlayerController controller;
  final List<AniSkipStamp> aniSkips;
  final bool hasTriggeredAutoNext;
  final VoidCallback onAutoNextTriggered;

  const _SkipAction({
    required this.engine,
    required this.controller,
    required this.aniSkips,
    required this.hasTriggeredAutoNext,
    required this.onAutoNextTriggered,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      videoEngineStateProvider.select((s) => s.position),
    );
    final duration = ref.watch(
      videoEngineStateProvider.select((s) => s.duration),
    );
    final skipPrefs = ref.watch(aniskipPrefsProvider);
    final playerPrefs = ref.watch(playerPrefsProvider);

    final seconds = position.inSeconds;
    final currentSkip = aniSkips
        .cast<AniSkipStamp?>()
        .firstWhere(
          (s) =>
              s != null && seconds >= s.startTime && seconds < s.endTime,
          orElse: () => null,
        );

    if (currentSkip != null &&
        skipPrefs.mode(currentSkip.type) != SkipMode.off) {
      final label = switch (currentSkip.type) {
        SkipType.opening || SkipType.mixedOpening => 'Skip Opening',
        SkipType.ending || SkipType.mixedEnding => 'Skip Ending',
        SkipType.recap => 'Skip Recap',
      };
      return TvButton(
        label: label,
        icon: Icons.skip_next_rounded,
        height: 52,
        variant: TvButtonVariant.filledWhite,
        onPressed: () =>
            engine.seekTo(Duration(seconds: currentSkip.endTime.ceil())),
      );
    }

    final remaining = duration.inSeconds - position.inSeconds;
    final isNearEnd =
        controller.hasNextEpisode &&
        duration.inSeconds > 0 &&
        (remaining <= playerPrefs.nextEpisodeThreshold ||
            position.inSeconds >= duration.inSeconds);

    if (isNearEnd && playerPrefs.autoNext && !hasTriggeredAutoNext) {
      final elapsed = playerPrefs.nextEpisodeThreshold - remaining;
      final progress = playerPrefs.nextEpisodeThreshold > 0
          ? (elapsed / playerPrefs.nextEpisodeThreshold).clamp(0.0, 1.0)
          : 1.0;
      if (progress >= 1.0 || remaining <= 0) {
        onAutoNextTriggered();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.skipEpisode(),
        );
      }
    }

    return const SizedBox(height: 52);
  }
}
