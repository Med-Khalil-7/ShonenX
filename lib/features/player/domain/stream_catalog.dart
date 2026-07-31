import 'package:shonenx/shared/models/video_stream.dart';

/// One stream, split into the axes a viewer actually thinks in.
class StreamFacet {
  const StreamFacet({
    required this.stream,
    required this.language,
    required this.height,
  });

  final VideoStream stream;

  /// `Japanese`, `English`, ... or null when the label says nothing about it.
  final String? language;

  /// Vertical resolution: 1080, 720, 360. Null when unlabelled.
  final int? height;

  String get qualityLabel => height == null ? stream.quality : '${height}p';
}

/// Sorts a source's stream list into language and quality.
///
/// Sources hand back one flat list where a single label carries everything:
/// `Japanese - 1080p (1920x1080) - 1.2GB`. Presented raw that becomes a
/// "Mirror" menu holding six entries that differ along two unrelated axes,
/// while the Quality and Audio menus next to it have nothing to show -- the
/// quality list is built by splitting an m3u8, and a direct MP4 has no
/// variants to split.
///
/// Splitting the label puts each axis back under its own control, and lets
/// changing one keep the other: pick English and you stay at 1080p.
class StreamCatalog {
  StreamCatalog._(this.facets);

  factory StreamCatalog.from(List<VideoStream> streams) =>
      StreamCatalog._([for (final s in streams) _facetOf(s)]);

  final List<StreamFacet> facets;

  static final _heightPattern = RegExp(r'(\d{3,4})\s*[pP]\b');
  static final _dimensionPattern = RegExp(r'(\d{2,5})\s*[x×]\s*(\d{2,5})');

  /// Segments that are plainly not a language: resolutions, file sizes,
  /// bitrates, and the catch-all labels sources use when they know nothing.
  static final _notLanguage = RegExp(
    r'\d|^(auto|default|unknown|raw|hls|mp4|source|original)$',
    caseSensitive: false,
  );

  static StreamFacet _facetOf(VideoStream stream) {
    final label = stream.quality;

    int? height;
    final byP = _heightPattern.firstMatch(label);
    if (byP != null) {
      height = int.tryParse(byP.group(1)!);
    } else {
      final byDimension = _dimensionPattern.firstMatch(label);
      if (byDimension != null) height = int.tryParse(byDimension.group(2)!);
    }

    // Labels are near-universally delimiter-separated. Take the first segment
    // that could plausibly be a language name.
    String? language;
    for (final part in label.split(RegExp(r'\s*[-–|·,]\s*'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (_notLanguage.hasMatch(trimmed)) continue;
      if (trimmed.length > 24) continue;
      language = trimmed;
      break;
    }

    // Fall back to the sub/dub wording sources use when they do not name the
    // language outright.
    if (language == null) {
      final lower = label.toLowerCase();
      if (lower.contains('dub')) {
        language = 'Dub';
      } else if (lower.contains('sub')) {
        language = 'Sub';
      }
    }

    return StreamFacet(stream: stream, language: language, height: height);
  }

  /// Distinct languages, in the order the source listed them.
  List<String> get languages {
    final seen = <String>[];
    for (final f in facets) {
      final l = f.language;
      if (l != null && !seen.contains(l)) seen.add(l);
    }
    return seen;
  }

  /// Distinct resolutions, highest first.
  List<int> get heights {
    final seen = <int>{};
    for (final f in facets) {
      final h = f.height;
      if (h != null) seen.add(h);
    }
    final list = seen.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Only worth offering the axis when there is a choice along it.
  bool get hasLanguages => languages.length > 1;
  bool get hasHeights => heights.length > 1;

  /// Cheapest rendition to point the scrub preview at.
  ///
  /// The preview runs a second player that decodes in software. Aimed at the
  /// 1080p variant the viewer is watching, every step of the scrub costs a
  /// full-size software decode, which on a weak box is most of why dragging
  /// through an episode stutters. Aimed at the smallest variant it costs a
  /// fraction of that, and the result is a thumbnail either way.
  ///
  /// Null means "nothing better than what is already playing" -- the caller
  /// keeps its current behaviour rather than guessing.
  static VideoStream? cheapestRendition(List<VideoStream> qualities) {
    // Entry zero is the master playlist relabelled 'Auto'. Handing that to the
    // preview player lets it negotiate its way straight back up to 1080p.
    final variants = [
      for (final q in qualities)
        if (q.quality.trim().toLowerCase() != 'auto') q,
    ];
    if (variants.isEmpty) return null;

    final ranked = StreamCatalog.from(
      variants,
    ).facets.where((f) => f.height != null).toList();
    if (ranked.isNotEmpty) {
      ranked.sort((a, b) => a.height!.compareTo(b.height!));
      return ranked.first.stream;
    }

    // Variants with no RESOLUTION in the playlist get a bitrate label instead.
    final byBitrate = <({int kbps, VideoStream stream})>[];
    for (final v in variants) {
      final m = RegExp(
        r'(\d+)\s*kbps',
        caseSensitive: false,
      ).firstMatch(v.quality);
      if (m != null) {
        byBitrate.add((kbps: int.parse(m.group(1)!), stream: v));
      }
    }
    if (byBitrate.isNotEmpty) {
      byBitrate.sort((a, b) => a.kbps.compareTo(b.kbps));
      return byBitrate.first.stream;
    }

    // A single unrankable variant still beats the master playlist.
    if (variants.length == 1) return variants.single;

    // Several variants and nothing to order them by. Masters are conventionally
    // ascending by bandwidth but nothing guarantees it, so guessing risks
    // handing the preview the most expensive stream of the lot.
    return null;
  }

  StreamFacet? facetFor(VideoStream? stream) {
    if (stream == null) return null;
    for (final f in facets) {
      if (identical(f.stream, stream) || f.stream.url == stream.url) return f;
    }
    return null;
  }

  /// Best stream for the requested axes, holding the other axis steady.
  ///
  /// Falls back rather than returning null: a source may not carry every
  /// combination, and refusing to switch would be worse than switching to the
  /// nearest thing it does have.
  VideoStream? find({String? language, int? height}) {
    Iterable<StreamFacet> pool = facets;

    if (language != null) {
      final byLanguage = pool.where((f) => f.language == language);
      if (byLanguage.isNotEmpty) pool = byLanguage;
    }
    if (height != null) {
      final exact = pool.where((f) => f.height == height);
      if (exact.isNotEmpty) {
        pool = exact;
      } else {
        // Nearest available resolution beats no change at all.
        final withHeight = pool.where((f) => f.height != null).toList()
          ..sort(
            (a, b) => (a.height! - height).abs().compareTo(
              (b.height! - height).abs(),
            ),
          );
        if (withHeight.isNotEmpty) pool = [withHeight.first];
      }
    }

    return pool.isEmpty ? null : pool.first.stream;
  }

  /// Streams matching the given facet exactly -- genuine mirrors of the same
  /// thing, which is the only case where a "Mirror" list means anything.
  List<VideoStream> mirrorsFor(StreamFacet? facet) {
    if (facet == null) return const [];
    return [
      for (final f in facets)
        if (f.language == facet.language && f.height == facet.height) f.stream,
    ];
  }
}
