import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/bato_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps Newest, Updated and Added to their current routes', () async {
    final requested = <Uri>[];
    final source = BatoSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(_catalogHtml);
      }),
    );

    expect(source.id, 'bato');
    expect(source.catalogFilters, [
      MangaCatalogFilter.recent,
      MangaCatalogFilter.updated,
      MangaCatalogFilter.added,
    ]);

    final newest = await source.browse();
    expect(requested.last.path, '/newest');
    expect(newest.items.single.id, 'sample-series');
    expect(newest.items.single.title, 'Sample Series');
    expect(newest.items.single.coverUri,
        Uri.parse('https://cdn.test/sample.webp'));
    expect(newest.items.single.subtitle, contains('12 Ch'));
    expect(newest.nextCursor, 'https://example.test/newest/page/2');

    await source.browse(filter: MangaCatalogFilter.updated);
    expect(requested.last.path, '/updated');
    await source.browse(filter: MangaCatalogFilter.added);
    expect(requested.last.path, '/added');
  });

  test('searches by keyword and exposes all structured filters', () async {
    final requested = <Uri>[];
    final source = BatoSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(
          request.url.path == '/filter' ? _filterHtml : _catalogHtml,
        );
      }),
    );

    await source.search('Blue Lock');
    expect(requested.last.path, '/filter');
    expect(requested.last.queryParameters['keyword'], 'Blue Lock');

    final options = await source.getSearchOptions();
    expect(options.types.map((option) => option.value), ['manga', 'manhwa']);
    expect(options.genres.map((option) => option.value), ['action', 'romance']);
    expect(options.statuses.map((option) => option.value), [
      'completed',
      'releasing',
    ]);
    expect(options.chapterPresets.map((option) => option.value), ['1', '10']);
    expect(options.supportsYearRange, isTrue);
    expect(options.supportsCategoryMode, isTrue);
    expect(options.sorts, [
      MangaSearchSort.updated,
      MangaSearchSort.recentlyAdded,
      MangaSearchSort.releaseDate,
      MangaSearchSort.titleAscending,
    ]);

    await source.filterCatalog(
      MangaSearchRequest(
        types: {'manga', 'manhwa'},
        genres: {'action', 'romance'},
        statuses: {'releasing'},
        minimumYear: 2020,
        maximumYear: 2022,
        chapterPreset: '10',
        categoryMode: MangaCategoryMode.all,
        sort: MangaSearchSort.titleAscending,
      ),
    );
    final query = requested.last.queryParametersAll;
    expect(query['type[]'], containsAll(['manga', 'manhwa']));
    expect(query['genre[]'], containsAll(['action', 'romance']));
    expect(query['status[]'], ['releasing']);
    expect(query['year[]'], ['2020', '2021', '2022']);
    expect(query['genre_mode'], ['and']);
    expect(query['minchap'], ['10']);
    expect(query['sort'], ['title_az']);
  });

  test('loads metadata and the complete AJAX chapter list', () async {
    final requested = <http.BaseRequest>[];
    final source = BatoSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request);
        if (request.url.path == '/get-chapter-list') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'chapter_id': 2,
                  'chapter_name': 'Chapter 2',
                  'chapter_slug': 'chapter-2',
                  'chapter_num': 2,
                  'updated_at': '2026-11-08T10:00:00Z',
                },
                {
                  'chapter_id': 1,
                  'chapter_name': 'Chapter 1',
                  'chapter_slug': 'chapter-1',
                  'chapter_num': 1,
                  'updated_at': '2026-11-07T10:00:00Z',
                },
              ],
            }),
            200,
          );
        }
        return _html(_detailsHtml);
      }),
    );

    final details = await source.getDetails('sample-series');
    expect(details.item.title, 'Sample Series');
    expect(details.item.coverUri, Uri.parse('https://cdn.test/sample.webp'));
    expect(details.description, 'The complete synopsis.');
    expect(details.alternativeTitles, [
      {'und': 'Sample Alt'},
      {'und': 'サンプル'},
    ]);
    expect(details.genres, ['Action', 'Mature']);
    expect(details.author, 'Example Author');
    expect(details.status, MangaStatus.ongoing);
    expect(details.chapters.map((chapter) => chapter.number), ['1', '2']);
    expect(details.chapters.last.id, '/read/sample-series/chapter-2');
    final ajax = requested.singleWhere(
      (request) => request.url.path == '/get-chapter-list',
    );
    expect(ajax.headers['X-Requested-With'], 'XMLHttpRequest');
    expect(ajax.url.queryParameters['slug'], 'sample-series');
  });

  test('streams only chapter pages and prefers lazy image URLs', () async {
    final source = BatoSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((_) async => _html(_readerHtml)),
    );

    final pages = await source
        .readChapter(
          mangaId: 'sample-series',
          chapterId: '/read/sample-series/chapter-1',
        )
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://cdn.test/0.webp'),
      Uri.parse('https://cdn.test/1.webp'),
    ]);
    expect(pages.first.headers['Referer'], 'https://example.test/');
  });
}

