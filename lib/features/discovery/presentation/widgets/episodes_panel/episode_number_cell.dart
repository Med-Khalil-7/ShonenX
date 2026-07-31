import 'package:flutter/material.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/utils/formatting.dart';
import 'package:shonenx/shared/models/unified_episode.dart';

enum EpisodeCellState {
  /// Never started.
  unwatched,

  /// Finished, or at least started -- the app stores no distinction.
  watched,

  /// The episode the user would resume.
  current,
}

/// One square in the episode grid: a number and nothing else.
///
/// Thumbnails and titles were dropped deliberately. Episode artwork from the
/// scrapers is frequently missing, mismatched or a duplicate of the series
/// banner, and a title only helps once you already know which episode you
/// want. What a remote actually needs is to land on a specific number quickly,
/// which a dense uniform grid does better than any list.
class EpisodeNumberCell extends StatelessWidget {
  final UnifiedEpisode episode;
  final EpisodeCellState state;

  /// Styling only -- nothing populates [UnifiedEpisode.isFiller] today. See
  /// the note in `episode_grid.dart`.
  final bool isFiller;

  /// Laid-out edge of the square. Drives the type size and corner radius so
  /// the cell reads the same on a 720p box and a 4K panel.
  final double size;

  final bool autofocus;

  /// Supplied for the first cell so the range tabs can hand focus somewhere
  /// known instead of leaving it to geometry.
  final FocusNode? focusNode;

  final ValueChanged<bool>? onFocusChange;
  final VoidCallback onTap;

  const EpisodeNumberCell({
    super.key,
    required this.episode,
    required this.state,
    required this.size,
    required this.onTap,
    this.isFiller = false,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  static const _filler = Color(0xFFFFB300); // amber 600

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (Color fill, Color fg) = switch (state) {
      EpisodeCellState.current => (cs.primary, cs.onPrimary),
      EpisodeCellState.watched => (
        cs.surfaceContainerHighest,
        cs.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      EpisodeCellState.unwatched => (Colors.transparent, cs.onSurface),
    };

    // Filler tints the outline and the glyph but never the fill: watched and
    // current are the states the user acts on, filler is only metadata about
    // the episode. A watched filler still has to read as watched.
    final border = isFiller
        ? _filler.withValues(alpha: 0.85)
        : state == EpisodeCellState.unwatched
        ? cs.outlineVariant
        : Colors.transparent;

    final number = isFiller && state != EpisodeCellState.current
        ? Color.lerp(fg, _filler, 0.55)!
        : fg;

    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      borderRadius: BorderRadius.circular(size * 0.16),
      // A scaled cell in a tight grid shears against the scroll viewport's
      // clip on the first and last visible rows. The ring alone marks focus,
      // as it does on the on-screen keyboard and the rail.
      scaleOnFocus: false,
      // Deliberately no focus fill: the default is cs.primary, which means
      // *current* here, and any grey would collide with *watched*.
      filledWhenFocused: false,
      alignment: 0.5,
      builder: (context, isFocused) => DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(size * 0.16),
          border: border == Colors.transparent
              ? null
              : Border.all(color: border, width: 1.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.all(size * 0.1),
              child: FittedBox(
                // Three- and four-digit numbers shrink rather than clip. One
                // Piece is 1100 episodes and counting.
                fit: BoxFit.scaleDown,
                child: Text(
                  formatEpisodeNumber(episode.number) ?? '',
                  style: TextStyle(
                    fontSize: size * 0.34,
                    height: 1,
                    color: number,
                    fontWeight:
                        isFocused || state == EpisodeCellState.current
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
            // A bar rather than a colour shift alone: at 10 feet an amber
            // number on a grey plate is easy to miss, an edge marker is not.
            if (isFiller)
              Positioned(
                left: size * 0.22,
                right: size * 0.22,
                bottom: size * 0.1,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: _filler,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
