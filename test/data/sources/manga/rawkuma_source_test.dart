import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/rawkuma_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('uses the singular latest-update route and parses its next page',
      () async {
    final requested = <Uri>[];
    final source = RawkumaSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(_latestHtml);
      }),
    );

    final page = await source.browse();

    expect(requested.single.path, '/latest-update/');
    expect(page.items.single.id, 'sample-series');
    expect(page.items.single.title, 'Sample Series');
    expect(
        page.items.single.coverUri, Uri.parse('https://cdn.test/sample.webp'));
    expect(page.items.single.subtitle, contains('12 Ch'));
    expect(
      page.nextCursor,
      'https://example.test/latest-update/?the_page=2',
    );
  });

  test('exposes and submits all native Library filters', () async {
    final requested = <http.BaseRequest>[];
    final source = RawkumaSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request);
        if (request.url.path == '/library/') return _html(_libraryHtml);
        if (request.url.queryParameters['action'] == 'get_nonce') {
          return _html(
            "<input type='hidden' name='search_nonce' value='nonce-123'>",
          );
        }
        return _html(_libraryResultHtml);
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.genres.map((option) => option.value), ['action', 'drama']);
    expect(options.types.map((option) => option.value), ['manga', 'manhwa']);
    expect(options.statuses.map((option) => option.value), ['ongoing']);
    expect(options.authors.single.value, 'author-one');
    expect(options.artists.single.value, 'artist-one');
    expect(options.supportsGenreExclusion, isTrue);
    expect(options.supportsExclusionCategoryMode, isTrue);
    expect(options.sorts, contains(MangaSearchSort.bookmarked));

    final page = await source.filterCatalog(
      MangaSearchRequest(
        genres: {'action', 'drama'},
        excludedGenres: {'adult'},
        types: {'manga'},
        statuses: {'ongoing'},
        authorValues: {'author-one'},
        artistValues: {'artist-one'},
        categoryMode: MangaCategoryMode.all,
        exclusionCategoryMode: MangaCategoryMode.any,
        sort: MangaSearchSort.bookmarked,
        sortDirection: MangaSortDirection.ascending,
      ),
    );

    expect(page.items.single.id, 'filtered-series');
    final post = requested.whereType<http.Request>().singleWhere(
          (request) =>
              request.url.queryParameters['action'] == 'advanced_search',
        );
    expect(post.method, 'POST');
    expect(post.bodyFields['nonce'], 'nonce-123');
    expect(jsonDecode(post.bodyFields['genre']!), ['action', 'drama']);
    expect(jsonDecode(post.bodyFields['genre_exclude']!), ['adult']);
    expect(jsonDecode(post.bodyFields['type']!), ['manga']);
    expect(jsonDecode(post.bodyFields['status']!), ['ongoing']);
    expect(jsonDecode(post.bodyFields['author']!), ['author-one']);
    expect(jsonDecode(post.bodyFields['artist']!), ['artist-one']);
    expect(post.bodyFields['inclusion'], 'AND');
    expect(post.bodyFields['exclusion'], 'OR');
    expect(post.bodyFields['orderby'], 'bookmarked');
    expect(post.bodyFields['order'], 'asc');
  });

  test('loads schema metadata, full chapters and native reader images',
      () async {
    final source = RawkumaSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path.contains('/chapter-2.22/')) {
          return _html(_readerHtml);
        }
        return _html(_detailsHtml);
      }),
    );

    final details = await source.getDetails('sample-series');
    expect(details.item.title, 'Sample Series');
    expect(
        details.item.coverUri, Uri.parse('https://cdn.test/sample-cover.webp'));
    expect(details.description, 'The complete Japanese synopsis.');
    expect(details.alternativeTitles, [
      {'und': 'サンプル'},
      {'und': 'Sample Alt'},
    ]);
    expect(details.genres, ['Action', 'Drama']);
    expect(details.author, 'Author One');
    expect(details.status, MangaStatus.ongoing);
    expect(details.chapters.map((chapter) => chapter.number), ['1', '2']);
    expect(details.chapters.last.language, 'ja');

    final pages = await source
        .readChapter(
          mangaId: 'sample-series',
          chapterId: 'https://example.test/manga/sample-series/chapter-2.22/',
        )
        .toList();
    expect(pages.map((page) => page.uri), [
      Uri.parse('https://cdn.test/001.webp'),
      Uri.parse('https://cdn.test/002.webp'),
    ]);
    expect(
      pages.first.headers['Referer'],
      'https://example.test/manga/sample-series/chapter-2.22/',
    );
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

const _latestHtml = '''
<main><div id="search-results">
  <div>
    <a href="https://example.test/manga/sample-series/">
      <img src="https://cdn.test/sample.webp" alt="Sample Series">
    </a>
    <a href="https://example.test/manga/sample-series/">Sample Series</a>
    <span class="numscore">8.5</span><span>Ongoing</span>
    <a href="https://example.test/manga/sample-series/chapter-12.12/">
      <p>Chapter 12</p>
    </a>
  </div>
</div>
<a href="https://example.test/latest-update/?the_page=1">1</a>
<a href="https://example.test/latest-update/?the_page=2">2</a>
</main>
''';

const _libraryHtml = '''
<script>
var searchTerms = {
  "genre": [{"name":"Action","slug":"action"},{"name":"Drama","slug":"drama"}],
  "type": [{"name":"Manga","slug":"manga"},{"name":"Manhwa","slug":"manhwa"}],
  "status": [{"name":"Ongoing","slug":"ongoing"}],
  "series-author": [{"name":"Author One","slug":"author-one"}],
  "artist": [{"name":"Artist One","slug":"artist-one"}]
};
</script>
''';

const _libraryResultHtml = '''
<div>
  <a href="https://example.test/manga/filtered-series/">
    <img class="wp-post-image" src="https://cdn.test/filtered.webp" alt="Filtered Series">
  </a>
  <a href="https://example.test/manga/filtered-series/">Filtered Series</a>
  <span class="numscore">7.7</span><span>Completed</span>
  <a href="https://example.test/manga/filtered-series/chapter-5.5/">Chapter 5</a>
</div>
''';

const _detailsHtml = '''
<script type="application/ld+json">
{
  "@context":"https://schema.org",
  "@type":"CreativeWorkSeries",
  "name":"Sample Series",
  "image":{"@type":"ImageObject","url":"https://cdn.test/sample-cover.webp"},
  "author":{"@type":"Person","name":"Author One"},
  "genre":["Action","Drama"],
  "creativeWorkStatus":"Ongoing",
  "datePublished":"2024",
  "numberOfPages":2,
  "aggregateRating":{"ratingValue":8.25},
  "alternateName":"サンプル, Sample Alt"
}
</script>
<article>
  <h1 itemprop="name">Sample Series</h1>
  <div itemprop="description" data-show="false">The complete Japanese synopsis.</div>
  <div id="chapter-list">
    <div data-chapter-number="2"><a href="https://example.test/manga/sample-series/chapter-2.22/"><span>Chapter 2</span><time datetime="2026-11-20T00:00:00Z"></time></a></div>
    <div data-chapter-number="1"><a href="https://example.test/manga/sample-series/chapter-1.11/"><span>Chapter 1</span><time datetime="2026-11-19T00:00:00Z"></time></a></div>
  </div>
</article>
''';

const _readerHtml = '''
<section data-image-data="1">
  <img src="https://cdn.test/001.webp">
  <img src="https://cdn.test/002.webp">
</section>
''';
