import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

class TvNavDestination {
  final IconData icon;
  final String label;

  /// Shell branch index, or null for a destination that pushes a route
  /// outside the shell.
  final int? branchIndex;

  /// Route to push when [branchIndex] is null.
  final String? route;

  const TvNavDestination({
    required this.icon,
    required this.label,
    this.branchIndex,
    this.route,
  });
}

/// Search leads: it is the thing a user reaches for most on a TV, where
/// browsing is slow and typing is slower still.
///
/// Settings deliberately is not here -- it lives as a button in the top-right
/// of Home.
const tvDestinations = <TvNavDestination>[
  TvNavDestination(
    icon: Icons.search_rounded,
    label: 'Search',
    branchIndex: 1,
  ),
  TvNavDestination(icon: Icons.home_rounded, label: 'Home', branchIndex: 0),
  TvNavDestination(
    icon: Icons.bolt_rounded,
    label: 'Library',
    branchIndex: 2,
  ),
];

/// Icon-only navigation rail with the app mark at the top and a red bar at the
/// screen's edge marking the active branch.
///
/// Drawn as an overlay rather than as a Row member. It used to expand on
/// focus, which meant every lazy list in the branch relaid out on each
/// expansion -- a cost a TV SoC cannot absorb smoothly. At a fixed width the
/// content padding is constant and nothing below it ever reflows.
class TvSideRail extends StatelessWidget {
  static const double width = ShonenX.railWidth;

  final int currentIndex;
  final ValueChanged<TvNavDestination> onSelected;

  /// Called when focus tries to leave the rail to the right.
  final VoidCallback onEscapeRight;

  final FocusScopeNode scopeNode;

  const TvSideRail({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.onEscapeRight,
    required this.scopeNode,
  });

  int get _selectedItem =>
      tvDestinations.indexWhere((d) => d.branchIndex == currentIndex);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final verticalInset = TvMetrics.verticalOfSize(MediaQuery.sizeOf(context));

    return FocusScope(
      node: scopeNode,
      child: Focus(
        // Reports descendant focus without becoming a focus stop itself.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // Right always returns to content. Geometry would usually do this,
          // but being explicit means it works from any item and never lands
          // somewhere surprising.
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            onEscapeRight();
            return KeyEventResult.handled;
          }
          // Nothing is left of the rail; swallow so focus does not jump
          // across to the far edge of the content.
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          width: TvSideRail.width,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: verticalInset),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Brand mark, never a focus stop -- a remote should not
                    // have to step over decoration to reach a destination.
                    const ExcludeFocus(child: _RailLogo()),
                    Expanded(
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < tvDestinations.length; i++)
                              FocusTraversalOrder(
                                order: NumericFocusOrder(i.toDouble()),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: _RailItem(
                                    destination: tvDestinations[i],
                                    selected: i == _selectedItem,
                                    onPressed: () =>
                                        onSelected(tvDestinations[i]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The indicator rides the screen edge rather than sitting inside
              // the item, so it stays visible even when the rail is drawn over
              // bright artwork.
              if (_selectedItem >= 0)
                _RailIndicator(
                  selectedItem: _selectedItem,
                  itemCount: tvDestinations.length,
                  color: cs.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailLogo extends StatelessWidget {
  const _RailLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ShonenX.railLogoSize,
      height: ShonenX.railLogoSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(ShonenX.railLogoRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/app_icon.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}

/// Slides between items rather than cross-fading, which reads as one object
/// moving instead of two blinking.
class _RailIndicator extends StatelessWidget {
  final int selectedItem;
  final int itemCount;
  final Color color;

  const _RailIndicator({
    required this.selectedItem,
    required this.itemCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const itemPitch = ShonenX.railItemSize + 16; // item + vertical padding

    return LayoutBuilder(
      builder: (context, constraints) {
        // Items are centred as a group, so the first one starts half a stack
        // above the midpoint.
        final stackHeight = itemCount * itemPitch;
        final firstTop = (constraints.maxHeight - stackHeight) / 2;
        final top =
            firstTop +
            selectedItem * itemPitch +
            (itemPitch - ShonenX.railIndicator.height) / 2;

        return AnimatedPositioned(
          duration: TvFocus.animation,
          curve: TvFocus.curve,
          left: 0,
          top: top,
          child: Container(
            width: ShonenX.railIndicator.width,
            height: ShonenX.railIndicator.height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  final TvNavDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      scaleOnFocus: false,
      // The rail is narrow; a ring would crowd the icon. Focus reads as a
      // filled plate instead, and red stays reserved for the edge indicator.
      ringColor: Colors.transparent,
      filledWhenFocused: true,
      focusFillColor: cs.surfaceContainer,
      builder: (context, isFocused) => Container(
        width: ShonenX.railItemSize,
        height: ShonenX.railItemSize,
        alignment: Alignment.center,
        child: Icon(
          destination.icon,
          size: ShonenX.railIconSize,
          color: isFocused || selected ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Rail overlaid on the branch content.
class TvShellBody extends StatefulWidget {
  final Widget content;
  final int currentIndex;
  final ValueChanged<TvNavDestination> onSelected;

  const TvShellBody({
    super.key,
    required this.content,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  State<TvShellBody> createState() => _TvShellBodyState();
}

class _TvShellBodyState extends State<TvShellBody> {
  final FocusScopeNode _railScope = FocusScopeNode(debugLabel: 'tvRail');
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'tvContent');

  @override
  void dispose() {
    _railScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  /// A FocusScopeNode restores its own focusedChild, so returning to content
  /// lands exactly where it left -- no bookkeeping required.
  void _focusContent() => _contentScope.requestFocus();

  void _focusRail() => _railScope.requestFocus();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: TvSideRail.width),
          child: FocusScope(
            node: _contentScope,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                // Left from the leftmost content column opens the rail. Let
                // normal traversal try first; only claim the key if focus did
                // not move.
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  final before = FocusManager.instance.primaryFocus;
                  final moved =
                      before?.focusInDirection(TraversalDirection.left) ??
                      false;
                  if (!moved) {
                    _focusRail();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: widget.content,
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: TvSideRail(
            scopeNode: _railScope,
            currentIndex: widget.currentIndex,
            onSelected: (d) {
              widget.onSelected(d);
              if (d.branchIndex != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _focusContent(),
                );
              }
            },
            onEscapeRight: _focusContent,
          ),
        ),
      ],
    );
  }
}

/// Handles the TV remote BACK button.
///
/// Android delivers BACK as a platform pop rather than a key event, so
/// PopScope is the reliable mechanism -- LogicalKeyboardKey.goBack only
/// arrives from some remotes.
class TvBackHandler extends StatelessWidget {
  final Widget child;
  final bool Function() onBack;

  const TvBackHandler({super.key, required this.child, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!onBack()) {
          // Nothing left to unwind: leave the app rather than trapping the
          // user on Home with a dead BACK button.
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      },
      child: child,
    );
  }
}
