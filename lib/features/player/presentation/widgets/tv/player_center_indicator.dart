import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';

/// Transient centre feedback: a red arc while buffering, and a dark disc with
/// a play or pause glyph for a moment after the state is toggled.
///
/// Not a button. On a remote the play/pause control lives in the transport row
/// where the rest of the transport is; a second, larger target in the middle
/// of the screen would only be reachable by traversing off the row it belongs
/// to.
class PlayerCenterIndicator extends ConsumerStatefulWidget {
  const PlayerCenterIndicator({super.key});

  @override
  ConsumerState<PlayerCenterIndicator> createState() =>
      _PlayerCenterIndicatorState();
}

class _PlayerCenterIndicatorState
    extends ConsumerState<PlayerCenterIndicator> {
  static const _holdFor = Duration(milliseconds: 700);

  bool? _lastPlaying;
  DateTime? _changedAt;

  @override
  Widget build(BuildContext context) {
    final isBuffering = ref.watch(
      videoEngineStateProvider.select((s) => s.isBuffering),
    );
    final isPlaying = ref.watch(
      videoEngineStateProvider.select((s) => s.isPlaying),
    );

    if (_lastPlaying != isPlaying) {
      _lastPlaying = isPlaying;
      _changedAt = DateTime.now();
      // Repaint once the hold expires; nothing else drives a rebuild when
      // playback state is steady.
      Future.delayed(_holdFor, () {
        if (mounted) setState(() {});
      });
    }

    final m = ShonenXMetrics.of(context);

    if (isBuffering) {
      return Center(
        child: SizedBox(
          width: m.centerIndicator * 0.47,
          height: m.centerIndicator * 0.47,
          child: const CircularProgressIndicator(
            strokeWidth: 5,
            color: ShonenX.red,
          ),
        ),
      );
    }

    final changedAt = _changedAt;
    final showGlyph =
        changedAt != null && DateTime.now().difference(changedAt) < _holdFor;

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: showGlyph ? 1 : 0,
        child: Center(
          child: Container(
            width: m.centerIndicator,
            height: m.centerIndicator,
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: m.centerIndicator * 0.47,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
