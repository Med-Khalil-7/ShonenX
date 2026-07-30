import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';

/// Remote and keyboard handling for the player.
///
/// Two modes, driven by [controlsVisible]:
///
/// * **Hidden** -- this node holds focus and swallows the arrow keys, so any
///   direction press simply reveals the controls. Nothing on screen is
///   focusable yet, so letting traversal run would send focus somewhere
///   invisible.
/// * **Visible** -- this node stops requesting focus and ignores arrows, and
///   ordinary directional traversal drives the real buttons.
///
/// The previous version was permanently in the first mode: one autofocused
/// `Focus` mapping arrows to seek and volume. That is a keyboard model, and it
/// meant no control in the overlay could ever be reached by D-pad.
class PlayerKeyboardListener extends ConsumerWidget {
  final Widget child;
  final VideoEngine engine;
  final PlayerController controller;

  final bool controlsVisible;

  /// Reveal the controls and hand focus to play/pause.
  final VoidCallback onWake;

  /// Any accepted key restarts the auto-hide countdown.
  final VoidCallback onUserInteraction;

  final VoidCallback onToggleEpisodePanel;
  final VoidCallback onBack;

  const PlayerKeyboardListener({
    super.key,
    required this.child,
    required this.engine,
    required this.controller,
    required this.controlsVisible,
    required this.onWake,
    required this.onUserInteraction,
    required this.onToggleEpisodePanel,
    required this.onBack,
  });

  // Not const: LogicalKeyboardKey overrides ==, which a const set forbids.
  static final _directional = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult _handleKeyEvent(WidgetRef ref, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent;

    // Transport keys work in both modes: a remote with dedicated media buttons
    // should not have to open the overlay first.
    switch (key) {
      case LogicalKeyboardKey.mediaPlayPause:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        if (isDown) {
          onUserInteraction();
          ref.read(videoEngineStateProvider).isPlaying
              ? engine.pause()
              : engine.play();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaPlay:
        if (isDown) engine.play();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaPause:
      case LogicalKeyboardKey.mediaStop:
        if (isDown) engine.pause();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaFastForward:
      case LogicalKeyboardKey.keyL:
        onUserInteraction();
        engine.seekRelative(const Duration(seconds: 10));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaRewind:
      case LogicalKeyboardKey.keyJ:
        onUserInteraction();
        engine.seekRelative(const Duration(seconds: -10));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaTrackNext:
      case LogicalKeyboardKey.keyN:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.channelDown:
        if (isDown) controller.skipEpisode();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaTrackPrevious:
      case LogicalKeyboardKey.keyP:
      case LogicalKeyboardKey.pageUp:
      case LogicalKeyboardKey.channelUp:
        if (isDown) controller.skipEpisode(forward: false);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyE:
        if (isDown) onToggleEpisodePanel();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyS:
        if (isDown) {
          onUserInteraction();
          ref.read(videoEngineStateProvider.notifier).cycleFit();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        if (isDown) onBack();
        return KeyEventResult.handled;
    }

    if (!controlsVisible && _directional.contains(key)) {
      // The first press only wakes the overlay. It must not also activate
      // whatever button focus happens to land on.
      if (isDown) onWake();
      return KeyEventResult.handled;
    }

    if (controlsVisible) {
      // Traversal gets the key, but the overlay stays alive while the user is
      // still moving around it.
      onUserInteraction();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Focus(
      autofocus: true,
      // Only a focus stop while the controls are hidden. Once they are up the
      // real buttons have to be reachable, and a node that keeps claiming
      // focus would fight every traversal attempt.
      canRequestFocus: !controlsVisible,
      skipTraversal: true,
      onKeyEvent: (_, event) => _handleKeyEvent(ref, event),
      child: child,
    );
  }
}
