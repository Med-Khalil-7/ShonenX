import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
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
        final m = ShonenXMetrics.of(ctx);
        return Center(
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: m.dialogWidth,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: m.label * 2.5,
                  vertical: m.label * 3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontSize: m.meta,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: m.label * 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TvButton(
                          label: confirmLabel,
                          width: m.dialogWidth * 0.38,
                          height: m.buttonHeight * 0.9,
                          // The dialog only ever appears because the user
                          // asked to leave, so confirm is the likely answer
                          // and should be one press away.
                          autofocus: true,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                        SizedBox(width: m.label * 2.5),
                        TvButton(
                          label: cancelLabel,
                          width: m.dialogWidth * 0.38,
                          height: m.buttonHeight * 0.9,
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
