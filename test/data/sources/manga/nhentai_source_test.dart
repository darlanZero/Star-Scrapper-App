import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/nhentai_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  const galleryHtml = '''
    <div class="gallery"><a class="cover" href="/g/123/">
      <img src="https://cdn.test/galleries/9/thumb.webp" alt="Test gallery">
      <div class="caption">Test gallery</div>
    </a></div>
  ''';
  const detailsHtml = '''
    <div id="cover"><img src="https://cdn.test/galleries/9/cover.webp"></div>
    <div id="info"><h1>Test gallery</h1><h2>Alternate title</h2>
      <section id="tags">
        <div class="tag-container field-name">Tags<span class="tags">
          <a class="tag" href="/tag/alpha/"><span class="name">alpha</span><span class="count">12</span></a>
        </span></div>
        <div class="tag-container field-name">Artists<span class="tags">
          <a class="tag" href="/artist/test-artist/"><span class="name">Test Artist</span></a>
        </span></div>
        <div class="tag-container field-name">Languages<span class="tags">
          <a class="tag"><span class="name">translated</span></a>
          <a class="tag"><span class="name">english</span></a>
        </span></div>
        <div class="tag-container field-name">Pages:<span class="tags"><span class="name">2</span></span></div>
        <time datetime="2026-10-30T00:00:00Z"></time>
      </section>
    </div>
    <div id="thumbnail-container">
      <a class="gallerythumb"><img data-src="https://cdn.test/galleries/9/1t.webp"></a>
      <a class="gallerythumb"><img data-src="https://cdn.test/galleries/9/2t.webp"></a>
    </div>
  ''';

  test('parses catalog, metadata and full reader pages', () async {
    final source = NHentaiSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        if (request.url.path == '/g/123/') {
          return http.Response(detailsHtml, 200);
        }
        return http.Response(galleryHtml, 200);
      }),
    );

    final catalog = await source.browse(filter: MangaCatalogFilter.recent);
    expect(catalog.items.single.id, '123');
    expect(catalog.items.single.title, 'Test gallery');
    expect(catalog.items.single.subtitle, '2 pages • English');

    final details = await source.getDetails('123');
    expect(details.alternativeTitles.single.values.single, 'Alternate title');
    expect(details.genres, ['alpha']);
    expect(details.artist, 'Test Artist');
    expect(details.chapters.single.pages, '2');
    expect(details.chapters.single.language, 'english');

    final pages =
        await source.readChapter(mangaId: '123', chapterId: '/g/123/').toList();
    expect(pages.map((page) => page.uri.toString()), [
      'https://cdn.test/galleries/9/1.webp',
      'https://cdn.test/galleries/9/2.webp',
    ]);
  });

  test('uses comma-separated search for combined taxonomy choices', () async {
    Uri? requested;
    final source = NHentaiSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        if (request.url.path == '/search/') {
          requested = request.url;
        }
        return http.Response(galleryHtml, 200);
      }),
    );

    await source.browseTaxonomy(
      MangaTaxonomyKind.tag,
      '/tag/big-breasts/|/tag/nakadashi/',
    );
    expect(requested?.path, '/search/');
    expect(requested?.queryParameters['q'], 'big breasts, nakadashi');
  });

  test('uses alphabet pagination links without a trailing slash', () async {
    final requestedPages = <String>[];
    final source = NHentaiSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        requestedPages.add(request.url.toString());
        if (request.url.queryParameters['page'] == '31') {
          return http.Response('''
            <a href="/tag/m-kichiheya/">
              <span class="name">m kichiheya</span>
              <span class="count">1</span>
            </a>
          ''', 200);
        }
        return http.Response('<a href="?page=31#m">M</a>', 200);
      }),
    );

    final tags = await source.getTaxonomy(
      MangaTaxonomyKind.tag,
      query: 'm kichiheya',
    );

    expect(tags.single.name, 'm kichiheya');
    expect(tags.single.id, '/tag/m-kichiheya/');
    expect(requestedPages, contains('https://nhentai.test/tags?page=31'));
  });
}
