import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/manga/manga_livre_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('maps recent and popular catalogs with pagination', () async {
    final requested = <Uri>[];
    final source = MangaLivreSource(
      baseUri: Uri.parse('https://manga.example'),
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response(_catalogHtml, 200);
      }),
    );

    final recent = await source.browse(filter: MangaCatalogFilter.recent);
    final popular = await source.browse(
      filter: MangaCatalogFilter.popular,
      cursor: '2',
    );

    expect(requested[0].path, '/manga/');
    expect(requested[0].queryParameters['ordem'], 'recentes');
    expect(requested[1].path, '/manga/page/2/');
    expect(requested[1].queryParameters['ordem'], 'popular');
    expect(recent.items.single.id, 'obra-teste');
    expect(recent.items.single.title, 'Obra Teste');
    expect(recent.items.single.subtitle, '12.5 Ch');
    expect(recent.nextCursor, '2');
    expect(popular.nextCursor, '3');
  });

  test('parses WordPress search cards', () async {
    late Uri requested;
    final source = MangaLivreSource(
      baseUri: Uri.parse('https://manga.example'),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(_searchHtml, 200);
      }),
    );

    final page = await source.search('Solo Leveling');

    expect(requested.path, '/');
    expect(requested.queryParameters['s'], 'Solo Leveling');
    expect(page.items.single.id, 'solo-leveling');
    expect(page.items.single.subtitle, '200 Ch • 9.1');
  });

  test('loads metadata and every chapter through the SlimeRead REST route',
      () async {
    final requested = <Uri>[];
    final source = MangaLivreSource(
      baseUri: Uri.parse('https://manga.example'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path.contains('/wp-json/')) {
          return http.Response(
            jsonEncode({
              'list': _extraChapterHtml,
              'offset': 2,
              'total': 2,
              'has_more': false,
            }),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(_detailHtml),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );

    final details = await source.getDetails('obra-teste');

    expect(details.item.title, 'Obra Teste');
    expect(details.description, 'Uma sinopse de teste.');
    expect(details.author, 'Autora Teste');
    expect(details.status, MangaStatus.ongoing);
    expect(details.genres, ['Ação']);
    expect(details.chapters.map((chapter) => chapter.number), ['1', '2.5']);
    expect(details.item.subtitle, '2.5 Ch • Ongoing');
    expect(requested.last.path, '/wp-json/slimeread/v1/chapters/123');
    expect(requested.last.queryParameters['offset'], '1');
  });

  test('streams direct chapter images in reader order', () async {
    final source = MangaLivreSource(
      baseUri: Uri.parse('https://manga.example'),
      client: MockClient((request) async => http.Response('''
        <div class="chapter-images">
          <div class="chapter-image-container" data-page="1">
            <img class="chapter-image" src="https://cdn.example/page-1.webp">
          </div>
          <div class="chapter-image-container" data-page="2">
            <img class="chapter-image" data-src="/images/page-2.webp">
          </div>
        </div>
      ''', 200)),
    );

    final pages = await source
        .readChapter(
          mangaId: 'obra-teste',
          chapterId: 'obra-teste-capitulo-1',
        )
        .toList();

    expect(pages.map((page) => page.uri.toString()), [
      'https://cdn.example/page-1.webp',
      'https://manga.example/images/page-2.webp',
    ]);
    expect(pages.first.headers['Referer'], 'https://manga.example/');
  });

  test('authenticates through the AJAX form and keeps hashed WordPress cookie',
      () async {
    final requests = <http.Request>[];
    final source = MangaLivreSource(
      baseUri: Uri.parse('https://manga.example'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            '<script>var slimereadLogin = '
            '{"loginNonce":"nonce-123"};</script>',
            200,
            headers: {'set-cookie': 'wordpress_test_cookie=ok; Path=/'},
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'redirect': 'https://manga.example/'},
          }),
          200,
          headers: {
            'set-cookie':
                'wordpress_logged_in_a1b2=session-token; Path=/; HttpOnly',
          },
        );
      }),
    );

    await source.authenticateWithCredentials(' reader@example.com ', 'secret');

    expect(source.isAuthenticated, isTrue);
    expect(requests.last.url.path, '/wp-admin/admin-ajax.php');
    expect(requests.last.bodyFields['log'], 'reader@example.com');
    expect(requests.last.bodyFields['action'], 'slimeread_ajax_login');
    expect(requests.last.bodyFields['security'], 'nonce-123');
  });
}

const _catalogHtml = '''
<div class="home-latest-grid manga-archive-grid">
  <article class="home-manga-card">
    <a class="home-manga-cover" href="https://manga.example/manga/obra-teste/">
      <img class="manga-cover-img" src="https://cdn.example/cover.webp">
    </a>
    <div class="home-card-body">
      <h3><a href="https://manga.example/manga/obra-teste/">Obra Teste</a></h3>
      <div class="home-card-chapters"><a>Cap. 12.5</a></div>
    </div>
  </article>
</div>
<div class="pagination"><a class="next page-numbers" href="/manga/page/2/">Next</a></div>
''';

const _searchHtml = '''
<div class="search-results-grid">
  <div class="manga-card">
    <a class="manga-card-link" href="https://manga.example/manga/solo-leveling/">
      <img class="manga-cover-img" src="https://cdn.example/solo.webp">
      <span class="latest-chapter"><span class="chapter-number">Cap. 200</span></span>
      <h3 class="manga-card-title">Solo Leveling</h3>
      <div class="manga-card-rating">9.1</div>
    </a>
  </div>
</div>
''';

const _detailHtml = '''
<h1 class="manga-title">Obra Teste</h1>
<img class="manga-cover-image" src="https://cdn.example/cover.webp">
<div class="manga-synopsis"><div class="synopsis-content">Uma sinopse de teste.</div></div>
<div class="manga-meta-item"><span class="meta-label">Autor</span><span class="meta-value">Autora Teste</span></div>
<div class="manga-meta-item"><span class="meta-label">Status</span><span class="meta-value">Em andamento</span></div>
<div class="manga-tags"><a class="manga-tag">Ação</a><a class="manga-tag">38237</a></div>
<ul class="chapters-list">
  <li class="chapter-item"><a class="chapter-link" href="https://manga.example/capitulo/obra-teste-capitulo-2-5/"><span class="chapter-number">Capítulo 2.5: Extra</span></a></li>
</ul>
<button id="sr-load-chapters" data-manga="123" data-offset="1" data-total="2"></button>
''';

const _extraChapterHtml = '''
<ul class="chapters-list">
  <li class="chapter-item"><a class="chapter-link" href="https://manga.example/capitulo/obra-teste-capitulo-1/"><span class="chapter-number">Capítulo 1</span></a></li>
</ul>
''';
