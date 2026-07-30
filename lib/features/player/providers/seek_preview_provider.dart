import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';

/// Frame at a scrub target, or null when one cannot be produced.
///
/// A family keyed on the position so Riverpod dedupes concurrent requests for
/// the same instant and disposes the ones the user has scrubbed past. The
/// engine caches the decoded bytes, so a repeat lookup costs nothing.
///
/// Null is an ordinary result: the engine may not support frame grabs at all,
/// or a particular seek may time out. Callers show the time readout alone.
final seekPreviewProvider = FutureProvider.autoDispose
    .family<Uint8List?, Duration>((ref, position) async {
      final engine = ref.watch(videoEngineProvider);
      if (!engine.supportsFramePreview) return null;
      return engine.grabFrameAt(position);
    });
