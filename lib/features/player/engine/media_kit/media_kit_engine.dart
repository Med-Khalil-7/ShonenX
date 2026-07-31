import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shonenx/features/player/domain/media_kit_prefs.dart';
import 'package:shonenx/features/player/domain/subtitle_prefs.dart';
import 'package:shonenx/features/player/engine/media_kit/frame_preview_player.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/features/player/presentation/widgets/media_kit/media_kit_settings.dart';
import 'package:shonenx/shared/models/video_stream.dart' as stream;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/features/player/providers/subtitle_prefs_provider.dart';

class MediaKitEngine implements VideoEngine {
  late final Player _player;
  late final VideoController _controller;

  MediaKitPrefs prefs;
  final Ref ref;

  bool _disposed = false;

  StreamSubscription<Duration>? _positionSubscription;

  /// The stream currently open, kept so the preview player can be pointed at
  /// the same URL. The engine did not previously retain this.
  stream.VideoStream? _current;

  /// Set by the controller once the quality list is known. Preferred over
  /// [_current] for frame grabs -- see [setPreviewSource].
  stream.VideoStream? _previewSource;

  FramePreviewPlayer? _preview;

  Future<void> updatePrefs(MediaKitPrefs newPrefs) async {
    if (_disposed) return;
    prefs = newPrefs;

    final player = _player.platform;
    if (player is! NativePlayer) return;

    try {
      await player.setProperty('audio-channels', prefs.audioChannel.value);
      if (_disposed) return;
      await player.setProperty('volume-max', '200');
      if (_disposed) return;
      await _player.setVolume(prefs.boostVolume ? 140 : 100);
      if (_disposed) return;

      await player.setProperty(
        'cache-secs',
        prefs.maxBuffer.inSeconds.toString(),
      );
      await player.setProperty(
        'demuxer-readahead-secs',
        prefs.maxBuffer.inSeconds.toString(),
      );

      if (prefs.rawConfiguration.isNotEmpty) {
        for (final line in prefs.rawConfiguration.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final parts = trimmed.split('=');
          if (parts.length == 2) {
            await player.setProperty(parts[0].trim(), parts[1].trim());
          } else if (parts.length == 1) {
            await player.setProperty(parts[0].trim(), 'yes');
          }
        }
      }
    } catch (_) {}
  }

  final List<StreamSubscription> _subscriptions = [];

