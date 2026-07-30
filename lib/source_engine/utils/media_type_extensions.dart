import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/source_registry.dart';

extension MediaTypeSourceResolution on MediaType {
  /// Every remaining media type is video, so they all resolve to the anime
  /// source pool. Kept as an extension so call sites stay unchanged.
  FutureProvider<List<SourceInfo>> get availableSourcesProvider =>
      availableAnimeSourcesProvider;

  bool get usesAnimeSources => true;
}
