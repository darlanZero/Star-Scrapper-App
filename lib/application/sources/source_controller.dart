import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';

/// Owns bundled sources, activation preferences and book-to-source resolution.
class SourceController {
  static const _activeSourceIdsKey = 'activeSourceIds';

  final List<Fonte> sources;
  final void Function() onChanged;

  SourceController({
    List<Fonte>? sources,
    required this.onChanged,
  }) : sources = sources ?? SourceCatalog.createAll();

  Fonte get selected => sources.firstWhere(
        (source) => source.isActive,
        orElse: () => sources.first,
      );

  MangaSource get selectedApi => selected.api;

  List<Fonte> get active => sources.where((source) => source.isActive).toList();

  List<Fonte> get inactive =>
      sources.where((source) => !source.isActive).toList();

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final activeSourceIds = prefs.getStringList(_activeSourceIdsKey);
    final legacyActiveNames = prefs.getStringList('activeFonts') ?? const [];

    for (final source in sources) {
      source.isActive = activeSourceIds != null
          ? activeSourceIds.contains(source.id)
          : legacyActiveNames.contains(source.name) ||
              (prefs.getBool(source.name) ?? false);
    }

    if (activeSourceIds == null) await _save();
    onChanged();
  }

  Future<void> toggle(Fonte source) async {
    source.isActive = !source.isActive;
    await _save();
    onChanged();
  }

  MangaSource? findScrapperForBook(Map<String, dynamic> book) {
    final coverUrl = (book['coverImageUrl'] ?? book['link'] ?? '').toString();
    if (coverUrl.isEmpty) return null;
    final coverHost = Uri.tryParse(coverUrl)?.host;
    if (coverHost == null || coverHost.isEmpty) return null;

    for (final source in sources) {
      final baseHost = source.api.baseUri.host;
      if (_hostsMatch(coverHost, baseHost)) return source.api;

      final imageHost = Uri.tryParse(source.image)?.host ?? '';
      if (_hostsMatch(coverHost, imageHost)) return source.api;
    }
    return null;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _activeSourceIdsKey,
      active.map((source) => source.id).toList(),
    );
  }

  bool _hostsMatch(String bookHost, String sourceHost) {
    if (sourceHost.isEmpty) return false;
    return bookHost == sourceHost || bookHost.endsWith('.$sourceHost');
  }
}
