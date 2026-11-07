import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/hanime1_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses paginated catalogs and translates presentation metadata',
      () async {
    Uri? requested;
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: true,
      client: MockClient((request) async {
        requested = request.url;
        return _html(_catalogHtml);
      }),
    );

    final page = await source.browse(filter: AnimeCatalogFilter.popularWeek);

    expect(requested!.queryParameters['sort'], '本週排行');
    expect(page.items, hasLength(1));
    expect(page.items.single.id, '/watch?v=409060');
    expect(page.items.single.title, 'Romance Older sister');
    expect(page.items.single.coverUri.toString(),
        'https://cdn.example.test/poster.webp?token=signed');
    expect(page.items.single.subtitle, contains('2 hours ago'));
    expect(page.nextCursor, '2');
  });

  test('parses the legacy cards used by adult, short-form and preview feeds',
      () async {
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: true,
      client: MockClient((_) async => _html(_legacyCatalogHtml)),
    );

    final page = await source.filter(
      AnimeSearchRequest(
        type: '裏番',
        sort: AnimeSearchSort.releaseDate,
      ),
    );

    expect(page.items, hasLength(1));
    expect(page.items.single.id, '/watch?v=408323');
    expect(page.items.single.title, 'Romance Older sister 6');
    expect(
      page.items.single.coverUri.toString(),
      'https://cdn.example.test/cover/408323.jpg?token=signed',
    );
  });

  test('exposes translated filter labels but sends raw Chinese values',
      () async {
    final requested = <Uri>[];
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: true,
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(
          request.url.path == '/search' && request.url.query.isEmpty
              ? _filterHtml
              : _catalogHtml,
        );
      }),
    );

    final options = await source.getSearchOptions();
    await source.filter(
      AnimeSearchRequest(
        query: 'sample',
        genres: {'純愛', '中文字幕'},
        type: '裏番',
        year: '過去 1 週',
        status: '20分鐘以上',
        rating: 'broad',
        sort: AnimeSearchSort.score,
      ),
    );

    expect(options.labelFor('genres', ''), 'Tags');
    expect(options.types.single.label, 'Adult anime');
    expect(
        options.genres.map((option) => option.label),
        containsAll([
          'Romance',
          'Chinese subtitles',
          'Nipple rings',
          'Foreign object insertion',
          'Facesitting',
        ]));
    final filtered = requested.last;
    expect(filtered.queryParameters['genre'], '裏番');
    expect(filtered.queryParametersAll['tags[]'], ['純愛', '中文字幕']);
    expect(filtered.queryParameters['date'], '過去 1 週');
    expect(filtered.queryParameters['duration'], '20分鐘以上');
    expect(filtered.queryParameters['broad'], 'on');
    expect(filtered.queryParameters['sort'], '讚好比例');
  });

  test('parses details, taxonomy, episode date and signed MP4 qualities',
      () async {
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: true,
      client: MockClient((request) async => _html(_watchHtml)),
    );

    final details = await source.getDetails('/watch?v=409060');
    final episodes = await source.getEpisodes('/watch?v=409060');
    final playback = await source.getPlayback(
      animeId: '/watch?v=409060',
      episodeId: '/watch?v=409060',
    );

    expect(details.item.title, 'Sample Adult anime');
    expect(details.description, 'A Romance story.');
    expect(details.genres, containsAll(['Adult anime', 'Romance']));
    expect(details.taxonomyLinks, hasLength(2));
    expect(details.alternativeTitles, ['Sample 裏番']);
    expect(episodes.single.releasedAt, DateTime(2026, 11, 6));
    expect(playback.streams.map((stream) => stream.quality),
        ['1080p', '720p', '480p']);
    expect(playback.streams.first.protocol, VideoProtocol.progressive);
    expect(playback.streams.first.headers['Referer'],
        'https://example.test/watch?v=409060');
    expect(playback.streams.first.headers['Origin'], 'https://example.test');
  });

  test('falls back to browser HTML and browser image loading after HTTP 403',
      () async {
    Uri? browserUri;
    Uri? imageUri;
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: false,
      client: MockClient((_) async => http.Response('Forbidden', 403)),
      browserHtmlLoader: (uri, userAgent) async {
        browserUri = uri;
        expect(userAgent, contains('Android 14'));
        return _catalogHtml;
      },
      browserImageLoader: (uri, userAgent) async {
        imageUri = uri;
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final page = await source.browse();
    final bytes = await source.loadBrowserImage(
      Uri.parse('https://cdn.example.test/poster.webp'),
    );

    expect(browserUri!.path, '/search');
    expect(page.items.single.title, '純愛 姐');
    expect(imageUri!.host, 'cdn.example.test');
    expect(bytes, [1, 2, 3]);
  });

  test('persists the verified browser cookies and user agent', () async {
    Map<String, String>? headers;
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: false,
      client: MockClient((request) async {
        headers = request.headers;
        return _html(_catalogHtml);
      }),
    );

    await source.updateBrowserSession(
      cookies: {'cf_clearance': 'verified'},
      userAgent: 'Verified browser agent',
    );
    await source.browse();

    expect(source.sessionUri.toString(), 'https://example.test/search');
    expect(headers!['cookie'], 'cf_clearance=verified');
    expect(headers!['user-agent'], 'Verified browser agent');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('hanime1_browser_cookies'),
        '{"cf_clearance":"verified"}');
  });

  test('caches filters and shares one metadata request for details and episode',
      () async {
    var filterRequests = 0;
    var watchRequests = 0;
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: false,
      client: MockClient((request) async {
        if (request.url.path == '/search') {
          filterRequests++;
          return _html(_filterHtml);
        }
        watchRequests++;
        return _html(_watchHtml);
      }),
    );

    await source.getSearchOptions();
    await source.getSearchOptions();
    await Future.wait([
      source.getDetails('/watch?v=409060'),
      source.getEpisodes('/watch?v=409060'),
    ]);

    expect(filterRequests, 1);
    expect(watchRequests, 1);
  });

  test('resolves blob players through the signed download MP4 table', () async {
    final requested = <Uri>[];
    final source = Hanime1Source(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: false,
      client: MockClient((request) async {
        requested.add(request.url);
        return _html(
          request.url.path == '/download' ? _downloadHtml : _blobWatchHtml,
        );
      }),
    );

    final playback = await source.getPlayback(
      animeId: '/watch?v=39137',
      episodeId: '/watch?v=39137',
    );

    expect(requested.map((uri) => uri.path), ['/watch', '/download']);
    expect(requested.last.queryParameters['v'], '39137');
    expect(playback.streams.map((stream) => stream.quality),
        ['1080p', '720p', '480p']);
    expect(playback.streams.first.uri.host, 'media.example.test');
    expect(playback.streams.first.headers['Referer'],
        'https://example.test/download?v=39137');
  });
}

