import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/player/providers/custom_subtitle_provider.dart';
import 'package:shonenx/features/player/domain/subtitle_prefs.dart';
import 'package:shonenx/features/player/providers/subtitle_prefs_provider.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/features/player/utils/subtitle_parser.dart';

/// Draws subtitles ourselves when the native track is switched off.
///
/// Always returns a [Positioned]: it is a direct child of the player's Stack,
/// and the empty branches used to return a bare SizedBox, which is a crash
/// waiting for whoever next reorders that Stack.
class CustomSubtitleOverlay extends ConsumerWidget {
  const CustomSubtitleOverlay({super.key});

  static const _hidden = Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(subtitlePrefsProvider);
    if (!prefs.useCustomSubtitle) return _hidden;

    // Watched at the top rather than inside the `data` branch: a ref.watch in
    // a callback registers a dependency that comes and goes with the branch
    // taken, which is how rebuilds get silently dropped.
    final position = ref.watch(
      videoEngineStateProvider.select((s) => s.position),
    );
    final cues = ref.watch(customSubtitleProvider).value ?? const [];
    if (cues.isEmpty) return _hidden;

    final activeCue = _findActiveCue(cues, position);
    if (activeCue == null) return _hidden;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final responsiveFontSize = getResponsiveSubtitleSize(
      screenWidth,
      prefs.fontSize,
    );

    return Positioned(
      bottom: prefs.bottomPadding,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: SubtitleParser.cleanSubtitleText(activeCue.text)
                    .split('\n')
                    .map((l) => l.replaceAll('\r', ''))
                    .where((l) => l.trim().isNotEmpty)
                    .map(
                      (line) => Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: prefs.padding * 1.5,
                          vertical: prefs.padding * 0.5,
                        ),
                        decoration: prefs.backgroundColor != 0x00000000
                            ? BoxDecoration(
                                color: prefs.bg,
                                borderRadius: BorderRadius.circular(4.0),
                              )
                            : null,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (getSubtitleStrokeStyle(
                                  prefs,
                                  responsiveFontSize,
                                ) !=
                                null)
                              Text(
                                line,
                                textAlign: TextAlign.center,
                                style: getSubtitleStrokeStyle(
                                  prefs,
                                  responsiveFontSize,
                                ),
                              ),
                            Text(
                              line,
                              textAlign: TextAlign.center,
                              style: getSubtitleTextStyle(
                                prefs,
                                responsiveFontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  SubtitleCue? _findActiveCue(List<SubtitleCue> cues, Duration position) {
    if (cues.isEmpty) return null;

    int low = 0;
    int high = cues.length - 1;

    while (low <= high) {
      // Bitwise shift is slightly faster than division by 2
      int mid = low + ((high - low) >> 1);
      final cue = cues[mid];

      if (position >= cue.start && position <= cue.end) {
        return cue; // Target found
      } else if (position < cue.start) {
        high = mid - 1; // Target is in the earlier half
      } else {
        low = mid + 1; // Target is in the later half
      }
    }

    return null; // No active subtitle at this position
  }
}
