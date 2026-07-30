import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/features/settings/presentation/widgets/subtitle_settings_sheet.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/models/video_stream.dart';

/// Everything that used to be scattered across the top and bottom bars:
/// quality, server, mirror, sub/dub, audio track, speed and aspect fit.
///
/// They were nine separate targets crowded along two edges, most of them
/// 22px icons. Collapsed into one panel they become a list of full-width rows,
/// which is the only shape a D-pad navigates well.
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
    final hasBothTypes = _hasBothServerTypes(state);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (state.qualities.isNotEmpty)
          _NavRow(
            label: 'Quality',
            value: state.activeQuality?.quality ?? 'Auto',
            autofocus: true,
            onTap: () => setState(() => _section = _Section.quality),
          ),
        if (state.servers.isNotEmpty)
          _NavRow(
            label: 'Server',
            value: state.activeServer?.name ?? '-',
            autofocus: state.qualities.isEmpty,
            onTap: () => setState(() => _section = _Section.server),
          ),
        if (state.streams.length > 1)
          _NavRow(
            label: 'Mirror',
            value: state.activeStream?.quality ?? '-',
            onTap: () => setState(() => _section = _Section.stream),
          ),
        if (hasBothTypes)
          _NavRow(
            label: 'Audio',
            value: (state.activeServer?.type ?? ServerType.sub).displayName,
            onTap: () async {
              await widget.controller.changeServerType();
              await widget.controller.changeStreamType();
            },
          ),
        if (engineState.audioTracks
            .where((t) => t.id != 'auto' && t.id != 'no')
            .isNotEmpty)
          _NavRow(
            label: 'Audio track',
            value: engineState.activeAudioTrack?.label ?? 'Auto',
            onTap: () => setState(() => _section = _Section.audioTrack),
          ),
        if (state.subtitles.isNotEmpty)
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
    switch (section) {
      case _Section.quality:
        return _OptionList<VideoStream>(
          options: state.qualities,
          labelOf: (q) => q.quality ?? 'Auto',
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
          options: state.streams,
          labelOf: (s) => s.quality ?? 'Stream',
          isSelected: (s) => s == state.activeStream,
          onSelected: (s) {
            widget.controller.changeStream(s);
            setState(() => _section = null);
          },
        );
      case _Section.subtitle:
        return _OptionList<SubtitleTrack?>(
          options: [null, ...state.subtitles],
          labelOf: (s) => s?.language ?? 'Off',
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

  /// Only worth offering a sub/dub switch when the source actually has both.
  static bool _hasBothServerTypes(PlayerState state) {
    final types = state.servers.map((s) => s.type).toSet();
    return types.contains(ServerType.sub) && types.contains(ServerType.dub);
  }
}

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          if (onBack != null) ...[
            TvFocusable(
              onTap: onBack,
              borderRadius: BorderRadius.circular(8),
              scaleOnFocus: false,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.arrow_back, size: 26),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
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

    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(10),
      scaleOnFocus: false,
      filledWhenFocused: true,
      focusFillColor: cs.surfaceContainerHigh,
      ringColor: Colors.transparent,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.titleMedium),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
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
    final selectedIndex = options.indexWhere(isSelected);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labelOf(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (selected) Icon(Icons.check, color: cs.primary),
              ],
            ),
          ),
        );
      },
    );
  }
}
