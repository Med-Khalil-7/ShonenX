import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shonenx/features/player/domain/stream_catalog.dart';
import 'package:shonenx/core/network/http_client.dart';
import 'package:shonenx/core/utils/extensions.dart';
import 'package:shonenx/core/utils/http_x.dart';
import 'package:shonenx/features/discovery/domain/media_args.dart';
import 'package:shonenx/features/discovery/providers/episodes_provider.dart';
import 'package:shonenx/features/history/domain/models/watch_history_entry.dart';
import 'package:shonenx/features/history/providers/watch_history_provider.dart';
import 'package:shonenx/features/player/domain/aniskip_prefs.dart';
import 'package:shonenx/features/player/domain/player_mode.dart';
import 'package:shonenx/features/player/providers/aniskip_prefs_provider.dart';
import 'package:shonenx/features/player/providers/aniskip_provider.dart';
import 'package:shonenx/features/player/providers/player_prefs_provider.dart';
import 'package:shonenx/features/player/providers/scrub_provider.dart';
import 'package:shonenx/features/player/providers/source_playback_prefs_provider.dart';
import 'package:shonenx/features/player/providers/subtitle_prefs_provider.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/features/tracking/engine/sync_engine.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/models/video_stream.dart';
import 'package:shonenx/source_engine/providers/anime_source.dart';
import 'package:shonenx/source_engine/source_engine_provider.dart';

const _keepError = Object();

class PlayerState {
  final List<VideoServer> servers;
  final List<VideoStream> streams;
  final List<SubtitleTrack> subtitles;
  final List<VideoStream> qualities;
  final VideoServer? activeServer;
  final VideoStream? activeStream;
  final VideoStream? activeQuality;
  final SubtitleTrack? activeSubtitle;
  final UnifiedEpisode? activeEpisode;
  final double playbackSpeed;
  final bool isLoading;
  final String? error;

  const PlayerState({
    this.servers = const [],
    this.streams = const [],
    this.subtitles = const [],
    this.qualities = const [],
    this.activeServer,
    this.activeEpisode,
    this.activeSubtitle,
    this.activeStream,
    this.activeQuality,
    this.playbackSpeed = 1.0,
    this.isLoading = true,
    this.error,
  });

  PlayerState copyWith({
    List<VideoServer>? servers,
    List<VideoStream>? streams,
    List<SubtitleTrack>? subtitles,
    List<VideoStream>? qualities,
    VideoServer? activeServer,
    VideoStream? activeStream,
    VideoStream? activeQuality,
    SubtitleTrack? activeSubtitle,
    UnifiedEpisode? activeEpisode,
    double? playbackSpeed,
    bool? isLoading,
    Object? error = _keepError,
  }) {
    return PlayerState(
      servers: servers ?? this.servers,
      streams: streams ?? this.streams,
      subtitles: subtitles ?? this.subtitles,
      qualities: qualities ?? this.qualities,
      activeServer: activeServer ?? this.activeServer,
      activeStream: activeStream ?? this.activeStream,
      activeQuality: activeQuality ?? this.activeQuality,
      activeSubtitle: activeSubtitle ?? this.activeSubtitle,
      activeEpisode: activeEpisode ?? this.activeEpisode,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keepError) ? this.error : error as String?,
    );
  }
}

class PlayerController extends Notifier<PlayerState> {
  Timer? _progressTimer;
  UnifiedMedia? _media;
  UnifiedMedia? get media => _media;
  AnimeSource? _source;

  // Thumbnail caching
  String? _cachedThumbnail;
  DateTime? _lastThumbnailTime;
  bool _initialCaptureDone = false;
  static const _thumbnailRefreshInterval = Duration(minutes: 2);

  final Set<SkipType> _alreadyAutoSkipped = {};
  AniSkipArgs? _autoSkipArgs;
  bool _autoNextTriggered = false;

  /// Position at the previous tick, so a jump can be told from a tick.
  Duration? _lastTickPosition;

  /// Whether playback has been outside the end-of-episode window since the
  /// last seek. Auto-next requires playing *into* the window, not landing in
  /// it -- see [_maybeAutoNext].
  bool _autoNextArmed = false;

  /// How close to the end auto-next fires.
  ///
  /// Five seconds, fixed. The setting behind this used to be 85 by default,
  /// which on a 24 minute episode cut away a minute and a half before the end
  /// -- through the outro and the next-episode preview -- and made every seek
  /// near the end feel like the player was fighting back. At five seconds it
  /// only ever takes over once the episode has genuinely finished.
  static const _autoNextWindowSeconds = 5;

