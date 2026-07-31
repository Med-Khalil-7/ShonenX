import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:shonenx/features/player/domain/aniskip_prefs.dart';
import 'package:shonenx/shared/models/video_server.dart';

enum PlayerType {
  mediakit,
  videoPlayer;

  factory PlayerType.fromString(String? value) {
    if (value == 'betterplayer' || value == 'mdk' || value == 'videoPlayer') {
      return PlayerType.videoPlayer;
    }
    return PlayerType.mediakit;
  }
}

class PlayerPrefsState {
  final PlayerType playerType;
  final String defaultQuality;
  final String defaultAudioLang;
  final String defaultSubtitleLang;
  final ServerType defaultServerType;
  final bool autoNext;
  final int nextEpisodeThreshold;
  final bool showSkipButton;
  final int skipDuration;

  /// Show the AniSkip "Skip Opening"/"Skip Ending" button over the video.
  ///
  /// Distinct from [showSkipButton], which is the manual +Xs quick-seek in the
  /// transport row.
  final bool showAniSkipButton;

  /// How long the Skip Opening/Ending button stays up before hiding itself.
  final int skipButtonHoldSeconds;

  /// Give the skip button focus the moment it appears, so it is one press.
  final bool focusSkipButton;

  /// Draw the auto-next countdown as a ring on the Next Episode button.
  final bool showAutoNextCountdown;

  /// How far one left/right press moves the scrub target.
  final int seekStepSeconds;

  /// How long the overlay stays up with no input.
  final int controlsTimeoutSeconds;

  const PlayerPrefsState({
    this.playerType = PlayerType.mediakit,
    this.defaultQuality = '1080p',
    this.defaultAudioLang = 'eng',
    this.defaultSubtitleLang = 'eng',
    this.defaultServerType = ServerType.sub,
    this.autoNext = true,
    this.nextEpisodeThreshold = 85,
    this.showSkipButton = true,
    this.skipDuration = 85,
    this.showAniSkipButton = true,
    this.skipButtonHoldSeconds = 8,
    this.focusSkipButton = true,
    this.showAutoNextCountdown = true,
    this.seekStepSeconds = 10,
    this.controlsTimeoutSeconds = 5,
  });

  PlayerPrefsState copyWith({
    AniSkipPrefs? aniSkipPrefs,
    PlayerType? playerType,
    String? defaultQuality,
    String? defaultAudioLang,
    String? defaultSubtitleLang,
    ServerType? defaultServerType,
    bool? autoNext,
    int? nextEpisodeThreshold,
    bool? showSkipButton,
    int? skipDuration,
    bool? showAniSkipButton,
    int? skipButtonHoldSeconds,
    bool? focusSkipButton,
    bool? showAutoNextCountdown,
    int? seekStepSeconds,
    int? controlsTimeoutSeconds,
  }) {
    return PlayerPrefsState(
      playerType: playerType ?? this.playerType,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      defaultAudioLang: defaultAudioLang ?? this.defaultAudioLang,
      defaultSubtitleLang: defaultSubtitleLang ?? this.defaultSubtitleLang,
      defaultServerType: defaultServerType ?? this.defaultServerType,
      autoNext: autoNext ?? this.autoNext,
      nextEpisodeThreshold: nextEpisodeThreshold ?? this.nextEpisodeThreshold,
      showSkipButton: showSkipButton ?? this.showSkipButton,
      skipDuration: skipDuration ?? this.skipDuration,
      showAniSkipButton: showAniSkipButton ?? this.showAniSkipButton,
      skipButtonHoldSeconds:
          skipButtonHoldSeconds ?? this.skipButtonHoldSeconds,
      focusSkipButton: focusSkipButton ?? this.focusSkipButton,
      showAutoNextCountdown:
          showAutoNextCountdown ?? this.showAutoNextCountdown,
      seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
      controlsTimeoutSeconds:
          controlsTimeoutSeconds ?? this.controlsTimeoutSeconds,
    );
  }

