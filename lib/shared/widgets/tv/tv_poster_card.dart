import 'package:shonenx/shared/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

/// A 2:3 poster with its title captioned underneath.
///
/// Intentionally not built on `MediaCard` / `CardRenderer`: those exist to
/// render a title, score, year, genres and a progress ring, and every one of
/// the nine card styles is defined by how it arranges that metadata. A TV row
/// shows artwork and a name, so going through `CardConfig` would mean a tenth
/// style whose entire definition is "disable most of the above".
/// `MediaCard` still drives Library and the browse grids.
class TvPosterCard extends StatelessWidget {
  final String? imageUrl;
  final String? heroTag;
  final VoidCallback? onTap;

  /// Null sizes the card from the row's own metrics.
  final double? width;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Captioned under the poster. Cover art is often stylised to the point of
  /// being unreadable from a sofa, so the name carries the identification.
  final String? title;

  /// Off for rows that identify their items some other way. Size the row with
  /// [rowExtent] passing the same value.
  final bool showTitle;

  const TvPosterCard({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.onTap,
    this.width,
    this.autofocus = false,
    this.focusNode,
    this.title,
    this.showTitle = true,
  });

  /// Slightly under body size: two lines of caption sit below every poster in
  /// a row, and the row still has to fit on a 720p panel.
  static double _captionSize(ShonenXMetrics m) => m.body * 0.9;

  static const double _captionLineHeight = 1.25;
  static const int _captionLines = 2;

  /// Vertical space the caption occupies, its gap included.
  ///
  /// Derived from an explicit line height rather than from font metrics, so
  /// the reserved space and the space the text actually takes cannot drift
  /// apart when the typeface changes.
  static double captionExtent(BuildContext context) {
    final m = ShonenXMetrics.of(context);
    return m.body * 0.4 + _captionSize(m) * _captionLineHeight * _captionLines;
  }

  /// Height to give a row of these, focus ring included.
  static double rowExtent(
    BuildContext context, {
    double? width,
    bool withTitle = true,
  }) {
    final m = ShonenXMetrics.of(context);
    return (width ?? m.rowPoster) / ShonenX.posterAspect +
        (withTitle ? captionExtent(context) : 0) +
        TvFocus.ringWidth * 2;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = ShonenXMetrics.of(context);
    final radius = BorderRadius.circular(ShonenX.posterRadius);

    Widget image = ClipRRect(
      borderRadius: radius,
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? _placeholder(context)
          : AppNetworkImage(
              url: imageUrl,
              // The source cover is ~1000px wide; the card is a tenth of that.
              // Decoding at card width is the difference between 6 MB and
              // 0.2 MB per poster, times the dozens on a home screen.
              width: width ?? m.rowPoster,
              error: _placeholder(context),
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
      builder: (context, isFocused) => SizedBox(
        width: width ?? m.rowPoster,
        child: !showTitle
            ? AspectRatio(aspectRatio: ShonenX.posterAspect, child: image)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Expanded rather than a computed height: the poster takes
                  // whatever the row has left, so a caption that renders a
                  // hair taller than predicted cannot overflow the row.
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: ShonenX.posterAspect,
                        child: image,
                      ),
                    ),
                  ),
                  SizedBox(height: m.body * 0.4),
                  SizedBox(
                    height:
                        _captionSize(m) * _captionLineHeight * _captionLines,
                    child: Text(
                      title ?? '',
                      maxLines: _captionLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _captionSize(m),
                        height: _captionLineHeight,
                        fontWeight: isFocused
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isFocused ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainer,
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined, size: 40, color: cs.onSurfaceVariant),
    );
  }
}