  // Subscriptions
  ProviderSubscription<Duration>? _positionSubscription;

  // Smart Memory
  String? _preferredServerId;
  ServerType? _preferredServerType;
  /// The viewer's choices for the source in hand, if they have made any.
  ///
  /// Per source, not app-wide: sources disagree on what they offer and on what
  /// they call it, so a choice made against one is not a statement about the
  /// others. The settings screen's defaults remain the fallback for a source
  /// that has never been chosen for.
  SourcePlaybackPrefs? get _sourcePrefs {
    final id = _source?.sourceInfo.id;
    if (id == null || id.isEmpty) return null;
    return ref.read(sourcePlaybackPrefsProvider(id));
  }

  SourcePlaybackPrefsNotifier? get _sourcePrefsNotifier {
    final id = _source?.sourceInfo.id;
    if (id == null || id.isEmpty) return null;
    return ref.read(sourcePlaybackPrefsProvider(id).notifier);
  }

  String? _preferredQuality;
  String? _preferredSubtitleLang = 'eng';
  String? _preferredAudioLang;

  @override
  PlayerState build() {
    ref.onDispose(() {
      _positionSubscription?.close();
      _progressTimer?.cancel();
    });

    final prefs = ref.read(playerPrefsProvider);
    _preferredQuality = prefs.defaultQuality;
    _preferredSubtitleLang = prefs.defaultSubtitleLang;
    _preferredAudioLang = prefs.defaultAudioLang;
    _preferredServerType = prefs.defaultServerType == ServerType.unknown
        ? null
        : prefs.defaultServerType;

    ref.listen(subtitlePrefsProvider, (prev, current) {
      if (prev?.useCustomSubtitle != current.useCustomSubtitle) {
        _applyNativeSubtitle(state.activeSubtitle);
      }
    });

    ref.listen(videoEngineStateProvider.select((s) => s.audioTracks), (
      prev,
      current,
    ) {
      if (_preferredAudioLang != null &&
          _preferredAudioLang != 'Auto' &&
          current.isNotEmpty) {
        final match = current.firstWhereOrNull(
          (t) =>
              t.language?.toLowerCase().contains(
                    _preferredAudioLang!.toLowerCase(),
                  ) ==
                  true ||
              t.label.toLowerCase().contains(
                    _preferredAudioLang!.toLowerCase(),
                  ) ==
                  true ||
              _preferredAudioLang!.toLowerCase().contains(
                    t.language?.toLowerCase() ?? '---',
                  ) ==
                  true ||
              _preferredAudioLang!.toLowerCase().contains(
                    t.label.toLowerCase(),
                  ) ==
                  true,
        );
        if (match != null) {
          ref.read(videoEngineProvider).setAudioTrack(match);
        }
      } else if (_preferredAudioLang == 'Auto') {
        ref.read(videoEngineProvider).setAudioTrack(AudioTrack.auto);
      }
    });

    return const PlayerState();
  }