  MediaKitEngine(this.prefs, this.ref) {
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        hwdec: prefs.hwdec,
        enableHardwareAcceleration: prefs.enableHardwareAcceleration,
        vo: prefs.vo != 'auto' ? prefs.vo : null,
      ),
    );
    updatePrefs(prefs);

    _subscriptions.addAll([
      _player.stream.position.listen((pos) {
        if (!_disposed) {
          ref
              .read(videoEngineStateProvider.notifier)
              .updateState(position: pos);
        }
      }),
      _player.stream.duration.listen((dur) {
        if (!_disposed) {
          ref
              .read(videoEngineStateProvider.notifier)
              .updateState(duration: dur);
        }
      }),
      _player.stream.buffer.listen((buf) {
        if (!_disposed) {
          ref.read(videoEngineStateProvider.notifier).updateState(buffer: buf);
        }
      }),
      _player.stream.playing.listen((playing) {
        if (!_disposed) {
          ref
              .read(videoEngineStateProvider.notifier)
              .updateState(isPlaying: playing);
        }
      }),
      _player.stream.buffering.listen((buffering) {
        if (!_disposed) {
          ref
              .read(videoEngineStateProvider.notifier)
              .updateState(isBuffering: buffering);
        }
      }),
      _player.stream.tracks.listen((tracks) {
        if (!_disposed) {
          final audioList = tracks.audio.map((t) => _mapAudioTrack(t)).toList();
          // Subtitles muxed into the container. These were read for audio
          // only, so any file carrying its own subtitle tracks looked like it
          // had none.
          final subtitleList = tracks.subtitle
              .where((t) => t.id != 'auto' && t.id != 'no')
              .map(_mapSubtitleTrack)
              .toList();
          ref
              .read(videoEngineStateProvider.notifier)
              .updateState(
                audioTracks: audioList,
                embeddedSubtitles: subtitleList,
              );
        }
      }),
      _player.stream.track.listen((track) {
        if (!_disposed) {
          ref
              .read(videoEngineStateProvider.notifier)
              .updateState(activeAudioTrack: _mapAudioTrack(track.audio));
        }
      }),
    ]);

    Future.microtask(() {
      if (!_disposed) {
        final initialAudioList = _player.state.tracks.audio
            .map((t) => _mapAudioTrack(t))
            .toList();
        ref
            .read(videoEngineStateProvider.notifier)
            .updateState(
              audioTracks: initialAudioList,
              activeAudioTrack: _mapAudioTrack(_player.state.track.audio),
            );
      }
    });
  }

  /// How long to wait for the first frame before calling it a failure.
  ///
  /// Generous, because a cold seek into an unbuffered HLS stream on a slow
  /// connection is legitimately slow. The point is not to be strict, it is to
  /// be finite.
  static const _readyTimeout = Duration(seconds: 25);

  /// Waits for playback to actually start, then runs [onReady].
  ///
  /// Readiness is "position moved past zero", which only the listener below
  /// can observe -- so if the stream never starts decoding, that listener
  /// never fires. Without a timeout the future here never completed and
  /// `initialize` never returned, which is what left the player spinning at
  /// 0:00 with no error: the caller's `isLoading = false` was on the next
  /// line and was never reached. A stream the device cannot decode has to
  /// fail, not hang.
  Future<void> _waitUntilReady(Future<void> Function() onReady) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final completer = Completer<void>();
    var handled = false;

    _positionSubscription = _player.stream.position.listen((position) async {
      if (handled || position.inMilliseconds <= 0) return;
      handled = true;

      await _positionSubscription?.cancel();
      _positionSubscription = null;

      try {
        await onReady();
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });

    try {
      await completer.future.timeout(_readyTimeout);
    } on TimeoutException {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      throw PlaybackDidNotStartException(_readyTimeout);
    }
  }

  @override
  Future<void> initialize(
    stream.VideoStream stream, {
    stream.SubtitleTrack? subtitle,
    Duration? startAt,
  }) async {
    _current = stream;
    // Frames cached from the previous stream are of the wrong video, and a
    // preview source left over from the last episode would show frames of it.
    // The controller re-arms this immediately after.
    _previewSource = null;
    unawaited(_disposePreview());
    final media = Media(stream.url, httpHeaders: stream.headers);

    await _player.open(media, play: true);

    await _waitUntilReady(() async {
      if (subtitle != null) {
        await setSubtitle(subtitle);
      }
      if (startAt != null) {
        await _player.seek(startAt);
      }
    });
  }

  @override
  Widget buildVideoView() {
    return Consumer(
      builder: (context, ref, _) {
        final fit = ref.watch(videoEngineStateProvider.select((s) => s.fit));
        final subtitlePrefs = ref.watch(subtitlePrefsProvider);
        final screenWidth = MediaQuery.sizeOf(context).width;
        final responsiveFontSize = getResponsiveSubtitleSize(
          screenWidth,
          subtitlePrefs.fontSize,
        );

        return Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: fit,
          subtitleViewConfiguration: SubtitleViewConfiguration(
            padding: EdgeInsets.only(bottom: subtitlePrefs.bottomPadding),
            style: getSubtitleStrokeStyleInShadowForm(
              subtitlePrefs,
              responsiveFontSize,
            ),
            textScaler: TextScaler.linear(subtitlePrefs.fontSize / 1.2),
          ),
        );
      },
    );
  }

  @override
  Widget? buildSettingsView(BuildContext context) => MediaKitSettings();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> seekRelative(Duration offset) async {
    final currentPos = _player.state.position;
    await _player.seek(currentPos + offset);
  }

  @override
  Future<void> changeQuality(stream.VideoStream newStream) async {
    _current = newStream;
    unawaited(_disposePreview());
    final currentPos = _player.state.position;

    await _player.open(Media(newStream.url, httpHeaders: newStream.headers));
    await _waitUntilReady(() async {
      await _player.seek(currentPos);
      await _player.play();
    });
  }

  @override
  bool get supportsFramePreview => true;

  @override
  void setPreviewSource(stream.VideoStream? source) {
    if (_previewSource?.url == source?.url) return;
    _previewSource = source;
    // The open preview points at the old URL.
    unawaited(_disposePreview());
  }

  @override
  Future<Uint8List?> grabFrameAt(Duration position) async {
    if (_disposed) return null;
    final source = _previewSource ?? _current;
    if (source == null) return null;

    final preview = _preview ??= FramePreviewPlayer(
      url: source.url,
      headers: source.headers,
    );
    return preview.frameAt(position);
  }

  @override
  Future<Uint8List?> grabCurrentFrame() async {
    if (_disposed) return null;
    try {
      return await _player.safeScreenshot(format: 'image/jpeg');
    } catch (_) {
      return null;
    }
  }

  /// Tears the hidden decoder down. Called when scrubbing stops, when the
  /// stream changes, and on dispose -- it must never outlive the scrub.
  @override
  Future<void> releaseFramePreview() => _disposePreview();

  Future<void> _disposePreview() async {
    final preview = _preview;
    _preview = null;
    await preview?.dispose();
  }

  @override
  Future<void> setSubtitle(stream.SubtitleTrack? subtitle) async {
    if (subtitle == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final embeddedId = subtitle.embeddedId;
    if (embeddedId != null) {
      // Selected by track id; an embedded track has no URI to load.
      await _player.setSubtitleTrack(
        SubtitleTrack(embeddedId, null, subtitle.language),
      );
      return;
    }
    if (subtitle.url.isEmpty) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(subtitle.url, language: subtitle.language),
    );
  }

  stream.SubtitleTrack _mapSubtitleTrack(SubtitleTrack track) {
    final title = track.title?.trim();
    final lang = track.language?.trim();

    String label;
    if (title != null && title.isNotEmpty) {
      label = (lang != null &&
              lang.isNotEmpty &&
              !title.toLowerCase().contains(lang.toLowerCase()))
          ? '$title ($lang)'
          : title;
    } else if (lang != null && lang.isNotEmpty) {
      label = lang;
    } else {
      label = 'Track ${track.id}';
    }

    return stream.SubtitleTrack(
      url: '',
      language: label,
      embeddedId: track.id,
    );
  }

  stream.AudioTrack _mapAudioTrack(AudioTrack track) {
    if (track.id == 'auto') return stream.AudioTrack.auto;
    if (track.id == 'no') return stream.AudioTrack.none;

    final title = track.title?.trim();
    final lang = track.language?.trim();

    String label;
    if (title != null && title.isNotEmpty) {
      if (lang != null &&
          lang.isNotEmpty &&
          !title.toLowerCase().contains(lang.toLowerCase())) {
        label = '$title ($lang)';
      } else {
        label = title;
      }
    } else if (lang != null && lang.isNotEmpty) {
      label = lang.toUpperCase();
    } else {
      label = 'Track ${track.id}';
    }

    return stream.AudioTrack(id: track.id, label: label, language: lang);
  }

  @override
  Future<void> setAudioTrack(stream.AudioTrack track) async {
    if (track.id == 'auto') {
      await _player.setAudioTrack(AudioTrack.auto());
    } else if (track.id == 'no') {
      await _player.setAudioTrack(AudioTrack.no());
    } else {
      final target = _player.state.tracks.audio.firstWhere(
        (t) => t.id == track.id,
        orElse: () => AudioTrack.auto(),
      );
      await _player.setAudioTrack(target);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  /// Idempotent, and it has to be.
  ///
  /// Two owners call this: `PlayerScreen.dispose` and the provider's own
  /// `ref.onDispose`. The flag alone was not enough -- it guarded the stream
  /// listeners but not the teardown below, so both callers reached
  /// `_player.dispose()`. media_kit throws on the second call, and because the
  /// first call is never awaited that throw lands as an unhandled async error
  /// part-way through the teardown, before `mpv_terminate_destroy` is
  /// scheduled. The mpv context then leaks -- and with it the MediaCodec
  /// instance it holds.
  ///
  /// That is what "the next episode loads everything and sits at 0:00" is: the
  /// demuxer is fine, so the playlist parses and the duration appears, but
  /// there is no decoder left to hand the frames to. The first playback after
  /// a cold start works because the codec pool is empty; every one after it
  /// inherits the leak.
  Future<void>? _disposing;

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await _positionSubscription?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _disposePreview();
    try {
      await _player.dispose();
    } catch (_) {
      // Already gone. Nothing left to release.
    }
  }

  @override
  Duration get currentPosition => _player.state.position;

  @override
  Duration get currentDuration => _player.state.duration;
}
