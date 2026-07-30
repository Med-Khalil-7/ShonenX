import 'package:flutter/material.dart';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.onSurfaceVariant, width: 1.5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
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

  const TvMetaRow({super.key, required this.media});

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
    final style = theme.textTheme.titleMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final year = yearOf(media);
    final score = media.score;
    final hasScore = score != null;

    Widget dot() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text('·', style: style),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvBadge.rating(media),
        const SizedBox(width: 10),
        const TvHdBadge(),
        if (hasScore) ...[
          dot(),
          Icon(Icons.star_rounded, size: 20, color: cs.onSurface),
          const SizedBox(width: 5),
          Text(
            // Trackers report 0-100 as often as 0-10; normalise the way the
            // card system already does.
            (score > 10 ? score / 10 : score).toStringAsFixed(1),
            style: style?.copyWith(color: cs.onSurface),
          ),
        ],
        if (year != null) ...[dot(), Text(year, style: style)],
      ],
    );
  }
}
