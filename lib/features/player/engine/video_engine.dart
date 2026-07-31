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

  /// Whether [grabFrameAt] can return anything.
  ///
  /// False on engines that cannot decode off the timeline. Callers must fall
  /// back rather than assume -- the scrub preview degrades to a bare time
  /// readout when this is false.
  bool get supportsFramePreview => false;

  /// A JPEG of the frame at [position], or null if one cannot be produced.
  ///
  /// Null is an ordinary outcome, not a failure: the platform may refuse, the
  /// seek may time out, or the engine may be mid-teardown.
  Future<Uint8List?> grabFrameAt(Duration position) async => null;

  /// Drops any resources held for [grabFrameAt].
  ///
  /// Called when scrubbing stops. The frame source can be expensive to keep
  /// alive, and nothing needs it between scrubs.
  Future<void> releaseFramePreview() async {}

  /// A JPEG of the frame on screen right now, or null.
  ///
  /// Used for the continue-watching thumbnail. Capturing the Flutter tree
  /// instead yields a black rectangle on Android, where the video is a
  /// platform texture the widget layer cannot read back.
  Future<Uint8List?> grabCurrentFrame() async => null;
}
