import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';

class AnimeLibraryStorage {
  static const favoritesKey = 'anime_library_favorites_v1';
  static const progressKey = 'anime_episode_progress_v1';

  Future<List<AnimeLibraryRecord>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(favoritesKey) ?? const [];
    return _decodeRecords(values, AnimeLibraryRecord.fromJson);
  }

  Future<void> saveFavorites(Iterable<AnimeLibraryRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      favoritesKey,
      records.map((record) => jsonEncode(record.toJson())).toList(),
    );
  }

  Future<List<AnimeEpisodeProgress>> loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(progressKey) ?? const [];
    return _decodeRecords(values, AnimeEpisodeProgress.fromJson);
  }

  Future<void> saveProgress(Iterable<AnimeEpisodeProgress> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      progressKey,
      records.map((record) => jsonEncode(record.toJson())).toList(),
    );
  }

  List<T> _decodeRecords<T>(
    Iterable<String> values,
    T Function(Map<dynamic, dynamic>) decode,
  ) {
    final records = <T>[];
    for (final value in values) {
      try {
        final json = jsonDecode(value);
        if (json is Map) records.add(decode(json));
      } catch (_) {
        // Preserve the remaining library when a single entry is corrupt.
      }
    }
    return records;
  }
}
