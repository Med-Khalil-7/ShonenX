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
import 'package:shonenx/features/player/presentation/widgets/tv/seek_preview_card.dart';
import 'package:shonenx/features/player/providers/aniskip_provider.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/player/providers/scrub_provider.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';

/// How far through the auto-next countdown we are, or null when it has not
/// started. Drawn as a ring on the Next Episode button.
final _autoNextProgressProvider = Provider.autoDispose<double?>((ref) {
  final prefs = ref.watch(playerPrefsProvider);
  if (!prefs.autoNext || !prefs.showAutoNextCountdown) return null;

  final position = ref.watch(
    videoEngineStateProvider.select((s) => s.position),
  );
  final duration = ref.watch(
    videoEngineStateProvider.select((s) => s.duration),
  );
  if (duration.inSeconds <= 0) return null;

  final remaining = duration.inSeconds - position.inSeconds;
  if (remaining > prefs.nextEpisodeThreshold) return null;

  final threshold = prefs.nextEpisodeThreshold;
  if (threshold <= 0) return 1.0;
  return ((threshold - remaining) / threshold).clamp(0.0, 1.0);
});

String formatPlaybackTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = two(d.inMinutes.remainder(60));
  final seconds = two(d.inSeconds.remainder(60));
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}

/// Seek bar and transport controls at the foot of the player.
/// Lets the screen drive the seek bar from outside the overlay.
///
/// With the controls hidden, left and right go straight to scrubbing rather
/// than waking the buttons -- the way every TV player behaves. That press
/// arrives at the screen's own key handler, before the bar is even mounted,
/// so the bar publishes a way in rather than the screen reaching into it.
class SeekBarHandle {
  void Function(bool forward)? _onStep;

  /// Focuses the bar and applies one step, as if the key had landed on it.
  void step({required bool forward}) => _onStep?.call(forward);
}

class PlayerTransportBar extends ConsumerStatefulWidget {
  final bool visible;
  final VideoEngine engine;
  final PlayerController controller;
  final AniSkipArgs? aniskipArgs;
  final FocusNode playPauseFocus;

  /// Filled in by the seek bar once it mounts.
  final SeekBarHandle? seekHandle;

  /// Any interaction restarts the auto-hide countdown.
  final VoidCallback onInteraction;

  /// A committed scrub takes the overlay down with it: the user has said where
  /// they want to be, and what they want next is the picture, not the bar.
  final VoidCallback onSeekCommitted;

  const PlayerTransportBar({
    super.key,
    required this.visible,
    required this.engine,
    required this.controller,
    required this.aniskipArgs,
    required this.playPauseFocus,
    required this.onInteraction,
    required this.onSeekCommitted,
    this.seekHandle,
  });

  @override
  ConsumerState<PlayerTransportBar> createState() =>
      _PlayerTransportBarState();
}