  factory PlayerPrefsState.fromMap(Map<String, dynamic> map) {
    return PlayerPrefsState(
      playerType: PlayerType.fromString(map['playerType']),
      defaultQuality: map['defaultQuality'] ?? '1080p',
      defaultAudioLang: map['defaultAudioLang'] ?? 'eng',
      defaultSubtitleLang: map['defaultSubtitleLang'] ?? 'eng',
      defaultServerType: map['defaultServerType'] != null
          ? ServerType.values.firstWhere(
              (e) => e.name == map['defaultServerType'],
              orElse: () => ServerType.sub,
            )
          : ServerType.sub,
      autoNext: map['autoNext'] ?? true,
      nextEpisodeThreshold: map['nextEpisodeThreshold'] ?? 85,
      showSkipButton: map['showSkipButton'] ?? true,
      skipDuration: map['skipDuration'] ?? 85,
      showAniSkipButton: map['showAniSkipButton'] ?? true,
      skipButtonHoldSeconds: map['skipButtonHoldSeconds'] ?? 8,
      focusSkipButton: map['focusSkipButton'] ?? true,
      showAutoNextCountdown: map['showAutoNextCountdown'] ?? true,
      seekStepSeconds: map['seekStepSeconds'] ?? 10,
      controlsTimeoutSeconds: map['controlsTimeoutSeconds'] ?? 5,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'playerType': playerType.name,
      'defaultQuality': defaultQuality,
      'defaultAudioLang': defaultAudioLang,
      'defaultSubtitleLang': defaultSubtitleLang,
      'defaultServerType': defaultServerType.name,
      'autoNext': autoNext,
      'nextEpisodeThreshold': nextEpisodeThreshold,
      'showSkipButton': showSkipButton,
      'skipDuration': skipDuration,
      'showAniSkipButton': showAniSkipButton,
      'skipButtonHoldSeconds': skipButtonHoldSeconds,
      'focusSkipButton': focusSkipButton,
      'showAutoNextCountdown': showAutoNextCountdown,
      'seekStepSeconds': seekStepSeconds,
      'controlsTimeoutSeconds': controlsTimeoutSeconds,
    };
  }

  factory PlayerPrefsState.fromJson(Map<String, dynamic> json) {
    return PlayerPrefsState.fromMap(json);
  }

  Map<String, dynamic> toJson() => toMap();
}

class PlayerPrefsNotifier extends Notifier<PlayerPrefsState> {
  static const _key = 'player_prefs';
  Timer? _debounce;

  @override
  PlayerPrefsState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final json = prefs.getString(_key);
    if (json != null) {
      return PlayerPrefsState.fromJson(jsonDecode(json));
    }
    return PlayerPrefsState(
      playerType: Platform.isAndroid
          ? PlayerType.mediakit
          : PlayerType.mediakit,
    );
  }

  void changePlayer(PlayerType playerType) {
    state = state.copyWith(playerType: playerType);
    _saveDb();
  }



  void setDefaultQuality(String quality) {
    state = state.copyWith(defaultQuality: quality);
    _saveDb();
  }

  void setDefaultAudioLang(String lang) {
    state = state.copyWith(defaultAudioLang: lang);
    _saveDb();
  }

  void setDefaultSubtitleLang(String lang) {
    state = state.copyWith(defaultSubtitleLang: lang);
    _saveDb();
  }

  void setDefaultServerType(ServerType type) {
    state = state.copyWith(defaultServerType: type);
    _saveDb();
  }

  void setAutoNext(bool value) {
    state = state.copyWith(autoNext: value);
    _saveDb();
  }

  void setNextEpisodeThreshold(int threshold) {
    state = state.copyWith(nextEpisodeThreshold: threshold);
    _saveDb();
  }

  void setShowSkipButton(bool value) {
    state = state.copyWith(showSkipButton: value);
    _saveDb();
  }

  void setShowAniSkipButton(bool value) {
    state = state.copyWith(showAniSkipButton: value);
    _saveDb();
  }

  void setSkipButtonHoldSeconds(int seconds) {
    state = state.copyWith(skipButtonHoldSeconds: seconds);
    _saveDb();
  }

  void setFocusSkipButton(bool value) {
    state = state.copyWith(focusSkipButton: value);
    _saveDb();
  }

  void setShowAutoNextCountdown(bool value) {
    state = state.copyWith(showAutoNextCountdown: value);
    _saveDb();
  }

  void setSeekStepSeconds(int seconds) {
    state = state.copyWith(seekStepSeconds: seconds);
    _saveDb();
  }

  void setControlsTimeoutSeconds(int seconds) {
    state = state.copyWith(controlsTimeoutSeconds: seconds);
    _saveDb();
  }

  void setSkipDuration(int duration) {
    state = state.copyWith(skipDuration: duration);
    _saveDb();
  }

  void _saveDb() {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      final prefs = ref.read(sharedPreferencesProvider);
      final newValue = jsonEncode(state.toJson());

      if (prefs.getString(_key) != newValue) {
        prefs.setString(_key, newValue);
      }
    });
  }
}

final playerPrefsProvider =
    NotifierProvider<PlayerPrefsNotifier, PlayerPrefsState>(
      PlayerPrefsNotifier.new,
    );
