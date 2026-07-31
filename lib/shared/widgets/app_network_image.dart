import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shonenx/core/utils/image_headers.dart';

/// Every network image in the app should go through this.
///
/// Flutter decodes to the source bitmap's own pixel size unless told otherwise.
/// An AniList cover is 1000x1500, which is 6 MB of RGBA once decoded, and it is
/// drawn in a row poster about 90 logical pixels wide. Forty of those on a home
/// screen is more memory than a 1 GB TV box has to give, and the decode itself
/// is what makes scrolling stutter.
///
/// Passing a decode budget fixes both: the codec downsamples during decode, so
/// the large bitmap never exists.
class AppNetworkImage extends StatelessWidget {
  final String? url;

  /// Logical size of the box this fills. Either may be null; when both are
  /// null the budget comes from the incoming constraints.
  final double? width;
  final double? height;

  final BoxFit fit;
  final Alignment alignment;

  /// Budget from the height rather than the width.
  ///
  /// For a wide source cropped into a narrow box -- a 16:9 banner shown in a
  /// portrait tile -- the width is the short edge, and budgeting from it makes
  /// the visible part blurry.
  final bool fromHeight;

  /// Below 1.0 for art that is never seen at full strength, e.g. a backdrop
  /// under a near-opaque scrim.
  final double decodeScale;

  /// Hard ceiling in physical pixels.
  final int? maxDecodePixels;

  final Widget? placeholder;
  final Widget? error;
  final Map<String, String>? headers;

  /// Defaults to no fade. A row builds a dozen of these at once and a dozen
  /// simultaneous fade controllers is real work on a weak CPU.
  final Duration fadeIn;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fromHeight = false,
    this.decodeScale = 1.0,
    this.maxDecodePixels,
    this.placeholder,
    this.error,
    this.headers,
    this.fadeIn = Duration.zero,
  });

  /// Physical pixels to decode for a box [logical] units on the chosen edge.
  static int decodeBudget(
    BuildContext context,
    double logical, {
    double scale = 1.0,
    int? max,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (logical * dpr * scale).round().clamp(16, max ?? 1920);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = placeholder ?? ColoredBox(color: cs.surfaceContainer);

    final raw = url;
    if (raw == null || raw.isEmpty) return fallback;

    // Sources encode request headers in a fragment on the URL.
    final resolved = raw.split('#').first;
    final resolvedHeaders = headers ?? decodeUrlHeaders(raw);

    return LayoutBuilder(
      builder: (context, constraints) {
        final logical = fromHeight
            ? (height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : null))
            : (width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : null));

        final budget = logical == null
            ? null
            : decodeBudget(
                context,
                logical,
                scale: decodeScale,
                max: maxDecodePixels,
              );

        return CachedNetworkImage(
          imageUrl: resolved,
          httpHeaders: resolvedHeaders.isEmpty ? null : resolvedHeaders,
          // One axis only, never both: ResizeImage hands both straight to
          // instantiateImageCodec, which stretches rather than crops when it
          // gets a full size. One axis keeps the aspect ratio.
          memCacheWidth: fromHeight ? null : budget,
          memCacheHeight: fromHeight ? budget : null,
          fit: fit,
          alignment: alignment,
          fadeInDuration: fadeIn,
          placeholderFadeInDuration: Duration.zero,
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => error ?? fallback,
        );
      },
    );
  }
}
