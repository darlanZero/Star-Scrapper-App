import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/apcomics_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps every homepage order and paginates the load-more catalog',
      () async {
    final requests = <Uri>[];
    final source = APComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requests.add(request.url);
        return _html(_catalogHtml(24));
      }),
    );

    for (final filter in source.catalogFilters) {
      await source.browse(filter: filter, cursor: '2');
    }

    expect(
      requests.map((uri) => uri.queryParameters['m_orderby']),
      ['latest', 'alphabet', 'rating', 'trending', 'views', 'new-manga'],
    );
    expect(requests,
        everyElement(predicate<Uri>((uri) => uri.path == '/page/2/')));

    final page = await source.browse();
    expect(page.items, hasLength(24));
    expect(page.items.first.id, '/manga/sample-1/');
    expect(page.items.first.title, 'Sample 1');
    expect(page.items.first.subtitle, '1 Ch • 4.5');
    expect(page.nextCursor, '2');
  });

  test('search uses WordPress manga search and its regular page route',
      () async {
    late Uri requested;
    final source = APComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested = request.url;
        return _html(_searchHtml);
      }),
    );

    final page = await source.search('dumb mom', cursor: '3');

    expect(requested.path, '/page/3/');
    expect(requested.queryParameters, {
      's': 'dumb mom',
      'post_type': 'wp-manga',
    });
    expect(page.items.single.id, '/manga/dumb-mom/');
    expect(page.items.single.coverUri, Uri.parse('https://cdn.test/cover.jpg'));
  });

  test('loads metadata, clickable tags and chapters from the AJAX endpoint',
      () async {
    final requests = <http.BaseRequest>[];
    final source = APComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requests.add(request);
        return request.method == 'POST'
            ? _html(_chaptersHtml)
            : _html(_detailsHtml);
      }),
    );

    final details = await source.getDetails('/manga/dumb-mom/');

    expect(details.item.title, 'Dumb Mom');
    expect(details.item.coverUri, Uri.parse('https://cdn.test/detail.jpg'));
    expect(details.description, 'English description.');
    expect(details.genres, ['big breasts (female)', 'milf']);
    expect(details.author, 'Cathriell Rue');
    expect(details.status, MangaStatus.ongoing);
    expect(details.chapters.map((chapter) => chapter.number), ['1', '2']);
    expect(details.taxonomyLinks.last.id, '/manga-tag/milf/');

    final post = requests.singleWhere((request) => request.method == 'POST');
    expect(post.url.path, '/manga/dumb-mom/ajax/chapters/');
    expect(post.headers['Referer'], 'https://example.test/manga/dumb-mom/');
  });

  test('reads native chapter images with the chapter referer', () async {
    final source = APComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _html(_readerHtml)),
    );

    final pages = await source
        .readChapter(
          mangaId: '/manga/dumb-mom/',
          chapterId: '/manga/dumb-mom/chapter-1/',
        )
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://cdn.test/1.jpg'),
      Uri.parse('https://cdn.test/2.jpg'),
    ]);
    expect(
      pages.first.headers['Referer'],
      'https://example.test/manga/dumb-mom/chapter-1/',
    );
  });

  test('indexes sitemap tags and browses a clicked tag', () async {
    final requests = <Uri>[];
    final source = APComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('.xml')) return _html(_tagSitemap);
        return _html(_catalogHtml(1));
      }),
    );

    final tags = await source.getTaxonomy(
      MangaTaxonomyKind.tag,
      query: 'breasts',
    );
    final page = await source.browseTaxonomy(
      MangaTaxonomyKind.tag,
      tags.single.id,
      cursor: '2',
    );

    expect(tags.single.name, 'Big breasts (female)');
    expect(requests.first.path, '/wp-manga-tag-sitemap.xml');
    expect(requests.last.path, '/manga-tag/big-breasts-female/page/2/');
    expect(page.items.single.title, 'Sample 1');
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

String _catalogHtml(int count) => '''
<div class="page-content-listing">
  ${List.generate(count, (index) {
      final number = index + 1;
      return '''
      <div class="page-item-detail manga">
        <div class="item-thumb"><a href="https://example.test/manga/sample-$number/"><img src="https://cdn.test/$number.jpg"></a></div>
        <div class="post-title"><a href="https://example.test/manga/sample-$number/">Sample $number</a></div>
        <div class="list-chapter"><span class="chapter"><a>1.CHAPTER - 1</a></span></div>
        <span class="score">4.5</span>
      </div>
    ''';
    }).join()}
</div>
''';

const _searchHtml = '''
<div class="row c-tabs-item__content">
  <div class="tab-thumb"><a href="/manga/dumb-mom/"><img src="https://cdn.test/cover.jpg"></a></div>
  <div class="post-title"><a href="/manga/dumb-mom/">Dumb Mom</a></div>
  <div class="latest-chap"><span class="chapter"><a>Chapter 3</a></span></div>
</div>
''';

const _detailsHtml = '''
<div class="post-title"><h1>Dumb Mom</h1></div>
<div class="summary_image"><img src="https://cdn.test/detail.jpg"></div>
<div class="summary__content"><p>English description.</p></div>
<div class="post-content_item"><div class="summary-heading">Alternative</div><div class="summary-content">Updating</div></div>
<div class="post-content_item"><div class="summary-heading">Author(s)</div><div class="summary-content">Updating</div></div>
<div class="post-content_item"><div class="summary-heading">Status</div><div class="summary-content">OnGoing</div></div>
<div class="artist-content"><a href="/manga-artist/cathriell-rue/">Cathriell Rue</a></div>
<div class="tags-content">
  <a href="/manga-tag/big-breasts-female/">big breasts (female)</a>
  <a href="/manga-tag/milf/">milf</a>
</div>
<span id="averagerate">3</span>
''';

const _chaptersHtml = '''
<ul>
  <li class="wp-manga-chapter"><a href="/manga/dumb-mom/chapter-2/">2. CHAPTER - 2</a><span class="chapter-release-date">November 2, 2026</span></li>
  <li class="wp-manga-chapter"><a href="/manga/dumb-mom/chapter-1/">1. CHAPTER - 1</a><span class="chapter-release-date">November 1, 2026</span></li>
</ul>
''';

const _readerHtml = '''
<div class="reading-content">
  <div class="page-break"><img src="  https://cdn.test/1.jpg  "></div>
  <div class="page-break"><img data-src="https://cdn.test/2.jpg"></div>
</div>
''';

const _tagSitemap = '''
<urlset>
  <url><loc>https://example.test/manga-tag/big-breasts-female/</loc></url>
  <url><loc>https://example.test/manga-tag/milf/</loc></url>
</urlset>
''';
