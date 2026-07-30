import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

    final layoutHeight = cwStyle
        .getLayout(isContinueWatching: true, isWideMode: isCwWide)
        .height;

    return HorizontalSection(
      title: title,
      height: layoutHeight,
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
        );
      },
    );
  }
}
