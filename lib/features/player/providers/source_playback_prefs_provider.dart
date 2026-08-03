import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';

/// What the viewer chose to watch a given source with.
///
/// Kept per source rather than app-wide because sources do not agree on what
/// they offer or what they call it: one labels a stream `Japanese - 1080p`,
/// another `SUB 720p`, and a third carries no dub at all. A choice made
/// against one of them says nothing about the others, so applying it to all of
/// them means picking a mirror the viewer never asked for.
///
/// Null means "not chosen for this source"; the caller falls back to the
/// app-wide default from the settings screen.
class SourcePlaybackPrefs {
  const SourcePlaybackPrefs({this.quality, this.audioLang});

  /// A quality *label*, as the source words it, not a height. Matching is the
  /// player's job -- the same rendition is `1080p`, `FHD` or `1920x1080`
  /// depending on who is asked.
  final String? quality;

  /// The audio language, or `Auto`.
  final String? audioLang;

  SourcePlaybackPrefs copyWith({String? quality, String? audioLang}) =>
      SourcePlaybackPrefs(
        quality: quality ?? this.quality,
        audioLang: audioLang ?? this.audioLang,
      );

  Map<String, dynamic> toJson() => {
    if (quality != null) 'quality': quality,
    if (audioLang != null) 'audioLang': audioLang,
  };

  static SourcePlaybackPrefs fromJson(Map<String, dynamic> json) {
    String? read(String key) {
      final value = json[key];
      return (value is String && value.isNotEmpty) ? value : null;
    }

    return SourcePlaybackPrefs(
      quality: read('quality'),
      audioLang: read('audioLang'),
    );
  }
}

/// Per-source playback preferences, keyed by source id.
///
/// Deliberately *not* stored in sourceSettingsProvider. That store belongs to
/// the extensions: its keys are the setting ids an extension declares in its
/// own schema, the sources screen renders whatever it finds there, and
/// syncSchemaDefaults reconciles it against that schema. Putting the player's
/// own state in it means two owners for one namespace, a collision the moment
/// an extension declares a setting by the same name, and rows appearing in a
/// settings screen that never declared them.
final sourcePlaybackPrefsProvider =
    NotifierProvider.family<
      SourcePlaybackPrefsNotifier,
      SourcePlaybackPrefs,
      String
    >(SourcePlaybackPrefsNotifier.new, name: 'sourcePlaybackPrefsProvider');

class SourcePlaybackPrefsNotifier extends Notifier<SourcePlaybackPrefs> {
  SourcePlaybackPrefsNotifier(this.sourceId);

  final String sourceId;

  static const _prefix = 'player_source_prefs_';

  String get _key => '$_prefix$sourceId';

  SharedPreferences get _storage => ref.read(sharedPreferencesProvider);

  @override
  SourcePlaybackPrefs build() {
    final raw = _storage.getString(_key);
    if (raw == null || raw.isEmpty) return const SourcePlaybackPrefs();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SourcePlaybackPrefs.fromJson(decoded);
      }
    } catch (_) {
      // Unreadable is the same as unset: the viewer picks again and it is
      // rewritten. Throwing here would take the player down with it.
    }
    return const SourcePlaybackPrefs();
  }

  void setQuality(String quality) {
    if (quality.isEmpty) return;
    _write(state.copyWith(quality: quality));
  }

  void setAudioLang(String audioLang) {
    if (audioLang.isEmpty) return;
    _write(state.copyWith(audioLang: audioLang));
  }

  void _write(SourcePlaybackPrefs next) {
    state = next;
    _storage.setString(_key, jsonEncode(next.toJson()));
  }
}
