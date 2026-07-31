import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/discovery/presentation/widgets/sheets/manual_match_sheet.dart';
import 'package:shonenx/features/discovery/providers/episodes_provider.dart';
import 'package:shonenx/features/discovery/providers/matched_media_provider.dart';
import 'package:shonenx/features/discovery/providers/media_preference_provider.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/app_bottom_sheet.dart';
import 'package:shonenx/shared/widgets/source_selector_list.dart';
import 'package:shonenx/shared/widgets/tv/tv_button.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/utils/media_type_extensions.dart';

/// Which source an entry matched to, and the two escape hatches for when it
/// matched wrong.
///
/// This used to sit at the top of the Episodes tab. That tab is gone, but the
/// controls are not optional -- a bad title match is the single most common
/// reason episodes fail to load, and without these there is no way to correct
/// it from a remote.
class EpisodeSourceHeader extends ConsumerWidget {
  final UnifiedMedia media;

  const EpisodeSourceHeader({super.key, required this.media});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = media.title.availableTitle;

    final availableSources =
        ref.watch(media.type.availableSourcesProvider).value ?? [];
    if (availableSources.isEmpty) return const SizedBox.shrink();

    final matchArgs = MediaArgs.fromMedia(media);
    final sourceState = ref.watch(mediaPreferenceProvider(matchArgs)).value;
    final matchedMediaState = ref.watch(matchedMediaProvider(matchArgs));

    final hasError = matchedMediaState.hasError;
    final String matchedTitle;
    if (hasError) {
      matchedTitle = 'Failed to match';
    } else if (matchedMediaState.isLoading) {
      matchedTitle = 'Searching...';
    } else {
      matchedTitle =
          matchedMediaState.value?.matchedMedia?.title ?? 'No match found';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                hasError ? 'ERROR' : 'MATCHED',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hasError ? cs.error : cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '· ${sourceState?.sourceInfo.name ?? 'Unknown'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Title and its two escape hatches share a line: stacked, they cost
          // the episode grid a whole row of squares for no added clarity.
          Row(
            children: [
              Expanded(
                child: Text(
                  matchedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasError ? cs.error : cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              TvButton(
                label: 'Source',
                icon: Icons.swap_horiz_rounded,
                height: 48,
                variant: TvButtonVariant.filledSurface,
                onPressed: () => _showSourceSelector(
                  context,
                  ref,
                  availableSources,
                  sourceState?.sourceInfo,
                  matchArgs,
                ),
              ),
              const SizedBox(width: 12),
              TvButton(
                label: 'Fix match',
                icon: Icons.help_outline_rounded,
                height: 48,
                variant: TvButtonVariant.filledSurface,
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  useRootNavigator: true,
                  builder: (_) => ManualMatchSheet(
                    mediaTitle: title,
                    type: media.type,
                    matchArgs: matchArgs,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _invalidateMatch(WidgetRef ref, MediaArgs matchArgs) {
    ref.invalidate(matchedMediaProvider(matchArgs));
    ref.invalidate(episodesListProvider(matchArgs));
    if (media.sourceId != null) {
      ref.invalidate(
        sourceEpisodesProvider((
          providerId: media.id,
          sourceId: media.sourceId!,
          type: media.type,
        )),
      );
    }
  }

  void _showSourceSelector(
    BuildContext context,
    WidgetRef ref,
    List<SourceInfo> availableSources,
    SourceInfo? currentSource,
    MediaArgs matchArgs,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Select Source',
        child: SourceSelectorList(
          availableSources: availableSources,
          currentSource: currentSource,
          mediaType: media.type,
          onSourceSelected: (context, source) {
            ref
                .read(mediaPreferenceProvider(matchArgs).notifier)
                .updateSource(source);
            _invalidateMatch(ref, matchArgs);
            Navigator.pop(sheetContext);
          },
          onSettingsClosed: () => _invalidateMatch(ref, matchArgs),
        ),
      ),
    );
  }
}

/// Shown in place of the episode list when nothing can supply episodes.
class NoExtensionsPlaceholder extends StatelessWidget {
  const NoExtensionsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer,
              ),
              child: Icon(
                Icons.extension_off_rounded,
                size: 30,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No extensions installed',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Install an extension to start streaming episodes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            TvButton(
              label: 'Get Extensions',
              icon: Icons.extension_rounded,
              autofocus: true,
              onPressed: () => context.push('/settings/extensions'),
            ),
          ],
        ),
      ),
    );
  }
}
