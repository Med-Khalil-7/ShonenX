import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/features/player/domain/aniskip_prefs.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/providers/aniskip_prefs_provider.dart';
import 'package:shonenx/features/player/providers/aniskip_provider.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';

/// Skip Opening / Skip Ending, on its own layer above the video.
///
/// Deliberately **not** part of the transport bar. It used to live there,
/// which meant it only existed while the overlay happened to be up -- and the
/// overlay is hidden during exactly the stretch of an episode where a skip
/// button is wanted. Netflix shows it over the video regardless, and so does
/// this.
///
/// It takes focus on appear so it is one press, and gives focus back to
/// whatever had it when it goes away, so it does not strand the user in an
/// empty overlay.
/// Lets the screen fire the skip without the button holding focus.
///
/// While the controls are down, the screen's own key handler is the focus
/// stop -- it has to be, or nothing would wake the overlay -- so the button
/// cannot hold focus and OK went to the overlay instead of to the skip that
/// was plainly on screen. This is how that press reaches it.
class SkipHandle {
  bool Function()? _skip;

  /// Skips if a stamp is being offered. Returns whether it did, so the caller
  /// can fall back to its usual handling when there is nothing to skip.
  bool skip() => _skip?.call() ?? false;
}

class PlayerSkipButton extends ConsumerStatefulWidget {
  const PlayerSkipButton({
    super.key,
    required this.engine,
    required this.aniskipArgs,
    this.handle,
  });

  final VideoEngine engine;
  final AniSkipArgs? aniskipArgs;
  final SkipHandle? handle;

  @override
  ConsumerState<PlayerSkipButton> createState() => _PlayerSkipButtonState();
}

class _PlayerSkipButtonState extends ConsumerState<PlayerSkipButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'skipButton');

  /// The stamp being offered, if any.
  AniSkipStamp? _showing;

  /// Stamps dismissed during the current visit to their window.
  ///
  /// Cleared the moment playback leaves the window, so seeking back into an
  /// opening offers the button again with a fresh countdown. It only exists to
  /// stop a dismissed button re-appearing every second while you are still
  /// sitting inside the same stamp.
  final Set<SkipType> _spent = {};

  Timer? _hideTimer;
  FocusNode? _restoreTo;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_holdFocus);
    widget.handle?._skip = _skipIfOffered;
  }

  /// Whether the player is the route on top.
  ///
  /// Holding focus is only right while this button is the frontmost thing on
  /// screen. With the close prompt or a settings panel pushed over the player
  /// it is behind them, and clawing focus back from underneath left those
  /// dialogs drawn but dead -- the buttons highlighted and OK did nothing,
  /// because the press was going to a skip button nobody could see.
  bool get _isTopmost {
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  /// The skip as the screen's key handler sees it: do it if there is one.
  bool _skipIfOffered() {
    final stamp = _showing;
    if (!mounted || stamp == null || !_isTopmost) return false;
    if (!ref.read(playerPrefsProvider).showAniSkipButton) return false;
    _skip(stamp);
    return true;
  }

  /// While the button is up it stays the selected control.
  ///
  /// Otherwise revealing the overlay hands focus to the transport row and OK
  /// plays or pauses instead of skipping -- with a skip button plainly on
  /// screen. It is only up for a few seconds, and dismisses itself.
  void _holdFocus() {
    if (!mounted || _showing == null || _focus.hasFocus) return;
    if (!ref.read(playerPrefsProvider).focusSkipButton) return;
    if (!_isTopmost) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showing != null && !_focus.hasFocus && _isTopmost) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (widget.handle?._skip == _skipIfOffered) widget.handle?._skip = null;
    _focus.removeListener(_holdFocus);
    _focus.dispose();
    super.dispose();
  }

  void _offer(AniSkipStamp stamp, {required bool takeFocus, required int hold}) {
    setState(() => _showing = stamp);

    if (takeFocus && _isTopmost) {
      final previous = FocusManager.instance.primaryFocus;
      // Do not record ourselves as the place to return to.
      if (previous != _focus) _restoreTo = previous;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showing != null && _isTopmost) _focus.requestFocus();
      });
    }

    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: hold), _dismiss);
  }

  void _dismiss({bool markSpent = true}) {
    if (!mounted || _showing == null) return;
    _hideTimer?.cancel();
    final stamp = _showing;
    setState(() => _showing = null);
    if (markSpent && stamp != null) _spent.add(stamp.type);

    // Hand focus back only if we still hold it; the user may have moved on.
    if (_focus.hasFocus) {
      final target = _restoreTo;
      if (target != null && target.canRequestFocus) {
        target.requestFocus();
      } else {
        _focus.unfocus();
      }
    }
    _restoreTo = null;
  }

  void _skip(AniSkipStamp stamp) {
    widget.engine.seekTo(Duration(seconds: stamp.endTime.ceil()));
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(playerPrefsProvider);
    final skipPrefs = ref.watch(aniskipPrefsProvider);
    final stamps = ref.watch(aniSkipProvider(widget.aniskipArgs)).value ?? [];
    final insets = TvMetrics.ofSize(MediaQuery.sizeOf(context));
    final m = ShonenXMetrics.of(context);

    // Episode changed underneath us: the offered stamp belongs to the old one.
    ref.listen(aniSkipProvider(widget.aniskipArgs), (_, __) => _spent.clear());

    ref.listen(videoEngineStateProvider.select((s) => s.position), (_, pos) {
      if (!prefs.showAniSkipButton) return;
      final seconds = pos.inSeconds;

      // Whether we are inside a stamp at all, independent of whether it has
      // already been dismissed. Folding the two together meant a dismissed
      // stamp read as "outside", which cleared the dismissal and re-offered
      // it immediately.
      final inside = stamps.cast<AniSkipStamp?>().firstWhere(
        (s) =>
            s != null &&
            seconds >= s.startTime &&
            seconds < s.endTime &&
            skipPrefs.mode(s.type) != SkipMode.off,
        orElse: () => null,
      );

      if (inside == null) {
        // Left the window. A later seek back in should offer it again, with
        // the countdown starting over.
        _spent.clear();
        if (_showing != null) _dismiss(markSpent: false);
        return;
      }

      if (!_spent.contains(inside.type) && _showing?.type != inside.type) {
        _offer(
          inside,
          takeFocus: prefs.focusSkipButton,
          hold: prefs.skipButtonHoldSeconds,
        );
      }
    });

    final stamp = _showing;
    if (stamp == null || !prefs.showAniSkipButton) {
      return const SizedBox.shrink();
    }

    final label = switch (stamp.type) {
      SkipType.opening || SkipType.mixedOpening => 'Skip Opening',
      SkipType.ending || SkipType.mixedEnding => 'Skip Ending',
      SkipType.recap => 'Skip Recap',
    };

    return Positioned(
      right: insets.right,
      // Clear of the transport bar, so the two never sit on top of each other
      // when the overlay is also up.
      bottom: insets.bottom + m.transportIcon * 5,
      child: TvButton(
        label: label,
        icon: Icons.skip_next_rounded,
        height: m.playerButtonHeight,
        focusNode: _focus,
        variant: TvButtonVariant.filledWhite,
        // No focus ring. It takes focus the moment it appears, so the ring was
        // permanently on -- a white outline around an already-white button
        // over dark video, which read as a highlighter rather than as focus.
        ringColor: Colors.transparent,
        ensureVisible: false,
        onPressed: () => _skip(stamp),
      ),
    );
  }
}
