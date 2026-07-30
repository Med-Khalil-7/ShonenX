import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/shared/models/unified_media.dart';

/// Small outlined pill used for the age rating and quality markers that sit
/// under a title (`R`, `PG-13`, `HD`).
class TvBadge extends StatelessWidget {
  final String label;

  const TvBadge(this.label, {super.key});

  /// There is no age-rating field on [UnifiedMedia] -- only `isAdult` -- so
  /// this is a two-bucket approximation, not real classification data.
  factory TvBadge.rating(UnifiedMedia media) =>
      TvBadge(media.isAdult == true ? 'R' : 'PG-13');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = ShonenXMetrics.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.badge * 0.55,
        vertical: m.badge * 0.2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.onSurfaceVariant, width: 1.5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: m.badge,
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The quality marker is decorative -- every stream the app plays is treated
/// as HD, matching how the reference UI renders it.
class TvHdBadge extends StatelessWidget {
  const TvHdBadge({super.key});

  @override
  Widget build(BuildContext context) => const TvBadge('HD');
}

/// `[R] [HD]  ·  ★ 3.0  ·  2003`
class TvMetaRow extends StatelessWidget {
  final UnifiedMedia media;

  /// Show the genre list in place of the year. The hero uses this because it
  /// has no room for a separate "Genres:" line under the synopsis.
  final bool showGenres;

  const TvMetaRow({
    super.key,
    required this.media,
    this.showGenres = false,
  });

  /// `season` is a free-form string across trackers -- `'2003'` from AniList,
  /// `'SPRING 2003'` from Kitsu -- so pull the year out rather than trusting
  /// its shape.
  static String? yearOf(UnifiedMedia media) {
    final season = media.season;
    if (season == null) return null;
    return RegExp(r'\d{4}').firstMatch(season)?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);
    final style = theme.textTheme.titleMedium?.copyWith(
      fontSize: m.meta,
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final year = yearOf(media);
    final score = media.score;
    final hasScore = score != null;

    Widget dot() => Padding(
      padding: EdgeInsets.symmetric(horizontal: m.meta * 0.5),
      child: Text('·', style: style),
    );

    final genres = media.genres ?? const <String>[];

    return Row(
      mainAxisSize: showGenres ? MainAxisSize.max : MainAxisSize.min,
      children: [
        TvBadge.rating(media),
        SizedBox(width: m.meta * 0.5),
        const TvHdBadge(),
        if (hasScore) ...[
          dot(),
          Icon(Icons.star_rounded, size: m.meta * 1.15, color: cs.onSurface),
          SizedBox(width: m.meta * 0.25),
          Text(
            // Trackers report 0-100 as often as 0-10; normalise the way the
            // card system already does.
            (score > 10 ? score / 10 : score).toStringAsFixed(1),
            style: style?.copyWith(color: cs.onSurface),
          ),
        ],
        if (showGenres) ...[
          if (genres.isNotEmpty) ...[
            dot(),
            Flexible(
              child: Text(
                genres.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ] else if (year != null) ...[
          dot(),
          Text(year, style: style),
        ],
      ],
    );
  }
}
