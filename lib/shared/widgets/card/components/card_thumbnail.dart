import 'package:shonenx/shared/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shonenx/shared/providers/ui_prefs_provider.dart';
import '../models/card_config.dart';

class CardThumbnail extends StatelessWidget {
  final CardConfig config;
  final double width;
  final double height;
  final double? radiusOverride;

  const CardThumbnail({
    super.key,
    required this.config,
    required this.width,
    required this.height,
    this.radiusOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final radius = radiusOverride ?? GlobalUI.uiRoundness;

    // Progress used to be drawn as a ring traced around the artwork. On a TV
    // it read as a border on the image rather than as a measure of anything,
    // and every continue-watching card carries a progress, so every one of
    // them was framed. The remaining-time text beside the title already says
    // the same thing in words.
    return _buildImage(cs, w: width, h: height, r: radius);
  }

  Widget _buildImage(
    ColorScheme cs, {
    required double w,
    required double h,
    required double r,
  }) {
    if (config.thumbnailBuilder != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: SizedBox(
          width: w,
          height: h,
          child: Builder(
            builder: (context) => config.thumbnailBuilder!(context, cs),
          ),
        ),
      );
    }

    if (config.imageUrl != null && config.imageUrl!.isNotEmpty) {
      // w/h here are layout only -- they do not bound the decode, which is
      // why an unsized 1000px cover used to cost 6 MB in a 120px cell.
      Widget img = SizedBox(
        width: w,
        height: h,
        child: AppNetworkImage(
          url: config.imageUrl,
          width: w,
          error: _buildFallback(cs, w, h),
        ),
      );
      if (config.heroTag != null && config.heroTag!.isNotEmpty) {
        img = Hero(tag: config.heroTag!, child: img);
      }
      return ClipRRect(borderRadius: BorderRadius.circular(r), child: img);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: _buildFallback(cs, w, h),
    );
  }

  Widget _buildFallback(ColorScheme cs, double w, double h) {
    return Container(
      width: w,
      height: h,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(config.fallbackIcon, color: cs.onSurfaceVariant, size: 28),
    );
  }
}
