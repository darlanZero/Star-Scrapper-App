import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/toonlook_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
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
}
