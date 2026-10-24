import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
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
    expect(ids, contains('goyabu'));
  });

  test('anime source presentation localizes audio labels by language', () {
    final sources = SourceCatalog.createAnimeSources();
    final aniwave = sources.singleWhere((source) => source.id == 'aniwave');
    final goyabu = sources.singleWhere((source) => source.id == 'goyabu');

    expect(aniwave.languageLabel, 'All languages');
    expect(aniwave.audioLabel, 'Sub/Dub');
    expect(aniwave.capabilityLabel, contains('Sub/Dub'));
    expect(aniwave.capabilityLabel, isNot(contains('Legendado')));
    expect(goyabu.languageLabel, 'Português (Brasil)');
    expect(goyabu.audioLabel, 'Legendado/Dublado');
    expect(goyabu.capabilityLabel, contains('Blogger'));
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
    expect(ids, contains('leitura_manga'));
    expect(ids, contains('hdoujin'));
  });

  test('Leitura Manga is a mixed PT-BR source, not an adult-only source', () {
    final source = SourceCatalog.createAll().singleWhere(
      (source) => source.id == 'leitura_manga',
    );

    expect(source.languagePrefix, 'Pt-BR');
    expect(source.isRRated, isFalse);
  });

  test('HDoujin is an All languages adult manga source', () {
    final source = SourceCatalog.createAll().singleWhere(
      (source) => source.id == 'hdoujin',
    );

    expect(source.languagePrefix, 'All');
    expect(source.contentType, SourceContentType.manga);
    expect(source.isRRated, isTrue);
    expect(source.api, isA<TaxonomyBrowsableMangaSource>());
    expect(
      source.api.catalogFilterLabel(MangaCatalogFilter.updated),
      'Recent doujin',
    );
  });
}
