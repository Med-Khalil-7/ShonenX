import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the user is scrubbing to, or null when they are not scrubbing.
///
/// Lives in a provider rather than in the seek row's own state because the
/// scrub is not a local affair: playback pauses for it, the video dims behind
/// the preview, and the overlay's auto-hide has to stand down while it is in
/// progress. Those are three widgets that would otherwise need the flag
/// threaded down to them.
class ScrubNotifier extends Notifier<Duration?> {
  @override
  Duration? build() => null;

  void update(Duration? target) {
    if (state == target) return;
    state = target;
  }
}

final scrubTargetProvider =
    NotifierProvider.autoDispose<ScrubNotifier, Duration?>(ScrubNotifier.new);

/// Convenience for the widgets that only care that a scrub is happening.
final isScrubbingProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(scrubTargetProvider) != null,
);
