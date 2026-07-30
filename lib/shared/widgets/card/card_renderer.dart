import 'package:flutter/material.dart';
import 'package:shonenx/shared/models/ui_style_enums.dart';

import 'models/card_config.dart';
import 'styles/cinematic_card.dart';
import 'styles/classic_card.dart';

class CardRenderer extends StatelessWidget {
  final MediaCardStyle style;
  final CardConfig config;

  const CardRenderer({super.key, required this.style, required this.config});

  @override
  Widget build(BuildContext context) {
    final Widget card = switch (style) {
      MediaCardStyle.classic => ClassicCard(config: config),
      MediaCardStyle.cinematic => CinematicCard(config: config),
    };

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          card,
          if (config.isLoading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
