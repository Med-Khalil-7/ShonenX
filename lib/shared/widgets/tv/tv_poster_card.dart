import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';

/// A bare 2:3 poster.
///
/// Intentionally not built on `MediaCard` / `CardRenderer`: those exist to
/// render a title, score, year, genres and a progress ring, and every one of
/// the nine card styles is defined by how it arranges that metadata. The TV
/// rows show artwork and nothing else, so going through `CardConfig` would
/// mean a tenth style whose entire definition is "disable all of the above".
/// `MediaCard` still drives Library and the browse grids.
class TvPosterCard extends StatelessWidget {
  final String? imageUrl;
  final String? heroTag;
  final VoidCallback? onTap;

  /// Null sizes the card from the row's own metrics.
  final double? width;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Shown when the poster fails to load, so a broken image is still
  /// identifiable from the sofa.
  final String? title;

  const TvPosterCard({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.onTap,
    this.width,
    this.autofocus = false,
    this.focusNode,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ShonenX.posterRadius);

    Widget image = ClipRRect(
      borderRadius: radius,
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? _placeholder(context)
          : CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) => Container(color: cs.surfaceContainer),
              errorWidget: (_, __, ___) => _placeholder(context),
            ),
    );

    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      borderRadius: radius,
      focusScale: 1.08,
      child: SizedBox(
        width: width ?? ShonenXMetrics.of(context).rowPoster,
        child: AspectRatio(aspectRatio: ShonenX.posterAspect, child: image),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainer,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: title == null
          ? Icon(Icons.movie_outlined, size: 40, color: cs.onSurfaceVariant)
          : Text(
              title!,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
    );
  }
}
