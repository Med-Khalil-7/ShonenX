import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shonenx/shared/models/video_stream.dart';

abstract class VideoEngine {
  Future<void> initialize(VideoStream stream, {SubtitleTrack? subtitle, Duration? startAt});

  Widget buildVideoView();
  Widget? buildSettingsView(BuildContext context);

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> seekRelative(Duration offset);
  Future<void> changeQuality(VideoStream newStream);
  Future<void> setSubtitle(SubtitleTrack? subtitle);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSpeed(double speed);

  Future<void> dispose();

  Duration get currentPosition;
  Duration get currentDuration;


  /// A JPEG of the frame on screen right now, or null.
  ///
  /// Used for the continue-watching thumbnail. Capturing the Flutter tree
  /// instead yields a black rectangle on Android, where the video is a
  /// platform texture the widget layer cannot read back.
  Future<Uint8List?> grabCurrentFrame() async => null;
}

/// Thrown when a stream opens but never produces a first frame.
///
/// The demuxer and the decoder are independent: a playlist can parse and a
/// duration can appear while nothing is being decoded at all. That is what a
/// codec the device cannot handle looks like from the outside, and it is worth
/// naming so the UI can say something better than showing a spinner forever.
class PlaybackDidNotStartException implements Exception {
  final Duration waited;

  const PlaybackDidNotStartException(this.waited);

  @override
  String toString() =>
      'Playback did not start within ${waited.inSeconds}s. This source may use '
      'a format this device cannot decode -- try another quality or server.';
}
