import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/eahentai_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps homepage feeds and popular time ranges', () async {
    final requested = <Uri>[];
    final source = EAHentaiSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/') return _html(_homeHtml);
        return _json({
          'items': [_albumJson],
          'totalPages': 2,
        });
      }),
    );

    expect(source.catalogFilters, [
      MangaCatalogFilter.popular,
      MangaCatalogFilter.recent,
      MangaCatalogFilter.trending,
      MangaCatalogFilter.added,
    ]);
    expect(
      source
          .catalogVariants(MangaCatalogFilter.popular)
          .map((variant) => variant.id),
      ['views_daily', 'views_weekly', 'views_monthly'],
    );

    final weekly = await source.browseVariant(
      MangaCatalogFilter.popular,
      'views_weekly',
    );
    expect(requested.last.path, '/api/image/popular/');
    expect(requested.last.queryParameters['orderby'], 'views_weekly');
    expect(weekly.items.single.id, '77');
    expect(
      weekly.items.single.coverUri,
      Uri.parse(
        'https://i.eahentai.com/file/ea-gallery/galleries/hash/thumbnail/01t.jpg',
      ),
    );

    final latest = await source.browse(filter: MangaCatalogFilter.recent);
    expect(requested.last.path, '/api/image/latest/');
    expect(latest.nextCursor, '1');

    final discover = await source.browse(filter: MangaCatalogFilter.trending);
    expect(discover.items.single.title, 'Discovered Work');

    await source.browse(filter: MangaCatalogFilter.added);
    expect(requested.last.path, '/api/discovery/most-saved');
  });

  test('loads A-Z taxonomies and applies all result order variants', () async {
    final requested = <Uri>[];
    final source = EAHentaiSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/artists') return _html(_artistsHtml);
        if (request.url.path == '/tags') return _html(_tagsHtml);
        return _json({
          'items': [_albumJson],
          'totalPages': 3,
        });
      }),
    );

    final artists = await source.getTaxonomyPage(MangaTaxonomyKind.artist);
    expect(artists.options.single.name, 'alpha artist');
    expect(artists.options.single.titleCount, 12);
    expect(artists.nextCursor, 'B');
    expect(requested.last.queryParameters['q'], 'A');

    final tags = await source.getTaxonomy(MangaTaxonomyKind.tag, query: 'anal');
    expect(tags.single.name, 'Anal');
    expect(tags.single.id, contains('q=Anal'));

    expect(
      source
          .taxonomyCatalogVariants(MangaTaxonomyKind.artist)
          .map((variant) => variant.label),
      ['Latest', 'Today', 'Weekly', 'Monthly', 'All time'],
    );
    final monthlyId = source.taxonomyVariantId(
      MangaTaxonomyKind.artist,
      '/artist/alpha%20artist',
      'views_monthly',
    );
    final catalog = await source.browseTaxonomy(
      MangaTaxonomyKind.artist,
      monthlyId,
    );
    expect(requested.last.path, '/api/image/entities/albums');
    expect(requested.last.queryParameters['type'], 'artist');
    expect(requested.last.queryParameters['q'], 'alpha artist');
    expect(requested.last.queryParameters['orderby'], 'views_monthly');
    expect(catalog.nextCursor, '1');
  });

  test('parses detail chips and streams the complete gallery', () async {
    final source = EAHentaiSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/a/77/0') return _html(_readerHtml);
        return _html(_detailsHtml);
      }),
    );

    final details = await source.getDetails('/a/77');
    expect(details.item.title, 'Example Gallery');
    expect(details.item.subtitle, '3 pages');
    expect(details.artist, 'alpha artist');
    expect(details.genres, ['Full Color']);
    expect(details.status, MangaStatus.completed);
    expect(details.chapters.single.language, 'en');
    expect(
      details.taxonomyLinks.map((link) => link.kind),
      containsAll([
        MangaTaxonomyKind.parody,
        MangaTaxonomyKind.character,
        MangaTaxonomyKind.artist,
        MangaTaxonomyKind.tag,
      ]),
    );

    final pages =
        await source.readChapter(mangaId: '77', chapterId: '/a/77/0').toList();
    expect(pages.map((page) => page.uri), [
      Uri.parse(
        'https://i.eahentai.com/file/ea-gallery/galleries/hash/image1.webp',
      ),
      Uri.parse(
        'https://i.eahentai.com/file/ea-gallery/galleries/hash/image2.webp',
      ),
      Uri.parse(
        'https://i.eahentai.com/file/ea-gallery/galleries/hash/image3.webp',
      ),
    ]);
    expect(pages.first.headers['Referer'], 'https://example.test/');
  });
}

const _albumJson = {
  'albumID': 77,
  'title': 'Example Gallery',
  'thumbnailUri': 'galleries/hash/thumbnail/01t.jpg',
  'albumType': 'Doujinshi',
  'views': 321,
};

const _homeHtml = '''
  <main><section><h2>Discover</h2><div>
    <a href="/a/88" aria-label="Discovered Work">
      <img src="https://cdn.test/discover.webp">
    </a>
    <a href="/a/88" aria-label="Discovered Work"></a>
  </div></section></main>
''';

const _artistsHtml = '''
  <main><a href="/artist/alpha%20artist">
    <h3>alpha artist</h3><span>12 albums</span>
  </a></main>
''';

const _tagsHtml = '''
  <main><a href="/search?type=gallery&amp;q=Anal&amp;p=1">
    <h3>Anal</h3><span>Sexual Act</span>
  </a></main>
''';

const _detailsHtml = '''
  <main>
    <h1>Example Gallery</h1>
    <img src="https://i.eahentai.com/file/ea-gallery/galleries/hash/thumbnail/image1t.jpg">
    <p>Uploaded November 8, 2026 Read Now</p>
    <p>Preview 3 pages</p>
    <a href="/parody/example-series">Example Series</a>
    <a href="/character/example-girl">Example Girl</a>
    <a href="/artist/alpha%20artist">alpha artist</a>
    <a href="/search?p=1&amp;q=Full%20Color">Full Color</a>
  </main>
''';

const _readerHtml = '''
  <main>
    <img src="https://i.eahentai.com/file/ea-gallery/galleries/hash/image1.webp">
    <img src="https://i.eahentai.com/file/ea-gallery/galleries/hash/image2.webp">
    <img src="https://i.eahentai.com/file/ea-gallery/galleries/hash/image3.webp">
  </main>
''';

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
