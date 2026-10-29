import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/manga/yomu_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Yomu maps catalog sorting, metadata and pagination', () async {
    late Uri requestUri;
    final source = YomuSource(
      client: MockClient((request) async {
        requestUri = request.url;
        expect(request.headers['x-yomu-client'], 'true');
        return _json({
          'garimpo': [
            {
              'id': 'internal-id',
              'slug': 'obra-yomu',
              'title': 'Obra Yomu',
              'cover': 'https://cdn.yomu.com.br/cover.webp',
              'type': 'manhwa',
              'rating': 9.2,
              'chapters': 42,
              'lastChapter': 'Cap. 41',
            }
          ],
          'pagination': {'page': 1, 'totalPages': 3},
        });
      }),
    );

    final page = await source.browse(filter: MangaCatalogFilter.added);

    expect(requestUri.path, '/api/library-proxy');
    expect(requestUri.queryParameters['sort'], 'new');
    expect(page.items.single.id, 'obra-yomu');
    expect(page.items.single.subtitle, '41/42 Ch • Manhwa • 9.2');
    expect(page.nextCursor, '2');
  });

  test('Yomu exposes site filters through the typed catalog contract',
      () async {
    final requests = <Uri>[];
    final source = YomuSource(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/api/genres') {
          return _json(['Ação', 'Romance']);
        }
        return _json({
          'garimpo': [],
          'pagination': {'page': 1, 'totalPages': 1},
        });
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.formats.map((item) => item.value), contains('pornhwa'));
    expect(options.genres.map((item) => item.value), contains('Ação'));
    expect(options.supportsAdultMode, isTrue);

    await source.filterCatalog(MangaSearchRequest(
      formats: {'manhwa'},
      statuses: {'ONGOING'},
      genres: {'Ação'},
      sort: MangaSearchSort.chapterCount,
    ));
    final uri = requests.last;
    expect(uri.queryParameters['type'], 'manhwa');
    expect(uri.queryParameters['status'], 'ONGOING');
    expect(uri.queryParameters['genre'], 'Ação');
    expect(uri.queryParameters['sort'], 'chapters');
  });

  test('Yomu parses authenticated details and every lazy reader page',
      () async {
    var scrolledReaderUsed = false;
    final source = YomuSource(
      client: MockClient((request) async {
        if (request.url.path == '/api/genres') {
          return _json(['Drama', 'Fantasia']);
        }
        return http.Response('unauthorized', 401);
      }),
      browserHtmlLoader: (uri, userAgent) async => _detailsHtml,
      scrolledHtmlLoader: (uri, userAgent) async {
        scrolledReaderUsed = true;
        expect(uri.path, '/ler/obra-yomu/2');
        return _readerHtml;
      },
    );

    final details = await source.getDetails('obra-yomu');
    expect(details.item.title, 'Obra Yomu');
    expect(details.item.coverUri?.host, 'cdn.yomu.com.br');
    expect(details.author, 'Autora Teste');
    expect(details.artist, 'Artista Teste');
    expect(details.status, MangaStatus.ongoing);
    expect(details.genres, containsAll(['Drama', 'Fantasia']));
    expect(details.chapters.map((chapter) => chapter.id), [
      'obra-yomu|1',
      'obra-yomu|2',
    ]);
    expect(
        await source.nextChapterId('obra-yomu', 'obra-yomu|1'), 'obra-yomu|2');

    final pages = await source
        .readChapter(mangaId: 'obra-yomu', chapterId: 'obra-yomu|2')
        .toList();
    expect(scrolledReaderUsed, isTrue);
    expect(pages, hasLength(4));
    expect(pages.last.uri?.path, '/page-4.webp');
  });

  test('Yomu recognizes the Auth.js browser session', () async {
    final source = YomuSource();
    expect(source.isAuthenticated, isFalse);

    await source.updateBrowserSession({
      '__Secure-authjs.session-token': 'session-value',
      'theme': 'dark',
    });

    expect(source.isAuthenticated, isTrue);
    final restored = YomuSource();
    await restored.restoreSession();
    expect(restored.isAuthenticated, isTrue);
  });

  test('Yomu yields lazy reader URLs progressively', () async {
    final controller = StreamController<String>();
    final source = YomuSource(
      readerPageLoader: (uri, userAgent) {
        expect(uri.path, '/ler/meu-anjo-secreto/1');
        return controller.stream;
      },
    );
    final pages = <MangaReaderPage>[];
    final completed = Completer<void>();
    final subscription = source
        .readChapter(
          mangaId: 'meu-anjo-secreto',
          chapterId: 'meu-anjo-secreto|1',
        )
        .listen(
          pages.add,
          onDone: completed.complete,
          onError: completed.completeError,
        );

    controller.add('https://cdn.yomu.com.br/page-1.webp');
    await Future<void>.delayed(Duration.zero);
    expect(pages.map((page) => page.uri?.path), ['/page-1.webp']);

    controller
      ..add('https://cdn.yomu.com.br/page-2.webp')
      ..add('https://cdn.yomu.com.br/page-3.webp');
    await controller.close();
    await completed.future;

    expect(pages, hasLength(3));
    expect(pages.last.uri?.path, '/page-3.webp');
    await subscription.cancel();
  });
}

const _detailsHtml = '''
<html><body><main>
  <img alt="Obra Yomu" src="https://cdn.yomu.com.br/obras/obra-yomu/capa/cover.webp">
  <span>Manhwa</span><span>Em Lançamento</span><span>Drama</span><span>Fantasia</span>
  <h1>Obra Yomu</h1>
  <div><span>Autor</span><span>Autora Teste</span></div>
  <div><span>Artista</span><span>Artista Teste</span></div>
  <p>Uma descrição suficientemente longa para representar a sinopse principal da obra Yomu sem confundir com outros textos menores.</p>
  <div>Avaliação 9.4 / 10</div>
  <a href="/ler/obra-yomu/2"><span title="CAPÍTULO 2">CAPÍTULO 2</span><span>Yomu</span><span>28/10/2026</span></a>
  <a href="/ler/obra-yomu/1"><span title="CAPÍTULO 1">CAPÍTULO 1</span><span>Yomu</span><span>20/10/2026</span></a>
</main></body></html>
''';

const _readerHtml = '''
<html><body><main>
  <img alt="Página 1" src="https://cdn.yomu.com.br/page-1.webp">
  <img alt="Página 2" src="https://cdn.yomu.com.br/page-2.webp">
  <img alt="Página 3" src="https://cdn.yomu.com.br/page-3.webp">
  <img alt="Página 4" src="https://cdn.yomu.com.br/page-4.webp">
</main></body></html>
''';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
