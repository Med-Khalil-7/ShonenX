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
class PlayerSkipButton extends ConsumerStatefulWidget {
  const PlayerSkipButton({
    super.key,
    required this.engine,
    required this.aniskipArgs,
  });

  final VideoEngine engine;
  final AniSkipArgs? aniskipArgs;

  @override
  ConsumerState<PlayerSkipButton> createState() => _PlayerSkipButtonState();
}

class _PlayerSkipButtonState extends ConsumerState<PlayerSkipButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'skipButton');

  /// The stamp being offered, if any.
  AniSkipStamp? _showing;

  /// Stamps already offered this episode. Once dismissed or used, a stamp does
  /// not come back -- otherwise leaving the overlay open through an opening
  /// re-triggers it every second.
  final Set<SkipType> _spent = {};

  Timer? _hideTimer;
  FocusNode? _restoreTo;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _offer(AniSkipStamp stamp, {required bool takeFocus, required int hold}) {
    setState(() => _showing = stamp);

    if (takeFocus) {
      final previous = FocusManager.instance.primaryFocus;
      // Do not record ourselves as the place to return to.
      if (previous != _focus) _restoreTo = previous;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showing != null) _focus.requestFocus();
      });
    }

    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: hold), _dismiss);
  }

  void _dismiss() {
    if (!mounted || _showing == null) return;
    _hideTimer?.cancel();
    final stamp = _showing;
    setState(() => _showing = null);
    if (stamp != null) _spent.add(stamp.type);

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

      final inside = stamps.cast<AniSkipStamp?>().firstWhere(
        (s) =>
            s != null &&
            seconds >= s.startTime &&
            seconds < s.endTime &&
            skipPrefs.mode(s.type) != SkipMode.off &&
            !_spent.contains(s.type),
        orElse: () => null,
      );

      if (inside != null && _showing?.type != inside.type) {
        _offer(
          inside,
          takeFocus: prefs.focusSkipButton,
          hold: prefs.skipButtonHoldSeconds,
        );
      } else if (inside == null && _showing != null) {
        // Walked out of the stamp without pressing it.
        _dismiss();
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
        height: m.buttonHeight,
        focusNode: _focus,
        variant: TvButtonVariant.filledWhite,
        ensureVisible: false,
        onPressed: () => _skip(stamp),
      ),
    );
  }
}
