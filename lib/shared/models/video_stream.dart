class VideoStream {
  final String url;
  final Map<String, String>? headers;
  final String quality;
  final List<SubtitleTrack> subtitles;
  final String? size;

  const VideoStream({
    required this.url,
    this.headers,
    this.quality = 'Auto',
    this.subtitles = const [],
    this.size,
  });

  VideoStream copyWith({
    String? url,
    Map<String, String>? headers,
    String? quality,
    List<SubtitleTrack>? subtitles,
    String? size,
  }) {
    return VideoStream(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      quality: quality ?? this.quality,
      subtitles: subtitles ?? this.subtitles,
      size: size ?? this.size,
    );
  }
}

class SubtitleTrack {
  final String url;
  final String language;

  /// Track id inside the container, for subtitles muxed into the video.
  ///
  /// Null means an external file the source handed us a URL for. Embedded
  /// tracks have no URL -- they are selected by id -- which is why they were
  /// invisible to a picker that only knew about URLs.
  final String? embeddedId;

  const SubtitleTrack({
    required this.url,
    required this.language,
    this.embeddedId,
  });

  bool get isEmbedded => embeddedId != null;

  static const none = SubtitleTrack(url: '', language: 'Off');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubtitleTrack &&
          other.url == url &&
          other.language == language &&
          other.embeddedId == embeddedId;

  @override
  int get hashCode => Object.hash(url, language, embeddedId);
}

class AudioTrack {
  final String id;
  final String label;
  final String? language;

  const AudioTrack({required this.id, required this.label, this.language});

  static const auto = AudioTrack(id: 'auto', label: 'Auto');
  static const none = AudioTrack(id: 'no', label: 'Off');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrack &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => id.hashCode ^ label.hashCode;
}
