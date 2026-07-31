class UnifiedEpisode {
  final String id;
  final double number;
  final int? season;
  final String? title;
  final bool isFiller;
  final String? thumbnailUrl;
  final String? airDate;
  final String? uploadDate;
  final String? scanlator;

  const UnifiedEpisode({
    required this.id,
    required this.number,
    this.season,
    this.title,
    this.isFiller = false,
    this.thumbnailUrl,
    this.scanlator,
    this.airDate,
    this.uploadDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'season': season,
      'title': title,
      'isFiller': isFiller,
      'thumbnailUrl': thumbnailUrl,
      'airDate': airDate,
      'uploadDate': uploadDate,
      'scanlator': scanlator,
    };
  }
}
