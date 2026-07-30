import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// A hidden second decoder used only to grab frames off the timeline.
///
/// mpv's screenshot command captures whatever the player is decoding *now* --
/// there is no "give me the frame at 12:30". Seeking the visible player to
/// fetch a preview would be exactly the thing the preview is meant to avoid,
/// so scrubbing gets its own player: same URL, no audio, no video output,
/// never played.
///
/// It is created on the first request rather than with the engine, because
/// most sessions never scrub, and it is torn down as soon as scrubbing stops.
/// A second decoder that outlives the scrub that needed it is a memory leak
/// with a long name.
class FramePreviewPlayer {
  FramePreviewPlayer({required this.url, required this.headers});

  final String url;
  final Map<String, String>? headers;

  /// Frames land in buckets so that nudging the thumb by a second re-uses the
  /// neighbouring grab instead of decoding again.
  static const _bucket = Duration(seconds: 5);

  /// Enough to cover a sweep back and forth over a stretch of the episode
  /// without unbounded growth. Frames are ~30-60KB of JPEG each.
  static const _maxCached = 40;

  /// How long to wait for the seek to actually land before giving up. A cold
  /// seek into an unbuffered part of an HLS stream can be slow, and blocking
  /// forever would wedge every later request behind it.
  static const _seekTimeout = Duration(seconds: 4);

  final Map<int, Uint8List> _cache = {};
  final List<int> _order = [];

  Player? _player;
  Future<void>? _opening;
  bool _disposed = false;

  /// Guards the player against concurrent seeks. Requests are coalesced by the
  /// caller, but an in-flight grab still has to finish before the next seek.
  Future<void> _queue = Future.value();

  int _keyFor(Duration position) =>
      position.inMilliseconds ~/ _bucket.inMilliseconds;

  Uint8List? cached(Duration position) => _cache[_keyFor(position)];

  Future<void> _ensureOpen() {
    return _opening ??= () async {
      final player = Player();
      _player = player;

      final native = player.platform;
      if (native is NativePlayer) {
        // A Player with no VideoController attached defaults to `vid=no` and
        // decodes nothing, so screenshot-raw would return an empty frame.
        await native.setProperty('vid', 'auto');
        // screenshot-raw reads back the decoded surface, which is unreliable
        // under hardware decode -- and this player is not on screen, so
        // software decoding costs nothing visible.
        await native.setProperty('hwdec', 'no');
        await native.setProperty('ao', 'null');
        // Keep the preview cheap: no need to read ahead on a player that only
        // ever renders single frames.
        await native.setProperty('cache-secs', '2');
      }

      await player.open(Media(url, httpHeaders: headers), play: false);
      await player.setVolume(0);
    }();
  }

  /// Returns a JPEG of the frame at [position], or null if one cannot be had.
  ///
  /// Null is a normal outcome, not an error: the platform may refuse the
  /// screenshot, the seek may time out, or the player may have been disposed
  /// mid-flight. Callers fall back to showing no thumbnail.
  Future<Uint8List?> frameAt(Duration position) {
    final key = _keyFor(position);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);

    final task = _queue.then((_) => _grab(position, key));
    // Failures must not poison the chain for every later request.
    _queue = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<Uint8List?> _grab(Duration position, int key) async {
    if (_disposed) return null;

    try {
      await _ensureOpen();
      final player = _player;
      if (player == null || _disposed) return null;

      await player.seek(position);
      await _waitForSeek(player, position);
      if (_disposed) return null;

      // safeScreenshot copies the pixels into Dart-owned memory before
      // returning; the plain screenshot() hands back a view into a buffer mpv
      // may reuse.
      final bytes = await player.safeScreenshot(format: 'image/jpeg');
      if (bytes == null || _disposed) return null;

      _cache[key] = bytes;
      _order.add(key);
      while (_order.length > _maxCached) {
        _cache.remove(_order.removeAt(0));
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// mpv reports the seek as done by moving `position`, but the frame is only
  /// decoded a moment later. Waiting for the position to land near the target
  /// is what stops the screenshot returning the frame we were on before.
  Future<void> _waitForSeek(Player player, Duration target) async {
    if ((player.state.position - target).abs() < _bucket) return;

    final completer = Completer<void>();
    late final StreamSubscription<Duration> sub;
    sub = player.stream.position.listen((pos) {
      if ((pos - target).abs() < _bucket && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(_seekTimeout, onTimeout: () {});
    } finally {
      await sub.cancel();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cache.clear();
    _order.clear();
    final player = _player;
    _player = null;
    _opening = null;
    try {
      await player?.dispose();
    } catch (_) {}
  }
}
