import 'package:flutter/material.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';

/// Centred confirm/cancel dialog, sized and weighted for a 10-foot read.
///
/// Returns `true` when confirmed, `null` when dismissed.
abstract final class TvConfirmDialog {
  static Future<bool?> show({
    required BuildContext context,
    required String message,
    String confirmLabel = 'Yes',
    String cancelLabel = 'No',
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Center(
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 600,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TvButton(
                          label: confirmLabel,
                          width: 227,
                          height: 52,
                          // The dialog only ever appears because the user
                          // asked to leave, so confirm is the likely answer
                          // and should be one press away.
                          autofocus: true,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                        const SizedBox(width: 32),
                        TvButton(
                          label: cancelLabel,
                          width: 227,
                          height: 52,
                          variant: TvButtonVariant.filledSurface,
                          onPressed: () => Navigator.of(ctx).pop(false),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
