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

/// Navigation rail with the app mark at the top and a red bar at the screen's
/// edge marking the active branch.
///
/// Icon-only at rest; taking focus expands it to show each destination's
/// label. The expansion is drawn **over** the branch content -- `TvShellBody`
/// pads the content by the *collapsed* width and never changes it -- so
/// nothing below reflows. An earlier version widened the content padding
/// instead, which relaid out every lazy list in the branch on each expansion,
/// a cost a TV SoC cannot absorb smoothly.
class TvSideRail extends StatefulWidget {
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

  @override
  State<TvSideRail> createState() => _TvSideRailState();
}

/// How much of the expanded panel an item occupies.
///
/// One number rather than two so the panel's opaque region and the item's
/// width cannot drift apart: the item must always sit inside the solid part,
/// or the focus plate appears to hang off the panel onto the content.
const double _railItemFraction = 0.86;

class _TvSideRailState extends State<TvSideRail> {
  bool _expanded = false;

  int get _selectedItem =>
      tvDestinations.indexWhere((d) => d.branchIndex == widget.currentIndex);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = ShonenXMetrics.of(context);
    final verticalInset = TvMetrics.verticalOfSize(MediaQuery.sizeOf(context));
    final itemGap = m.railItem * 0.25;
    final width = _expanded ? m.railExpandedWidth : m.railWidth;

    return FocusScope(
      node: widget.scopeNode,
      child: Focus(
        // Reports descendant focus without becoming a focus stop itself.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (_expanded != hasFocus) setState(() => _expanded = hasFocus);
        },
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // Right always returns to content. Geometry would usually do this,
          // but being explicit means it works from any item and never lands
          // somewhere surprising.
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onEscapeRight();
            return KeyEventResult.handled;
          }
          // Nothing is left of the rail; swallow so focus does not jump
          // across to the far edge of the content.
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: TvFocus.animation,
          curve: TvFocus.curve,
          width: width,
          // Expanded, the panel is opaque behind every item and fades out only
          // over the strip to their right, so it reads over artwork without a
          // hard vertical seam. The opaque region has to clear the widest item
          // (see [_railItemFraction]) -- fading earlier left the focused row
          // hanging off the edge of its own panel.
          //
          // Collapsed it draws nothing at all: the icons sit directly on the
          // branch content, as they always have.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _expanded
                  ? [ShonenX.bg, ShonenX.bg, ShonenX.bg.withValues(alpha: 0)]
                  : const [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x00000000),
                    ],
              stops: const [0, _railItemFraction, 1],
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: verticalInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: m.railLogo * 0.43),
                    // Brand mark, never a focus stop -- a remote should not
                    // have to step over decoration to reach a destination.
                    Padding(
                      padding: EdgeInsets.only(left: m.railItemInset),
                      child: const ExcludeFocus(child: _RailLogo()),
                    ),
                    Expanded(
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < tvDestinations.length; i++)
                              FocusTraversalOrder(
                                order: NumericFocusOrder(i.toDouble()),
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: m.railItemInset,
                                    top: itemGap / 2,
                                    bottom: itemGap / 2,
                                  ),
                                  child: _RailItem(
                                    destination: tvDestinations[i],
                                    selected: i == _selectedItem,
                                    expanded: _expanded,
                                    onPressed: () =>
                                        widget.onSelected(tvDestinations[i]),
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
                Positioned.fill(
                  child: IgnorePointer(
                    child: _RailIndicator(
                      selectedItem: _selectedItem,
                      itemCount: tvDestinations.length,
                      topOffset:
                          verticalInset + m.railLogo * 0.43 + m.railLogo,
                      bottomOffset: verticalInset,
                      itemPitch: m.railItem + itemGap,
                      indicator: m.railIndicator,
                      color: cs.primary,
                    ),
                  ),
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
    final m = ShonenXMetrics.of(context);
    return Container(
      width: m.railLogo,
      height: m.railLogo,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(ShonenX.railLogoRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/app_icon.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: m.railIcon,
        ),
      ),
    );
  }
}

/// Slides between items rather than cross-fading, which reads as one object
/// moving instead of two blinking.
///
/// Mirrors the item column's geometry rather than living inside it: the bar
/// has to sit flush against the screen edge, and the items are inset from it.
class _RailIndicator extends StatelessWidget {
  final int selectedItem;
  final int itemCount;

  /// Space above and below the region the items are centred in.
  final double topOffset;
  final double bottomOffset;

  /// Item box plus the padding above and below it.
  final double itemPitch;
  final Size indicator;

  final Color color;

  const _RailIndicator({
    required this.selectedItem,
    required this.itemCount,
    required this.topOffset,
    required this.bottomOffset,
    required this.itemPitch,
    required this.indicator,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final regionHeight = constraints.maxHeight - topOffset - bottomOffset;
        // Items are centred as a group, so the first starts half a stack above
        // the midpoint of that region.
        final firstTop = (regionHeight - itemCount * itemPitch) / 2;
        final top =
            topOffset +
            firstTop +
            selectedItem * itemPitch +
            (itemPitch - indicator.height) / 2;

        // The AnimatedPositioned needs a Stack of its own: LayoutBuilder
        // breaks the parent-child relationship a Stack requires, so placing it
        // directly in the rail's Stack pinned it to the corner.
        return Stack(
          children: [
            AnimatedPositioned(
              duration: TvFocus.animation,
              curve: TvFocus.curve,
              left: 0,
              top: top,
              child: Container(
                width: indicator.width,
                height: indicator.height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(indicator.width),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One destination: icon at rest, icon plus label once the rail expands.
///
/// The icon holds its position through the animation -- it is the fixed part
/// of the row and the label is what arrives -- so the expansion reads as text
/// appearing rather than the whole rail sliding.
class _RailItem extends StatelessWidget {
  final TvNavDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onPressed;

  const _RailItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);

    // Icon plus the longest label, kept inside the panel's opaque region and
    // clear of the inset it already carries on the left.
    final expandedWidth =
        m.railExpandedWidth * _railItemFraction - m.railItemInset * 2;

    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(m.railItem * 0.25),
      scaleOnFocus: false,
      // The rail is narrow; a ring would crowd the icon. Focus reads as a
      // filled plate instead, and red stays reserved for the edge indicator.
      ringColor: Colors.transparent,
      filledWhenFocused: true,
      focusFillColor: cs.surfaceContainer,
      builder: (context, isFocused) {
        // The selected destination reads red so the rail says where you are
        // even before the edge indicator is in view.
        final color = selected
            ? cs.primary
            : (isFocused ? cs.onSurface : cs.onSurfaceVariant);

        return AnimatedContainer(
          duration: TvFocus.animation,
          curve: TvFocus.curve,
          width: expanded ? expandedWidth : m.railItem,
          height: m.railItem,
          child: Row(
            children: [
              SizedBox(
                width: m.railItem,
                child: Icon(destination.icon, size: m.railIcon, color: color),
              ),
              if (expanded)
                // Clipped, not wrapped: mid-animation the row is narrower than
                // the text and a wrapping label would jump to two lines and
                // back.
                Expanded(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      maxWidth: expandedWidth,
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: m.label,
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
          padding: EdgeInsets.only(
            left: ShonenXMetrics.of(context).railWidth,
          ),
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
