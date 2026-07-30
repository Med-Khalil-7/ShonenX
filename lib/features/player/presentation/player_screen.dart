import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screenshot/screenshot.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:shonenx/features/discovery/presentation/widgets/episodes_panel/episode_list_panel.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/presentation/widgets/custom_subtitle_overlay.dart';
import 'package:shonenx/features/player/presentation/widgets/player_keyboard_listener.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_center_indicator.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_settings_panel.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_top_bar.dart';
import 'package:shonenx/features/player/presentation/widgets/tv/player_transport_bar.dart';
import 'package:shonenx/features/player/providers/aniskip_provider.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
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
  /// Retained for `captureExitThumbnail`, which is what puts artwork on the
  /// continue-watching row. The manual screenshot button is gone; this is not.
  final ScreenshotController _screenshotController = ScreenshotController();

  /// Long enough to cross the overlay with a D-pad. Three seconds was tuned
  /// for a mouse and expires mid-traversal on a remote.
  static const _autoHide = Duration(seconds: 5);

  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'playPause');

  bool _showControls = false;
  Timer? _controlsTimer;
  bool _panelOpen = false;
  bool _exitPromptOpen = false;

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
      ref
          .read(playerControllerProvider.notifier)
          .initialize(widget.mode, screenshot: _screenshotController);
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

    try {
      ref.read(videoEngineProvider).dispose();
    } catch (_) {}

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
    // A panel or the exit prompt means the user is mid-decision; hiding the
    // controls under them would drop focus into nothing on dismissal.
    if (_panelOpen || _exitPromptOpen) return;
    setState(() => _showControls = false);
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
          return EpisodeListPanel(
            media: (widget.mode as PlayerModeOnline).media,
            currentEpisodeNumber: current.number,
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
                  child: Screenshot(
                    controller: _screenshotController,
                    child: engine.buildVideoView(),
                  ),
                ),
              ),
              if (playerState.activeSubtitle != null)
                const CustomSubtitleOverlay(),
              const PlayerCenterIndicator(),
              PlayerTopBar(
                visible: _showControls,
                title: _mediaTitle,
                subtitle: _episodeLabel(activeEpisode),
                onBack: _handleBack,
                onEpisodes: _toggleEpisodePanel,
                onSubtitles: _openSettingsPanel,
                onSettings: _openSettingsPanel,
              ),
              PlayerTransportBar(
                visible: _showControls,
                engine: engine,
                controller: controller,
                aniskipArgs: _aniSkipArgs(engine),
                playPauseFocus: _playPauseFocus,
                onInteraction: _keepAwake,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `E01 "Cruelty"`, or just `E01` when the source gives no episode title.
  static String? _episodeLabel(dynamic episode) {
    if (episode == null) return null;
    final number = episode.number as double;
    final asText = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    final label = 'E${asText.padLeft(2, '0')}';
    final title = episode.title as String?;
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
