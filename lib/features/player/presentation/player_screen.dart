import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:shonenx/features/discovery/presentation/episodes_screen.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/presentation/widgets/custom_subtitle_overlay.dart';
import 'package:shonenx/features/player/presentation/widgets/player_keyboard_listener.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_center_indicator.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_audio_panel.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_settings_panel.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_skip_button.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_top_bar.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_transport_bar.dart';
import 'package:shonenx/features/player/providers/aniskip_provider.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/player/providers/scrub_provider.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/video_stream.dart';
import 'package:shonenx/core/utils/extensions.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';
import 'package:shonenx/shared/widgets/tv/tv_confirm_dialog.dart';
import 'package:shonenx/shared/widgets/tv/tv_side_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final PlayerMode mode;

  const PlayerScreen({super.key, required this.mode});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  /// Long enough to cross the overlay with a D-pad. Three seconds was tuned
  /// for a mouse and expires mid-traversal on a remote.
  Duration get _autoHide => Duration(
    seconds: ref.read(playerPrefsProvider).controlsTimeoutSeconds,
  );

  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'playPause');

  /// Way in to the seek bar for presses that land before it is on screen.
  final SeekBarHandle _seekHandle = SeekBarHandle();

  /// The video, so the frame under a scrub can be captured off it.
  final GlobalKey _videoKey = GlobalKey();

  /// A still of the frame the scrub started from.
  ///
  /// Scrubbing moves the one open player -- there is no second decoder any
  /// more -- so without this the whole screen would follow the thumb, which
  /// reads as having already jumped when nothing has been committed. Held over
  /// the video, it keeps the scene exactly where the user left it until they
  /// decide: OK takes the new position, BACK puts playback back on this frame.
  ui.Image? _frozenFrame;

  bool _showControls = false;
  Timer? _controlsTimer;
  bool _panelOpen = false;
  bool _exitPromptOpen = false;

  /// Remembered so the subtitle toggle can restore what was switched off.
  SubtitleTrack? _lastSubtitle;

  /// The title being played, for the modes that have one.
  ///
  /// Auto mode carries the media but resolves the episode itself, so anything
  /// gated on `is PlayerModeOnline` silently lost the episodes button and the
  /// skip-intro lookup the moment a play button started using it.
  UnifiedMedia? get _mediaOrNull => switch (widget.mode) {
    PlayerModeOnline(:final media) => media,
    PlayerModeAuto(:final media) => media,
    PlayerModeOffline() => null,
  };

  String get _mediaTitle => switch (widget.mode) {
    PlayerModeOnline(:final media) => media.title.availableTitle,
    PlayerModeAuto(:final media) => media.title.availableTitle,
    PlayerModeOffline(:final title) => title ?? 'Local Media',
  };

  AniSkipArgs? _aniSkipArgs(VideoEngine engine) {
    // In auto mode the episode is not known until the controller has resolved
    // it, so read it from state rather than from the route argument.
    final media = _mediaOrNull;
    if (media == null) return null;

    final episode = switch (widget.mode) {
      PlayerModeOnline(:final episode) => episode,
      _ => ref.read(playerControllerProvider).activeEpisode,
    };
    if (episode == null) return null;

    final malId = int.tryParse(media.idMal ?? '');
    if (malId == null) return null;
    return AniSkipArgs(
      idMal: malId,
      episodeNumber: episode.number,
      episodeLength: engine.currentDuration.inSeconds,
    );
  }

  @override
  void initState() {
    super.initState();
    try {
      WakelockPlus.enable();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(playerControllerProvider.notifier);
      controller.initialize(widget.mode);
      // Once, here -- not from the transport bar's build, which re-registered
      // it on every position tick.
      controller.setupAutoSkipListener(
        _aniSkipArgs(ref.read(videoEngineProvider)),
      );
      _wake();
    });
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _controlsTimer?.cancel();
    _frozenFrame?.dispose();
    _playPauseFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Deliberately not disposing the engine here. videoEngineProvider is
    // autoDispose and this screen holds the only watch, so its own
    // ref.onDispose tears the engine down a moment later. Doing it here as
    // well meant two concurrent teardowns of one mpv context.
    super.dispose();
  }

  /// Show the controls, put focus on play/pause, and restart the countdown.
  void _wake({bool focusTransport = true}) {
    _controlsTimer?.cancel();
    if (!_showControls) {
      setState(() => _showControls = true);
      if (focusTransport) {
        // Post-frame: the transport bar is not mounted until this build lands,
        // so its node cannot take focus any earlier.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showControls) _playPauseFocus.requestFocus();
        });
      }
    }
    _controlsTimer = Timer(_autoHide, _hide);
  }

  /// Keeps the controls up without stealing focus from whatever holds it.
  void _keepAwake() {
    if (!_showControls) return;
    _controlsTimer?.cancel();
    _controlsTimer = Timer(_autoHide, _hide);
  }

  /// Grabs the on-screen frame at half resolution and holds it.
  ///
  /// Half because it is a backdrop behind an overlay, and a full 1080p capture
  /// is 8MB of RGBA on a device that has not got it to spare. It is released
  /// the moment the scrub ends.
  Future<void> _freezeFrame() async {
    try {
      final boundary = _videoKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: 0.5);
      // The scrub can end while the capture is in flight, and a still left
      // over from it would sit frozen over live playback.
      if (!mounted || !ref.read(isScrubbingProvider)) {
        image.dispose();
        return;
      }
      setState(() => _frozenFrame = image);
    } catch (_) {
      // No capture: the scene follows the scrub, which is the old behaviour
      // rather than a broken screen.
    }
  }

  void _releaseFrame() {
    final image = _frozenFrame;
    if (image == null) return;
    setState(() => _frozenFrame = null);
    image.dispose();
  }

  void _hide() {
    if (!mounted || !_showControls) return;
    // A panel, the exit prompt or an open scrub all mean the user is
    // mid-decision; hiding the controls under them would drop focus into
    // nothing. Check back rather than returning, or the countdown is lost and
    // the overlay stays up for the rest of the episode.
    if (_panelOpen || _exitPromptOpen || ref.read(isScrubbingProvider)) {
      _controlsTimer = Timer(_autoHide, _hide);
      return;
    }
    setState(() => _showControls = false);
  }

  /// Drops the overlay now, without waiting out the countdown. Used when the
  /// user has just committed a seek and wants to watch the result.
  /// Raises the overlay onto the timeline and takes the press with it.
  ///
  /// Focus goes to the seek bar rather than play/pause, so the press that
  /// started this and every one after it drive the same control.
  void _scrubFromHidden(bool forward) {
    _wake(focusTransport: false);
    // The bar is mounted by this build, not before it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _seekHandle.step(forward: forward);
    });
  }

  void _hideNow() {
    _controlsTimer?.cancel();
    if (mounted && _showControls) setState(() => _showControls = false);
  }

  void _toggleEpisodePanel() {
    final media = _mediaOrNull;
    if (media == null) return;
    if (_panelOpen) {
      Navigator.of(context).pop();
      return;
    }
    _openPanel(
      label: 'Episodes',
      // The episodes screen itself, over the whole player. Not a copy of it:
      // a side panel a third of the screen wide squeezed the grid to four
      // columns, and the list that replaced it lost the range tabs. This is
      // the same widget the route builds, so the two cannot diverge.
      widthFactor: 1.0,
      builder: (sheetContext) => EpisodesScreen(
        media: media,
        onPlay: (episode, _) {
          Navigator.of(sheetContext).pop();
          ref.read(playerControllerProvider.notifier).loadEpisode(episode);
        },
      ),
    );
  }

  void _openSettingsPanel() {
    _openPanel(
      label: 'Settings',
      builder: (_) => PlayerSettingsPanel(
        engine: ref.read(videoEngineProvider),
        controller: ref.read(playerControllerProvider.notifier),
      ),
    );
  }

  void _openAudioPanel() {
    _openPanel(
      label: 'Audio',
      builder: (_) => PlayerAudioPanel(
        controller: ref.read(playerControllerProvider.notifier),
      ),
    );
  }

  /// Flips subtitles without opening anything.
  ///
  /// Turning them back on returns to the last track that was actually chosen,
  /// falling back to the preferred language and then to whatever the source
  /// offers first -- so the toggle is symmetrical rather than "off, then go
  /// hunting in a menu".
  void _toggleSubtitles() {
    final controller = ref.read(playerControllerProvider.notifier);
    final state = ref.read(playerControllerProvider);
    final active = state.activeSubtitle;

    if (active != null && active.url.isNotEmpty) {
      _lastSubtitle = active;
      controller.changeSubtitle(SubtitleTrack.none);
      return;
    }

    final tracks = state.subtitles.where((s) => s.url.isNotEmpty).toList();
    if (tracks.isEmpty) return;

    final preferred = ref.read(playerPrefsProvider).defaultSubtitleLang;
    final restored =
        _lastSubtitle ??
        tracks.firstWhereOrNull(
          (s) => s.language.toLowerCase().contains(preferred.toLowerCase()),
        ) ??
        tracks.first;
    controller.changeSubtitle(restored);
  }

  void _openPanel({
    required String label,
    required WidgetBuilder builder,
    double? widthFactor,
  }) {
    setState(() => _panelOpen = true);
    _controlsTimer?.cancel();
    TvSideSheet.show(
      context: context,
      label: label,
      builder: builder,
      widthFactor: widthFactor,
    ).then((_) {
      if (!mounted) return;
      setState(() => _panelOpen = false);
      // Do not grab focus: it belongs to whichever control opened the panel.
      _wake(focusTransport: false);
    });
  }

  /// BACK unwinds one layer at a time -- open panel, then the overlay, then
  /// the screen. Leaving always asks first: a mis-press on a remote is cheap,
  /// and losing your place is not.
  /// Guards against BACK arriving again while the previous one is still
  /// unwinding. This method awaits a dialog, so without it a held BACK ran a
  /// second pass that popped the player out from under the panel it was in
  /// the middle of closing.
  bool _backInFlight = false;

  Future<void> _handleBack() async {
    if (_backInFlight) return;
    _backInFlight = true;
    try {
      await _handleBackInner();
    } finally {
      _backInFlight = false;
    }
  }

  Future<void> _handleBackInner() async {
    if (_panelOpen) {
      Navigator.of(context).pop();
      return;
    }
    if (_showControls) {
      _controlsTimer?.cancel();
      setState(() => _showControls = false);
      return;
    }
    if (_exitPromptOpen) return;

    setState(() => _exitPromptOpen = true);
    final engine = ref.read(videoEngineProvider);
    final wasPlaying = ref.read(videoEngineStateProvider).isPlaying;
    try {
      engine.pause();
    } catch (_) {}

    final confirmed = await TvConfirmDialog.show(
      context: context,
      message: 'Do you want to close the player?',
    );
    if (!mounted) return;
    setState(() => _exitPromptOpen = false);

    if (confirmed == true) {
      ref.read(playerControllerProvider.notifier).captureExitThumbnail();
      if (mounted) context.pop();
    } else if (wasPlaying) {
      try {
        engine.play();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerControllerProvider);

    ref.listen<bool>(isScrubbingProvider, (_, scrubbing) {
      if (scrubbing) {
        if (_frozenFrame == null) unawaited(_freezeFrame());
        // An open scrub holds the overlay up outright.
        //
        // _hide used to re-arm its own countdown when it found a scrub in
        // progress, which meant the bar could still go on sitting still --
        // and a scrub whose bar has slid off screen is unusable: the picture
        // is frozen and dimmed with nothing to say why. Cancelling the timer
        // is the only state where the overlay is guaranteed to stay.
        _controlsTimer?.cancel();
        if (!_showControls) setState(() => _showControls = true);
      } else {
        _releaseFrame();
        // Back to the ordinary countdown.
        _controlsTimer?.cancel();
        if (_showControls) _controlsTimer = Timer(_autoHide, _hide);
      }
    });
    final controller = ref.read(playerControllerProvider.notifier);
    final engine = ref.watch(videoEngineProvider);
    final activeEpisode = ref.watch(
      playerControllerProvider.select((s) => s.activeEpisode),
    );

    ref.listen(playerControllerProvider.select((s) => s.error), (prev, next) {
      if (next != null && next != prev && mounted) _showPlaybackError(next);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PlayerKeyboardListener(
          engine: engine,
          controller: controller,
          controlsVisible: _showControls,
          onWake: _wake,
          onScrub: _scrubFromHidden,
          onUserInteraction: _keepAwake,
          onToggleEpisodePanel: _toggleEpisodePanel,
          onBack: _handleBack,
          child: Stack(
            children: [
              Center(
                child: Offstage(
                  offstage: playerState.isLoading,
                  child: RepaintBoundary(
                    key: _videoKey,
                    child: engine.buildVideoView(),
                  ),
                ),
              ),
              // Holds the scene still for the length of a scrub. Above the
              // video so the player can move underneath it.
              if (_frozenFrame != null)
                Positioned.fill(
                  child: RawImage(image: _frozenFrame, fit: BoxFit.contain),
                ),
              // Pulls the held frame back so the preview card reads against it
              // instead of competing with it.
              const _ScrubScrim(),
              if (playerState.activeSubtitle != null)
                const CustomSubtitleOverlay(),
              const PlayerCenterIndicator(),
              PlayerTopBar(
                visible: _showControls,
                title: _mediaTitle,
                subtitle: _episodeLabel(activeEpisode),
                onBack: _handleBack,
                onEpisodes: _mediaOrNull != null
                    ? _toggleEpisodePanel
                    : null,
                onAudio: _openAudioPanel,
                onToggleSubtitles: _toggleSubtitles,
                onSettings: _openSettingsPanel,
                subtitlesOn:
                    playerState.activeSubtitle != null &&
                    playerState.activeSubtitle!.url.isNotEmpty,
              ),
              PlayerSkipButton(
                engine: engine,
                aniskipArgs: _aniSkipArgs(engine),
              ),
              PlayerTransportBar(
                visible: _showControls,
                engine: engine,
                controller: controller,
                aniskipArgs: _aniSkipArgs(engine),
                playPauseFocus: _playPauseFocus,
                seekHandle: _seekHandle,
                onInteraction: _keepAwake,
                onSeekCommitted: _hideNow,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `E01 "Cruelty"`, falling back to `E01 "Episode 1"`.
  ///
  /// Sources frequently fill the title field with a restatement of the number
  /// -- `Episode 58`, `Ep. 58`, or just `58` -- which the quotes then present
  /// as if it were the episode's name. Those are treated as no title at all,
  /// so the fallback is used consistently whether the field was empty or
  /// merely unhelpful.
  static String? _episodeLabel(UnifiedEpisode? episode) {
    if (episode == null) return null;
    final number = episode.number;
    final asText = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    final label = 'E${asText.padLeft(2, '0')}';

    final title = episode.title?.trim();
    final hasRealTitle = title != null &&
        title.isNotEmpty &&
        !RegExp(
          r'^(episode|ep\.?|e)?\s*0*' + RegExp.escape(asText) + r'$',
          caseSensitive: false,
        ).hasMatch(title);

    return '$label "${hasRealTitle ? title : 'Episode $asText'}"';
  }

  void _showPlaybackError(String message) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showDialog<void>(
      context: context,
      builder: (ctx) => Center(
        child: Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 760,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: cs.error),
                      const SizedBox(width: 12),
                      Text(
                        'Failed to load media stream',
                        style: textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Try a different server, source or episode.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      TvButton(
                        label: 'Change server',
                        icon: Icons.playlist_play_rounded,
                        autofocus: true,
                        height: 56,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _openSettingsPanel();
                        },
                      ),
                      const SizedBox(width: 16),
                      TvButton(
                        label: 'Dismiss',
                        height: 56,
                        variant: TvButtonVariant.filledSurface,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
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

/// Dims the video for the duration of a scrub.
///
/// Dims the held frame for the length of a scrub.
///
/// What is behind the overlay is where the user came from, not where they are
/// going. At full brightness it competes with the preview card and invites
/// being read as the destination.
class _ScrubScrim extends ConsumerWidget {
  const _ScrubScrim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrubbing = ref.watch(isScrubbingProvider);

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: Durations.medium1,
        curve: Curves.easeOut,
        opacity: scrubbing ? 1 : 0,
        child: const ColoredBox(
          color: Colors.black54,
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
