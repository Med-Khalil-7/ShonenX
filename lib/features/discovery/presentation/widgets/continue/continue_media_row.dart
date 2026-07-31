import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/shared/providers/ui_prefs_provider.dart';
import 'package:shonenx/features/discovery/presentation/widgets/continue/continue_watching_card.dart';
import 'package:shonenx/features/discovery/presentation/widgets/rows/horizontal_section.dart';
import 'package:shonenx/features/history/domain/models/watch_history_entry.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/shared/models/unified_media.dart';

class ContinueMediaRow extends ConsumerWidget {
  final String title;
  final MediaType type;

  const ContinueMediaRow({super.key, required this.title, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(continueWatchingPerAnimeProvider(10));

    if (asyncData.value?.isEmpty == true) {
      return const SizedBox.shrink();
    }

    final cwStyle = ref.watch(
      uiPrefsProvider.select((p) => p.continueWatchingStyle),
    );
    final isCwWide = ref.watch(
      uiPrefsProvider.select((p) => p.isContinueWatchingWide(cwStyle.name)),
    );

    // The card styles carry their own pixel sizes, tuned for a phone, and a
    // continue card came out over twice as wide as the poster beside it --
    // the row read as a different, louder screen sitting on top of Home.
    //
    // Width is what is scaled rather than height: the cards are landscape and
    // the posters portrait, so matching heights would make the cards wider
    // still. At 1.55 posters wide a card is clearly the bigger item without
    // dominating, and the row's height follows from it.
    final m = ShonenXMetrics.of(context);
    final layout = cwStyle.getLayout(
      isContinueWatching: true,
      isWideMode: isCwWide,
    );
    final cardScale = layout.width == 0
        ? 1.0
        : (m.rowPoster * 1.55) / layout.width;
    final rowHeight = layout.height * cardScale;

    return HorizontalSection(
      title: title,
      height: rowHeight,
      emptyText: 'No anime in this list.',
      data: asyncData,
      onMoreTap: () => context.push('/continue/${type.id}'),
      itemBuilder: (context, dynamic entry) {
        final watchEntry = entry as WatchHistoryEntry;
        final progress = watchEntry.durationInMilliseconds == 0
            ? 0.0
            : watchEntry.positionInMilliseconds /
                  watchEntry.durationInMilliseconds;

        return ContinueWatchingItem(
          entry: watchEntry,
          progress: progress,
          style: cwStyle,
          scale: cardScale,
        );
      },
    );
  }
}
