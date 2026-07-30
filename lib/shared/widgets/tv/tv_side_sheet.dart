import 'package:flutter/material.dart';

/// Right-anchored slide-in panel.
///
/// Lifted out of the player, which grew two copies of this same
/// `showGeneralDialog` block. The episode list, the subtitle picker and the
/// player settings panel all now share one implementation.
///
/// A bottom sheet would be wrong here: on a 16:9 panel it either covers the
/// video or leaves a strip too short to list episodes in.
abstract final class TvSideSheet {
  /// Fraction of the screen width the panel occupies.
  static const widthFraction = 0.38;

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String label = 'Panel',
    double? widthFactor,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: label,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: MediaQuery.of(ctx).size.width * (widthFactor ?? widthFraction),
          height: double.infinity,
          child: Material(
            color: Theme.of(ctx).colorScheme.surfaceContainer,
            child: SafeArea(child: builder(ctx)),
          ),
        ),
      ),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }
}
