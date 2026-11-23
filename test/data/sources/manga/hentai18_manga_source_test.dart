import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/madara_adult_sources.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps custom Hentai18 cards, sorting and query pagination', () async {
    late Uri requested;
    final source = Hentai18MangaSource(
      baseUri: Uri.parse('https://h18.test/'),
      client: MockClient((request) async {
        requested = request.url;
        return _html(_catalogHtml);
      }),
    );

    expect(source.catalogFilters, [
      MangaCatalogFilter.recent,
      MangaCatalogFilter.popular,
      MangaCatalogFilter.trending,
      MangaCatalogFilter.added,
    ]);

    final page = await source.browseVariant(
      MangaCatalogFilter.popular,
      'manhwa',
      cursor: '2',
    );

    expect(requested.path, '/category/manhwa/');
    expect(requested.queryParameters, {'sort': 'popular', 'page': '2'});
    expect(page.items.single.id, '/read-hentai/ogh-reboot');
    expect(page.items.single.title, 'Ogh Reboot');
    expect(page.items.single.coverUri,
        Uri.parse('https://media.test/ogh-reboot.webp'));
    expect(page.items.single.subtitle, '38 Ch • 3.5');
    expect(page.nextCursor, '3');

    await source.browseVariant(MangaCatalogFilter.trending, 'manga');
    expect(requested.queryParameters['sort'], 'rating');
  });

  test('maps details, clickable genres and chapters', () async {
    final source = Hentai18MangaSource(
      baseUri: Uri.parse('https://h18.test/'),
      client: MockClient((request) async => _html(_detailsHtml)),
    );

    final details = await source.getDetails('/read-hentai/ogh-reboot');

    expect(details.item.title, 'Ogh Reboot');
    expect(details.item.coverUri, Uri.parse('https://media.test/cover.webp'));
    expect(details.description, 'Test synopsis.');
    expect(details.status, MangaStatus.ongoing);
    expect(details.genres, ['Drama', 'Mature']);
    expect(details.taxonomyLinks.last.id, '/tag/mature');
    expect(details.chapters.map((chapter) => chapter.number), ['38', '37']);
    expect(details.chapters.first.publishedAt, '2026-11-22');
  });

  test('reads every custom Hentai18 reader image with referer', () async {
    final source = Hentai18MangaSource(
      baseUri: Uri.parse('https://h18.test/'),
      client: MockClient((request) async => _html(_readerHtml)),
    );

    final pages = await source
        .readChapter(
          mangaId: '/read-hentai/ogh-reboot',
          chapterId: '/read-hentai/ogh-reboot-chapter-38-ch154004',
        )
        .toList();

    expect(pages.map((page) => page.uri), [
      Uri.parse('https://cdn.test/1.webp'),
      Uri.parse('https://cdn.test/2.webp'),
    ]);
    expect(
      pages.first.headers['Referer'],
      'https://h18.test/read-hentai/ogh-reboot-chapter-38-ch154004',
    );
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

const _catalogHtml = '''
<article class="hx-card has-chaps">
  <a class="hx-card-cover" href="/read-hentai/ogh-reboot" title="Ogh Reboot">
    <img src="https://media.test/ogh-reboot.webp">
    <span class="hx-card-star">3.5</span>
  </a>
  <h3 class="hx-card-title"><a href="/read-hentai/ogh-reboot" title="Ogh Reboot">Ogh Reboot</a></h3>
  <ul class="hx-card-chaps"><li><a href="/read-hentai/ogh-reboot-chapter-38-ch154004"><span class="hx-card-chap-name">Chapter 38</span></a></li></ul>
</article>
<a href="/category/manhwa?page=3">Next</a>
''';

const _detailsHtml = '''
<div class="hx-detail">
  <div class="hx-detail-poster"><img src="https://media.test/cover.webp"></div>
  <div class="hx-detail-info">
    <span class="hx-pill-status">Ongoing</span>
    <h1>Ogh Reboot</h1>
    <p class="hx-detail-alt"><span>Also known as</span> Alternative</p>
    <p class="hx-synopsis-text">Test synopsis.</p>
    <div class="hx-genres"><a href="/tag/drama">Drama</a><a href="/tag/mature">Mature</a></div>
  </div>
</div>
<div id="chapter-list">
  <a class="hx-ep" href="/read-hentai/ogh-reboot-chapter-38-ch154004"><span class="hx-ep-name">Chapter 38</span><time datetime="2026-11-22"></time></a>
  <a class="hx-ep" href="/read-hentai/ogh-reboot-chapter-37-ch152394"><span class="hx-ep-name">Chapter 37</span><time datetime="2026-11-10"></time></a>
</div>
''';

const _readerHtml = '''
<div class="hx-pages">
  <img src="https://cdn.test/1.webp">
  <img src="https://cdn.test/2.webp">
</div>
''';
