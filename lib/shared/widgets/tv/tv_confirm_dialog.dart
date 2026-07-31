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
                    // Expanded, not a fraction of the dialog. Two buttons at
                    // 0.38 each plus the gap between them plus the padding
                    // either side added up to more than the dialog is wide, so
                    // the row overflowed -- and any longer label made it
                    // worse. Sharing what is actually left cannot overflow.
                    Row(
                      children: [
                        Expanded(
                          child: TvButton(
                            label: confirmLabel,
                            height: m.buttonHeight * 0.9,
                            // The dialog only ever appears because the user
                            // asked to leave, so confirm is the likely answer
                            // and should be one press away.
                            autofocus: true,
                            onPressed: () => Navigator.of(ctx).pop(true),
                          ),
                        ),
                        SizedBox(width: m.label),
                        Expanded(
                          child: TvButton(
                            label: cancelLabel,
                            height: m.buttonHeight * 0.9,
                            variant: TvButtonVariant.filledSurface,
                            onPressed: () => Navigator.of(ctx).pop(false),
                          ),
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
