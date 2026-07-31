import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/source_engine/models/source_info.dart';

sealed class PlayerMode {
  const PlayerMode();
}

class PlayerModeOnline extends PlayerMode {
  final UnifiedMedia media;
  final UnifiedEpisode episode;
  final SourceInfo sourceInfo;
  final Duration? startPosition;

  const PlayerModeOnline({
    required this.media,
    required this.episode,
    required this.sourceInfo,
    this.startPosition,
  });
}

/// Play this title, working out which episode inside the player.
///
/// Picking the episode means fetching the whole episode list from the source,
/// which is a network round trip. Doing it before navigating left the user on
/// the previous screen watching a spinner with nothing to look at; doing it
/// here means the player opens immediately and shows its own loading over the
/// surface it is about to fill.
class PlayerModeAuto extends PlayerMode {
  final UnifiedMedia media;

  /// Resume position for a specific episode, when the caller already knows one
  /// -- the continue-watching row does. Null means "work it out from history".
  final double? episodeNumber;
  final Duration? startPosition;

  const PlayerModeAuto({
    required this.media,
    this.episodeNumber,
    this.startPosition,
  });
}

class PlayerModeOffline extends PlayerMode {
  final String filePath;
  final String? title;

  const PlayerModeOffline({
    required this.filePath,
    this.title,
  });
}
