import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Owns anime/video source activation independently from legacy manga sources.
class AnimeSourceController {
  static const _activeSourceIdsKey = 'activeAnimeSourceIds';

  final List<AnimeSource> sources;
  final void Function() onChanged;
  final Set<String> _activeIds = {};

  AnimeSourceController({
    List<AnimeSource>? sources,
    required this.onChanged,
  }) : sources = sources ?? SourceCatalog.createAnimeSources();

  List<AnimeSource> get active =>
      sources.where((source) => _activeIds.contains(source.id)).toList();

  List<AnimeSource> get inactive =>
      sources.where((source) => !_activeIds.contains(source.id)).toList();

  bool isActive(AnimeSource source) => _activeIds.contains(source.id);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _activeIds
      ..clear()
      ..addAll(prefs.getStringList(_activeSourceIdsKey) ?? const []);
    _activeIds.removeWhere(
      (id) => !sources.any((source) => source.id == id),
    );
    await _save();
    onChanged();
  }

  Future<void> toggle(AnimeSource source) async {
    if (!_activeIds.remove(source.id)) _activeIds.add(source.id);
    await _save();
    onChanged();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _activeSourceIdsKey,
      sources
          .where((source) => _activeIds.contains(source.id))
          .map((source) => source.id)
          .toList(),
    );
  }
}
