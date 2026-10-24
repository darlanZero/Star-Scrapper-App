import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('bundled sources have unique stable identifiers', () {
    final sources = SourceCatalog.createAll();
    final ids = sources.map((source) => source.id).toList();

    expect(sources, isNotEmpty);
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, everyElement(matches(RegExp(r'^[a-z0-9_]+$'))));
  });

  test('bundled sources have unique display names', () {
    final sources = SourceCatalog.createAll();
    final names = sources.map((source) => source.name).toList();

    expect(names.toSet(), hasLength(names.length));
  });

  test('current bundled providers are explicitly manga sources', () {
    expect(
      SourceCatalog.createAll().map((source) => source.contentType),
      everyElement(SourceContentType.manga),
    );
  });

  test('bundled anime sources use their typed video contract', () {
    final sources = SourceCatalog.createAnimeSources();
    final ids = sources.map((source) => source.id).toList();

    expect(sources, isNotEmpty);
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, contains('anitube'));
    expect(ids, contains('aniwave'));
    expect(ids, contains('smart_animes'));
  });

  test('bundled manga sources use their typed contract with stable ids', () {
    final sources = SourceCatalog.createMangaSources();
    final ids = sources.map((source) => source.id).toList();

    expect(sources, isNotEmpty);
    expect(sources, everyElement(isA<MangaSource>()));
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, everyElement(matches(RegExp(r'^[a-z0-9_]+$'))));
    expect(ids, contains('mangadex'));
    expect(ids, contains('seita_celestial'));
    expect(ids, contains('luratoons'));
    expect(ids, contains('mediocrescan'));
  });
}
