import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/features/player/providers/seek_preview_provider.dart';

/// The frame and time under the scrub thumb.
///
/// Sits above the seek bar and tracks the thumb horizontally. When the engine
/// cannot grab frames -- ExoPlayer, or a seek that timed out -- the time
/// readout stands on its own rather than the whole thing disappearing.
class SeekPreviewCard extends ConsumerStatefulWidget {
  const SeekPreviewCard({
    super.key,
    required this.target,
    required this.label,
    required this.fraction,
    required this.enabled,
    this.hint,
  });

  /// Scrub target, rounded by the caller so it does not change every frame.
  final Duration target;

  final String label;

  /// What the confirm button will do, shown only once a scrub is under way.
  /// Committing on OK is not a convention a viewer can be assumed to know.
  final String? hint;

  /// Where the thumb sits along the bar, 0..1. Used to follow it.
  final double fraction;

  /// False on engines with no frame grab; the card shows the time only.
  final bool enabled;

  @override
  ConsumerState<SeekPreviewCard> createState() => _SeekPreviewCardState();
}

class _SeekPreviewCardState extends ConsumerState<SeekPreviewCard> {
  /// The last frame that actually arrived.
  ///
  /// Held across requests so a scrub shows a slightly stale frame rather than
  /// blinking empty every time the target moves -- decoding takes a few
  /// hundred milliseconds and a flashing card is worse than a late one.
  Uint8List? _lastFrame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ShonenXMetrics.of(context);
    final width = m.seekPreview;

    if (widget.enabled) {
      final frame = ref.watch(seekPreviewProvider(widget.target));
      final bytes = frame.value;
      if (bytes != null && !identical(bytes, _lastFrame)) {
        _lastFrame = bytes;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Follow the thumb, but never let the card leave the bar.
        final left = (constraints.maxWidth * widget.fraction - width / 2).clamp(
          0.0,
          (constraints.maxWidth - width).clamp(0.0, double.infinity),
        );

        final hint = widget.hint;

        return SizedBox(
          height:
              (widget.enabled ? width / (16 / 9) + m.playerLabel * 2 : m.playerLabel * 2) +
              (hint == null ? 0 : m.playerLabel * 1.4),
          child: Stack(
            children: [
              Positioned(
                left: left,
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.enabled) ...[
                        _Frame(bytes: _lastFrame, width: width),
                        SizedBox(height: m.playerLabel * 0.3),
                      ],
                      Text(
                        widget.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: m.playerLabel,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(blurRadius: 6, color: Colors.black87),
                          ],
                        ),
                      ),
                      if (hint != null)
                        Text(
                          hint,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontSize: m.playerLabel * 0.8,
                            color: Colors.white70,
                            shadows: const [
                              Shadow(blurRadius: 6, color: Colors.black87),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.bytes, required this.width});

  final Uint8List? bytes;
  final double width;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(ShonenX.posterRadius);

    return Container(
      width: width,
      height: width / (16 / 9),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: radius,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(blurRadius: 12, color: Colors.black54),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white24,
                ),
              ),
            )
          : Image.memory(
              bytes!,
              fit: BoxFit.cover,
              // Without this every new frame fades in from nothing, which
              // reads as flicker when they arrive a few per second.
              gaplessPlayback: true,
            ),
    );
  }
}
