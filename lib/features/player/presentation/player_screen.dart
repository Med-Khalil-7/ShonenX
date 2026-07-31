import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_grid.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
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

  bool _showControls = false;
  Timer? _controlsTimer;
  bool _panelOpen = false;
  bool _exitPromptOpen = false;

  /// Remembered so the subtitle toggle can restore what was switched off.
  SubtitleTrack? _lastSubtitle;

  String get _mediaTitle => switch (widget.mode) {
    PlayerModeOnline(:final media) => media.title.availableTitle,
    PlayerModeOffline(:final title) => title ?? 'Local Media',
  };

  AniSkipArgs? _aniSkipArgs(VideoEngine engine) {
    if (widget.mode case PlayerModeOnline(:final media, :final episode)) {
      final malId = int.tryParse(media.idMal ?? '');
      if (malId == null) return null;
      return AniSkipArgs(
        idMal: malId,
        episodeNumber: episode.number,
        episodeLength: engine.currentDuration.inSeconds,
      );
    }
    return null;
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
  void _hideNow() {
    _controlsTimer?.cancel();
    if (mounted && _showControls) setState(() => _showControls = false);
  }

  void _toggleEpisodePanel() {
    if (widget.mode is! PlayerModeOnline) return;
    if (_panelOpen) {
      Navigator.of(context).pop();
      return;
    }
    _openPanel(
      label: 'Episodes',
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(
            playerControllerProvider.select((s) => s.activeEpisode),
          );
          if (current == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return EpisodeGridView(
            media: (widget.mode as PlayerModeOnline).media,
            currentEpisodeNumber: current.number,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            onEpisodeTap: (episode, _) {
              Navigator.of(sheetContext).pop();
              ref.read(playerControllerProvider.notifier).loadEpisode(episode);
            },
          );
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

  void _openPanel({required String label, required WidgetBuilder builder}) {
    setState(() => _panelOpen = true);
    _controlsTimer?.cancel();
    TvSideSheet.show(context: context, label: label, builder: builder).then((_) {
      if (!mounted) return;
      setState(() => _panelOpen = false);
      // Do not grab focus: it belongs to whichever control opened the panel.
      _wake(focusTransport: false);
    });
  }

  /// BACK unwinds one layer at a time -- open panel, then the overlay, then
  /// the screen. Leaving always asks first: a mis-press on a remote is cheap,
  /// and losing your place is not.
  Future<void> _handleBack() async {
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
          onUserInteraction: _keepAwake,
          onToggleEpisodePanel: _toggleEpisodePanel,
          onBack: _handleBack,
          child: Stack(
            children: [
              Center(
                child: Offstage(
                  offstage: playerState.isLoading,
                  child: engine.buildVideoView(),
                ),
              ),
              // Pulls the paused frame back while a scrub is open, so the
              // preview card reads against it instead of competing with it.
              const _ScrubScrim(),
              if (playerState.activeSubtitle != null)
                const CustomSubtitleOverlay(),
              const PlayerCenterIndicator(),
              PlayerTopBar(
                visible: _showControls,
                title: _mediaTitle,
                subtitle: _episodeLabel(activeEpisode),
                onBack: _handleBack,
                onEpisodes: widget.mode is PlayerModeOnline
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
                onInteraction: _keepAwake,
                onSeekCommitted: _hideNow,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `E01 "Cruelty"`, or just `E01` when the source gives no episode title.
  static String? _episodeLabel(UnifiedEpisode? episode) {
    if (episode == null) return null;
    final number = episode.number;
    final asText = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    final label = 'E${asText.padLeft(2, '0')}';
    final title = episode.title;
    return (title == null || title.isEmpty) ? label : '$label "$title"';
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
/// Playback is paused while scrubbing, so what is behind the overlay is a
/// still frame from wherever the user happened to be -- not where they are
/// going. Holding it at full brightness invites reading it as the destination.
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
