import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:skeletonizer/skeletonizer.dart';

class HorizontalSection<T> extends StatelessWidget {
  final String title;
  final AsyncValue<List<T>> data;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final double height;
  final String emptyText;
  final double? gap;
  final VoidCallback? onMoreTap;
  final Widget Function(BuildContext context, int index)? skeletonItemBuilder;
  final int skeletonCount;

  const HorizontalSection({
    super.key,
    required this.title,
    required this.data,
    required this.itemBuilder,
    required this.height,
    this.gap,
    this.emptyText = 'No data found',
    this.onMoreTap,
    this.skeletonItemBuilder,
    this.skeletonCount = 12,
  });

  @override
  Widget build(BuildContext context) {
    // The gutter lives on the list's own padding rather than an outer Padding,
    // so items scroll under the safe edge instead of having their focus ring
    // clipped at the first and last position.
    final m = ShonenXMetrics.of(context);
    final edge = m.shellGutter(MediaQuery.sizeOf(context));
    // Cards carry a focus ring drawn as a Border, which occupies its width
    // even when transparent, so each one is already ringWidth wider on both
    // sides than the art inside it. Deduct that or the visible gap comes out
    // at roughly three times what was asked for.
    final separator = math.max(
      0.0,
      (gap ?? m.rowGap) - TvFocus.ringWidth * 2,
    );

    // Each row is its own traversal group: left/right stay inside the row and
    // up/down move between rows, instead of the geometric policy wandering
    // diagonally into a neighbouring row's items.
    return FocusTraversalGroup(
      child: Padding(
        // The gap below a row belongs to the row. Home used to add it around
        // every section from the outside, so a section that had nothing to
        // show and collapsed itself still left its gap behind -- an empty
        // Continue Watching pushed the first category down by a row's margin.
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: edge,
                right: edge,
                top: 8,
                bottom: 12,
              ),
              // No "see all" affordance: it is an extra focus stop between the
              // heading and the row it labels, and everything it leads to is
              // reachable by scrolling the row itself.
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: m.heading,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              height: height,
              child: data.when(
                loading: () => Skeletonizer(
                  enabled: true,
                  child: ListView.separated(
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: edge),
                    itemCount: skeletonCount,
                    itemBuilder: (context, index) {
                      if (skeletonItemBuilder != null) {
                        return skeletonItemBuilder!(context, index);
                      }
                      return Container(
                        width: height * 0.7,
                        height: height,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        SizedBox(width: separator),
                  ),
                ),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        emptyText,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.separated(
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: edge),
                    // Directional traversal can only reach focus nodes that have
                    // actually been built. Without a generous cache the row simply
                    // dead-ends at the edge of the viewport.
                    cacheExtent: 700,
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        itemBuilder(context, items[index]),
                    separatorBuilder: (context, index) =>
                        SizedBox(width: separator),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
