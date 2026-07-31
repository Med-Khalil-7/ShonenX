import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';

/// The frame and time under the scrub thumb, floating above the seek bar.
///
/// The frame is not a thumbnail: it is [videoView], the one player that is
/// already open, drawn a second time at card size. There is no second URL, no
/// second decoder and no second load -- the same texture the full screen is
/// showing, sampled again. Scrubbing moves that player, so the picture here is
/// the frame you will land on, by construction.
///
/// What this replaces: a hidden mpv instance that opened the episode again at
/// a lower rendition and screenshotted it. A separate demuxer seeking a
/// separate variant playlist could not be relied on to sit on the same shot,
/// and two decoders at once is more than a 1GB box has to give.
class SeekPreviewCard extends StatelessWidget {
  const SeekPreviewCard({
    super.key,
    required this.label,
    required this.fraction,
    required this.videoView,
  });

  final String label;

  /// The playing engine's own video output.
  final Widget videoView;

  /// Where the thumb sits along the bar, 0..1. Used to follow it.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ShonenXMetrics.of(context);
    final width = m.seekPreview;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Follow the thumb, but never let the card leave the bar.
        final left = (constraints.maxWidth * fraction - width / 2).clamp(
          0.0,
          (constraints.maxWidth - width).clamp(0.0, double.infinity),
        );

        return SizedBox(
          height: width / (16 / 9) + m.playerLabel * 2,
          child: Stack(
            children: [
              Positioned(
                left: left,
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: width,
                        height: width / (16 / 9),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(
                            ShonenX.posterRadius,
                          ),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(blurRadius: 12, color: Colors.black54),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: width,
                            height: width / (16 / 9),
                            child: videoView,
                          ),
                        ),
                      ),
                      SizedBox(height: m.playerLabel * 0.3),
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: m.playerLabel,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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