  Future<void> _applyNativeSubtitle(SubtitleTrack? subtitle) async {
    final prefs = ref.read(subtitlePrefsProvider);
    try {
      // Embedded tracks always go native: the custom overlay renders cues it
      // parsed from a URL, and a muxed track has none to parse.
      if (subtitle != null && subtitle.isEmbedded) {
        await ref.read(videoEngineProvider).setSubtitle(subtitle);
      } else if (prefs.useCustomSubtitle || subtitle?.url.isEmpty == true) {
        await ref.read(videoEngineProvider).setSubtitle(null);
      } else {
        await ref.read(videoEngineProvider).setSubtitle(subtitle);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to switch subtitle: $e');
    }
  }

  Future<void> initialize(PlayerMode mode) async {

    if (mode is PlayerModeOnline) {
      _source = ref.read(animeSourceProvider(mode.sourceInfo));
      _media = mode.media;

      await _loadData(mode.episode, startPosition: mode.startPosition);
    } else if (mode is PlayerModeAuto) {
      await _resolveAndLoad(mode);
    } else if (mode is PlayerModeOffline) {
      _source = null;
      _media = null;
      await _loadOfflineData(mode);
    }
  }

  /// Works out which episode to play, then plays it.
  ///
  /// This is the work the callers used to do before navigating -- fetching the
  /// episode list is a network round trip, and doing it up front meant the play
  /// button sat spinning on the previous screen. Done here the player is
  /// already on screen, so the wait happens against the surface it is about to
  /// fill instead of against a list the user has finished with.
  Future<void> _resolveAndLoad(PlayerModeAuto mode) async {
    state = state.copyWith(isLoading: true, error: null);
    _media = mode.media;

    try {
      // Bounded. Resolving is a search against the source and can be slow,
      // but it must not be able to hang: with the resolve inside the player
      // there is no screen behind it to go back to, just a spinner.
      final listState = await ref
          .read(episodesListProvider(MediaArgs.fromMedia(mode.media)).future)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw TimeoutException(
              'the source took too long to answer',
            ),
          );
      final episodes = listState.episodes;
      if (episodes.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'No episodes found for this source.',
        );
        return;
      }

      _source = ref.read(animeSourceProvider(listState.source));

      // An explicit episode from the caller wins -- continue-watching knows
      // exactly where it left off.
      UnifiedEpisode? target;
      Duration? startPosition = mode.startPosition;

      if (mode.episodeNumber != null) {
        target = episodes.firstWhereOrNull(
          (e) => e.number == mode.episodeNumber,
        );
      }

      if (target == null) {
        // Resume the part-watched episode, else the one after the last
        // finished, else the first.
        final history =
            ref.read(historyEpisodesProvider(mode.media.id)).value ?? [];
        final last = history.firstOrNull;
        if (last != null) {
          final partway =
              last.positionInMilliseconds > 0 &&
              last.positionInMilliseconds < last.durationInMilliseconds;
          if (partway) {
            target = episodes.firstWhereOrNull(
              (e) => e.number == last.episodeNumber,
            );
            startPosition ??= Duration(
              milliseconds: last.positionInMilliseconds,
            );
          } else {
            target = episodes.firstWhereOrNull(
              (e) => e.number == last.episodeNumber + 1,
            );
          }
        }
      }
      target ??= episodes.first;

      await _loadData(target, startPosition: startPosition);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not start playback: $e',
      );
    }
  }

  Future<void> _loadOfflineData(PlayerModeOffline mode) async {
    state = state.copyWith(isLoading: true, error: null, activeEpisode: null);

    try {
      final activeStream = VideoStream(
        url: mode.filePath,
        quality: 'Local',
        subtitles: [],
      );

      state = state.copyWith(
        servers: [],
        activeServer: null,
        streams: [activeStream],
        activeStream: activeStream,
        qualities: [activeStream],
        activeQuality: activeStream,
        subtitles: [SubtitleTrack.none],
        activeSubtitle: SubtitleTrack.none,
        isLoading: false,
      );

      await ref
          .read(videoEngineProvider)
          .initialize(activeStream, subtitle: null, startAt: Duration.zero);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> changeServer(VideoServer newServer) async {
    final active = state.activeServer;
    if (active != null &&
        newServer.id == active.id &&
        newServer.type == active.type) {
      return;
    }

    _preferredServerId = newServer.id;
    _preferredServerType = newServer.type;
    ref.read(playerPrefsProvider.notifier).setDefaultServerType(newServer.type);

    final currentPos = ref.read(videoEngineProvider).currentPosition;
    await _loadData(
      state.activeEpisode!,
      server: newServer,
      startPosition: currentPos,
    );
  }

  Future<void> changeServerType({bool? isDub, bool toggle = true}) async {
    ServerType targetType = isDub == true ? ServerType.dub : ServerType.sub;
    if (toggle && isDub == null) {
      targetType = state.activeServer?.type == ServerType.dub
          ? ServerType.sub
          : ServerType.dub;
    }
    final server = state.servers.firstWhereOrNull((s) => s.type == targetType);
    if (server == null) return;
    await changeServer(server);
  }

  Future<void> changeStreamType({bool? isDub, bool toggle = true}) async {
    final currentStream = state.activeStream;
    if (currentStream == null) return;

    bool targetDub = isDub ?? false;
    if (toggle && isDub == null) {
      final q = currentStream.quality.toLowerCase();
      final currentlyDub = q.contains('dub') || q.contains('english');
      targetDub = !currentlyDub;
    }

    _preferredServerType = targetDub ? ServerType.dub : ServerType.sub;
    ref
        .read(playerPrefsProvider.notifier)
        .setDefaultServerType(_preferredServerType!);

    VideoStream? targetStream;
    if (targetDub) {
      targetStream = state.streams.firstWhereOrNull((s) {
        final sq = s.quality.toLowerCase();
        return sq.contains('dub') || sq.contains('english');
      });
    } else {
      targetStream = state.streams.firstWhereOrNull((s) {
        final sq = s.quality.toLowerCase();
        return sq.contains('sub') || sq.contains('japanese');
      });
      targetStream ??= state.streams.firstWhereOrNull((s) {
        final sq = s.quality.toLowerCase();
        return !sq.contains('dub') && !sq.contains('english');
      });
    }

    if (targetStream != null && targetStream.url != currentStream.url) {
      await changeStream(targetStream);
    }
  }

  Future<void> loadEpisode(
    UnifiedEpisode newEpisode, {
    bool force = false,
  }) async {
    _alreadyAutoSkipped.clear();
    _autoNextTriggered = false;
    _autoNextArmed = false;
    _lastTickPosition = null;
    _cachedThumbnail = null;
    _lastThumbnailTime = null;
    _initialCaptureDone = false;
    await _loadData(newEpisode, force: force);
  }

  Future<void> skipEpisode({bool forward = true}) async {
    if (_media == null || state.activeEpisode == null) return;
    final episodes = await ref.read(
      episodesListProvider(
        MediaArgs.fromMedia(_media!),
      ).selectAsync((s) => s.episodes),
    );

    final currentIndex = episodes.indexWhere(
      (e) => e.id == state.activeEpisode!.id,
    );
    if (currentIndex == -1) return;

    final targetIndex = currentIndex + (forward ? 1 : -1);
    if (targetIndex < 0 || targetIndex >= episodes.length) return;

    await loadEpisode(episodes[targetIndex]);
  }

  bool get hasNextEpisode {
    if (_media == null || state.activeEpisode == null) return false;
    final episodesState = ref
        .read(episodesListProvider(MediaArgs.fromMedia(_media!)))
        .value;
    if (episodesState != null) {
      final episodes = episodesState.episodes;
      final currentIndex = episodes.indexWhere(
        (e) => e.id == state.activeEpisode!.id,
      );
      if (currentIndex != -1) {
        return currentIndex < episodes.length - 1;
      }
    }

    final total = _media!.episodes;
    if (total != null && total > 0) {
      return state.activeEpisode!.number < total;
    }
    return true; // Assume there is one if total is unknown, until proven otherwise
  }

  bool _matchesQuality(String candidate, String target) {
    final c = candidate.toLowerCase();
    final t = target.toLowerCase();
    if (c == t) return true;
    if (t == 'auto') return c == 'auto';
    if (c == 'auto') return false;

    final cleanTarget = t.replaceAll('p', '').trim();
    if (cleanTarget.isNotEmpty && c.contains(cleanTarget)) {
      return true;
    }
    return c.contains(t) || t.contains(c);
  }

  Future<void> _loadData(
    UnifiedEpisode episode, {
    VideoServer? server,
    Duration? startPosition,
    bool force = false,
  }) async {
    if (_source == null) return;

    // Re-read the axes for *this* source before choosing anything. The fields
    // still hold whatever the last source resolved to, so falling back to the
    // global default rather than leaving them is what stops one extension's
    // choice leaking into the next.
    final globalPrefs = ref.read(playerPrefsProvider);
    final chosen = _sourcePrefs;
    _preferredQuality = chosen?.quality ?? globalPrefs.defaultQuality;
    _preferredAudioLang = chosen?.audioLang ?? globalPrefs.defaultAudioLang;

    if (state.activeEpisode?.id != episode.id) {
      _alreadyAutoSkipped.clear();
    _autoNextTriggered = false;
    _autoNextArmed = false;
    _lastTickPosition = null;
    }
    state = state.copyWith(
      isLoading: true,
      error: null,
      activeEpisode: episode,
    );

    try {
      List<VideoServer> servers = state.servers;
      if (force || (server == null || state.activeEpisode?.id != episode.id)) {
        servers = await _source!.getServers(episode.id);
        if (servers.isEmpty) throw Exception('No servers available.');
      }

      // Video Server Selection
      VideoServer activeServer = servers.first;
      if (server != null) {
        activeServer = server;
      } else {
        // Priority 1: Exact match (Same ID and Same Type)
        final exactMatch = servers.firstWhereOrNull(
          (s) => s.id == _preferredServerId && s.type == _preferredServerType,
        );

        if (exactMatch != null) {
          activeServer = exactMatch;
        } else {
          // Priority 2: Type match (ID didn't match, but we have the preferred type e.g., Dub)
          final typeMatch = servers.firstWhereOrNull(
            (s) => s.type == _preferredServerType,
          );
          if (typeMatch != null) {
            activeServer = typeMatch;
          }
        }
      }

      final streams = await _source!.getSources(episode.id, activeServer);
      if (streams.isEmpty) throw Exception('No streams available.');

      // Mirror selection, in order of how deliberate the choice was.
      //
      // Language first, because it is the only one of these the viewer picked
      // by hand for this source. It used to run last, after the sub/dub
      // filter -- and that filter reads `english` in a label as "this is a
      // dub", so with the server type left at sub the English mirror was
      // dropped from the pool before the language filter ever saw it. The
      // saved choice was correct and unreachable: playback fell back to
      // Japanese every time.
      List<VideoStream> pool = streams;

      final lang = _preferredAudioLang;
      if (lang != null && lang.isNotEmpty && lang != 'Auto') {
        final wanted = lang.toLowerCase();
        final sameLanguage = [
          for (final facet in StreamCatalog.from(pool).facets)
            if (facet.language != null &&
                (facet.language!.toLowerCase() == wanted ||
                    facet.language!.toLowerCase().contains(wanted) ||
                    wanted.contains(facet.language!.toLowerCase())))
              facet.stream,
        ];
        if (sameLanguage.isNotEmpty) pool = sameLanguage;
      }

      // Then sub/dub, but only as far as it narrows without emptying: it is a
      // guess read off the label, and it must not overrule the language above.
      if (_preferredServerType != null) {
        final isPrefDub = _preferredServerType == ServerType.dub;
        final byType = pool.where((s) {
          final sq = s.quality.toLowerCase();
          final isDub = sq.contains('dub') || sq.contains('english');
          return isPrefDub ? isDub : (!isDub);
        }).toList();
        if (byType.isNotEmpty) pool = byType;
      }

      VideoStream activeStream = pool.first;

      // Finally resolution, within whatever the two above left.
      if (_preferredQuality != null && _preferredQuality != 'Auto') {
        final qualityMatch =
            pool.firstWhereOrNull(
              (s) => _matchesQuality(s.quality, _preferredQuality!),
            ) ??
            streams.firstWhereOrNull(
              (s) => _matchesQuality(s.quality, _preferredQuality!),
            );
        if (qualityMatch != null) activeStream = qualityMatch;
      }

      // Fetch qualities for the activeStream
      final httpClient = ref.read(httpClientProvider);
      final qualitiesList = <VideoStream>[
        activeStream.copyWith(quality: 'Auto'),
      ];

      try {
        final parsedQualities = await httpClient.splitM3U8(
          activeStream.url,
          headers: activeStream.headers,
        );
        for (final q in parsedQualities) {
          qualitiesList.add(
            VideoStream(
              url: q.url,
              headers: activeStream.headers,
              quality: q.quality,
              subtitles: activeStream.subtitles,
            ),
          );
        }
      } catch (_) {
        // Fall back gracefully if parsing fails
      }

      // Select active quality from parsed list
      VideoStream activeQuality = qualitiesList.first;
      if (_preferredQuality != null && _preferredQuality != 'Auto') {
        final qualityMatch = qualitiesList.firstWhereOrNull(
          (s) => _matchesQuality(s.quality, _preferredQuality!),
        );
        if (qualityMatch != null) activeQuality = qualityMatch;
      }

      final subtitles = [SubtitleTrack.none, ...activeStream.subtitles];

      // Subtitle Selection
      SubtitleTrack? activeSubtitle = subtitles.first;
      if (_preferredSubtitleLang != null &&
          _preferredSubtitleLang != 'Off' &&
          subtitles.isNotEmpty) {
        final subMatch = subtitles.firstWhereOrNull(
          (s) =>
              s.language.toLowerCase().contains(
                _preferredSubtitleLang!.toLowerCase(),
              ) ||
              _preferredSubtitleLang!.toLowerCase().contains(
                s.language.toLowerCase(),
              ),
        );
        if (subMatch != null) activeSubtitle = subMatch;
      } else if (_preferredSubtitleLang == 'Off') {
        activeSubtitle = SubtitleTrack.none;
      }

      state = state.copyWith(
        servers: servers,
        activeServer: activeServer,
        streams: streams,
        activeStream: activeStream,
        qualities: qualitiesList,
        activeQuality: activeQuality,
        subtitles: subtitles,
        activeSubtitle: activeSubtitle,
        isLoading: false,
      );

      await ref
          .read(videoEngineProvider)
          .initialize(
            activeQuality,
            subtitle:
                ref.read(subtitlePrefsProvider).useCustomSubtitle ||
                    activeSubtitle.url.isEmpty == true
                ? null
                : activeSubtitle,
            startAt: startPosition,
          );

      _startProgressTracker();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> changeStream(VideoStream newStream) async {
    final engine = ref.read(videoEngineProvider);
    final currentPos = engine.currentPosition;

    // Remember the language this mirror represents.
    //
    // For these sources the mirror list *is* the language picker -- one label
    // carries both axes, `Japanese - 1080p`. changeQuality and changeAudioTrack
    // both persisted their choice; this one did not, so picking a language here
    // was forgotten the moment the next episode loaded and the mirror was
    // chosen from defaults again. _preferredAudioLang is what _loadData filters
    // the mirror list by, so writing it here is what makes the choice stick.
    final facet = StreamCatalog.from(state.streams).facetFor(newStream);

    final language = facet?.language;
    if (language != null && language.isNotEmpty) {
      _preferredAudioLang = language;
      _sourcePrefsNotifier?.setAudioLang(language);
    }

    // And the resolution, because on these sources this *is* the quality
    // picker too.
    //
    // One label carries both axes -- `Japanese - 1080p` -- so when the mirror
    // list has heights in it the panel routes the quality menu through here
    // rather than through changeQuality. This only ever wrote the language
    // down, so choosing a resolution on those sources was never saved and the
    // next episode came back at whatever the default said.
    final height = facet?.height;
    if (height != null) {
      _preferredQuality = '${height}p';
      _sourcePrefsNotifier?.setQuality('${height}p');
    }

    state = state.copyWith(
      isLoading: true,
      activeStream: newStream,
      subtitles: [...newStream.subtitles, SubtitleTrack.none],
      activeSubtitle: newStream.subtitles.firstOrNull ?? SubtitleTrack.none,
      error: null,
    );

    try {
      final httpClient = ref.read(httpClientProvider);
      final newQualities = <VideoStream>[newStream.copyWith(quality: 'Auto')];

      try {
        final parsedQualities = await httpClient.splitM3U8(
          newStream.url,
          headers: newStream.headers,
        );
        for (final q in parsedQualities) {
          newQualities.add(
            VideoStream(
              url: q.url,
              headers: newStream.headers,
              quality: q.quality,
              subtitles: newStream.subtitles,
            ),
          );
        }
      } catch (_) {}

      VideoStream activeQuality = newQualities.first;
      if (_preferredQuality != null && _preferredQuality != 'Auto') {
        final qualityMatch = newQualities.firstWhereOrNull(
          (s) => _matchesQuality(s.quality, _preferredQuality!),
        );
        if (qualityMatch != null) activeQuality = qualityMatch;
      }

      state = state.copyWith(
        qualities: newQualities,
        activeQuality: activeQuality,
        isLoading: false,
      );

      await engine.initialize(
        activeQuality,
        subtitle: ref.read(subtitlePrefsProvider).useCustomSubtitle
            ? null
            : newStream.subtitles.firstOrNull,
        startAt: currentPos,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to switch stream: $e',
      );
    }
  }

  Future<void> changeQuality(VideoStream newQuality) async {
    if (state.activeQuality?.quality == newQuality.quality &&
        state.activeQuality?.url == newQuality.url) {
      return;
    }

    _preferredQuality = newQuality.quality;
    _sourcePrefsNotifier?.setQuality(newQuality.quality);

    final engine = ref.read(videoEngineProvider);
    final currentPos = engine.currentPosition;

    state = state.copyWith(
      activeQuality: newQuality,
      isLoading: true,
      error: null,
    );

    try {
      await engine.initialize(
        newQuality,
        subtitle:
            ref.read(subtitlePrefsProvider).useCustomSubtitle ||
                state.activeSubtitle?.url.isEmpty == true
            ? null
            : state.activeSubtitle,
        startAt: currentPos,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to switch quality: $e',
      );
    }
  }

  Future<void> changeSubtitle(SubtitleTrack? newSubtitle) async {
    if (newSubtitle != null && newSubtitle.url.isNotEmpty) {
      _preferredSubtitleLang = newSubtitle.language;
      ref
          .read(playerPrefsProvider.notifier)
          .setDefaultSubtitleLang(newSubtitle.language);
    } else if (newSubtitle != null) {
      _preferredSubtitleLang = 'Off';
      ref.read(playerPrefsProvider.notifier).setDefaultSubtitleLang('Off');
    }

    state = state.copyWith(activeSubtitle: newSubtitle, error: null);
    await _applyNativeSubtitle(newSubtitle);
  }

  Future<void> changeAudioTrack(AudioTrack track) async {
    // Same axis as the mirror picker, so it is remembered the same way: on
    // the source, not as an app-wide default.
    if (track.language != null && track.language!.isNotEmpty) {
      _preferredAudioLang = track.language;
    } else if (track.id != 'auto' && track.id != 'no') {
      _preferredAudioLang = track.label;
    } else if (track.id == 'auto') {
      _preferredAudioLang = 'Auto';
    }
    final picked = _preferredAudioLang;
    if (picked != null) _sourcePrefsNotifier?.setAudioLang(picked);

    await ref.read(videoEngineProvider).setAudioTrack(track);
  }

  Future<void> changeSpeed(double speed) async {
    state = state.copyWith(playbackSpeed: speed);
    await ref.read(videoEngineProvider).setSpeed(speed);
  }

  /// Watches playback for auto-skip and auto-next.
  ///
  /// Registered once per episode. It used to snapshot prefs and stamps at
  /// registration, which is why the transport bar re-ran it on every position
  /// tick -- closing and reopening a subscription roughly once a second for
  /// the whole episode. Both inputs are read live instead.
  void setupAutoSkipListener(AniSkipArgs? args) {
    _positionSubscription?.close();
    _autoSkipArgs = args;

    _positionSubscription = ref.listen(
      videoEngineStateProvider.select((s) => s.position),
      (previous, current) => _onPositionTick(current),
    );
  }

  void _onPositionTick(Duration position) {
    final seconds = position.inSeconds;
    if (seconds <= 0) return;

    final prefs = ref.read(aniskipPrefsProvider);
    final skips = ref.read(aniSkipProvider(_autoSkipArgs)).value ?? const [];

    for (final skip in skips) {
      if (prefs.mode(skip.type) != SkipMode.auto) continue;
      if (seconds < skip.startTime || seconds >= skip.endTime) continue;
      if (_alreadyAutoSkipped.add(skip.type)) {
        ref
            .read(videoEngineProvider)
            .seekTo(Duration(seconds: skip.endTime.ceil()));
      }
    }

    _maybeAutoNext(position);
  }

  /// Rolls into the next episode as this one runs out.
  ///
  /// This lived in the skip button before, so moving that button onto its own
  /// layer would have quietly taken auto-next with it. It belongs here: it is
  /// playback behaviour, not a piece of the overlay.
  void _maybeAutoNext(Duration position) {
    if (_autoNextTriggered) return;

    final playerPrefs = ref.read(playerPrefsProvider);
    if (!playerPrefs.autoNext || !hasNextEpisode) return;

    // Never mid-switch or mid-scrub. Position and duration come from two
    // different places, and during a load or a drag they do not describe the
    // same moment.
    if (state.isLoading || ref.read(isScrubbingProvider)) {
      _lastTickPosition = position;
      return;
    }

    final duration = ref.read(videoEngineStateProvider).duration;
    if (duration.inSeconds <= 0) return;

    final remaining = duration.inSeconds - position.inSeconds;

    // A large negative remaining is not "past the end", it is a stale position
    // measured against a duration that has already moved on -- the old
    // episode's clock against the new episode's length.
    if (remaining < -5) return;

    final previous = _lastTickPosition;
    _lastTickPosition = position;

    // Did the clock tick, or did somebody move it? A seek shows up here as a
    // jump of more than a couple of seconds, forwards or backwards.
    final delta = previous == null
        ? null
        : (position - previous).inSeconds;
    final playedOn = delta != null && delta >= 0 && delta <= 3;

    if (!playedOn) {
      // Landed here rather than arrived. Scrubbing to the last minute and
      // pressing OK used to roll straight into the next episode: the commit
      // put the position inside the window and the very next tick took that
      // as the episode ending. Someone who seeks into the credits is choosing
      // to watch them.
      _autoNextArmed = remaining > _autoNextWindowSeconds;
      return;
    }

    // Outside the window: arm, so playing into it later counts.
    if (remaining > _autoNextWindowSeconds) {
      _autoNextArmed = true;
      return;
    }

    // Inside the window. Advance if we played in from outside it -- or if the
    // episode has genuinely run out, which is true however you got here.
    if (!_autoNextArmed && remaining > 1) return;

    _autoNextTriggered = true;
    skipEpisode();
  }

  /// Aims the scrub preview at the smallest rendition of the current episode.
  ///
  /// Safe to call whenever the quality list changes; a null result leaves the
  /// engine previewing whatever is playing, which is the old behaviour.
  Future<void> _startProgressTracker() async {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async => await _saveCurrentProgress(),
    );
  }

  /// Grabs the frame for the continue-watching row.
  ///
  /// Asks the engine rather than screenshotting the Flutter tree: on Android
  /// the video is a platform texture, so a RepaintBoundary capture of it comes
  /// back black.
  /// Supplied by the player screen. See [setFrameGrabber].
  Future<Uint8List?> Function()? _frameGrabber;

  /// Registers a way to read the frame currently on screen.
  ///
  /// ExoPlayer renders straight to a Surface and hands back no pixels, so
  /// grabCurrentFrame returns null on it -- and since it became the default
  /// engine, nothing was ever captured and every continue-watching card fell
  /// back to its placeholder. The screen can read the frame off its own
  /// RepaintBoundary, which is the only place those pixels are reachable.
  void setFrameGrabber(Future<Uint8List?> Function()? grab) {
    _frameGrabber = grab;
  }

  Future<String?> _captureThumbnail() async {
    try {
      // The engine first: mpv can screenshot itself, and its frame is the
      // decoded one rather than a readback of the composited surface.
      final image =
          await ref.read(videoEngineProvider).grabCurrentFrame() ??
          await _frameGrabber?.call();
      if (image != null) {
        _cachedThumbnail = base64Encode(image);
        _lastThumbnailTime = DateTime.now();
      }
    } catch (_) {}
    return _cachedThumbnail;
  }

  bool get _shouldCaptureThumbnail {
    if (!_initialCaptureDone) return true;
    if (_lastThumbnailTime == null) return true;
    return DateTime.now().difference(_lastThumbnailTime!) >=
        _thumbnailRefreshInterval;
  }

  Future<void> captureExitThumbnail() async {
    await _captureThumbnail();
    await _saveCurrentProgress(skipCapture: true);
  }

  Future<void> _saveCurrentProgress({bool skipCapture = false}) async {
    if (!ref.mounted) {
      _progressTimer?.cancel();
      return;
    }

    if (state.activeServer == null) return;

    final engine = ref.read(videoEngineProvider);
    final position = engine.currentPosition;
    final duration = engine.currentDuration;
    if (position == Duration.zero || duration == Duration.zero) return;

    if (_media == null) return;

    // Capture thumbnail only when needed
    if (!skipCapture && _shouldCaptureThumbnail) {
      await _captureThumbnail();
      _initialCaptureDone = true;
    }

    final thumbnail = _cachedThumbnail ?? '';

    final entry = WatchHistoryEntry()
      ..episodeNumber = state.activeEpisode?.number ?? 1
      ..totalEpisodes = _media!.episodes
      ..animeId = _media!.id
      ..animeIdMal = _media!.idMal
      ..animeTitle = _media!.title.availableTitle
      ..episodeTitle = state.activeEpisode?.title
      ..cover = _media!.cover
      ..banner = _media!.banner
      ..thumbnailUrl = thumbnail.isNotEmpty
          ? thumbnail
          : state.activeEpisode?.thumbnailUrl
      ..positionInMilliseconds = position.inMilliseconds
      ..durationInMilliseconds = duration.inMilliseconds
      ..sourceId = _source?.sourceInfo.id ?? _media!.sourceId
      ..sourceName = _source?.sourceInfo.name ?? _media!.sourceName
      ..providerId = _media!.providerId != _media!.id
          ? _media!.providerId
          : null
      ..lastUpdated = DateTime.now();

    ref.read(watchHistoryRepositoryProvider).saveProgress(entry);

    if (state.activeEpisode != null) {
      ref
          .read(syncEngineProvider)
          .processPlayback(
            media: _media!,
            episodeNumber: state.activeEpisode!.number,
            position: position,
            duration: duration,
          );
    }
  }
}

final playerControllerProvider =
    NotifierProvider.autoDispose<PlayerController, PlayerState>(
      PlayerController.new,
    );
