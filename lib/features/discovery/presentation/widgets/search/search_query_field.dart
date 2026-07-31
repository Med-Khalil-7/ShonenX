import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';

/// Display-only query box.
///
/// Deliberately not a `TextField`: any focusable editable summons the leanback
/// IME, which covers the screen and returns focus somewhere unpredictable.
/// Text arrives from [TvOnScreenKeyboard] instead, so this only has to render.
class SearchQueryField extends StatefulWidget {
  final String text;
  final String hint;
  final double height;

  const SearchQueryField({
    super.key,
    required this.text,
    this.hint = 'Search',
    required this.height,
  });

  @override
  State<SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<SearchQueryField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEmpty = widget.text.isEmpty;

    return Container(
      height: widget.height,
      padding: EdgeInsets.symmetric(horizontal: widget.height * 0.36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShonenX.searchFieldRadius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              isEmpty ? widget.hint : widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                fontSize: widget.height * 0.42,
              ),
            ),
          ),
          if (!isEmpty) ...[
            const SizedBox(width: 2),
            FadeTransition(
              opacity: _blink,
              child: Container(
                width: 2,
                height: widget.height * 0.5,
                color: cs.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
