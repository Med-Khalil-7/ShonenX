import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_category.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:shonenx/features/discovery/domain/models/home_section.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/features/discovery/providers/discovery_prefs_provider.dart';
import 'package:shonenx/source_engine/source_engine_provider.dart';
import 'package:shonenx/features/tracking/engine/remote_tracker.dart';

class UserHomeLayoutNotifier extends Notifier<List<HomeSection>> {
  SharedPreferences get _storage => ref.read(sharedPreferencesProvider);

  /// Bumped when the shipped default changes shape.
  ///
  /// The default only applies when nothing is stored, so without a new key an
  /// existing install keeps whatever the first run wrote -- which is how it
  /// ended up showing a single row. A hand-ordered layout is lost once; it is
  /// re-editable in Settings -> Home.
  static const _schemaVersion = 2;

  String get _dataKey {
    final prefs = ref.read(discoveryPrefsProvider);
    if (prefs.mode == MetadataMode.source) {
      return 'home_layout_source_v$_schemaVersion';
    } else {
      final tracker = ref.read(metadataSourceProvider);
      return 'home_layout_tracker_${tracker.type.name}_v$_schemaVersion';
    }
  }

  @override
  List<HomeSection> build() {
    final prefs = ref.watch(discoveryPrefsProvider);
    RemoteTracker? tracker;
    if (prefs.mode == MetadataMode.tracker) {
      tracker = ref.watch(metadataSourceProvider);
    }

    final key = _dataKey;
    final json = _storage.getStringList(key);

    if (json != null && json.isNotEmpty) {
      return json.map((e) => HomeSection.fromJson(e)).toList();
    }

    if (prefs.mode == MetadataMode.source || tracker == null) {
      // One discovery section only. In source mode the feed provider ignores
      // the category and always asks the extension for its trending list, so
      // N category rows would be N copies of the same list; the home screen
      // fans this one section out to a row per active extension instead.
      // Continue Watching leads. It is the only row whose contents the user
      // put there themselves, and the one thing they are most likely to have
      // opened Home to reach; a category row is browsing, and browsing can
      // wait a scroll.
      return const [
        HomeSection(
          id: '1',
          title: 'Continue Watching',
          type: HomeSectionType.continueMedia,
          targetMediaType: MediaType.ANIME,
        ),
        HomeSection(
          id: '3',
          title: 'Trending Anime',
          type: HomeSectionType.discovery,
          targetMediaType: MediaType.ANIME,
          trackerCategory: TrackerCategory.trending,
        ),
      ];
    } else {
      int idCounter = 1;
      final sections = <HomeSection>[];

      // Continue Watching leads, ahead of every category. It is the only row
      // whose contents the user put there themselves, and the one thing they
      // are most likely to have opened Home to reach.
      for (final media in tracker.supportedMediaTypes) {
        sections.add(
          HomeSection(
            id: (idCounter++).toString(),
            title: 'Continue Watching',
            type: HomeSectionType.continueMedia,
            targetMediaType: media,
          ),
        );
      }

      // A row per category the tracker actually serves. AniList gives
      // Trending Now, All-Time Popular, Top Rated All-Time and Upcoming Next
      // Season; the previous default asked for Trending and stopped, which is
      // why Home opened onto a single row.
      for (final category in tracker.supportedCategories) {
        for (final media in tracker.supportedMediaTypes) {
          sections.add(
            HomeSection(
              id: (idCounter++).toString(),
              // Only qualify with the media type when there is more than one
              // to tell apart -- "Trending Now Anime" reads as a typo when
              // anime is the only thing the app carries.
              title: tracker.supportedMediaTypes.length > 1
                  ? '${category.label} ${media.displayName}'
                  : category.label,
              type: HomeSectionType.discovery,
              targetMediaType: media,
              trackerCategory: category,
            ),
          );
        }
      }

      return sections;
    }
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;

    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    state = list;
    _saveDb();
  }

  void addSection(HomeSection section) {
    state = [...state, section];
    _saveDb();
  }

  void removeSection(String id) {
    state = state.where((e) => e.id != id).toList();
    _saveDb();
  }

  void updateSection(HomeSection updated) {
    state = [
      for (final s in state)
        if (s.id == updated.id) updated else s,
    ];
    _saveDb();
  }

  void reset() {
    _storage.remove(_dataKey);
    ref.invalidateSelf();
  }

  void setSections(List<HomeSection> sections) {
    state = sections;
    _saveDb();
  }

  void _saveDb() {
    _storage.setStringList(_dataKey, state.map((e) => e.toJson()).toList());
  }
}

final userHomeLayoutProvider =
    NotifierProvider<UserHomeLayoutNotifier, List<HomeSection>>(
      UserHomeLayoutNotifier.new,
      name: 'userHomeLayoutProvider',
    );
