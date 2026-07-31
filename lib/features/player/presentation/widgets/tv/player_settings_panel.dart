import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/features/player/domain/stream_catalog.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/features/settings/presentation/widgets/subtitle_settings_sheet.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/models/video_stream.dart';

/// Everything that used to be scattered across the top and bottom bars:
/// quality, server, mirror, audio track, subtitles, speed and fit.
///
/// They were nine separate targets crowded along two edges, most of them
/// 22px icons. Collapsed into one panel they become a list of full-width rows,
/// which is the only shape a D-pad navigates well.
///
/// Episodes is not among them: it has its own control in the top bar, and a
/// second route to the same panel is one more row to cross on the way to
/// everything below it.
class PlayerSettingsPanel extends ConsumerStatefulWidget {
  final VideoEngine engine;
  final PlayerController controller;

  const PlayerSettingsPanel({
    super.key,
    required this.engine,
    required this.controller,
  });

  @override
  ConsumerState<PlayerSettingsPanel> createState() =>
      _PlayerSettingsPanelState();
}

class _PlayerSettingsPanelState extends ConsumerState<PlayerSettingsPanel> {
  /// Null shows the top level; otherwise the open sub-list.
  _Section? _section;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final engineState = ref.watch(videoEngineStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: _section?.title ?? 'Settings',
          onBack: _section == null
              ? null
              : () => setState(() => _section = null),
        ),
        Expanded(
          child: _section == null
              ? _buildRoot(state, engineState)
              : _buildSection(_section!, state, engineState),
        ),
      ],
    );
  }

  Widget _buildRoot(PlayerState state, EngineState engineState) {
    final catalog = StreamCatalog.from(state.streams);
    final active = catalog.facetFor(state.activeStream);

    // Sources that ship direct files put resolution in the stream label, so
    // the quality axis lives there rather than in the m3u8-derived list.
    final qualityFromStreams = catalog.hasHeights;
    final qualityValue = qualityFromStreams
        ? (active?.qualityLabel ?? '-')
        : (state.activeQuality?.quality ?? 'Auto');
    final hasQuality = qualityFromStreams || state.qualities.length > 1;

    // A mirror list only means something when two streams are the same thing.
    final mirrors = catalog.mirrorsFor(active);
    final hasMirrors = mirrors.length > 1;

    // Filtering out auto/no still leaves the single embedded track that every
    // single-language file has, and a menu with one entry is noise.
    final realAudioTracks = engineState.audioTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final hasAudioTracks = realAudioTracks.length > 1;

    // Whichever of the two lead rows this source actually offers takes first
    // focus, so the panel never opens with nothing selected.
    final firstRow = hasQuality ? _Row.quality : _Row.server;

    return ListView(
      padding: EdgeInsets.symmetric(
        vertical: ShonenXMetrics.of(context).meta * 0.6,
      ),
      children: [
        if (hasQuality)
          _NavRow(
            label: 'Quality',
            value: qualityValue,
            autofocus: firstRow == _Row.quality,
            onTap: () => setState(() => _section = _Section.quality),
          ),
        if (state.servers.length > 1)
          _NavRow(
            label: 'Server',
            value: state.activeServer?.name ?? '-',
            autofocus: firstRow == _Row.server,
            onTap: () => setState(() => _section = _Section.server),
          ),
        if (hasMirrors)
          _NavRow(
            label: 'Mirror',
            value: state.activeStream?.quality ?? '-',
            onTap: () => setState(() => _section = _Section.stream),
          ),
        if (hasAudioTracks)
          _NavRow(
            label: 'Audio track',
            value: engineState.activeAudioTrack?.label ?? 'Auto',
            onTap: () => setState(() => _section = _Section.audioTrack),
          ),
        if (_subtitleOptions(state, engineState).length > 1)
          _NavRow(
            label: 'Subtitles',
            value: state.activeSubtitle?.language ?? 'Off',
            onTap: () => setState(() => _section = _Section.subtitle),
          ),
        _NavRow(
          label: 'Playback speed',
          value: '${state.playbackSpeed}x',
          onTap: () => setState(() => _section = _Section.speed),
        ),
        _NavRow(
          label: 'Aspect fit',
          value: switch (engineState.fit) {
            BoxFit.contain => 'Contain',
            BoxFit.cover => 'Cover',
            _ => 'Fill',
          },
          onTap: () =>
              ref.read(videoEngineStateProvider.notifier).cycleFit(),
        ),
        _NavRow(
          label: 'Subtitle style',
          value: '',
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            useRootNavigator: true,
            builder: (_) => const SubtitleSettingsSheet(),
          ),
        ),
        Builder(
          builder: (context) {
            final settingsView = widget.engine.buildSettingsView(context);
            if (settingsView == null) return const SizedBox.shrink();
            return _NavRow(
              label: 'Player engine',
              value: '',
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                useRootNavigator: true,
                builder: (_) => settingsView,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSection(
    _Section section,
    PlayerState state,
    EngineState engineState,
  ) {
    final catalog = StreamCatalog.from(state.streams);
    final active = catalog.facetFor(state.activeStream);

    switch (section) {
      case _Section.quality:
        if (catalog.hasHeights) {
          // Switching resolution holds the language steady, and vice versa --
          // the whole point of splitting the label into two axes.
          return _OptionList<int>(
            options: catalog.heights,
            labelOf: (h) => '${h}p',
            isSelected: (h) => h == active?.height,
            onSelected: (h) {
              final target = catalog.find(
                language: active?.language,
                height: h,
              );
              if (target != null) widget.controller.changeStream(target);
              setState(() => _section = null);
            },
          );
        }
        return _OptionList<VideoStream>(
          options: state.qualities,
          labelOf: (q) => q.quality,
          isSelected: (q) => q == state.activeQuality,
          onSelected: (q) {
            widget.controller.changeQuality(q);
            setState(() => _section = null);
          },
        );
      case _Section.server:
        return _OptionList<VideoServer>(
          options: state.servers,
          labelOf: (s) => '${s.name} · ${s.type.displayName}',
          isSelected: (s) => s == state.activeServer,
          onSelected: (s) {
            widget.controller.changeServer(s);
            setState(() => _section = null);
          },
        );
      case _Section.stream:
        return _OptionList<VideoStream>(
          options: catalog.mirrorsFor(active),
          labelOf: (s) => s.quality,
          isSelected: (s) => s == state.activeStream,
          onSelected: (s) {
            widget.controller.changeStream(s);
            setState(() => _section = null);
          },
        );
      case _Section.subtitle:
        return _OptionList<SubtitleTrack>(
          options: _subtitleOptions(state, engineState),
          labelOf: (s) =>
              (s.url.isEmpty && !s.isEmbedded) ? 'Off' : s.language,
          isSelected: (s) => s == state.activeSubtitle,
          onSelected: (s) {
            widget.controller.changeSubtitle(s);
            setState(() => _section = null);
          },
        );
      case _Section.audioTrack:
        return _OptionList<AudioTrack>(
          options: engineState.audioTracks,
          labelOf: (t) => t.label,
          isSelected: (t) => t == engineState.activeAudioTrack,
          onSelected: (t) {
            widget.controller.changeAudioTrack(t);
            setState(() => _section = null);
          },
        );
      case _Section.speed:
        const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
        return _OptionList<double>(
          options: speeds,
          labelOf: (s) => '${s}x',
          isSelected: (s) => s == state.playbackSpeed,
          onSelected: (s) {
            widget.controller.changeSpeed(s);
            setState(() => _section = null);
          },
        );
    }
  }

}

/// External subtitles from the source, plus any muxed into the file.
///
/// Two independent sources: the extension hands over sidecar URLs, and the
/// container may carry its own tracks. Only the first was ever listed.
List<SubtitleTrack> _subtitleOptions(PlayerState state, EngineState engine) {
  // state.subtitles already begins with SubtitleTrack.none, so nothing else
  // should add an "Off" entry.
  final seen = <String>{};
  final out = <SubtitleTrack>[];
  for (final track in [...state.subtitles, ...engine.embeddedSubtitles]) {
    final key = '${track.embeddedId ?? track.url}|${track.language}';
    if (seen.add(key)) out.add(track);
  }
  return out;
}

/// Which row gets first focus. Depends on what the source actually offers.
enum _Row { quality, server }

enum _Section {
  quality('Quality'),
  server('Server'),
  stream('Mirror'),
  subtitle('Subtitles'),
  audioTrack('Audio track'),
  speed('Playback speed');

  final String title;
  const _Section(this.title);
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const _Header({required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ShonenXMetrics.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        m.meta * 1.4,
        m.meta * 1.4,
        m.meta * 1.4,
        m.meta * 0.8,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            TvFocusable(
              onTap: onBack,
              borderRadius: BorderRadius.circular(8),
              scaleOnFocus: false,
              child: SizedBox(
                width: m.iconButton * 1.5,
                height: m.iconButton * 1.5,
                child: Icon(Icons.arrow_back, size: m.iconButton),
              ),
            ),
            SizedBox(width: m.meta * 0.9),
          ],
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: m.heading,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool autofocus;

  const _NavRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.autofocus = false,
  });

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
        height: m.buttonHeight * 1.3,
        padding: EdgeInsets.symmetric(horizontal: m.meta * 1.4),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: m.meta),
              ),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: m.meta,
                  color: cs.onSurfaceVariant,
                ),
              ),
            SizedBox(width: m.meta * 0.6),
            Icon(
              Icons.chevron_right,
              size: m.meta * 1.5,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionList<T> extends StatelessWidget {
  final List<T> options;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final ValueChanged<T> onSelected;

  const _OptionList({
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = ShonenXMetrics.of(context);
    final selectedIndex = options.indexWhere(isSelected);

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: m.meta * 0.6),
      itemCount: options.length,
      itemBuilder: (context, index) {
        final option = options[index];
        final selected = isSelected(option);

        return TvFocusable(
          onTap: () => onSelected(option),
          // Open on what is already in use, so confirming the current value is
          // a single press and changing it is a short one.
          autofocus: index == (selectedIndex < 0 ? 0 : selectedIndex),
          borderRadius: BorderRadius.circular(10),
          scaleOnFocus: false,
          filledWhenFocused: true,
          focusFillColor: cs.surfaceContainerHigh,
          ringColor: Colors.transparent,
          child: Container(
            height: m.buttonHeight * 1.2,
            padding: EdgeInsets.symmetric(horizontal: m.meta * 1.4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labelOf(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: m.meta,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check, size: m.meta * 1.4, color: cs.primary),
              ],
            ),
          ),
        );
      },
    );
  }
}
