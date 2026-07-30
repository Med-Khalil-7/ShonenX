import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

class TvNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Shell branch index, or null for a destination that pushes a route
  /// outside the shell (Settings).
  final int? branchIndex;

  /// Route to push when [branchIndex] is null.
  final String? route;

  const TvNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.branchIndex,
    this.route,
  });
}

const tvDestinations = <TvNavDestination>[
  TvNavDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
    branchIndex: 0,
  ),
  TvNavDestination(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    label: 'Search',
    branchIndex: 1,
  ),
  TvNavDestination(
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
    label: 'Library',
    branchIndex: 2,
  ),
  // Settings lives outside the shell, but on a TV it needs to be reachable
  // from the rail: previously the only way in was a header button on Home,
  // which is an awkward first focus stop.
  TvNavDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Settings',
    route: '/settings',
  ),
];

/// Google TV style navigation rail: a column of icons that expands to show
/// labels while anything inside it holds focus.
///
/// It is drawn as an overlay on top of the content rather than taking part in
/// a Row. Expanding a Row member would relayout every lazy list in the branch
/// on each expansion, which a TV SoC cannot absorb smoothly.
class TvSideRail extends StatefulWidget {
  static const double collapsedWidth = 88;
  static const double expandedWidth = 280;

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

class _TvSideRailState extends State<TvSideRail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: _expanded
              ? TvSideRail.expandedWidth
              : TvSideRail.collapsedWidth,
          decoration: BoxDecoration(
            // Opaque, not blurred: BackdropFilter is the single most
            // expensive thing you can put in a TV shell.
            color: _expanded ? cs.surfaceContainerHigh : Colors.transparent,
            // BorderSide.none rather than a transparent side: a side still
            // occupies its width even when invisible, and at the collapsed
            // width that 1px is exactly enough to overflow the item row.
            border: Border(
              right: _expanded
                  ? BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    )
                  : BorderSide.none,
            ),
          ),
          child: SafeArea(
            right: false,
            minimum: const EdgeInsets.symmetric(vertical: 24),
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  for (var i = 0; i < tvDestinations.length; i++) ...[
                    if (tvDestinations[i].route == '/settings') const Spacer(),
                    FocusTraversalOrder(
                      order: NumericFocusOrder(i.toDouble()),
                      child: _RailItem(
                        destination: tvDestinations[i],
                        selected:
                            tvDestinations[i].branchIndex ==
                            widget.currentIndex,
                        expanded: _expanded,
                        onPressed: () =>
                            widget.onSelected(tvDestinations[i]),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
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
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final Color background;
    final Color foreground;
    if (_focused) {
      background = cs.primary;
      foreground = cs.onPrimary;
    } else if (widget.selected) {
      background = cs.surfaceContainerHighest;
      foreground = cs.onSurface;
    } else {
      background = Colors.transparent;
      foreground = cs.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        child: Builder(
          builder: (context) {
            return GestureDetector(
              onTap: widget.onPressed,
              child: Actions(
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      widget.onPressed();
                      return null;
                    },
                  ),
                },
                child: AnimatedContainer(
                  duration: TvFocus.animation,
                  curve: TvFocus.curve,
                  height: 64,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: TvSideRail.collapsedWidth - 24,
                        child: Icon(
                          widget.selected
                              ? widget.destination.selectedIcon
                              : widget.destination.icon,
                          size: 30,
                          color: foreground,
                        ),
                      ),
                      // Labels read horizontally. The old rail rotated them
                      // 90 degrees, which is unreadable across a room.
                      if (widget.expanded)
                        Expanded(
                          child: Text(
                            widget.destination.label,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: text.titleMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
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
          padding: const EdgeInsets.only(
            left: TvSideRail.collapsedWidth,
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
                  final moved = before?.focusInDirection(
                        TraversalDirection.left,
                      ) ??
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
                // Focus back into content; the rail collapses as a side
                // effect of losing focus.
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
