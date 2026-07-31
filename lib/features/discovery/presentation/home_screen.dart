import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/features/discovery/domain/models/home_section.dart';
import 'package:shonenx/features/discovery/presentation/widgets/continue/continue_media_row.dart';
import 'package:shonenx/features/discovery/presentation/widgets/hero/spotlight_carousel.dart';
import 'package:shonenx/features/discovery/presentation/widgets/rows/horizontal_section.dart';
import 'package:shonenx/features/discovery/presentation/widgets/rows/library_row.dart';
import 'package:shonenx/features/discovery/presentation/widgets/sheets/discovery_mode_sheet.dart';
import 'package:shonenx/features/discovery/providers/discovery_prefs_provider.dart';
import 'package:shonenx/features/discovery/providers/home_feed_provider.dart';
import 'package:shonenx/features/discovery/providers/home_layout_provider.dart';
import 'package:shonenx/features/library/providers/cloud_library_provider.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_category.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_type.dart';
import 'package:shonenx/features/tracking/providers/tracker_registry.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/providers/content_prefs_provider.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';
import 'package:shonenx/shared/widgets/tv/tv_poster_card.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/source_engine_provider.dart';
import 'package:shonenx/source_engine/source_registry.dart';

/// Top-level, not a field on the widget.
///
/// It used to be declared as an instance field of a ConsumerWidget that the
/// router constructs non-const, which minted a fresh provider family -- and so
/// a fresh cache -- on every reconstruction.
final categorySectionFeedProvider =
    FutureProvider.family<List<UnifiedMedia>, (TrackerCategory, MediaType)>((
      ref,
      arg,
    ) async {
      final category = arg.$1;
      final mediaType = arg.$2;
      final mode = ref.watch(discoveryPrefsProvider.select((p) => p.mode));

      if (mode == MetadataMode.tracker) {
        final tracker = ref.watch(metadataSourceProvider);
        final adultMode = ref.watch(contentPrefsProvider).adultContentMode;
        final result = await tracker.getCategoryItems(
          category,
          type: mediaType,
          adultMode: adultMode,
          cacheDuration: const Duration(hours: 12),
        );
        return result.items;
      } else {
        final allSources = await ref.watch(
          availableAnimeSourcesProvider.future,
        );
        final prefs = ref.watch(discoveryPrefsProvider);
        final activeSources = allSources
            .where((s) => prefs.activeSources.contains(s.id))
            .toList();
        if (activeSources.isEmpty) return const [];
        final sourceInfo = activeSources.first;
        final source = ref.read(animeSourceProvider(sourceInfo));
        var items = await source.getTrending();
        if (items.isEmpty) {
          items = await source.search('', mediaType);
        }
        return items;
      }
    });

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The header sits on top of the hero, so it can only be reached by an
  /// explicit hand-off -- see [SpotlightCarousel.onEscapeUp].
  final FocusNode _headerFocus = FocusNode(debugLabel: 'homeHeader');

  final ScrollController _scroll = ScrollController();

  /// The hero's first thumbnail. Directional traversal cannot find its way out
  /// of the first row's own traversal group, so up from there is handed over
  /// explicitly -- the same fallback the navigation rail uses.
  final FocusNode _heroFocus = FocusNode(debugLabel: 'heroEntry');

  @override
  void dispose() {
    _headerFocus.dispose();
    _heroFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Up from the first row lands on the hero.
  ///
  /// Let normal traversal try first; only claim the key when focus did not
  /// move, which is exactly the case at the top row.
  KeyEventResult _handleUp(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final before = FocusManager.instance.primaryFocus;
    if (before != null && before.focusInDirection(TraversalDirection.up)) {
      return KeyEventResult.handled;
    }
    if (_heroFocus.canRequestFocus) {
      _heroFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Returns the page to the top when focus comes back up to the hero, which
  /// is otherwise left half-scrolled behind the row the user came from.
  void _scrollToTop() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = ref.watch(userHomeLayoutProvider);
    final allActive = sections.where((s) => !s.disabled).toList();

    final discoveryCount = allActive
        .where((s) => s.type == HomeSectionType.discovery)
        .length;
    final heroSection = allActive
        .where((s) => s.type == HomeSectionType.discovery)
        .firstOrNull;

    // The hero already shows this feed, so it does not need a row of its own
    // as well -- unless it is the only discovery section there is, which is
    // the case in source mode, where dropping it would leave no rows at all.
    final activeSections = (discoveryCount > 1 && heroSection != null)
        ? allActive.where((s) => s.id != heroSection.id).toList()
        : allActive;

    return AppScaffold(
      // The hero reaches the panel edge; the rows below apply overscan
      // themselves via HorizontalSection.
      fullBleed: true,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(singleSourceFeedProvider);
          ref.invalidate(categorySectionFeedProvider);
          for (final section in sections) {
            if (section.type == HomeSectionType.libraryStatus &&
                section.libraryStatus != null &&
                section.targetTracker != TrackerType.local) {
              ref
                  .read(
                    cloudLibraryProvider((
                      status: section.libraryStatus!,
                      trackerType: section.targetTracker,
                      mediaType: section.targetMediaType ?? MediaType.ANIME,
                    )).notifier,
                  )
                  .refresh();
            }
          }
        },
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _handleUp,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    if (heroSection != null)
                      SpotlightCarousel(
                        data: ref.watch(
                          categorySectionFeedProvider((
                            heroSection.trackerCategory ??
                                TrackerCategory.trending,
                            heroSection.targetMediaType ?? MediaType.ANIME,
                          )),
                        ),
                        onEscapeUp: _headerFocus.requestFocus,
                        onEnter: _scrollToTop,
                        entryFocus: _heroFocus,
                      )
                    else
                      SizedBox(
                        height:
                            TvMetrics.verticalOfSize(
                              MediaQuery.sizeOf(context),
                            ) +
                            16,
                      ),
                    Positioned(
                      top:
                          TvMetrics.verticalOfSize(MediaQuery.sizeOf(context)) +
                          16,
                      right: ShonenXMetrics.of(
                        context,
                      ).shellGutter(MediaQuery.sizeOf(context)),
                      child: _HeaderActions(firstFocus: _headerFocus),
                    ),
                  ],
                ),
              ),
              // Breathing room between the hero and the first row heading. The
              // hero's bottom scrim already fades into the page, so without this
              // the heading reads as part of the hero rather than as the label
              // of the row under it.
              SliverToBoxAdapter(
                child: SizedBox(height: ShonenXMetrics.of(context).body * 2.5),
              ),
              ...() {
                final discoveryIndexMap = <MediaType, int>{};
                final totalDiscoveryCounts = <MediaType, int>{};
                for (final s in activeSections) {
                  if (s.type == HomeSectionType.discovery) {
                    final mt = s.targetMediaType ?? MediaType.ANIME;
                    totalDiscoveryCounts[mt] =
                        (totalDiscoveryCounts[mt] ?? 0) + 1;
                  }
                }

                return activeSections.map((section) {
                  int? dIndex;
                  int totalCount = 0;
                  if (section.type == HomeSectionType.discovery) {
                    final mt = section.targetMediaType ?? MediaType.ANIME;
                    dIndex = discoveryIndexMap[mt] ?? 0;
                    discoveryIndexMap[mt] = dIndex + 1;
                    totalCount = totalDiscoveryCounts[mt] ?? 1;
                  }

                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: _buildSectionWidget(
                        context,
                        section,
                        discoveryIndex: dIndex,
                        totalDiscoverySections: totalCount,
                      ),
                    ),
                  );
                });
              }(),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      TvMetrics.verticalOfSize(MediaQuery.sizeOf(context)) + 40,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionWidget(
    BuildContext context,
    HomeSection section, {
    int? discoveryIndex,
    int totalDiscoverySections = 1,
  }) {
    final mediaType = section.targetMediaType ?? MediaType.ANIME;

    switch (section.type) {
      case HomeSectionType.continueMedia:
        return ContinueMediaRow(title: section.title, type: mediaType);

      case HomeSectionType.libraryStatus:
        if (section.libraryStatus == null) return const SizedBox.shrink();

        return Consumer(
          builder: (context, ref, _) {
            final activeTracker = section.targetTracker != null
                ? ref
                      .watch(availableTrackersProvider)
                      .firstWhere((t) => t.type == section.targetTracker!)
                : ref.watch(primaryTrackerProvider);

            return LibraryRow(
              title: section.title,
              status: section.libraryStatus!,
              targetTracker: activeTracker.type,
              targetMediaType: mediaType,
            );
          },
        );

      case HomeSectionType.discovery:
        return _buildDiscoverySectionRow(
          context,
          section,
          discoveryIndex: discoveryIndex,
          totalDiscoverySections: totalDiscoverySections,
        );
    }
  }

  Widget _buildDiscoverySectionRow(
    BuildContext context,
    HomeSection section, {
    int? discoveryIndex,
    int totalDiscoverySections = 1,
  }) {
    final mediaType = section.targetMediaType ?? MediaType.ANIME;
    final category = section.trackerCategory ?? TrackerCategory.trending;

    return Consumer(
      builder: (context, ref, _) {
        final prefs = ref.watch(discoveryPrefsProvider);
        if (prefs.mode == MetadataMode.source) {
          return _buildSourceSectionRows(
            context,
            ref,
            mediaType,
            prefs,
            discoveryIndex ?? 0,
            totalDiscoverySections,
          );
        }

        final m = ShonenXMetrics.of(context);
        return HorizontalSection<UnifiedMedia>(
          title: section.title,
          height: TvPosterCard.rowExtent(context, width: m.rowPoster),
          gap: m.rowGap,
          data: ref.watch(categorySectionFeedProvider((category, mediaType))),
          skeletonItemBuilder: (context, index) =>
              TvPosterCard(imageUrl: null, width: m.rowPoster),
          itemBuilder: (context, item) => TvPosterCard(
            width: m.rowPoster,
            heroTag: '${section.id}-${item.id}',
            title: item.title.availableTitle,
            imageUrl: item.cover ?? item.banner,
            onTap: () => context.push(
              '/details/${item.type.id}?tag=${section.id}-${item.id}',
              extra: item,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceSectionRows(
    BuildContext context,
    WidgetRef ref,
    MediaType mediaType,
    DiscoveryPrefs prefs,
    int discoveryIndex,
    int totalDiscoverySections,
  ) {
    final allSourcesAsync = ref.watch(availableAnimeSourcesProvider);

    return allSourcesAsync.when(
      data: (allSources) {
        final activeSources = allSources
            .where((s) => prefs.activeSources.contains(s.id))
            .toList();

        if (activeSources.isEmpty) {
          return const SizedBox.shrink();
        }

        if (totalDiscoverySections <= 1) {
          return Column(
            children: activeSources
                .map(
                  (info) =>
                      _buildSingleSourceRow(context, ref, info, info.name),
                )
                .toList(),
          );
        }

        if (discoveryIndex >= activeSources.length) {
          return const SizedBox.shrink();
        }

        final info = activeSources[discoveryIndex];
        return _buildSingleSourceRow(context, ref, info, info.name);
      },
      loading: () {
        final m = ShonenXMetrics.of(context);
        return Column(
          children: List.generate(
            2,
            (sIndex) => HorizontalSection<UnifiedMedia>(
              title: 'Loading',
              height: TvPosterCard.rowExtent(context, width: m.rowPoster),
              gap: m.rowGap,
              data: const AsyncValue.loading(),
              itemBuilder: (_, __) => const SizedBox.shrink(),
              skeletonItemBuilder: (context, index) =>
                  TvPosterCard(imageUrl: null, width: m.rowPoster),
            ),
          ),
        );
      },
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSingleSourceRow(
    BuildContext context,
    WidgetRef ref,
    SourceInfo info,
    String title,
  ) {
    final m = ShonenXMetrics.of(context);
    return HorizontalSection<UnifiedMedia>(
      title: title,
      height: TvPosterCard.rowExtent(context, width: m.rowPoster),
      gap: m.rowGap,
      data: ref.watch(singleSourceFeedProvider((info, MediaType.ANIME))),
      skeletonItemBuilder: (context, index) =>
          TvPosterCard(imageUrl: null, width: m.rowPoster),
      itemBuilder: (context, item) => TvPosterCard(
        width: m.rowPoster,
        heroTag: '$title-${item.id}',
        title: item.title.availableTitle,
        imageUrl: item.cover ?? item.banner,
        onTap: () => context.push(
          '/details/${item.type.id}?tag=$title-${item.id}',
          extra: item,
        ),
      ),
    );
  }
}

/// Discovery mode and Settings, kept in the top-right corner.
class _HeaderActions extends ConsumerWidget {
  final FocusNode firstFocus;

  const _HeaderActions({required this.firstFocus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(discoveryPrefsProvider.select((p) => p.mode));
    final isTracker = mode == MetadataMode.tracker;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderButton(
          focusNode: firstFocus,
          icon: isTracker ? Icons.cloud_outlined : Icons.extension_outlined,
          active: isTracker,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            useRootNavigator: true,
            builder: (_) => const DiscoveryModeSheet(),
          ),
        ),
        const SizedBox(width: 16),
        _HeaderButton(
          icon: Icons.settings_outlined,
          onTap: () => context.push('/settings'),
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final FocusNode? focusNode;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TvFocusable(
      onTap: onTap,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(12),
      scaleOnFocus: false,
      builder: (context, isFocused) => Container(
        width: ShonenXMetrics.of(context).iconButton * 1.35,
        height: ShonenXMetrics.of(context).iconButton * 1.35,
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.18)
              : cs.surfaceContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          // Deliberately smaller than the detail screen's icons: these sit in
          // the corner as chrome, not as part of the content.
          size: ShonenXMetrics.of(context).iconButton * 0.72,
          color: isFocused || active ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
