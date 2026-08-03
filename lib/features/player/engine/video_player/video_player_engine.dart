import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shonenx/core/network/http_client.dart';
import 'package:shonenx/core/utils/http_x.dart';
import 'package:shonenx/features/player/engine/video_engine.dart';
import 'package:shonenx/shared/models/video_stream.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';

class VideoPlayerEngine implements VideoEngine {
  VideoPlayerController? _controller;

  /// Published so the view rebuilds when the controller is *replaced*.
  ///
  /// The view used to detect that by watching the engine state's duration,
  /// which works for a new episode and not at all for a new rendition of the
  /// same one: switching quality or language keeps the duration identical, so
  /// nothing rebuilt and the widget went on holding a controller that had just
  /// been disposed. Black screen until some unrelated press repainted the
  /// tree, which is exactly when it came back.
  final ValueNotifier<VideoPlayerController?> _current =
      ValueNotifier<VideoPlayerController?>(null);
  final Ref ref;


  static final HTTP _http = HTTP();

  VideoPlayerEngine(this.ref);

  Future<void> updatePrefs() async {}

  @override
  Future<void> initialize(
    VideoStream stream, {
    SubtitleTrack? subtitle,
    Duration? startAt,
  }) async {
    ref
        .read(videoEngineStateProvider.notifier)
        .updateState(isBuffering: true, isPlaying: false);


    _controller?.removeListener(_listener);
    _current.value = null;
    await _controller?.dispose();

    final headers = <String, String>{...?stream.headers};

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: headers,
      formatHint: await _http.isHLS(stream.url, headers: headers)
          ? VideoFormat.hls
          : null,
    );
    _controller?.addListener(_listener);
    _current.value = _controller;

    await _controller?.initialize();

    if (subtitle != null) {
      await setSubtitle(subtitle);
    }
    if (startAt != null && startAt > Duration.zero) {
      await seekTo(startAt);
    }
    await _controller?.play();
  }

  void _listener() {
    final value = _controller?.value;
    if (value == null) return;

    final buffered = value.buffered;
    final bufferDuration = buffered.isNotEmpty
        ? buffered.last.end
        : Duration.zero;

    ref
        .read(videoEngineStateProvider.notifier)
        .updateState(
          position: value.position,
          duration: value.duration,
          buffer: bufferDuration,
          isPlaying: value.isPlaying,
          isBuffering: value.isBuffering || !value.isInitialized,
        );
  }

  @override
  Widget buildVideoView() {
    return Consumer(
      builder: (context, ref, _) {
        final fit = ref.watch(videoEngineStateProvider.select((s) => s.fit));

        // Two listenables, and both are load-bearing: the outer one fires when
        // the controller is swapped for a new rendition, the inner one when
        // that controller finishes initialising and has a frame to draw.
        return ValueListenableBuilder<VideoPlayerController?>(
          valueListenable: _current,
          builder: (context, controller, __) {
            if (controller == null) {
              return const ColoredBox(color: Colors.black);
            }
            return ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, ___) {
                if (!value.isInitialized) {
                  return const ColoredBox(color: Colors.black);
                }
                return _videoBox(context, controller, value, fit);
              },
            );
          },
        );
      },
    );
  }

  Widget _videoBox(
    BuildContext context,
    VideoPlayerController controller,
    VideoPlayerValue value,
    BoxFit fit,
  ) {
        final size = value.size;
        final aspectWidth = size.width > 0 ? size.width : 16.0;
        final aspectHeight = size.height > 0 ? size.height : 9.0;
        final aspectRatio = aspectWidth / aspectHeight;

        final screenWidth = MediaQuery.sizeOf(context).width;
        final boxWidth = screenWidth > 0 ? screenWidth : 1280.0;
        final boxHeight = boxWidth / aspectRatio;

        return ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: FittedBox(
              fit: fit,
              child: SizedBox(
                width: boxWidth,
                height: boxHeight,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        );
  }

  @override
  Widget? buildSettingsView(BuildContext context) => null;

  @override
  Future<void> play() async {
    return _controller?.play();
  }

  @override
  Future<void> pause() async {
    return _controller?.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  Future<void> seekRelative(Duration offset) async {
    final current = _controller?.value.position ?? Duration.zero;
    await seekTo(current + offset);
  }

  @override
  Future<void> changeQuality(VideoStream newStream) async {
    final currentPos = _controller?.value.position;
    await initialize(newStream, startAt: currentPos);
  }

  @override
  Future<void> setSubtitle(SubtitleTrack? subtitle) async {
    if (_controller == null) return;
    if (subtitle == null || subtitle.url.isEmpty) {
      await _controller!.setClosedCaptionFile(null);
      return;
    }
    try {
      final response = await _http.get(subtitle.url);
      if (response.statusCode == 200) {
        final content = response.body;
        ClosedCaptionFile captionFile;
        if (subtitle.url.toLowerCase().endsWith('.vtt') ||
            content.contains('WEBVTT')) {
          captionFile = WebVTTCaptionFile(content);
        } else {
          captionFile = SubRipCaptionFile(content);
        }
        await _controller!.setClosedCaptionFile(Future.value(captionFile));
      }
    } catch (_) {
      await _controller!.setClosedCaptionFile(null);
    }
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    throw UnimplementedError("Not supported by video_player");
  }

  @override
  Future<void> setSpeed(double speed) async =>
      _controller?.setPlaybackSpeed(speed);

  @override
  Future<void> dispose() async {
    _current.value = null;
    _controller?.removeListener(_listener);
    await _controller?.dispose();
    _controller = null;
  }

  @override
  Duration get currentPosition => _controller?.value.position ?? Duration.zero;

  @override
  Duration get currentDuration => _controller?.value.duration ?? Duration.zero;

  @override
  Future<Uint8List?> grabCurrentFrame() async => null;
}
