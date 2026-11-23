import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/adult_gallery_sources.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('HentaiVox accepts absolute gallery links from the live markup',
      () async {
    final source = HentaiVoxSource(
      baseUri: Uri.parse('https://vox.test/'),
      client: MockClient((request) async => _html('''
        <div class="gallery">
          <h3 class="gallery-type"><a href="https://vox.test/category/comic">Comic</a></h3>
          <a class="gallery-thumb" href="https://vox.test/view/455298"><img data-src="https://img.test/thumb.jpg"></a>
          <div class="gallery-name"><h2><a href="https://vox.test/view/455298">Absolute work</a></h2></div>
        </div>
        <a href="https://vox.test/page/2">Next</a>
      ''')),
    );

    final page = await source.browse();

    expect(page.items.single.id, '455298');
    expect(page.items.single.title, 'Absolute work');
    expect(page.items.single.coverUri, Uri.parse('https://img.test/thumb.jpg'));
    expect(page.items.single.subtitle, 'Comic');
    expect(page.nextCursor, '2');
  });

  test('HentaiEra.to resolves each reader page from reader_img', () async {
    final requests = <Uri>[];
    final source = HentaiEraSource(
      sourceId: 'hentaiera_to',
      sourceName: 'HentaiEra.to',
      baseUri: Uri.parse('https://hentaiera.to/'),
      client: MockClient((request) async {
        requests.add(request.url);
        final page = RegExp(r'/gallery/711887/(\d+)/$')
            .firstMatch(request.url.path)
            ?.group(1);
        if (page != null) {
          return _html(
              '<img id="reader_img" src="https://read.test/$page.webp">');
        }
        return _html('''
          <h1>Era work</h1>
          <a href="/gallery/711887/1/"><img src="https://img.test/cover.webp"></a>
          <a href="/gallery/711887/2/"></a>
          <a href="/language/english/">English</a>
          <a href="/category/doujinshi/">Doujinshi</a>
          <p>2 Pages</p>
        ''');
      }),
    );

    final pages = await source
        .readChapter(mangaId: '711887', chapterId: '711887')
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://read.test/1.webp'),
      Uri.parse('https://read.test/2.webp'),
    ]);
    expect(
      requests.map((uri) => uri.path),
      containsAll([
        '/gallery/711887/',
        '/gallery/711887/1/',
        '/gallery/711887/2/',
      ]),
    );
  });

  test('HentaiVox resolves every real reader image instead of guessing names',
      () async {
    final source = HentaiVoxSource(
      baseUri: Uri.parse('https://vox.test/'),
      client: MockClient((request) async {
        final page = RegExp(r'/view/455137/(\d+)$')
            .firstMatch(request.url.path)
            ?.group(1);
        if (page != null) {
          return _html(
            '<img class="js-main-img" src="https://img.test/2522483-$page.jpg">',
          );
        }
        return _html('''
          <h1>Vox work</h1>
          <img src="https://img.test/2522483-cover.jpg">
          <a href="/view/455137/1">1</a>
          <a href="/view/455137/2">2</a>
          <p>2 Pages</p>
        ''');
      }),
    );

    final pages = await source
        .readChapter(mangaId: '455137', chapterId: '455137')
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://img.test/2522483-1.jpg'),
      Uri.parse('https://img.test/2522483-2.jpg'),
    ]);
  });

  test('HentaiEnvy uses the reader image base exposed by readerApp', () async {
    final source = HentaiEnvySource(
      baseUri: Uri.parse('https://envy.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/g/1649715/1/') {
          return _html('''
            <section id="readerApp"
              data-reader-image-base="https://m11.test/033/djms2lfcgq"
              data-reader-total="2">
              <img id="readerImg" src="https://m11.test/033/djms2lfcgq/1.webp">
            </section>
          ''');
        }
        return _html('''
          <h1>Envy work</h1>
          <div class="hnv-gallery-cover"><img src="https://m11.test/thumb.jpg"></div>
          <p>999 Pages in this category</p>
        ''');
      }),
    );

    final pages = await source
        .readChapter(mangaId: '1649715', chapterId: '1649715')
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://m11.test/033/djms2lfcgq/1.webp'),
      Uri.parse('https://m11.test/033/djms2lfcgq/2.webp'),
    ]);
  });

  test('HentaiEra sends complete mutually exclusive sort parameters', () async {
    final requested = <Uri>[];
    final source = HentaiEraSource(
      baseUri: Uri.parse('https://era.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html('<main></main>');
      }),
    );

    await source.browse(filter: MangaCatalogFilter.recent);
    await source.browse(filter: MangaCatalogFilter.updated);
    await source.browse(filter: MangaCatalogFilter.popular);

    expect(requested.first.queryParameters['lt'], '1');
    expect(requested.first.queryParameters['dl'], '0');
    expect(requested.first.queryParameters['mg'], '1');
    expect(requested.first.queryParameters['en'], '1');
    expect(requested[1].queryParameters['dl'], '1');
    expect(requested[1].queryParameters['lt'], '0');
    expect(source.catalogFilterLabel(MangaCatalogFilter.updated), 'Downloaded');
    expect(requested.last.queryParameters['pp'], '1');
    expect(requested.last.queryParameters['dl'], '0');
  });

  test('HentaiEra taxonomy cards retain their catalog image', () async {
    final source = HentaiEraSource(
      baseUri: Uri.parse('https://era.test/'),
      client: MockClient((request) async => _html('''
        <div class="thumbnail">
          <div class="inner_thumb">
            <a href="/tag/action/"><img data-src="https://img.test/action.jpg"></a>
          </div>
          <div class="g_text"><h2 class="gallery_title"><a href="/tag/action/">Action</a></h2></div>
          <span class="inside_p">12</span>
        </div>
      ''')),
    );

    final tags = await source.getTaxonomy(MangaTaxonomyKind.tag);

    expect(tags.single.imageUri, Uri.parse('https://img.test/action.jpg'));
    expect(tags.single.titleCount, 12);
  });

  test('3Hentai keeps popular cards out of the newest feed', () async {
    final source = ThreeHentaiSource(
      baseUri: Uri.parse('https://three.test/'),
      client: MockClient((request) async => _html('''
        <h2 class="listing-title">Popular Hentai at the moment</h2>
        <div class="listing-container">
          <a class="cover" href="/d/1/"><span class="title">Popular</span></a>
        </div>
        <h2 class="listing-title">Newest</h2>
        <div class="listing-container">
          <a class="cover" href="/d/2/"><span class="title">Newest</span></a>
        </div>
      ''')),
    );

    final recent = await source.browse();
    final popular = await source.browse(filter: MangaCatalogFilter.popular);

    expect(recent.items.map((item) => item.title), ['Newest']);
    expect(popular.items.map((item) => item.title), ['Popular']);
  });

  test('only HentaiEra exposes advanced filters alongside taxonomies', () {
    expect(HentaiVoxSource(), isNot(isA<FilterableMangaSource>()));
    expect(HentaiEnvySource(), isNot(isA<FilterableMangaSource>()));
    expect(ThreeHentaiSource(), isNot(isA<FilterableMangaSource>()));
    expect(HentaiEraSource(), isA<FilterableMangaSource>());
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
