import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/shared/models/video_server.dart';

/// Dub / sub, and which server serves it.
///
/// A panel of its own rather than a row buried in settings, because on an
/// anime client this is the single most-changed playback option. It lists the
/// servers grouped by [ServerType] and switches with one press.
///
/// Selecting goes through `changeServer`, which already remembers the choice
/// and reloads at the current position. The settings panel used to fire
/// `changeServerType()` and `changeStreamType()` back to back for the same
/// intent -- a full server reload followed by an in-place mirror swap.
class PlayerAudioPanel extends ConsumerWidget {
  const PlayerAudioPanel({super.key, required this.controller});

  final PlayerController controller;

  static const _order = [ServerType.sub, ServerType.dub, ServerType.raw];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);

    final state = ref.watch(playerControllerProvider);
    final servers = state.servers;
    final active = state.activeServer;

    // Anything the source tagged as unknown still has to be reachable, so it
    // trails the known types rather than being filtered out.
    final types = [
      ..._order.where((t) => servers.any((s) => s.type == t)),
      if (servers.any((s) => !_order.contains(s.type))) ServerType.unknown,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            m.meta * 1.4,
            m.meta * 1.4,
            m.meta * 1.4,
            m.meta * 0.8,
          ),
          child: Text(
            'Audio',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: m.heading,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (servers.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.meta * 1.4),
            child: Text(
              'No servers reported by this source.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: m.meta,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: m.meta * 2),
              children: [
                for (final type in types) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      m.meta * 1.4,
                      m.meta,
                      m.meta * 1.4,
                      m.meta * 0.4,
                    ),
                    child: Text(
                      type.displayName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: m.badge,
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  for (final server in servers.where(
                    (s) => type == ServerType.unknown
                        ? !_order.contains(s.type)
                        : s.type == type,
                  ))
                    _ServerRow(
                      server: server,
                      selected: server == active,
                      // Open on what is playing, so confirming the current
                      // choice is one press and changing it is a short one.
                      autofocus: server == active,
                      onTap: () {
                        Navigator.of(context).pop();
                        controller.changeServer(server);
                      },
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final VideoServer server;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);

    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(10),
      scaleOnFocus: false,
      filledWhenFocused: true,
      focusFillColor: cs.surfaceContainerHigh,
      ringColor: Colors.transparent,
      child: Container(
        height: m.buttonHeight * 1.1,
        padding: EdgeInsets.symmetric(horizontal: m.meta * 1.4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: m.meta),
              ),
            ),
            if (selected) Icon(Icons.check, size: m.meta * 1.3, color: cs.primary),
          ],
        ),
      ),
    );
  }
}
