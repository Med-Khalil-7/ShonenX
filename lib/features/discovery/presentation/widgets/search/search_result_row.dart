import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/tv/tv_badge.dart';

/// One search hit: thumbnail, title, rating + quality badges, one line of
/// synopsis.
class SearchResultRow extends StatelessWidget {
  final UnifiedMedia media;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  const SearchResultRow({
    super.key,
    required this.media,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);

    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(8),
      // A row this wide scaling up would shove the column edge past the
      // viewport; the ring alone is enough at this size.
      scaleOnFocus: false,
      padding: EdgeInsets.all(m.body * 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: m.resultThumb,
              height: m.resultThumb / ShonenX.posterAspect,
              child: _thumbnail(cs),
            ),
          ),
          SizedBox(width: m.body * 1.6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.title.availableTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: m.meta,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                SizedBox(height: m.body * 0.8),
                Row(
                  children: [
                    TvBadge.rating(media),
                    SizedBox(width: m.badge),
                    const TvHdBadge(),
                  ],
                ),
                SizedBox(height: m.body),
                if (media.description != null)
                  Text(
                    _plainText(media.description!),
                    maxLines: 1,
                    // Clipped rather than ellipsised: the line is decorative
                    // context at this size, and a trailing "..." on every row
                    // draws the eye to the wrong place.
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: m.body,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(ColorScheme cs) {
    final url = media.cover ?? media.banner;
    if (url == null || url.isEmpty) {
      return Container(
        color: cs.surfaceContainer,
        child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: cs.surfaceContainer),
      errorWidget: (_, __, ___) => Container(color: cs.surfaceContainer),
    );
  }

  /// Descriptions arrive as fragments of HTML from every tracker.
  static String _plainText(String raw) => raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
