import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/nhentai_xxx_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  const detailsHtml = '''
    <div class="gallery_top">
      <div class="cover"><img src="https://i5.test/018/gallery/cover.jpg"></div>
      <div class="info"><h1>Test gallery</h1><h2>Alternate title</h2>
        <ul>
          <li class="tags"><span class="text">Tags</span>
            <a class="tag_btn" href="/tag/alpha/"><span class="tag_name">alpha</span><span class="tag_count">12</span></a>
          </li>
          <li class="tags"><span class="text">Artists</span>
            <a class="tag_btn" href="/artist/test/"><span class="tag_name">Test Artist</span></a>
          </li>
          <li class="tags"><span class="text">Languages</span>
            <a class="tag_btn"><span class="tag_name">English</span></a>
          </li>
        </ul>
        <span class="tag_name pages">12</span>
        <span class="uploaded" data-uploaded-utc="2026-10-30T00:00:00Z"></span>
      </div>
    </div>
    <div class="gallery_thumbs"><div class="gt_th"><img src="https://i5.test/018/gallery/1t.jpg"></div></div>
  ''';

  String card(String id, String title) => '''
    <div class="gallery_item"><a href="/g/$id/" title="$title">
      <picture><img data-src="https://i5.test/$id/thumb.jpg" alt="$title"></picture>
      <div class="caption">$title</div>
    </a></div>
  ''';

  test('separates Popular Now from paginated New Uploads', () async {
    final source = NHentaiXxxSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        if (request.url.path.startsWith('/g/')) {
          return http.Response(detailsHtml, 200);
        }
        return http.Response('''
          <div class="content_box"><h2>Popular Now</h2>${card('1', 'Popular')}</div>
          <div class="content_box"><h2>New Uploads</h2>${card('2', 'Recent')}</div>
        ''', 200);
      }),
    );

    final popular = await source.browse(filter: MangaCatalogFilter.popular);
    final recent = await source.browse(filter: MangaCatalogFilter.recent);

    expect(popular.items.single.title, 'Popular');
    expect(popular.nextCursor, isNull);
    expect(recent.items.single.title, 'Recent');
    expect(recent.nextCursor, '2');
  });

  test('uses key parameter for title search', () async {
    Uri? requested;
    final source = NHentaiXxxSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('', 200);
      }),
    );

    await source.search('secret angel');
    expect(requested?.path, '/search/');
    expect(requested?.queryParameters['key'], 'secret angel');
  });

  test('parses searchable character cards and both result routes', () async {
    final requested = <Uri>[];
    final source = NHentaiXxxSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response('''
          <div class="tags_thumbs"><div class="thumb">
            <div class="tags_sort">
              <h3 class="ts_lat"><a href="/character/2k-tan/">Latest</a></h3>
              <h3 class="ts_pop"><a href="/character/2k-tan/popular/">Popular</a></h3>
            </div>
            <a href="/character/2k-tan/">
              <div class="t_cnt"><span class="c_num">1.2K</span></div>
              <img data-src="https://i4.test/character/thumb.jpg">
              <div class="caption">2k-tan</div>
            </a>
          </div></div>
        ''', 200);
      }),
    );

    final options = await source.getSortedTaxonomy(
      MangaTaxonomyKind.character,
      query: '2k',
      sort: MangaTaxonomySort.popular,
    );

    expect(requested.first.path, '/characters/NUM/');
    expect(options.single.id, '/character/2k-tan/');
    expect(options.single.popularId, '/character/2k-tan/popular/');
    expect(options.single.titleCount, 1200);
    expect(options.single.imageUri.toString(),
        'https://i4.test/character/thumb.jpg');
  });

  test('paginates visual character and parody indexes', () async {
    final requestedPages = <String>[];
    final source = NHentaiXxxSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async {
        final page = request.url.queryParameters['page'] ?? '1';
        requestedPages.add(page);
        final next = page == '1'
            ? '<a rel="next" href="/characters/?page=2">Next</a>'
            : '';
        return http.Response('''
          <div class="tags_thumbs"><div class="thumb">
            <div class="tags_sort">
              <h3 class="ts_lat"><a href="/character/hero-$page/">Latest</a></h3>
              <h3 class="ts_pop"><a href="/character/hero-$page/popular/">Popular</a></h3>
            </div>
            <a href="/character/hero-$page/">
              <span class="c_num">$page</span>
              <img src="https://i.test/hero-$page.jpg">
              <div class="caption">Hero $page</div>
            </a>
          </div></div>
          $next
        ''', 200);
      }),
    );

    final first = await source.getTaxonomyPage(
      MangaTaxonomyKind.character,
    );
    final second = await source.getTaxonomyPage(
      MangaTaxonomyKind.character,
      cursor: first.nextCursor,
    );

    expect(first.options.single.name, 'Hero 1');
    expect(first.nextCursor, '2');
    expect(second.options.single.name, 'Hero 2');
    expect(second.nextCursor, isNull);
    expect(requestedPages, ['1', '2']);
  });

  test('parses details and generates every full webp reader page', () async {
    final source = NHentaiXxxSource(
      baseUri: Uri.parse('https://nhentai.test'),
      client: MockClient((request) async => http.Response(detailsHtml, 200)),
    );

    final details = await source.getDetails('709428');
    expect(details.item.subtitle, '12 pages • English');
    expect(details.genres, ['alpha']);
    expect(details.artist, 'Test Artist');
    expect(details.chapters.single.pages, '12');

    final pages = await source
        .readChapter(mangaId: '709428', chapterId: '/g/709428/')
        .toList();
    expect(pages, hasLength(12));
    expect(pages.first.uri.toString(), 'https://i5.test/018/gallery/1.webp');
    expect(pages.last.uri.toString(), 'https://i5.test/018/gallery/12.webp');
  });
}