http.Response _html(String body) => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

const _catalogHtml = '''
<div class="video-item-container">
  <a class="video-link" href="/watch?v=409060">
    <img class="main-thumb" src="https://cdn.example.test/poster.webp?token=signed">
  </a>
  <div class="duration">24:03</div>
  <div class="stats-container"><span class="stat-item">1.2萬次</span></div>
  <div class="title">純愛 姐</div>
  <div class="subtitle"><a>Studio A</a><span class="subtitle-time">• 2小時前</span></div>
</div>
<nav class="pagination"><a href="/search?sort=本週排行&page=2">2</a></nav>
''';

const _legacyCatalogHtml = '''
<div class="home-rows-videos-wrapper">
  <a href="https://example.test/watch?v=408323">
    <div class="home-rows-videos-div search-videos">
      <div class="video-card-inner">
        <img src="https://cdn.example.test/cover/408323.jpg?token=signed">
        <div class="home-rows-videos-title">純愛 姐 6</div>
      </div>
    </div>
  </a>
</div>
''';

const _filterHtml = '''
<div class="genre-option" data-value="全部"></div>
<div class="genre-option" data-value="裏番"></div>
<input name="tags[]" value="純愛">
<input name="tags[]" value="中文字幕">
<input name="tags[]" value="乳環">
<input name="tags[]" value="異物插入">
<input name="tags[]" value="顏面騎乘">
<div class="hentai-date-options-wrapper" data-value="過去 1 週"></div>
<div class="hentai-duration-options-wrapper" data-value="20分鐘以上"></div>
''';

const _watchHtml = '''
<h1 id="shareBtn-title">Sample 裏番</h1>
<div class="video-caption-text">A 純愛 story.</div>
<div class="creator"><div><span id="video-artist-name">Studio A</span></div>
  <a href="/search?genre=裏番">裏番</a>
</div>
<div class="video-description-panel"><span class="hidden-xs">2026-11-06</span></div>
<div class="video-tags-wrapper">
  <a href="/search?tags%5B%5D=純愛">#純愛 (10)</a>
  <a href="/search?query=姐姐">#姐姐</a>
</div>
<video id="player" poster="/poster.jpg">
  <source src="https://cdn.example.test/video-480.mp4?token=one" size="480" type="video/mp4">
  <source src="https://cdn.example.test/video-1080.mp4?token=three" size="1080" type="video/mp4">
  <source src="https://cdn.example.test/video-720.mp4?token=two" size="720" type="video/mp4">
</video>
''';

const _blobWatchHtml = '''
<h1 id="shareBtn-title">Blob-backed video</h1>
<video id="player" src="blob:https://example.test/player"></video>
''';

const _downloadHtml = '''
<table class="download-table">
  <tr><td>Full HD (1080p)</td><td><a data-url="https://media.example.test/video-1080.mp4?token=a">Download</a></td></tr>
  <tr><td>HD (720p)</td><td><a data-url="https://media.example.test/video-720.mp4?token=b">Download</a></td></tr>
  <tr><td>Standard (480p)</td><td><a data-url="https://media.example.test/video-480.mp4?token=c">Download</a></td></tr>
</table>
''';
