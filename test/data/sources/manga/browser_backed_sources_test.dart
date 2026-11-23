import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/hitomi_source.dart';
import 'package:star_scrapper_app/data/sources/manga/toonlook_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('Hitomi falls back to rendered HTML for its JavaScript catalog',
      () async {
    Uri? renderedUri;
    String? renderedUserAgent;
    final source = HitomiSource(
      baseUri: Uri.parse('https://hitomi.test/'),
      client: MockClient((request) async => http.Response(
            '<html><body><script>window.bootstrap = true;</script></body></html>',
            200,
          )),
      browserHtmlLoader: (uri, userAgent) async {
        renderedUri = uri;
        renderedUserAgent = userAgent;
        return '''
          <div class="gallery-content">
            <div>
              <div class="dj-img1"><img src="//cdn.test/cover.webp"></div>
              <h1 class="lillie"><a href="/reader/12345.html">Rendered title</a></h1>
              <table class="dj-desc">
                <tr><td>ignored</td></tr>
                <tr><td>Type</td><td>Doujinshi</td></tr>
                <tr><td>Language</td><td>English</td></tr>
              </table>
            </div>
          </div>
        ''';
      },
    );

    final page = await source.browse();

    expect(renderedUri?.origin, 'https://hitomi.test');
    expect(renderedUri?.path, '/');
    expect(renderedUserAgent, contains('Android 14'));
    expect(page.items.single.id, '/reader/12345.html');
    expect(page.items.single.title, 'Rendered title');
    expect(
        page.items.single.coverUri, Uri.parse('https://cdn.test/cover.webp'));
    expect(page.items.single.subtitle, 'Doujinshi');
  });

  test('Hitomi renders details and resolves current w1/w2 image shards',
      () async {
    const hash =
        '055a370bf7fc1ca986b7de86ac7983e37795bbeb4e1537c15d9db95a96c9181d';
    final source = HitomiSource(
      baseUri: Uri.parse('https://hitomi.test/'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/galleries/4349109.js')) {
          return http.Response(
            'var galleryinfo = {"files":[{"hash":"$hash"}]};',
            200,
          );
        }
        if (request.url.path.endsWith('/gg.js')) {
          return http.Response(
              "gg={m:function(g){var o=1;o=0;return o;},b:'42/'};", 200);
        }
        return http.Response('<script>bootstrap()</script>', 200);
      }),
      browserHtmlLoader: (uri, userAgent) async => '''
        <h1 id="gallery-brand">You've Grown Up!</h1>
        <div id="language">日本語</div>
        <ul class="thumbnail-list"><li><img id="bigtn_img" src="//cdn.test/t.webp"></li></ul>
      ''',
    );

    final details = await source.getDetails(
      '/doujinshi/you-ve-grown-up!-%E6%97%A5%E6%9C%AC%E8%AA%9E-4349109.html',
    );
    final pages = await source
        .readChapter(
          mangaId: details.item.id,
          chapterId: details.chapters.single.id,
        )
        .toList();

    expect(details.item.title, "You've Grown Up!");
    expect(details.chapters.single.pages, '1');
    expect(
      pages.single.uri,
      Uri.parse(
        'https://w2.gold-usergeneratedcontent.net/42/3457/$hash.webp',
      ),
    );
  });

  test('Hitomi waits for detail identity instead of related catalog cards', () {
    expect(
      HitomiSource.browserReadySelector(
        Uri.parse('https://hitomi.la/doujinshi/work-123.html'),
      ),
      '#gallery-brand',
    );
    expect(
      HitomiSource.browserReadySelector(
        Uri.parse('https://hitomi.la/tag/action-all.html'),
      ),
      '.gallery-content > div',
    );
  });

  test('ToonLook exposes its real chapter URL as the WebView fallback', () {
    final MangaSource source = ToonLookSource(
      baseUri: Uri.parse('https://toonlook.test/'),
    );

    expect(source, isA<WebViewChapterMangaSource>());
    final browserSource = source as WebViewChapterMangaSource;
    expect(
      browserSource.chapterWebUri(
        mangaId: '/manhwa/example/',
        chapterId: '/manhwa/example/123-chapter-1/',
      ),
      Uri.parse('https://toonlook.test/manhwa/example/123-chapter-1/'),
    );
  });

  test('ToonLook scopes chapters, parses description, dates and order',
      () async {
    final chapterHtml = List.generate(68, (index) {
      final chapter = 68 - index;
      final date = chapter == 68 ? 'NEW' : '14/11/26';
      return '''
        <a class="chapter-item" href="/manhwa/work/id-chapter-$chapter/"
          data-langs="en" data-title-en="Chapter $chapter">
          <span class="chapter-item__name">Chapter $chapter</span>
          <span class="chapter-item__date">$date</span>
        </a>
      ''';
    }).join();
    final source = ToonLookSource(
      baseUri: Uri.parse('https://toonlook.test/'),
      client: MockClient((request) async => http.Response('''
        <h1>Love, Lust, &amp; Joy</h1>
        <div id="mangaDescContent">Canonical description.</div>
        <div id="chaptersList" class="chapters-list">$chapterHtml</div>
        <aside>
          <a href="/manhwa/other/216-chapter-216/">Chapter 216</a>
        </aside>
      ''', 200)),
    );

    final details = await source.getDetails('/manhwa/work/');

    expect(details.description, 'Canonical description.');
    expect(details.chapters, hasLength(68));
    expect(details.chapters.first.number, '68');
    expect(details.chapters.last.number, '1');
    expect(details.chapters[1].publishedAt, '2026-11-14');
    expect(details.chapters.map((chapter) => chapter.number),
        isNot(contains('216')));
  });

  test('ToonLook exposes daily through all-time views under Popular', () async {
    late Uri requested;
    final source = ToonLookSource(
      baseUri: Uri.parse('https://toonlook.test/'),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('<main></main>', 200);
      }),
    );

    expect(
      source.catalogVariants(MangaCatalogFilter.popular).map((item) => item.id),
      ['daily_top', 'weekly_top', 'monthly_top', 'yearly_top', 'all_top'],
    );
    await source.browseVariant(
      MangaCatalogFilter.popular,
      'monthly_top',
    );
    expect(requested.path, '/top-manhwa/');
    expect(requested.queryParameters['sortby'], 'monthly_top');
  });

  test('ToonLook decodes chapterData and delegates scrambled image recovery',
      () async {
    final payload = base64Encode(utf8.encode('[{"src":"en/a/b/page.webp"}]'));
    Uri? loadedImage;
    String? descrambledLanguage;
    final source = ToonLookSource(
      baseUri: Uri.parse('https://toonlook.test/'),
      client: MockClient((request) async => http.Response('''
        <script>
          chapterData = {
            "base":"https://img.test",
            "lang":"en",
            "data":"$payload",
            "imageScramble":{"enabled":true,"stripHeight":500,"salt":"pepper"}
          };
        </script>
      ''', 200)),
      binaryLoader: (uri, headers) async {
        loadedImage = uri;
        return (
          statusCode: 200,
          body: Uint8List.fromList(utf8.encode('image-bytes')),
          headers: <String, String>{},
        );
      },
      imageDescrambler: (bytes, uri, language, stripHeight, salt) async {
        descrambledLanguage = language;
        expect(stripHeight, 500);
        expect(salt, 'pepper');
        return '/tmp/toonlook-page.png';
      },
    );

    final pages = await source
        .readChapter(mangaId: '/manhwa/work/', chapterId: '/chapter/1/')
        .toList();

    expect(loadedImage, Uri.parse('https://img.test/en/a/b/page.webp'));
    expect(descrambledLanguage, 'en');
    expect(pages.single.filePath, '/tmp/toonlook-page.png');
  });

  test('Hitomi resolves details from galleryinfo JSON when static HTML shell has empty gallery-brand',
      () async {
    const hash =
        '139d22d4189755e2e930840f70f8f53a944370570344c45c0762c1290ae2cba7';
    var browserCalled = false;
    final source = HitomiSource(
      baseUri: Uri.parse('https://hitomi.test/'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/galleries/4349175.js')) {
          return http.Response(
            'var galleryinfo = ${jsonEncode({
              'title': 'Sample Hitomi Work',
              'language': 'english',
              'artists': [
                {'artist': 'artist one', 'url': '/artist/artist%20one-all.html'}
              ],
              'tags': [
                {'tag': 'big breasts', 'url': '/tag/female%3Abig%20breasts-all.html'}
              ],
              'files': [
                {'hash': hash},
                {'hash': hash},
              ],
            })};',
            200,
          );
        }
        return http.Response('<h1 id="gallery-brand"></h1>', 200);
      }),
      browserHtmlLoader: (uri, userAgent) async {
        browserCalled = true;
        return '<h1 id="gallery-brand">Fallback</h1>';
      },
    );

    final details = await source.getDetails('/doujinshi/sample-work-4349175.html');
    expect(browserCalled, isFalse);
    expect(details.item.title, 'Sample Hitomi Work');
    expect(details.chapters.single.pages, '2');
    expect(details.author, 'artist one');
    expect(details.genres, ['big breasts']);
  });

  test('Hitomi catalog falls back to srcset and picture source when img has no src',
      () async {
    final source = HitomiSource(
      baseUri: Uri.parse('https://hitomi.test/'),
      client: MockClient((request) async => http.Response('''
        <div class="gallery-content">
          <div>
            <div class="dj-img1">
              <picture>
                <source type="image/avif" data-srcset="//tn.test/avif/1.avif 2x, //tn.test/avif/1s.avif 1x">
                <source type="image/webp" data-srcset="//tn.test/webp/1.webp 2x">
                <img class="lazyload">
              </picture>
            </div>
            <h1 class="lillie"><a href="/doujinshi/work-1.html">Work 1</a></h1>
          </div>
          <div>
            <div class="dj-img-cont">
              <img data-srcset="//tn.test/webp/2.webp 1x">
            </div>
            <h1 class="lillie"><a href="/cg/work-2.html">Work 2</a></h1>
          </div>
        </div>
      ''', 200)),
    );

    final page = await source.browse();
    expect(page.items, hasLength(2));
    expect(page.items[0].coverUri, Uri.parse('https://tn.test/webp/1.webp'));
    expect(page.items[1].coverUri, Uri.parse('https://tn.test/webp/2.webp'));
  });

  test('Hitomi browseVariant routes to the real sort URLs', () async {
    final requested = <Uri>[];
    final source = HitomiSource(
      baseUri: Uri.parse('https://hitomi.test/'),
      client: MockClient((request) async => http.Response('', 200)),
      browserHtmlLoader: (uri, userAgent) async {
        requested.add(uri);
        return '<div class="gallery-content"></div>';
      },
    );

    for (final variant in const [
      'date_added',
      'published',
      'today',
      'week',
      'month',
      'year',
      'random',
    ]) {
      await source.browseVariant(MangaCatalogFilter.popular, variant);
    }

    expect(
      requested.map((u) => u.toString()).toList(),
      [
        'https://hitomi.test/',
        'https://hitomi.test/date/published-all.html',
        'https://hitomi.test/popular/today-all.html',
        'https://hitomi.test/popular/week-all.html',
        'https://hitomi.test/popular/month-all.html',
        'https://hitomi.test/popular/year-all.html',
        'https://hitomi.test/search.html?orderbydirection%3Arandom',
      ],
    );
  });

  test('Hitomi search.html ignores #loader-content placeholder and triggers browser fallback',
      () async {
    var browserCalled = false;
    final source = HitomiSource(
      baseUri: Uri.parse('https://hitomi.test/'),
      client: MockClient((request) async => http.Response(
            '<div class="gallery-content"><div id="loader-content"></div></div>',
            200,
          )),
      browserHtmlLoader: (uri, userAgent) async {
        browserCalled = true;
        return '''
          <div class="gallery-content">
            <div>
              <div class="dj-img1"><img data-src="//tn.test/random.webp"></div>
              <h1 class="lillie"><a href="/doujinshi/random-1.html">Random Work</a></h1>
            </div>
          </div>
        ''';
      },
    );

    final page = await source.browseVariant(
      MangaCatalogFilter.popular,
      'random',
    );
    expect(browserCalled, isTrue);
    expect(page.items.single.title, 'Random Work');
    expect(
      HitomiSource.browserReadySelector(
        Uri.parse('https://hitomi.la/search.html?orderbydirection%3Arandom'),
      ),
      '.gallery-content > div:not(#loader-content)',
    );
  });
}