class _PlayerTransportBarState extends ConsumerState<PlayerTransportBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ShonenXMetrics.of(context);
    final insets = TvMetrics.ofSize(MediaQuery.sizeOf(context));
    final aniSkips = ref.watch(aniSkipProvider(widget.aniskipArgs));

    // AniSkip needs the episode length, which is zero until playback starts,
    // so the args change once early on. Re-register then -- and only then.
    ref.listen(videoEngineStateProvider.select((s) => s.duration), (prev, next) {
      if (prev != next && next.inSeconds > 0) {
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
              m.transportIcon * 1.6,
              insets.right,
              insets.bottom + m.transportIcon * 0.5,
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
                  _SeekRow(
                    engine: widget.engine,
                    aniSkips: aniSkips.value ?? const [],
                    onInteraction: widget.onInteraction,
                    onCommitted: widget.onSeekCommitted,
                    handle: widget.seekHandle,
                  ),
                  SizedBox(height: m.transportIcon * 0.25),
                  // Inset to line the controls up with the seek track rather
                  // than the screen edge: the track is set in by the two time
                  // readouts, so without this play/pause and Next Episode
                  // hang off past both ends of the bar they belong to.
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: m.playerLabel * 4.5),
                    child: _ControlRow(
                      engine: widget.engine,
                      controller: widget.controller,
                      playPauseFocus: widget.playPauseFocus,
                      onInteraction: widget.onInteraction,
                      theme: theme,
                      metrics: m,
                    ),
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
/// Scrubbing does not move playback. Left and right walk a pending position
/// and the preview card follows it; the video itself pauses and holds the
/// frame it was on. Only OK commits: that is the one moment a seek is issued
/// and the one moment the player has to re-buffer.
///
/// The alternative -- seeking as you go, or committing on a timer once you
/// stop -- makes every intermediate position a real seek. On a remote, where
/// crossing an episode takes a dozen presses, that is a dozen re-buffers to
/// reach a place the user was only passing through.
class _SeekRow extends ConsumerStatefulWidget {
  final VideoEngine engine;
  final List<AniSkipStamp> aniSkips;
  final VoidCallback onInteraction;

  /// Called once the scrub is committed, so the overlay can fade away and
  /// leave the video it just seeked to.
  final VoidCallback onCommitted;

  final SeekBarHandle? handle;

  const _SeekRow({
    required this.engine,
    required this.aniSkips,
    required this.onInteraction,
    required this.onCommitted,
    required this.handle,
  });

  @override
  ConsumerState<_SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends ConsumerState<_SeekRow> {
  /// How long the thumb has to sit still before the player is moved to it.
  ///
  /// Every one of these is a real seek, and on an HLS stream that means
  /// fetching a segment. Firing one per keypress turns a walk down the
  /// timeline into a queue of fetches the box works through long after the
  /// user has stopped pressing, which is what makes a weak device feel like it
  /// is skipping. Half a second is past the rate anyone presses deliberately,
  /// so a run of presses costs one seek at the end of it rather than one each.
  static const _previewAfter = Duration(milliseconds: 550);

  // Not const: LogicalKeyboardKey overrides ==, which a const set forbids.
  static final _confirmKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
  };

  static final _cancelKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
    LogicalKeyboardKey.gameButtonB,
  };

  late final FocusNode _node = FocusNode(
    debugLabel: 'seekBar',
    onKeyEvent: _handleKey,
  );

  Duration? _pending;

  /// Where playback actually is, and where it was before the scrub started.
  ///
  /// [_shownAt] is the position the picture on screen belongs to -- committing
  /// is then a no-op, which is the whole point: you cannot land somewhere
  /// other than the frame you were looking at. [_resumeAt] is what BACK
  /// restores.
  Duration? _shownAt;
  Duration? _resumeAt;

  /// One preview seek at a time. A second issued while the first is in flight
  /// would queue up behind it and play the scrub back in slow motion.
  bool _seeking = false;

  /// Whether playback was running when the scrub began, so committing or
  /// abandoning it can put things back the way they were.
  bool _wasPlaying = false;

  Timer? _previewTimer;
  bool _focused = false;

  bool get _scrubbing => _pending != null;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
    widget.handle?._onStep = _stepFromOutside;
  }

  /// A left/right press that arrived while the controls were down.
  ///
  /// Takes focus first: the scrub is now the thing the remote is driving, and
  /// the next press has to reach this node rather than the play button the
  /// overlay would otherwise have focused.
  void _stepFromOutside(bool forward) {
    if (!mounted) return;
    if (!_node.hasFocus) _node.requestFocus();
    _step(forward: forward);
  }

  void _onFocusChanged() {
    if (!mounted || _focused == _node.hasFocus) return;
    setState(() => _focused = _node.hasFocus);

    if (_focused) return;

    // Stepping off the bar abandons the scrub rather than committing it: the
    // user moved to another control, which is not an instruction to seek.
    _cancelScrub();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    // An episode change can take the bar away mid-scrub. Clear the flag or the
    // scrim stays over a player that has nothing left to dim for.
    if (_pending != null) {
      try {
        ref.read(scrubTargetProvider.notifier).update(null);
      } catch (_) {}
    }
    _node.dispose();
    super.dispose();
  }

  /// Freezes playback for the duration of the scrub.
  ///
  /// Pausing is what makes the preview readable: with the video still running
  /// underneath, the frame behind the card keeps changing and there are two
  /// moving pictures competing for attention.
  void _beginScrub() {
    if (_scrubbing) return;
    final state = ref.read(videoEngineStateProvider);
    _wasPlaying = state.isPlaying;
    _resumeAt = state.position;
    _shownAt = state.position;
    if (_wasPlaying) {
      try {
        widget.engine.pause();
      } catch (_) {}
    }
  }

  /// Moves the paused player onto the thumb, so the picture behind the bar is
  /// the preview.
  ///
  /// This replaces a second, hidden decoder that opened the same episode at a
  /// lower rendition and screenshotted it. That could never be trusted -- it
  /// seeks a different demuxer over a different variant playlist, and the
  /// frame it returned was routinely from another shot -- and on a 1GB box it
  /// meant two decoders alive at once, which is what exhausted MediaCodec and
  /// killed playback. Seeking the player that is already open cannot show the
  /// wrong frame, because it is the frame.
  Future<void> _showPending() async {
    if (_seeking || !mounted) return;
    final target = _pending;
    if (target == null || target == _shownAt) return;

    _seeking = true;
    try {
      await widget.engine.seekTo(target);
      if (mounted) setState(() => _shownAt = target);
    } catch (_) {
      // Leave _shownAt alone: the picture is still whatever it was, and
      // committing has to seek for real.
    } finally {
      _seeking = false;
      // The thumb kept moving while that one was in flight. Go again rather
      // than waiting for another keypress to notice.
      if (mounted && _scrubbing && _pending != _shownAt) {
        unawaited(_showPending());
      }
    }
  }

  /// Ends the scrub and resumes. Usually there is nothing left to seek.
  void _commitScrub() {
    final target = _pending;
    if (target == null) return;

    _previewTimer?.cancel();
    final settled = target == _shownAt;
    setState(() {
      _pending = null;
      _resumeAt = null;
    });
    ref.read(scrubTargetProvider.notifier).update(null);

    () async {
      try {
        // Only if the last nudge never got its preview seek -- OK pressed
        // inside the debounce window. Otherwise the player is already showing
        // this exact frame and seeking again would re-buffer for nothing.
        if (!settled) await widget.engine.seekTo(target);
        if (_wasPlaying) await widget.engine.play();
      } catch (_) {}
    }();

    widget.onCommitted();
  }

  /// Drops the scrub, putting playback back where it started.
  ///
  /// The preview moved the real player, so abandoning has to undo that --
  /// otherwise backing out of a scrub leaves you wherever you happened to
  /// browse to, which is the one thing BACK must not do.
  void _cancelScrub() {
    if (!_scrubbing) return;

    _previewTimer?.cancel();
    final restore = _resumeAt;
    final moved = restore != null && _shownAt != restore;
    setState(() {
      _pending = null;
      _resumeAt = null;
    });
    ref.read(scrubTargetProvider.notifier).update(null);

    () async {
      try {
        if (moved) await widget.engine.seekTo(restore);
        if (_wasPlaying) await widget.engine.play();
      } catch (_) {}
    }();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // OK lands the scrub. Handled here rather than through an ActivateIntent
    // so the press never reaches the default binding while a scrub is open --
    // the same button would otherwise toggle play/pause underneath it.
    if (_confirmKeys.contains(event.logicalKey)) {
      if (!_scrubbing) return KeyEventResult.ignored;
      widget.onInteraction();
      if (event is KeyDownEvent) _commitScrub();
      return KeyEventResult.handled;
    }

    // BACK abandons it, so a scrub started by accident costs nothing.
    if (_cancelKeys.contains(event.logicalKey)) {
      if (!_scrubbing) return KeyEventResult.ignored;
      widget.onInteraction();
      if (event is KeyDownEvent) _cancelScrub();
      return KeyEventResult.handled;
    }

    final forward = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => true,
      LogicalKeyboardKey.arrowLeft => false,
      _ => null,
    };
    if (forward == null) return KeyEventResult.ignored;

    _step(forward: forward);
    return KeyEventResult.handled;
  }

  /// Moves the thumb one step and schedules the picture to catch up.
  void _step({required bool forward}) {
    final seconds = ref.read(playerPrefsProvider).seekStepSeconds;
    final delta = Duration(seconds: forward ? seconds : -seconds);

    widget.onInteraction();
    _beginScrub();

    final duration = ref.read(videoEngineStateProvider).duration;
    final base = _pending ?? ref.read(videoEngineStateProvider).position;
    final next = base + delta;
    final target = next < Duration.zero
        ? Duration.zero
        : (next > duration ? duration : next);

    setState(() => _pending = target);
    ref.read(scrubTargetProvider.notifier).update(target);

    _previewTimer?.cancel();
    _previewTimer = Timer(_previewAfter, () {
      if (mounted) unawaited(_showPending());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);
    final position = ref.watch(
      videoEngineStateProvider.select((s) => s.position),
    );
    final duration = ref.watch(
      videoEngineStateProvider.select((s) => s.duration),
    );
    final buffer = ref.watch(videoEngineStateProvider.select((s) => s.buffer));

    final shown = _pending ?? position;
    final timeStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: m.playerLabel,
      color: Colors.white70,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Shown on focus, not just while moving: landing on the bar should
    // already tell you where you are.
    final showPreview = _focused;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPreview)
          Padding(
            // Line the card's track up with the bar itself, which is inset by
            // the two time readouts either side of it.
            padding: EdgeInsets.symmetric(horizontal: m.playerLabel * 4.5),
            child: SeekPreviewCard(
              label: formatPlaybackTime(shown),
              // The engine's own output, not a copy of it.
              videoView: widget.engine.buildVideoView(),
              // Nothing has moved yet on the first frame after focus lands,
              // so say what the bar does before saying how to leave it.
              fraction: duration.inMilliseconds == 0
                  ? 0
                  : shown.inMilliseconds / duration.inMilliseconds,
            ),
          ),
        Row(
          children: [
            SizedBox(
              width: m.playerLabel * 4.5,
              child: Text(formatPlaybackTime(shown), style: timeStyle),
            ),
            Expanded(
              child: Focus(
                focusNode: _node,
                child: SizedBox(
                  height: m.transportIcon,
                  child: CustomPaint(
                    size: Size(double.infinity, m.transportIcon),
                    painter: ProgressBarPainter(
                      skipStamps: widget.aniSkips,
                      totalDuration: duration.inMilliseconds / 1000.0,
                      progress: shown.inMilliseconds / 1000.0,
                      buffer: buffer.inMilliseconds / 1000.0,
                      barHeight: _focused ? m.seekTrack * 1.6 : m.seekTrack,
                      thumbWidth: _focused
                          ? m.seekThumb * 2.6
                          : m.seekThumb * 2,
                      thumbHeight: _focused
                          ? m.seekThumb * 2.6
                          : m.seekThumb * 2,
                      thumbRadius: Radius.circular(
                        _focused ? m.seekThumb * 1.3 : m.seekThumb,
                      ),
                      // Red while scrubbing so it is obvious the bar has focus
                      // and that the position shown is not where playback is
                      // yet.
                      thumbColor: _focused ? cs.primary : Colors.white,
                      // The played track turns red with the thumb. Colouring
                      // only the dot left a red marker sliding along a white
                      // line, so the bar as a whole never looked focused.
                      progressColor: _focused ? cs.primary : Colors.white,
                      bufferColor: Colors.white38,
                      baseColor: Colors.white24,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: m.playerLabel * 4.5,
              child: Text(
                formatPlaybackTime(duration),
                style: timeStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
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
  final ShonenXMetrics metrics;

  const _ControlRow({
    required this.engine,
    required this.controller,
    required this.playPauseFocus,
    required this.onInteraction,
    required this.theme,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(
      videoEngineStateProvider.select((s) => s.isPlaying),
    );
    final prefs = ref.watch(playerPrefsProvider);

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
        SizedBox(width: metrics.transportGap),
        _TransportButton(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          onPressed: () {
            onInteraction();
            engine.seekRelative(const Duration(seconds: -10));
          },
        ),
        SizedBox(width: metrics.transportGap),
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
            // The fraction was computed and thrown away before; drawing it
            // is what makes auto-next something you can see coming.
            progress: ref.watch(_autoNextProgressProvider),
            onPressed: () {
              onInteraction();
              controller.skipEpisode();
            },
          )
        else if (prefs.showSkipButton)
          _TransportButton(
            icon: Icons.fast_forward_rounded,
            tooltip: 'Skip forward',
            label: '+${prefs.skipDuration}s',
            onPressed: () {
              onInteraction();
              engine.seekRelative(Duration(seconds: prefs.skipDuration));
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

  /// 0..1 countdown drawn as a ring around the icon, or null for none.
  final double? progress;

  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.focusNode,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ShonenXMetrics.of(context);

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
          padding: EdgeInsets.all(m.transportIcon * 0.2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) ...[
                Text(
                  label!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: m.playerLabel,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: m.playerLabel * 0.6),
              ],
              SizedBox(
                width: m.transportIcon,
                height: m.transportIcon,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (progress != null)
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.25),
                        ),
                      ),
                    Icon(
                      icon,
                      size: progress != null
                          ? m.transportIcon * 0.6
                          : m.transportIcon,
                      semanticLabel: tooltip,
                      color: color,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
