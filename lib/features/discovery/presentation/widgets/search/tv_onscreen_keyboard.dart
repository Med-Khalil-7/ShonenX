import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';

/// D-pad driven keyboard.
///
/// Android TV's own IME (leanback) takes over the whole screen and hands focus
/// back unpredictably, which is why the search field elsewhere in the app
/// carries a comment warning callers off `autofocus`. Drawing the keys inline
/// keeps the results visible while typing and keeps focus under our control.
///
/// Digits run 1-9 then 0, which is how they are laid out on a remote's number
/// pad and on every other on-screen keyboard on the platform.
class TvOnScreenKeyboard extends StatelessWidget {
  static const _rows = <String>[
    'abcdef',
    'ghijkl',
    'mnopqr',
    'stuvwx',
    'yz1234',
    '567890',
  ];

  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;

  /// Focused by the search screen so the first press after arriving lands on a
  /// letter rather than nowhere.
  final FocusNode? firstKeyFocus;

  const TvOnScreenKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onSpace,
    this.firstKeyFocus,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(ShonenX.keyboardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      // The hairlines between keys are this layer showing through the 1px
      // gaps, rather than a border on each cell -- adjacent borders would
      // double up and read as 2px.
      child: ColoredBox(
        color: cs.outlineVariant,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 1,
          children: [
            Row(
              spacing: 1,
              children: [
                Expanded(
                  child: _Key(
                    icon: Icons.space_bar_rounded,
                    onTap: onSpace,
                    semanticLabel: 'Space',
                  ),
                ),
                Expanded(
                  child: _Key(
                    icon: Icons.backspace_outlined,
                    onTap: onBackspace,
                    semanticLabel: 'Backspace',
                  ),
                ),
              ],
            ),
            for (final (rowIndex, row) in _rows.indexed)
              Row(
                spacing: 1,
                children: [
                  for (final (colIndex, char) in row.split('').indexed)
                    Expanded(
                      child: _Key(
                        label: char,
                        onTap: () => onChar(char),
                        // Arrive on a letter, not on the space bar that
                        // happens to come first in traversal order.
                        autofocus: rowIndex == 0 && colIndex == 0,
                        focusNode: rowIndex == 0 && colIndex == 0
                            ? firstKeyFocus
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool autofocus;

  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.focusNode,
    this.semanticLabel,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TvFocusable(
      onTap: onTap,
      focusNode: focusNode,
      autofocus: autofocus,
      borderRadius: BorderRadius.zero,
      // A key that grew on focus would overlap its neighbours, and the panel
      // clips, so the growth would be sheared off on the outer columns.
      scaleOnFocus: false,
      filledWhenFocused: true,
      focusFillColor: cs.surfaceContainerHigh,
      builder: (context, isFocused) => Container(
        height: ShonenX.keyHeight,
        alignment: Alignment.center,
        color: isFocused ? Colors.transparent : cs.surface,
        child: icon != null
            ? Icon(
                icon,
                size: 26,
                color: cs.onSurface,
                semanticLabel: semanticLabel,
              )
            : Text(
                label!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}
