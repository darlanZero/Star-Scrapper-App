import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/hentai_img_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('exposes every image and video feed with R-rated English metadata', () {
    final source = HentaiImgSource();

    expect(source.id, 'hentai_img');
    expect(source.isRRated, isTrue);
    expect(source.languageLabel, 'English');
    expect(source.catalogFilters, [
      AnimeCatalogFilter.recent,
      AnimeCatalogFilter.added,
      AnimeCatalogFilter.updated,
      AnimeCatalogFilter.completed,
      AnimeCatalogFilter.popular,
      AnimeCatalogFilter.featured,
      AnimeCatalogFilter.seriesPopular,
      AnimeCatalogFilter.seriesMostViewed,
      AnimeCatalogFilter.movies,
      AnimeCatalogFilter.episodeMostViewed,
    ]);
  });

  test('uses only the primary feed and follows WordPress pagination', () async {
    final requested = <Uri>[];
    final source = HentaiImgSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(_catalogHtml);
      }),
    );

    final page = await source.browse(filter: AnimeCatalogFilter.added);

    expect(requested.single.path, '/recently-download/');
    expect(page.items, hasLength(2));
    expect(page.items.first.id, '/image/gallery-one/');
    expect(page.items.last.id, '/video/movie-one/');
    expect(page.items.last.subtitle, startsWith('Video'));
    expect(page.nextCursor, '/recently-download/page/2/');

    await source.browse(
      filter: AnimeCatalogFilter.added,
      cursor: page.nextCursor,
    );
    expect(requested.last.path, '/recently-download/page/2/');
  });

  test('parses the responsive catalog returned to Android clients', () async {
    final source = HentaiImgSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((_) async => _html('''
        <div id="page"><div id="right_sidebar">
          <h3>New Images</h3>
          <ul id="entry_list">
            <li><a href="/image/mobile-gallery/">
              <div class="content_img"><img src="/mobile.webp" alt="Mobile Gallery"></div>
              <span class="posted">2026/11/08</span><br><span>Mobile Gallery</span>
            </a></li>
          </ul>
        </div></div>
        <a class="paginator_page" rel="next" href="/search/page/2/">Next</a>
      ''')),
    );

    final page = await source.browse();
    expect(page.items.single.id, '/image/mobile-gallery/');
    expect(page.items.single.title, 'Mobile Gallery');
    expect(page.items.single.coverUri,
        Uri.parse('https://example.test/mobile.webp'));
    expect(page.nextCursor, '/search/page/2/');
  });

  test('loads tag options and searches through the local tag route', () async {
    final requested = <Uri>[];
    final source = HentaiImgSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/tag/') {
          return _html('''
            <ul id="tags">
              <li><a href="/search/tag/big-breasts/">big breasts (28,406)</a></li>
              <li><a href="/search/tag/ai-generated/">AI generated (120)</a></li>
            </ul>
          ''');
        }
        return _html(_catalogHtml);
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.tags.map((tag) => tag.value), [
      'big-breasts',
      'ai-generated',
    ]);

    await source.filter(AnimeSearchRequest(tags: {'ai-generated'}));
    expect(requested.last.path, '/search/tag/ai-generated/');

    await source.browseTaxonomy(AnimeTaxonomyKind.tag, 'big-breasts');
    expect(requested.last.path, '/search/tag/big-breasts/');
  });

  test('routes image posts to the reader and keeps videos in the player',
      () async {
    final source = HentaiImgSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _html(
            request.url.path.startsWith('/image/') ? _galleryHtml : _videoHtml,
          )),
    );

    final gallery = await source.getReaderDetails('/image/gallery-one/');
    expect(gallery, isNotNull);
    expect(gallery!.chapters.single.pages, '2');
    expect(
      gallery.taxonomyLinks.single.id,
      'ai-generated',
    );
    expect(await source.getReaderDetails('/video/movie-one/'), isNull);

    final details = await source.getDetails('/video/movie-one/');
    expect(details.item.title, 'Movie One');
    expect(details.item.coverUri, Uri.parse('https://cdn.test/poster.jpg'));
    expect(details.taxonomyLinks.single.id, 'animated');

    final playback = await source.getPlayback(
      animeId: '/video/movie-one/',
      episodeId: '/video/movie-one/',
    );
    final stream = playback.streams.single;
    expect(stream.uri, Uri.parse('https://video.test/movie.m3u8'));
    expect(stream.protocol, VideoProtocol.hls);
    expect(stream.headers['Referer'], 'https://example.test/video/movie-one/');
    expect(stream.headers['Origin'], 'https://example.test');
  });
}

const _catalogHtml = '''
  <div id="post_list_title">New Images</div>
  <div id="display_area_image"><ul id="image-list">
    <li><div class="image-list-item">
      <div class="image-list-item-image"><a href="/image/gallery-one/">
        <img src="https://cdn.test/gallery.jpg" alt="Gallery One"></a></div>
      <p class="image-list-item-title"><a href="/image/gallery-one/">Gallery One</a></p>
      <p class="image-list-item-regist-date"><span>2026/11/08</span></p>
    </div></li>
    <li><div class="image-list-item">
      <div class="image-list-item-image"><a href="/video/movie-one/">
        <img src="https://cdn.test/movie.jpg" alt="Movie One"></a></div>
      <p class="image-list-item-title"><a href="/video/movie-one/">Movie One</a></p>
    </div></li>
  </ul></div>
  <div id="display_area_image"><ul id="image-list">
    <li><div class="image-list-item"><a href="/image/sidebar/">
      <img src="/sidebar.jpg" alt="Sidebar item"></a></div></li>
  </ul></div>
  <div class="wp-pagenavi">
    <a class="nextpostslink" rel="next" href="/recently-download/page/2/">Next</a>
  </div>
''';

const _galleryHtml = '''
  <div id="title"><h2>Gallery One</h2></div>
  <div id="detail_tag"><a href="/search/tag/ai-generated/">AI generated</a></div>
  <div id="display_image_detail">
    <a data-modal-gallery-image-item href="https://static.test/1.jpg"><img src="/p=700/1.jpg"></a>
    <a data-modal-gallery-image-item href="https://static.test/2.jpg"><img src="/p=700/2.jpg"></a>
  </div>
''';

const _videoHtml = '''
  <h1 id="post_title">Movie One</h1>
  <div id="the_tags">
    <a href="https://hentai-video-xxx.com/search/tag/animated/">Animated</a>
  </div>
  <video id="video_1" poster="https://cdn.test/poster.jpg">
    <source src="https://video.test/movie.m3u8" type="application/x-mpegURL">
  </video>
''';

http.Response _html(String body) => http.Response(body, 200, headers: {
      'content-type': 'text/html; charset=utf-8',
    });
