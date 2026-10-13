import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/library/anime_library_storage.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/application/library/library_organization_contracts.dart';

class AnimeLibraryController extends ChangeNotifier
    implements LibraryOrganizationUpdater {
  final AnimeLibraryStorage storage;
  final Map<String, AnimeLibraryRecord> _favorites = {};
  final Map<String, AnimeEpisodeProgress> _progress = {};
  bool _initialized = false;
  bool _trackerEnabled = true;
  Duration _updateInterval = const Duration(hours: 24);
  Set<String> _tabsToUpdate = {};
  DateTime? _trackerLastCheckedAt;
  Map<String, String> _latestEpisodeByAnime = {};
  List<AnimeSource> _sources = const [];
  LibraryTabConfiguration? _tabConfiguration;
  bool _tabConfigurationReady = false;
  Timer? _updateTimer;

  AnimeLibraryController({AnimeLibraryStorage? storage})
      : storage = storage ?? AnimeLibraryStorage();

  bool get initialized => _initialized;
  bool get trackerEnabled => _trackerEnabled;
  Duration get updateInterval => _updateInterval;
  Set<String> get tabsToUpdate => Set.unmodifiable(_tabsToUpdate);
  DateTime? get trackerLastCheckedAt => _trackerLastCheckedAt;

  List<AnimeLibraryRecord> get favorites {
    final values = _favorites.values.toList()
      ..sort((a, b) => b.addedAtMillis.compareTo(a.addedAtMillis));
    return List.unmodifiable(values);
  }

  List<AnimeEpisodeProgress> get history {
    final values = _progress.values.toList()
      ..sort((a, b) => b.lastPlayedAtMillis.compareTo(a.lastPlayedAtMillis));
    return List.unmodifiable(values);
  }

  List<AnimeLibraryRecord> favoritesInTab(String tab) => favorites
      .where((record) => record.tabs.contains(tab))
      .toList(growable: false);

  List<AnimeLibraryRecord> favoritesInTabAndSubtab(
    String tab,
    String subtab,
  ) =>
      favorites
          .where(
            (record) =>
                record.tabs.contains(tab) &&
                (record.subTabsByPrimary[tab] ?? const []).contains(subtab),
          )
          .toList(growable: false);

  Future<void> moveTo({
    required AnimeLibraryRecord record,
    required String primaryTab,
    String? subTab,
  }) async {
    _replace(
      record.copyWith(
        tabs: [primaryTab],
        subTabsByPrimary: {
          if (subTab != null && subTab.isNotEmpty) primaryTab: [subTab],
        },
      ),
    );
    notifyListeners();
    await storage.saveFavorites(_favorites.values);
  }

  Future<void> renameAnime(
    AnimeLibraryRecord record,
    String title,
  ) async {
    final normalized = title.trim();
    if (normalized.isEmpty) return;
    _replace(record.copyWith(title: normalized));
    notifyListeners();
    await storage.saveFavorites(_favorites.values);
  }

  Future<void> refreshFavoriteMetadata({
    required String sourceId,
    required AnimeDetails details,
  }) async {
    final key = _animeKey(sourceId, details.item.id);
    final current = _favorites[key];
    if (current == null) return;

    _favorites[key] = AnimeLibraryRecord(
      sourceId: current.sourceId,
      animeId: current.animeId,
      title: current.title,
      coverUrl: details.item.coverUri?.toString() ?? current.coverUrl,
      bannerUrl: details.bannerUri?.toString() ?? current.bannerUrl,
      subtitle: details.item.subtitle ?? current.subtitle,
      addedAtMillis: current.addedAtMillis,
      tabs: current.tabs,
      subTabsByPrimary: current.subTabsByPrimary,
      studios: details.studios.isEmpty ? current.studios : details.studios,
      producers:
          details.producers.isEmpty ? current.producers : details.producers,
    );
    notifyListeners();
    await storage.saveFavorites(_favorites.values);
  }

  Future<void> migrateAnime({
    required AnimeLibraryRecord record,
    required String targetSourceId,
    required AnimeDetails targetDetails,
    required Map<String, AnimeEpisode> episodeMatches,
  }) async {
    final migrated = AnimeLibraryRecord(
      sourceId: targetSourceId,
      animeId: targetDetails.item.id,
      title: record.title,
      coverUrl: targetDetails.item.coverUri?.toString(),
      bannerUrl: targetDetails.bannerUri?.toString(),
      subtitle: targetDetails.item.subtitle,
      addedAtMillis: record.addedAtMillis,
      tabs: record.tabs,
      subTabsByPrimary: record.subTabsByPrimary,
      studios: targetDetails.studios,
      producers: targetDetails.producers,
    );
    _favorites
      ..remove(record.key)
      ..[migrated.key] = migrated;

    for (final old in progressForAnime(
      sourceId: record.sourceId,
      animeId: record.animeId,
    )) {
      final target = episodeMatches[old.episodeId];
      if (target == null) continue;
      _progress.remove(old.key);
      final replacement = AnimeEpisodeProgress(
        sourceId: targetSourceId,
        animeId: targetDetails.item.id,
        episodeId: target.id,
        episodeTitle: target.title,
        episodeNumber: target.number,
        positionMillis: old.positionMillis,
        durationMillis: old.durationMillis,
        lastPlayedAtMillis: old.lastPlayedAtMillis,
        viewed: old.viewed,
        completed: old.completed,
        animeTitle: migrated.title,
        animeCoverUrl: migrated.coverUrl,
      );
      _progress[replacement.key] = replacement;
    }
    notifyListeners();
    await Future.wait([
      storage.saveFavorites(_favorites.values),
      storage.saveProgress(_progress.values),
    ]);
  }

  Future<void> initialize() async {
    final loaded = await Future.wait([
      storage.loadFavorites(),
      storage.loadProgress(),
    ]);
    _favorites
      ..clear()
      ..addEntries(
        loaded[0].cast<AnimeLibraryRecord>().map(
              (record) => MapEntry(record.key, record),
            ),
      );
    _progress
      ..clear()
      ..addEntries(
        loaded[1].cast<AnimeEpisodeProgress>().map(
              (record) => MapEntry(record.key, record),
            ),
      );
    _initialized = true;
    await _loadTrackerSettings();
    if (_tabConfigurationReady) {
      await _repairFavoriteTabAssignments();
    }
    notifyListeners();
  }

  void configureTabs(
    LibraryTabConfiguration configuration, {
    Future<void>? ready,
  }) {
    if (identical(_tabConfiguration, configuration)) return;
    _tabConfiguration = configuration;
    if (ready == null) {
      _tabConfigurationReady = true;
      if (_initialized) unawaited(_repairFavoriteTabAssignments());
      return;
    }
    unawaited(
      ready.then((_) {
        if (!identical(_tabConfiguration, configuration)) return;
        _tabConfigurationReady = true;
        if (_initialized) unawaited(_repairFavoriteTabAssignments());
      }),
    );
  }

  void setSources(List<AnimeSource> sources) {
    _sources = List.unmodifiable(sources);
    _scheduleUpdates();
  }

  Future<void> setTrackerEnabled(bool value) async {
    _trackerEnabled = value;
    await _saveTrackerSettings();
    _scheduleUpdates();
    notifyListeners();
  }

  Future<void> setUpdateInterval(Duration value) async {
    if (value.inHours <= 0) return;
    _updateInterval = value;
    await _saveTrackerSettings();
    _scheduleUpdates();
    notifyListeners();
  }

  Future<void> setTabsToUpdate(Set<String> value) async {
    _tabsToUpdate = Set.of(value);
    await _saveTrackerSettings();
    notifyListeners();
  }

  Future<int> runTrackerNow() async {
    var changes = 0;
    final selected = _tabsToUpdate.isEmpty
        ? favorites
        : favorites.where(
            (record) => record.tabs.any(_tabsToUpdate.contains),
          );
    for (final record in selected) {
      final source =
          _sources.where((item) => item.id == record.sourceId).firstOrNull;
      if (source == null) continue;
      try {
        final episodes = await source.getEpisodes(record.animeId);
        if (episodes.isEmpty) continue;
        final token = episodes.last.id;
        final previous = _latestEpisodeByAnime[record.key];
        if (previous != null && previous != token) changes++;
        _latestEpisodeByAnime[record.key] = token;
      } catch (_) {
        // A failing source must not stop updates from the other sources.
      }
    }
    _trackerLastCheckedAt = DateTime.now();
    await _saveTrackerSettings();
    notifyListeners();
    return changes;
  }

  Future<void> _loadTrackerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _trackerEnabled = prefs.getBool('animeTrackerEnabled') ?? true;
    _updateInterval = Duration(
      hours: prefs.getInt('animeUpdateIntervalHours') ?? 24,
    );
    _tabsToUpdate =
        (prefs.getStringList('animeTabsToUpdate') ?? const []).toSet();
    final checked = prefs.getInt('animeTrackerLastCheckedAtMs') ?? 0;
    _trackerLastCheckedAt =
        checked == 0 ? null : DateTime.fromMillisecondsSinceEpoch(checked);
    try {
      final decoded = jsonDecode(
        prefs.getString('animeLatestEpisodeByTitle') ?? '{}',
      );
      if (decoded is Map) {
        _latestEpisodeByAnime = decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      _latestEpisodeByAnime = {};
    }
    _scheduleUpdates();
  }

  Future<void> _saveTrackerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('animeTrackerEnabled', _trackerEnabled),
      prefs.setInt('animeUpdateIntervalHours', _updateInterval.inHours),
      prefs.setStringList('animeTabsToUpdate', _tabsToUpdate.toList()),
      prefs.setInt(
        'animeTrackerLastCheckedAtMs',
        _trackerLastCheckedAt?.millisecondsSinceEpoch ?? 0,
      ),
      prefs.setString(
        'animeLatestEpisodeByTitle',
        jsonEncode(_latestEpisodeByAnime),
      ),
    ]);
  }

  void _scheduleUpdates() {
    _updateTimer?.cancel();
    if (!_trackerEnabled || _sources.isEmpty) return;
    _updateTimer = Timer.periodic(_updateInterval, (_) => runTrackerNow());
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  bool isFavorite(String sourceId, String animeId) =>
      _favorites.containsKey(_animeKey(sourceId, animeId));

  Future<bool> toggleFavorite({
    required String sourceId,
    required AnimeDetails details,
  }) async {
    final key = _animeKey(sourceId, details.item.id);
    final added = !_favorites.containsKey(key);
    if (added) {
      final placement = _defaultTabPlacement();
      _favorites[key] = AnimeLibraryRecord.fromDetails(
        sourceId: sourceId,
        details: details,
        primaryTab: placement.primary,
        subTab: placement.subtab,
      );
    } else {
      _favorites.remove(key);
    }
    notifyListeners();
    await storage.saveFavorites(_favorites.values);
    return added;
  }

  ({String primary, String? subtab}) _defaultTabPlacement() {
    final configuration = _tabConfigurationReady ? _tabConfiguration : null;
    final primary = configuration?.libraryTabs.firstOrNull ?? 'Watching';
    final subtab = configuration?.getDefaultSubTabForPrimary(primary);
    return (
      primary: primary,
      subtab: subtab == null || subtab.isEmpty ? null : subtab,
    );
  }

  Future<void> _repairFavoriteTabAssignments() async {
    final configuration = _tabConfiguration;
    if (!_initialized || !_tabConfigurationReady || configuration == null) {
      return;
    }
    final availableTabs = configuration.libraryTabs;
    if (availableTabs.isEmpty) return;

    var changed = false;
    for (final record in _favorites.values.toList()) {
      var tabs = record.tabs
          .where(availableTabs.contains)
          .toSet()
          .toList(growable: false);
      if (tabs.isEmpty) tabs = [availableTabs.first];

      final subtabs = <String, List<String>>{};
      for (final tab in tabs) {
        final availableSubtabs = configuration.getSubTabsForPrimary(tab);
        if (availableSubtabs.isEmpty) continue;
        var selected = (record.subTabsByPrimary[tab] ?? const <String>[])
            .where(availableSubtabs.contains)
            .toSet()
            .toList(growable: false);
        if (selected.isEmpty) {
          final fallback = configuration.getDefaultSubTabForPrimary(tab);
          selected = [
            if (fallback.isNotEmpty && availableSubtabs.contains(fallback))
              fallback
            else
              availableSubtabs.first,
          ];
        }
        subtabs[tab] = selected;
      }

      if (!listEquals(record.tabs, tabs) ||
          !_sameSubtabs(record.subTabsByPrimary, subtabs)) {
        _replace(record.copyWith(tabs: tabs, subTabsByPrimary: subtabs));
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    await storage.saveFavorites(_favorites.values);
  }

  bool _sameSubtabs(
    Map<String, List<String>> left,
    Map<String, List<String>> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!listEquals(entry.value, right[entry.key])) return false;
    }
    return true;
  }

  AnimeEpisodeProgress? progressFor({
    required String sourceId,
    required String animeId,
    required String episodeId,
  }) =>
      _progress[_episodeKey(sourceId, animeId, episodeId)];

  List<AnimeEpisodeProgress> progressForAnime({
    required String sourceId,
    required String animeId,
  }) {
    final values = _progress.values
        .where(
          (record) => record.sourceId == sourceId && record.animeId == animeId,
        )
        .toList()
      ..sort(
        (a, b) => b.lastPlayedAtMillis.compareTo(a.lastPlayedAtMillis),
      );
    return List.unmodifiable(values);
  }

  AnimeEpisodeProgress? lastProgressForAnime({
    required String sourceId,
    required String animeId,
  }) {
    final values = progressForAnime(sourceId: sourceId, animeId: animeId);
    return values.isEmpty ? null : values.first;
  }

  Future<AnimeEpisodeProgress> markEpisodeViewed({
    required String sourceId,
    required AnimeEpisode episode,
    AnimeDetails? details,
  }) async {
    final key = _episodeKey(sourceId, episode.animeId, episode.id);
    final previous = _progress[key];
    final record = AnimeEpisodeProgress(
      sourceId: sourceId,
      animeId: episode.animeId,
      episodeId: episode.id,
      episodeTitle: episode.title,
      episodeNumber: episode.number,
      positionMillis: previous?.positionMillis ?? 0,
      durationMillis: previous?.durationMillis ?? 0,
      lastPlayedAtMillis: DateTime.now().millisecondsSinceEpoch,
      viewed: true,
      completed: previous?.completed ?? false,
      animeTitle: details?.item.title ?? previous?.animeTitle,
      animeCoverUrl:
          details?.item.coverUri?.toString() ?? previous?.animeCoverUrl,
    );
    _progress[key] = record;
    notifyListeners();
    await storage.saveProgress(_progress.values);
    return record;
  }

  Future<bool> saveEpisodePosition({
    required String sourceId,
    required AnimeEpisode episode,
    required Duration position,
    required Duration duration,
    AnimeDetails? details,
  }) async {
    final key = _episodeKey(sourceId, episode.animeId, episode.id);
    final current = _progress[key] ??
        AnimeEpisodeProgress(
          sourceId: sourceId,
          animeId: episode.animeId,
          episodeId: episode.id,
          episodeTitle: episode.title,
          episodeNumber: episode.number,
          lastPlayedAtMillis: DateTime.now().millisecondsSinceEpoch,
          animeTitle: details?.item.title,
          animeCoverUrl: details?.item.coverUri?.toString(),
        );
    final completed = duration > Duration.zero &&
        (position.inMilliseconds / duration.inMilliseconds >= 0.9 ||
            duration - position <= const Duration(seconds: 30));
    final newlyCompleted = completed && !current.completed;
    _progress[key] = current.copyWith(
      positionMillis: position.inMilliseconds.clamp(
          0,
          duration > Duration.zero
              ? duration.inMilliseconds
              : position.inMilliseconds),
      durationMillis: duration.inMilliseconds,
      lastPlayedAtMillis: DateTime.now().millisecondsSinceEpoch,
      viewed: true,
      completed: completed,
      animeTitle: details?.item.title,
      animeCoverUrl: details?.item.coverUri?.toString(),
    );
    notifyListeners();
    await storage.saveProgress(_progress.values);
    return newlyCompleted;
  }

  Duration resumePosition({
    required String sourceId,
    required String animeId,
    required String episodeId,
  }) {
    final progress = progressFor(
      sourceId: sourceId,
      animeId: animeId,
      episodeId: episodeId,
    );
    return progress?.canResume == true ? progress!.position : Duration.zero;
  }

  static String _animeKey(String sourceId, String animeId) =>
      '$sourceId::$animeId';

  static String _episodeKey(
    String sourceId,
    String animeId,
    String episodeId,
  ) =>
      '$sourceId::$animeId::$episodeId';

  void _replace(AnimeLibraryRecord record) => _favorites[record.key] = record;

  void _persistOrganization() {
    notifyListeners();
    storage.saveFavorites(_favorites.values);
  }

  @override
  void renamePrimaryTabBooks(String oldName, String newName) {
    for (final record in _favorites.values.toList()) {
      if (!record.tabs.contains(oldName)) continue;
      final tabs =
          record.tabs.map((tab) => tab == oldName ? newName : tab).toList();
      final subtabs = Map<String, List<String>>.from(record.subTabsByPrimary);
      final moved = subtabs.remove(oldName);
      if (moved != null) subtabs[newName] = moved;
      _replace(record.copyWith(tabs: tabs, subTabsByPrimary: subtabs));
    }
    _persistOrganization();
  }

  @override
  void remapBooksFromRemovedTab(String removedTab, String defaultTab) {
    for (final record in _favorites.values.toList()) {
      if (!record.tabs.contains(removedTab)) continue;
      final tabs = record.tabs.where((tab) => tab != removedTab).toList();
      if (!tabs.contains(defaultTab)) tabs.add(defaultTab);
      final subtabs = Map<String, List<String>>.from(record.subTabsByPrimary)
        ..remove(removedTab);
      _replace(record.copyWith(tabs: tabs, subTabsByPrimary: subtabs));
    }
    _persistOrganization();
  }

  @override
  void renameSubTabBooks(String primaryTab, String oldName, String newName) {
    for (final record in _favorites.values.toList()) {
      final current = record.subTabsByPrimary[primaryTab];
      if (current == null || !current.contains(oldName)) continue;
      final subtabs = Map<String, List<String>>.from(record.subTabsByPrimary);
      subtabs[primaryTab] =
          current.map((name) => name == oldName ? newName : name).toList();
      _replace(record.copyWith(subTabsByPrimary: subtabs));
    }
    _persistOrganization();
  }

  @override
  void remapBooksFromRemovedSubTab(
    String primaryTab,
    String removedSubTab,
    String defaultSubTab,
  ) {
    for (final record in _favorites.values.toList()) {
      final current = record.subTabsByPrimary[primaryTab];
      if (current == null || !current.contains(removedSubTab)) continue;
      final values = current.where((name) => name != removedSubTab).toList();
      if (defaultSubTab.isNotEmpty && !values.contains(defaultSubTab)) {
        values.add(defaultSubTab);
      }
      final subtabs = Map<String, List<String>>.from(record.subTabsByPrimary)
        ..[primaryTab] = values;
      _replace(record.copyWith(subTabsByPrimary: subtabs));
    }
    _persistOrganization();
  }

  @override
  void nestPrimaryAsSubTab(String oldPrimaryTab, String targetPrimary) {
    for (final record in _favorites.values.toList()) {
      if (!record.tabs.contains(oldPrimaryTab)) continue;
      final tabs = record.tabs.where((tab) => tab != oldPrimaryTab).toList();
      if (!tabs.contains(targetPrimary)) tabs.add(targetPrimary);
      final subtabs = Map<String, List<String>>.from(record.subTabsByPrimary)
        ..remove(oldPrimaryTab);
      final target = [...?subtabs[targetPrimary]];
      if (!target.contains(oldPrimaryTab)) target.add(oldPrimaryTab);
      subtabs[targetPrimary] = target;
      _replace(record.copyWith(tabs: tabs, subTabsByPrimary: subtabs));
    }
    _persistOrganization();
  }
}
