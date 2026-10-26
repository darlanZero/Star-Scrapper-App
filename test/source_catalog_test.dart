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
    expect(ids, contains('hentai_haven'));
    expect(ids, contains('animeq'));
  });

  test('anime source presentation localizes audio labels by language', () {
    final sources = SourceCatalog.createAnimeSources();
    final aniwave = sources.singleWhere((source) => source.id == 'aniwave');
    final goyabu = sources.singleWhere((source) => source.id == 'goyabu');
    final animeQ = sources.singleWhere((source) => source.id == 'animeq');

    expect(aniwave.languageLabel, 'All languages');
    expect(aniwave.audioLabel, 'Sub/Dub');
    expect(aniwave.capabilityLabel, contains('Sub/Dub'));
    expect(aniwave.capabilityLabel, isNot(contains('Legendado')));
    expect(goyabu.languageLabel, 'Português (Brasil)');
    expect(goyabu.audioLabel, 'Legendado/Dublado');
    expect(goyabu.capabilityLabel, contains('Blogger'));
    expect(animeQ.languageLabel, 'Português (Brasil)');
    expect(animeQ.isRRated, isFalse);
    expect(animeQ.capabilityLabel, contains('MP4'));
    final hentaiHaven =
        sources.singleWhere((source) => source.id == 'hentai_haven');
    expect(hentaiHaven.isRRated, isTrue);
    expect(hentaiHaven.capabilityLabel, startsWith('R-rated'));
  });

  test('anime sources are grouped by language in display order', () {
    final groups = SourceCatalog.createAnimeSources().groupedByLanguage;

    expect(groups.keys, ['All Languages', 'PT-BR']);
    expect(
      groups['All Languages']!.map((source) => source.id),
      ['anitube', 'aniwave', 'hentai_haven'],
    );
    expect(
      groups['PT-BR']!.map((source) => source.id),
      ['smart_animes', 'goyabu', 'animeq'],
    );
    expect(
      () => groups['PT-BR']!.add(SourceCatalog.createAnimeSources().first),
      throwsUnsupportedError,
    );
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
    expect(ids, contains('imperio_britannia'));
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

  test('Império da Britannia is a mixed PT-BR authenticated source', () {
    final source = SourceCatalog.createAll().singleWhere(
      (source) => source.id == 'imperio_britannia',
    );

    expect(source.languagePrefix, 'Pt-BR');
    expect(source.isRRated, isFalse);
    expect(source.api, isA<CredentialAuthMangaSource>());
    expect(source.api, isA<BrowserSessionMangaSource>());
    expect(source.api, isA<FilterableMangaSource>());
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
