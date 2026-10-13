import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/sources/anime_source_controller.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('persists anime source activation by stable id', () async {
    SharedPreferences.setMockInitialValues({});
    final source = _FakeAnimeSource();
    var changes = 0;
    final controller = AnimeSourceController(
      sources: [source],
      onChanged: () => changes++,
    );

    await controller.initialize();
    expect(controller.active, isEmpty);

    await controller.toggle(source);
    expect(controller.active, [source]);
    expect(changes, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('activeAnimeSourceIds'), ['fake_anime']);
  });

  test('ignores stale anime source ids', () async {
    SharedPreferences.setMockInitialValues({
      'activeAnimeSourceIds': ['removed_source'],
    });
    final controller = AnimeSourceController(
      sources: [_FakeAnimeSource()],
      onChanged: () {},
    );

    await controller.initialize();

    expect(controller.active, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('activeAnimeSourceIds'), isEmpty);
  });
}

class _FakeAnimeSource implements AnimeSource {
  @override
  Uri get baseUri => Uri.parse('https://anime.example/');

  @override
  String get id => 'fake_anime';

  @override
  String get name => 'Fake Anime';

  @override
  Map<String, String> get requestHeaders => const {};

  @override
  List<AnimeCatalogFilter> get catalogFilters =>
      const [AnimeCatalogFilter.recent];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.popular,
    String? cursor,
  }) =>
      throw UnimplementedError();

  @override
  Future<AnimeDetails> getDetails(String animeId) => throw UnimplementedError();

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) =>
      throw UnimplementedError();

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) =>
      throw UnimplementedError();

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) =>
      throw UnimplementedError();
}
