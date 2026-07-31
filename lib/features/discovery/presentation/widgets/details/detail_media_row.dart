import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/features/discovery/presentation/widgets/rows/horizontal_section.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/tv/tv_poster_card.dart';

/// Relations / recommendations row on the detail screen.
class DetailMediaRow extends StatelessWidget {
  final String title;
  final List<UnifiedMedia> items;
  final String tagPrefix;

  const DetailMediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.tagPrefix,
  });

  @override
  Widget build(BuildContext context) {
    return HorizontalSection<UnifiedMedia>(
      title: title,
      height: TvPosterCard.rowExtent(context),
      gap: ShonenXMetrics.of(context).rowGap,
      data: AsyncValue.data(items),
      itemBuilder: (context, item) => TvPosterCard(
        heroTag: '$tagPrefix-${item.id}',
        title: item.title.availableTitle,
        imageUrl: item.cover ?? item.banner,
        // pushReplacement, not push: chasing relations would otherwise build a
        // back stack the user has to unwind one title at a time.
        onTap: () => context.pushReplacement(
          '/details/${item.type.id}?tag=$tagPrefix-${item.id}',
          extra: item,
        ),
      ),
    );
  }
}

/// Characters and their voice actors.
class DetailCharacterRow extends StatelessWidget {
  final List<MediaCharacter> characters;

  const DetailCharacterRow({super.key, required this.characters});

  @override
  Widget build(BuildContext context) {
    return HorizontalSection<MediaCharacter>(
      title: 'Characters',
      // Portrait plus two text lines. The card lets the portrait absorb any
      // slack, so this only has to be roughly right -- see _CharacterCard.
      height: ShonenXMetrics.of(context).rowPoster * 1.25 +
          ShonenXMetrics.of(context).body * 3.2,
      gap: ShonenXMetrics.of(context).rowGap,
      data: AsyncValue.data(characters),
      itemBuilder: (context, character) => _CharacterCard(character: character),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final MediaCharacter character;

  const _CharacterCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);
    final radius = BorderRadius.circular(ShonenX.posterRadius);

    return TvFocusable(
      // No destination to open -- a character sheet would be one more thing to
      // dismiss with a remote. This is reference information, so it is not a
      // focus stop either.
      canRequestFocus: false,
      borderRadius: radius,
      child: SizedBox(
        width: m.rowPoster,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The portrait takes whatever the row has left over after the two
            // captions. Pinning its height instead made the card depend on the
            // font's line metrics matching the row's estimate of them, and a
            // 5px shortfall is a red overflow banner.
            Expanded(
              child: ClipRRect(
                borderRadius: radius,
                child: SizedBox(
                  width: m.rowPoster,
                  child:
                      (character.image == null || character.image!.isEmpty)
                      ? Container(
                          color: cs.surfaceContainer,
                          child: Icon(
                            Icons.person_outline,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: character.image!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: cs.surfaceContainer),
                          errorWidget: (_, __, ___) =>
                              Container(color: cs.surfaceContainer),
                        ),
                ),
              ),
            ),
            SizedBox(height: m.body * 0.5),
            Text(
              character.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: m.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (character.role != null)
              Text(
                character.role!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: m.badge,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
