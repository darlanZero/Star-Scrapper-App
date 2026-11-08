import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/hentai_img_manga_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('builds one gallery chapter and streams every original image', () async {
    final requested = <Uri>[];
    final source = HentaiImgMangaSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(_galleryHtml);
      }),
    );

    final details = await source.getDetails('/image/gallery-one/');
    expect(details.item.title, 'Gallery One');
    expect(details.item.coverUri, Uri.parse('https://static.test/1.jpg'));
    expect(details.chapters.single.pages, '3');
    expect(details.chapters.single.language, 'en');
    expect(details.taxonomyLinks.single.id, 'big-breasts');

    final pages = await source
        .readChapter(
          mangaId: '/image/gallery-one/',
          chapterId: '/image/gallery-one/',
        )
        .toList();
    expect(pages.map((page) => page.uri), [
      Uri.parse('https://static.test/1.jpg'),
      Uri.parse('https://static.test/2.jpg'),
      Uri.parse('https://static.test/3.jpg'),
    ]);
    expect(pages.first.headers['Referer'], 'https://hentai-img.com/');
    expect(requested, hasLength(2));
  });

  test('parses tag counts and browses tags on hentai-img itself', () async {
    final requested = <Uri>[];
    final source = HentaiImgMangaSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/tag/') {
          return _html('''
            <ul id="tags">
              <li><a href="/search/tag/big-breasts/">big breasts (28,406)</a></li>
            </ul>
            <div class="wp-pagenavi"><a href="/tag/page/2/">2</a></div>
          ''');
        }
        if (request.url.path == '/tag/page/2/') {
          return _html('''
            <ul id="tags">
              <li><a href="/search/tag/animated/">animated (502)</a></li>
            </ul>
          ''');
        }
        return _html('''
          <div id="display_area_image"><ul id="image-list">
            <li><div class="image-list-item">
              <div class="image-list-item-image"><a href="/image/one/">
                <img src="/one.jpg" alt="One"></a></div>
              <p class="image-list-item-title"><a href="/image/one/">One</a></p>
            </div></li>
          </ul></div>
        ''');
      }),
    );

    final tags = await source.getTaxonomy(MangaTaxonomyKind.tag);
    expect(tags.map((tag) => tag.id), ['big-breasts', 'animated']);
    expect(tags.first.titleCount, 28406);

    final page = await source.browseTaxonomy(
      MangaTaxonomyKind.tag,
      'big-breasts',
    );
    expect(requested.last.path, '/search/tag/big-breasts/');
    expect(page.items.single.title, 'One');
  });
}

const _galleryHtml = '''
  <div id="page"><div id="right_sidebar"><h3>Gallery One</h3>
  <ul id="detail_list" data-modal-gallery-image-container>
    <li><a data-modal-gallery-image-item href="https://static.test/1.jpg"><img src="/p=305/1.jpg"></a></li>
    <li><a data-modal-gallery-image-item href="https://static.test/2.jpg"><img src="/p=305/2.jpg"></a></li>
    <li><a data-modal-gallery-image-item href="https://static.test/3.jpg"><img src="/p=305/3.jpg"></a></li>
  </ul></div></div>
  <div id="detail_tag"><a href="/search/tag/big-breasts/">big breasts</a></div>
''';

http.Response _html(String body) => http.Response(body, 200, headers: {
      'content-type': 'text/html; charset=utf-8',
    });
