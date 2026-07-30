import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

/// Back arrow, title and episode on the left; episodes, subtitles and settings
/// on the right.
class PlayerTopBar extends StatelessWidget {
  final bool visible;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onEpisodes;
  final VoidCallback onSubtitles;
  final VoidCallback onSettings;

  const PlayerTopBar({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onEpisodes,
    required this.onSubtitles,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ShonenXMetrics.of(context);
    final insets = TvMetrics.ofSize(MediaQuery.sizeOf(context));

    return AnimatedPositioned(
      duration: Durations.medium2,
      curve: Curves.fastEaseInToSlowEaseOut,
      // Slides fully clear of the panel, so a hidden bar cannot intercept a
      // press meant for the video.
      top: visible ? 0 : -180,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: Durations.short4,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              insets.left,
              insets.top + m.playerIcon * 0.6,
              insets.right,
              m.playerIcon * 1.8,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black26, Colors.transparent],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlayerIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: onBack,
                ),
                SizedBox(width: m.playerIcon),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: m.heading * 0.93,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: m.meta * 0.2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: m.meta,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: m.playerIconGap * 0.6),
                _PlayerIconButton(
                  icon: Icons.layers_outlined,
                  tooltip: 'Episodes',
                  onPressed: onEpisodes,
                ),
                SizedBox(width: m.playerIconGap),
                _PlayerIconButton(
                  icon: Icons.subtitles_outlined,
                  tooltip: 'Subtitles',
                  onPressed: onSubtitles,
                ),
                SizedBox(width: m.playerIconGap),
                _PlayerIconButton(
                  icon: Icons.settings,
                  tooltip: 'Settings',
                  onPressed: onSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PlayerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShonenXMetrics.of(context);
    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      scaleOnFocus: false,
      // Over video, a white ring competes with whatever is behind it. The
      // player marks focus by tinting the icon instead, which stays legible on
      // any frame.
      ringColor: Colors.transparent,
      builder: (context, isFocused) => SizedBox(
        width: m.playerIcon * 1.6,
        height: m.playerIcon * 1.4,
        child: Icon(
          icon,
          size: m.playerIcon,
          semanticLabel: tooltip,
          color: isFocused ? Theme.of(context).colorScheme.primary : Colors.white,
        ),
      ),
    );
  }
}
