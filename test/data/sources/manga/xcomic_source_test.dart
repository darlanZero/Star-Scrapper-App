import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/xcomic_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps xComic structured filters and all sort modes', () async {
    Uri? requested;
    final source = XComicSource(
      baseUri: Uri.parse('https://xcomic.test'),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(_catalogFixture, 200);
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.types.map((value) => value.label), contains('Imageset'));
    expect(options.demographics, hasLength(12));
    expect(options.originalLanguages, hasLength(4));
    expect(options.translatedLanguages.map((value) => value.value),
        contains('pt-br'));
    expect(options.chapterPresets.map((value) => value.label),
        contains('100–199'));
    expect(options.sorts, contains(MangaSearchSort.mostComments));

    await source.filterCatalog(
      MangaSearchRequest(
        types: {'manga', 'manhwa'},
        formats: {'full_color'},
        genres: {'action'},
        demographics: {'shounen'},
        originalLanguages: {'ja'},
        translatedLanguages: {'en', 'pt-br'},
        statuses: {'releasing'},
        chapterPreset: '100-199',
        minimumYear: 2018,
        maximumYear: 2026,
        sort: MangaSearchSort.mostComments,
      ),
      cursor: '3',
    );

    expect(requested?.path, '/search');
    expect(requested?.queryParameters['types'], 'manga,manhwa');
    expect(requested?.queryParameters['genres_in'],
        anyOf('action,full_color', 'full_color,action'));
    expect(requested?.queryParameters['demographic'], 'shounen');
    expect(requested?.queryParameters['orig'], 'ja');
    expect(requested?.queryParameters['lang'], 'en,pt-br');
    expect(requested?.queryParameters['status'], 'releasing');
    expect(requested?.queryParameters['chapters'], '100-199');
    expect(requested?.queryParameters['year_min'], '2018');
    expect(requested?.queryParameters['year_max'], '2026');
    expect(requested?.queryParameters['sortby'], 'comment');
    expect(requested?.queryParameters['page'], '3');
  });

  test('parses catalog cards and pagination', () async {
    final source = XComicSource(
      baseUri: Uri.parse('https://xcomic.test'),
      client: MockClient((_) async => http.Response(_catalogFixture, 200)),
    );

    final page = await source.browse(filter: MangaCatalogFilter.updated);

    expect(page.items, hasLength(1));
    expect(page.items.single.id, 'hero');
    expect(page.items.single.title, 'Example Hero');
    expect(page.items.single.coverUri.toString(),
        'https://xcomic.test/covers/hero.webp');
    expect(page.items.single.subtitle, contains('120 Ch'));
    expect(page.nextCursor, '2');
  });

  test('keeps chapters from separate scans and languages distinct', () async {
    final source = XComicSource(
      baseUri: Uri.parse('https://xcomic.test'),
      client: MockClient((request) async {
        final body = switch (request.url.path) {
          '/title/hero' => _detailsFixture,
          '/source/brscan' => _brSourceFixture,
          '/source/enscan' => _enSourceFixture,
          _ => '<html></html>',
        };
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );

    final details = await source.getDetails('hero');

    expect(details.item.title, 'Example Hero');
    expect(details.description, 'A multilingual example.');
    expect(details.chapters, hasLength(3));
    expect(details.chapters.where((chapter) => chapter.number == '2'),
        hasLength(2));
    expect(details.chapters.map((chapter) => chapter.language).toSet(),
        {'pt-br', 'en'});
    expect(details.chapters.map((chapter) => chapter.scanId).toSet(),
        {'brscan', 'enscan'});
    expect(
        details.chapters
            .firstWhere((chapter) => chapter.scanId == 'brscan')
            .scanName,
        'BR Team');
    expect(
      details.chapters
          .firstWhere((chapter) => chapter.scanId == 'brscan')
          .missingChapters,
      'missing(2): 3-4',
    );
  });

  test('streams all native reader images with chapter referer', () async {
    final source = XComicSource(
      baseUri: Uri.parse('https://xcomic.test'),
      client: MockClient((_) async => http.Response(_readerFixture, 200)),
    );

    final pages = await source
        .readChapter(mangaId: 'hero', chapterId: '/chapter/br2')
        .toList();

    expect(pages, hasLength(2));
    expect(pages.first.uri.toString(), 'https://img.test/1.webp');
    expect(pages.last.uri.toString(), 'https://xcomic.test/images/2.webp');
    expect(pages.first.headers['Referer'], 'https://xcomic.test/chapter/br2');
  });

  test('extracts reader images from Qwik state before hydration', () async {
    final source = XComicSource(
      baseUri: Uri.parse('https://xcomic.test'),
      client: MockClient((_) async => http.Response(_qwikReaderFixture, 200)),
    );

    final pages = await source
        .readChapter(mangaId: 'hero', chapterId: '/chapter/qwik1')
        .toList();

    expect(pages.map((page) => page.uri.toString()), [
      'https://i01.img01.org/pages/1.webp',
      'https://i02.img02.org/pages/2.webp',
    ]);
    expect(
      pages.first.headers['Referer'],
      'https://xcomic.test/chapter/qwik1',
    );
  });
}

const _catalogFixture = '''
<html><body><main>
  <div class="card">
    <a href="/title/hero"><img src="/covers/hero.webp"></a>
    <a href="/title/hero">Example Hero</a>
    <span>8.7 · Manga · 2022 · releasing · 120 chapters</span>
  </div>
  <a href="/search?sortby=update&page=2">2</a>
</main></body></html>
''';

const _detailsFixture = '''
<html><head><meta name="description" content="A multilingual example."></head>
<body><main>
  <div><img src="/covers/hero.webp"><h1><a href="/title/hero">Example Hero</a></h1></div>
  <a href="/search?word=Example Author">Example Author</a>
  <a href="/tag/action">Action</a>
  <section>
    <div class="scan"><span>🇧🇷</span><a href="/source/brscan">Herói Exemplo</a>
      <span>2 chapters · 10 follows</span><span>missing(2): 3-4</span><span>#brscan</span><span>BR Team</span></div>
    <div class="scan"><span>🇬🇧</span><a href="/source/enscan">Example Hero</a>
      <span>1 chapters · 8 follows</span><span>#enscan</span><span>EN Team</span></div>
  </section>
</main></body></html>
''';

const _brSourceFixture = '''
<html><body><main><a href="/source/brscan">Herói Exemplo</a>
  <div><a href="/chapter/br2">Volume 1 Chapter 2</a><time><span>today</span></time></div>
  <div><a href="/chapter/br1">Volume 1 Chapter 1</a><time><span>yesterday</span></time></div>
</main></body></html>
''';

const _enSourceFixture = '''
<html><body><main><a href="/source/enscan">Example Hero</a>
  <div><a href="/chapter/en2">Vol. 1 Ch. 2</a><time><span>2d ago</span></time></div>
</main></body></html>
''';

const _readerFixture = '''
<html><body>
  <div data-name="image-item"><div data-name="image-show"><img src="https://img.test/1.webp"></div></div>
  <div data-name="image-item"><div data-name="image-show"><img src="/images/2.webp"></div></div>
</body></html>
''';

const _qwikReaderFixture = r'''
<html><body><script type="qwik/json">
[0,"imageUrls",4,[0,"https://i01.img01.org/pages/1.webp",0,"https://i02.img02.org/pages/2.webp"],0,"prevChapter",3,1]
</script></body></html>
''';
