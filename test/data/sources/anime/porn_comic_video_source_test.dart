import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/porn_comic_video_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('keeps Animation and Cosplay feeds and sidebars independent', () async {
    final requested = <Uri>[];
    final source = PornComicVideoSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html('''
          <ul id="list"><li><a class="thumb" href="/gif/1.html" title="Latest">
            <img src="/latest.webp"></a><i class="media">short video</i>
          </li></ul>
          <div class="page"><a class="a1" href="/gif/index-3.html">Next</a></div>
          <div class="right"><div class="ranking">
            <a href="/cos/9.html" title="Popular"><img src="/popular.webp"></a>
          </div></div>
        ''');
      }),
    );

    final animation = await source.browse(
      filter: AnimeCatalogFilter.recent,
      cursor: '2',
    );
    expect(requested.last.path, '/gif/index-2.html');
    expect(animation.items.single.title, 'Latest');
    expect(animation.nextCursor, '3');

    final cosplay = await source.browse(
      filter: AnimeCatalogFilter.popularMonth,
    );
    expect(requested.last.path, '/cos');
    expect(cosplay.items.single.title, 'Popular');
    expect(cosplay.nextCursor, isNull);
  });

  test('resolves JSON-LD contentUrl into native HLS playback', () async {
    final source = PornComicVideoSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async {
        if (request.url.host == 'video.test') {
          return http.Response('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=4200000,RESOLUTION=608x1080
fhd/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=270x480
sd/index.m3u8
''', 200);
        }
        return _html('''
        <h1 class="title">Video work</h1>
        <div class="summary">
          <a href="/anime/example.html">Example parody</a>
          <a href="/characters/hero.html">Hero</a>
          <a href="/artist/creator.html">Creator</a>
        </div>
        <div class="manga-tags"><a href="/tags/animated.html">Animated</a></div>
        <script type="application/ld+json">
          {"@type":"VideoObject","description":"Test video",
           "thumbnailUrl":["https://img.test/poster.webp"],
           "contentUrl":"https://video.test/path/master.m3u8?m=signed&t=123"}
        </script>
      ''');
      }),
    );

    final details = await source.getDetails('/gif/1.html');
    expect(details.item.coverUri, Uri.parse('https://img.test/poster.webp'));
    expect(details.description, 'Test video');
    expect(
        details.taxonomyLinks.map((link) => link.kind),
        containsAll([
          AnimeTaxonomyKind.parody,
          AnimeTaxonomyKind.character,
          AnimeTaxonomyKind.artist,
          AnimeTaxonomyKind.tag,
        ]));
    expect((await source.getEpisodes('/gif/1.html')).single.id, '/gif/1.html');

    final playback = await source.getPlayback(
      animeId: '/gif/1.html',
      episodeId: '/gif/1.html',
    );
    expect(playback.streams, hasLength(2));
    expect(playback.streams.first.protocol, VideoProtocol.hls);
    expect(playback.streams.first.uri.path, '/path/fhd/index.m3u8');
    expect(playback.streams.first.uri.queryParameters,
        containsPair('m', 'signed'));
    expect(playback.streams.first.uri.queryParameters,
        containsPair('from', '/path/master.m3u8'));
    expect(playback.streams.first.headers['Referer'],
        'https://porn.test/gif/1.html');
  });

  test('parses the masonry grid used by Animation latest', () async {
    final source = PornComicVideoSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async => _html('''
        <div class="grid">
          <div class="grid-item">
            <a href="/gif/7.html" title="Latest animation">
              <img src="/animation.webp"><span class="title">Latest animation</span>
            </a>
            <span class="media corner">short video</span>
          </div>
        </div>
      ''')),
    );

    final page = await source.browse(filter: AnimeCatalogFilter.recent);
    expect(page.items.single.id, '/gif/7.html');
    expect(page.items.single.title, 'Latest animation');
  });

  test('routes image and GIF cosplay galleries to the reader', () async {
    final source = PornComicVideoSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async => _html('''
        <h1 class="title">GIF collection</h1>
        <div class="info"><span class="lang_cat">English</span></div>
        <div class="manga-picture"><img src="https://img.test/1.gif"></div>
        <div id="pages"><a href="/cos/9-2.html">2</a></div>
        <div class="summary">
          <a href="/artist/model.html">Model name</a>
          <a href="/circle/topic.html">Topic name</a>
        </div>
      ''')),
    );

    final details = await source.getReaderDetails('/cos/9.html');
    expect(details, isNotNull);
    expect(details!.chapters.single.pages, '2');
    expect(details.taxonomyLinks.map((link) => link.id),
        containsAll(['/artist/model.html', '/circle/topic.html']));
  });
}

http.Response _html(String body) => http.Response(body, 200, headers: {
      'content-type': 'text/html; charset=utf-8',
    });
