import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/features/discovery/presentation/widgets/search/search_result_row.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/source_engine/models/paginated_result.dart';

/// Vertical results list. Shares its pagination contract with
/// [PaginatedMediaGrid]; only the item shape differs.
///
/// A list rather than a grid because the search screen gives half its width to
/// the keyboard: a grid in the remaining column would be two narrow cards
/// wide, and the synopsis line -- the thing that tells two similarly-named
/// entries apart -- would not fit at all.
class PaginatedMediaList extends ConsumerWidget {
  final AsyncValue<PaginatedResult<UnifiedMedia>?> state;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final VoidCallback onAutoLoad;

  const PaginatedMediaList({
    super.key,
    required this.state,
    required this.scrollController,
    required this.isLoadingMore,
    required this.onAutoLoad,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 16),
          child: Text(
            'Results',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (result) {
              if (result == null || result.items.isEmpty) {
                return Center(
                  child: Text(
                    'No results found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!scrollController.hasClients) return;
                // A first page that does not fill the viewport leaves the
                // scroll listener with nothing to fire on, so the list would
                // never page again.
                if (scrollController.position.maxScrollExtent == 0 &&
                    result.hasNextPage &&
                    !isLoadingMore) {
                  onAutoLoad();
                }
              });

              return Stack(
                children: [
                  ListView.separated(
                    controller: scrollController,
                    // Directional traversal can only reach nodes that have
                    // been built; without a generous cache the list dead-ends
                    // at the edge of the viewport.
                    cacheExtent: 1600,
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: result.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final media = result.items[index];
                      return SearchResultRow(
                        media: media,
                        onTap: () => context.push(
                          '/details/${media.type.id}?tag=search-${media.id}',
                          extra: media,
                        ),
                      );
                    },
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    bottom: isLoadingMore ? 40 : -60,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
