import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/fsi_comics_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps the five requested catalogs and their regular pagination',
      () async {
    final requests = <Uri>[];
    final source = FsiComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requests.add(request.url);
        return _html(_catalogHtml);
      }),
    );

    expect(
      source.catalogVariants(MangaCatalogFilter.recent).map((item) => item.id),
      ['all', '3d', 'western', 'hentai', 'ai'],
    );
    for (final variant in const ['all', '3d', 'western', 'hentai', 'ai']) {
      final page = await source.browseVariant(
        MangaCatalogFilter.recent,
        variant,
        cursor: '2',
      );
      expect(page.items.single.title, 'Test of Faith Chapter 1 – Velour3DX');
      expect(page.nextCursor, '3');
    }

    expect(requests.map((uri) => uri.path), [
      '/all-porn-comics/page/2/',
      '/all-porn-comics/3d-porn-comics/page/2/',
      '/all-porn-comics/western-porn-comics/page/2/',
      '/all-porn-comics/hentai-porn-comics/page/2/',
      '/ai-generated/page/2/',
    ]);
  });

  test('loads a single-post comic with clickable artist and protected pages',
      () async {
    final source = FsiComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _html(_detailsHtml)),
    );

    final details = await source.getDetails('/test-of-faith-chapter-1/');

    expect(details.item.title, 'Test of Faith Chapter 1 – Velour3DX');
    expect(details.item.coverUri, Uri.parse('https://cdn.test/001.webp'));
    expect(details.item.subtitle, '2 pages');
    expect(details.description, contains('A young woman'));
    expect(details.author, 'Velour3DX');
    expect(details.artist, 'Velour3DX');
    expect(details.status, MangaStatus.completed);
    expect(details.chapters.single.number, '1');
    expect(details.chapters.single.pages, '2');
    expect(details.chapters.single.publishedAt, '2026-11-20T17:13:59+05:30');
    expect(
      details.taxonomyLinks
          .singleWhere(
            (link) => link.kind == MangaTaxonomyKind.artist,
          )
          .id,
      '/all-porn-comics/3d-porn-comics/velour3dx/',
    );
  });

  test('reads every data-safe-src independent of the website view mode',
      () async {
    final source = FsiComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _html(_detailsHtml)),
    );

    final pages = await source
        .readChapter(
          mangaId: '/test-of-faith-chapter-1/',
          chapterId: '/test-of-faith-chapter-1/',
        )
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://cdn.test/001.webp'),
      Uri.parse('https://cdn.test/002.webp'),
    ]);
    expect(
      pages.first.headers['Referer'],
      'https://example.test/test-of-faith-chapter-1/',
    );
  });

  test('uses browser loaders for Cloudflare HTML, images and reader files',
      () async {
    final htmlRequests = <Uri>[];
    late Uri imageRequest;
    final source = FsiComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      browserHtmlLoader: (uri, userAgent) async {
        htmlRequests.add(uri);
        return uri.path == '/all-porn-comics/' ? _catalogHtml : _detailsHtml;
      },
      browserImageLoader: (uri, userAgent) async {
        imageRequest = uri;
        return Uint8List.fromList([1, 2, 3]);
      },
      readerPageLoader: (uri, userAgent, pageCount) async* {
        expect(pageCount, 2);
        yield r'C:\cache\fsi\0001.webp';
        yield r'C:\cache\fsi\0002.webp';
      },
    );

    final catalog = await source.browse();
    final pages = await source
        .readChapter(
          mangaId: catalog.items.single.id,
          chapterId: catalog.items.single.id,
        )
        .toList();
    final bytes = await source.loadBrowserImage(
      Uri.parse('https://cdn.test/cover.webp'),
    );

    expect(htmlRequests, [
      Uri.parse('https://example.test/all-porn-comics/'),
      Uri.parse('https://example.test/test-of-faith-chapter-1/'),
    ]);
    expect(pages.map((page) => page.filePath), [
      r'C:\cache\fsi\0001.webp',
      r'C:\cache\fsi\0002.webp',
    ]);
    expect(imageRequest, Uri.parse('https://cdn.test/cover.webp'));
    expect(bytes, [1, 2, 3]);
  });

  test('browses related comics from the artist link in the description',
      () async {
    final requests = <Uri>[];
    final source = FsiComicsSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requests.add(request.url);
        return _html(request.url.path == '/test-of-faith-chapter-1/'
            ? _detailsHtml
            : _catalogHtml);
      }),
    );
    final details = await source.getDetails('/test-of-faith-chapter-1/');
    final artist = details.taxonomyLinks.singleWhere(
      (link) => link.kind == MangaTaxonomyKind.artist,
    );
    final options = await source.getTaxonomy(MangaTaxonomyKind.artist);
    final related = await source.browseTaxonomy(
      MangaTaxonomyKind.artist,
      artist.id,
      cursor: '2',
    );

    expect(options.single.name, 'Velour3DX');
    expect(requests.last.path,
        '/all-porn-comics/3d-porn-comics/velour3dx/page/2/');
    expect(related.items.single.id, '/test-of-faith-chapter-1/');
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

const _catalogHtml = '''
<main><div class="blog-content">
  <div class="p-wrap p-grid p-grid-1">
    <div class="p-featured"><a href="/test-of-faith-chapter-1/"><img src="https://cdn.test/cover.webp"></a></div>
    <div class="p-categories"><a class="p-category" href="/all-porn-comics/3d-porn-comics/velour3dx/">Velour3DX</a></div>
    <h4 class="entry-title"><a class="p-url" href="/test-of-faith-chapter-1/">Test of Faith Chapter 1 – Velour3DX</a></h4>
  </div>
  <nav class="pagination"><a href="/all-porn-comics/page/3/">3</a></nav>
</div></main>
''';

const _detailsHtml = '''
<main>
  <h1 class="s-title fw-headline">Test of Faith Chapter 1 – Velour3DX</h1>
  <time class="date published" datetime="2026-11-20T17:13:59+05:30">Published: November 20, 2026</time>
  <div class="entry-content">
    <p class="wp-block-paragraph">A young woman living in a remote monastery.</p>
    <p class="wp-block-paragraph"><a href="/all-porn-comics/3d-porn-comics/velour3dx/">Velour3DX</a> is the publisher.</p>
    <div class="fz-gallery-controls-wrapper">
      <li data-value="grid">GRID VIEW</li>
      <li data-value="list">LIST VIEW</li>
      <li data-value="carousel">CAROUSEL VIEW</li>
    </div>
    <figure class="wp-block-gallery">
      <img src="data:image/gif;base64,placeholder" data-safe-src="https://cdn.test/001.webp">
      <img src="data:image/gif;base64,placeholder" data-safe-src="https://cdn.test/002.webp">
    </figure>
  </div>
  <a href="/tag/demon/">Demon</a>
</main>
''';
