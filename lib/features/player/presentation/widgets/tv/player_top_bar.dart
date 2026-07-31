import 'package:flutter/material.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';

/// Back arrow, title and episode on the left; episodes, audio, subtitles and
/// settings on the right.
///
/// Four destinations, four behaviours: episodes and audio each open a panel,
/// subtitles is a straight toggle with no panel at all, settings opens the
/// settings panel. Episodes keeps the same stacked-layers mark it carries on
/// the detail screen, so the same icon means the same thing in both places.
class PlayerTopBar extends StatelessWidget {
  final bool visible;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  /// Opens the episode list. Null for local playback, which has no list --
  /// the control is dropped rather than shown doing nothing.
  final VoidCallback? onEpisodes;

  final VoidCallback onAudio;
  final VoidCallback onToggleSubtitles;
  final VoidCallback onSettings;

  /// Drives the subtitles icon, so the control shows its own state instead of
  /// making the user open something to find out.
  final bool subtitlesOn;

  const PlayerTopBar({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onEpisodes,
    required this.onAudio,
    required this.onToggleSubtitles,
    required this.onSettings,
    required this.subtitlesOn,
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
                if (onEpisodes != null) ...[
                  _PlayerIconButton(
                    icon: Icons.layers_outlined,
                    tooltip: 'Episodes',
                    onPressed: onEpisodes!,
                  ),
                  SizedBox(width: m.playerIconGap),
                ],
                _PlayerIconButton(
                  icon: Icons.multitrack_audio_rounded,
                  tooltip: 'Audio',
                  onPressed: onAudio,
                ),
                SizedBox(width: m.playerIconGap),
                _PlayerIconButton(
                  icon: subtitlesOn
                      ? Icons.subtitles
                      : Icons.subtitles_off_outlined,
                  tooltip: subtitlesOn ? 'Subtitles on' : 'Subtitles off',
                  onPressed: onToggleSubtitles,
                  dimmed: !subtitlesOn,
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

  /// Renders the icon as off. Used by the subtitle toggle.
  final bool dimmed;

  const _PlayerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.dimmed = false,
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
          color: isFocused
              ? Theme.of(context).colorScheme.primary
              : (dimmed ? Colors.white38 : Colors.white),
        ),
      ),
    );
  }
}