const _catalogHtml = '''
  <div class="unit item-"><div class="inner">
    <a href="https://example.test/manga/sample-series" class="poster">
      <div><img class="lazyload image-thumb" data-src="https://cdn.test/sample.webp" alt="Sample Series"></div>
    </a>
    <div class="info">
      <div><a href="/type/manga" class="type">Manga</a></div>
      <a href="https://example.test/manga/sample-series">Sample Series</a>
      <ul class="content"><li><a href="/read/sample-series/chapter-12">
        <span>Chapter 12:</span><span>1 hour ago</span>
      </a></li></ul>
    </div>
  </div></div>
  <a class="page-link" href="https://example.test/newest/page/2" rel="next">Next</a>
''';

const _filterHtml = '''
  <form id="filters" action="/filter" method="GET">
    <input id="type-manga" name="type[]" value="manga"><label for="type-manga">Manga</label>
    <input id="type-manhwa" name="type[]" value="manhwa"><label for="type-manhwa">Manhwa</label>
    <input id="genre-action" name="genre[]" value="action"><label for="genre-action">Action</label>
    <input id="genre-romance" name="genre[]" value="romance"><label for="genre-romance">Romance</label>
    <input id="status-completed" name="status[]" value="completed"><label for="status-completed">Completed</label>
    <input id="status-releasing" name="status[]" value="releasing"><label for="status-releasing">Releasing</label>
    <input id="minchap-1" name="minchap" value="1"><label for="minchap-1">&gt;= 1 chapters</label>
    <input id="minchap-10" name="minchap" value="10"><label for="minchap-10">&gt;= 10 chapters</label>
  </form>
''';

const _detailsHtml = '''
  <div id="manga-page"><div class="manga-detail"><div class="main-inner">
    <aside class="content">
      <div class="poster"><img data-src="https://cdn.test/sample.webp"></div>
      <div class="info">
        <p>Ongoing</p><h1 itemprop="name">Sample Series</h1>
        <h6>Sample Alt, サンプル</h6>
        <div class="min-info"><a href="/type/manga">Manga</a><span>2 chapters</span></div>
        <div class="description">Short synopsis.</div>
      </div>
    </aside>
    <aside class="sidebar"><div id="info-rating"><div class="meta">
      <div><span>Author:</span><span><a itemprop="author">Example Author</a></span></div>
      <div><span>Genres:</span><span>
        <a href="/genre/action">Action</a><a href="/genre/mature">Mature</a>
      </span></div>
    </div></div></aside>
  </div></div></div>
  <div id="synopsisModal"><p>The complete synopsis.</p></div>
  <ul id="chapter-list"><li class="item">
    <a href="/read/sample-series/chapter-1" title="Chapter 1"><span>Chapter 1</span><span>Yesterday</span></a>
  </li></ul>
''';

const _readerHtml = '''
  <div class="chapter-images-container"><div class="pages">
    <div class="page notice-page"><img data-number="notice" src="/banner.gif"></div>
    <div class="page"><img data-number="0" src="https://cdn.test/0.webp"></div>
    <div class="page"><img data-number="1" src="data:image/svg+xml,test" data-src="https://cdn.test/1.webp"></div>
  </div></div>
''';

http.Response _html(String body) => http.Response(body, 200, headers: {
      'content-type': 'text/html; charset=utf-8',
    });
