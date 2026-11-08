import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/jable_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('exposes the Japanese R-rated catalogs requested by the provider', () {
    final source = JableSource();

    expect(source.id, 'jable');
    expect(source.isRRated, isTrue);
    expect(source.languageLabel, 'Japanese');
    expect(source.audioLabel, 'Japanese');
    expect(source.capabilityLabel, contains('Static English opt-in'));
    expect(
      source.catalogFilters,
      [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularMonth,
        AnimeCatalogFilter.popularWeek,
        AnimeCatalogFilter.popularToday,
      ],
    );
  });

  test('loads grouped tags and translates only their presentation labels',
      () async {
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: true,
      client: MockClient((_) async => _html(_menuHtml)),
    );

    final options = await source.getSearchOptions();

    expect(options.labelFor('genres', ''), 'Tags by type');
    expect(
        options.genres.map((option) => option.value), ['fishnets', 'facial']);
    expect(options.genres.map((option) => option.label), [
      'Costume · Fishnets',
      'Sex acts · Facial',
    ]);
    expect(
        options.sortLabelFor(AnimeSearchSort.defaultOrder, ''), 'Best recent');
    expect(
        options.sortLabelFor(AnimeSearchSort.favorites, ''), 'Most favorites');
  });

  test('clicks the monthly AJAX sort and parses cards and pagination',
      () async {
    Uri? browserUri;
    String? selector;
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: false,
      client: MockClient((_) async => http.Response('Forbidden', 403)),
      browserHtmlLoader: (uri, userAgent, clickSelector, maxClicks) async {
        browserUri = uri;
        selector = clickSelector;
        return _catalogHtml;
      },
    );

    final page = await source.browse(
      filter: AnimeCatalogFilter.popularMonth,
    );

    expect(browserUri!.path, '/hot/');
    expect(selector, contains('sort_by:video_viewed_month'));
    expect(page.items.single.id, 'snos-407');
    expect(page.items.single.title, 'SNOS-407 Sample title');
    expect(page.items.single.coverUri.toString(),
        'https://cdn.example.test/snos-407.jpg');
    expect(page.items.single.subtitle, contains('2:18:10'));
    expect(page.nextCursor, '2');
  });

  test('uses raw tag slugs and the favorites AJAX sort', () async {
    Uri? browserUri;
    String? selector;
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((_) async => http.Response('Forbidden', 403)),
      browserHtmlLoader: (uri, _, clickSelector, maxClicks) async {
        browserUri = uri;
        selector = clickSelector;
        return _catalogHtml;
      },
    );

    final page = await source.filter(
      AnimeSearchRequest(
        genres: {'fishnets'},
        sort: AnimeSearchSort.favorites,
      ),
    );

    expect(browserUri!.path, '/tags/fishnets/');
    expect(selector, contains('sort_by:most_favourited'));
    expect(page.items.single.id, 'snos-407');
  });

  test('applies the AJAX sort before selecting a later page', () async {
    Uri? browserUri;
    String? selector;
    int? clicks;
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((_) async => http.Response('Forbidden', 403)),
      browserHtmlLoader: (uri, _, clickSelector, maxClicks) async {
        browserUri = uri;
        selector = clickSelector;
        clicks = maxClicks;
        return _catalogHtml;
      },
    );

    await source.browse(
      filter: AnimeCatalogFilter.popularWeek,
      cursor: '2',
    );

    expect(browserUri!.path, '/hot/');
    expect(selector, contains('sort_by:video_viewed_week'));
    expect(selector, contains('from:02'));
    expect(clicks, 2);
  });

  test('uses the path-based search endpoint and its popularity sort', () async {
    Uri? browserUri;
    String? selector;
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((_) async => http.Response('Forbidden', 403)),
      browserHtmlLoader: (uri, _, clickSelector, maxClicks) async {
        browserUri = uri;
        selector = clickSelector;
        return _catalogHtml;
      },
    );

    await source.filter(
      AnimeSearchRequest(
        query: 'SNOS',
        sort: AnimeSearchSort.mostViewed,
      ),
    );

    expect(browserUri!.path, '/search/SNOS/');
    expect(selector, contains('sort_by:video_viewed'));
  });

  test('parses details, taxonomy, performer, release date and HLS', () async {
    var watchRequests = 0;
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      translateToEnglish: true,
      client: MockClient((request) async {
        watchRequests++;
        return _html(_videoHtml);
      }),
    );

    final details = await source.getDetails('snos-407');
    final episodes = await source.getEpisodes('snos-407');
    final playback = await source.getPlayback(
      animeId: 'snos-407',
      episodeId: 'snos-407',
    );

    expect(details.item.title, 'SNOS-407 Sample title');
    expect(details.genres, containsAll(['Roleplay', 'Facial']));
    expect(details.studios, ['Sakura Mio']);
    expect(
      details.taxonomyLinks.map((link) => link.kind),
      containsAll([
        AnimeTaxonomyKind.topic,
        AnimeTaxonomyKind.tag,
        AnimeTaxonomyKind.model,
      ]),
    );
    expect(episodes.single.releasedAt, DateTime(2026, 11, 5));
    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(playback.streams.single.uri.toString(),
        'https://media.example.test/master.m3u8?token=signed');
    expect(playback.streams.single.headers['Referer'],
        'https://example.test/videos/snos-407/');
    expect(playback.streams.single.headers['Origin'], 'https://example.test');
    expect(watchRequests, 2,
        reason:
            'details/episodes share one request; playback is resolved late');
  });

  test('persists browser session and delegates protected images', () async {
    Map<String, String>? requestHeaders;
    Uri? imageUri;
    final source = JableSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requestHeaders = request.headers;
        return _html(_catalogHtml);
      }),
      browserImageLoader: (uri, _) async {
        imageUri = uri;
        return Uint8List.fromList([4, 2]);
      },
    );

    await source.updateBrowserSession(
      cookies: {'cf_clearance': 'verified'},
      userAgent: 'Verified Floorp agent',
    );
    await source.browse();
    final bytes = await source.loadBrowserImage(
      Uri.parse('https://cdn.example.test/poster.jpg'),
    );

    expect(requestHeaders!['cookie'], 'cf_clearance=verified');
    expect(requestHeaders!['user-agent'], 'Verified Floorp agent');
    expect(imageUri!.host, 'cdn.example.test');
    expect(bytes, [4, 2]);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('jable_browser_cookies'),
        '{"cf_clearance":"verified"}');
  });
}

http.Response _html(String body) => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

const _menuHtml = '''
<nav class="app-nav">
  <div class="title-box"><h2>コスチューム</h2></div>
  <a class="tag" href="/tags/fishnets/">網タイツ</a>
  <div class="title-box"><h2>セックス行為</h2></div>
  <a class="tag" href="/tags/facial/">顔射</a>
</nav>
''';

const _catalogHtml = '''
<div class="video-img-box">
  <div class="img-box">
    <a href="/videos/snos-407/">
      <img data-src="https://cdn.example.test/snos-407.jpg">
      <div class="absolute-bottom-right"><span class="label">2:18:10</span></div>
    </a>
  </div>
  <div class="detail">
    <h6 class="title"><a href="/videos/snos-407/">SNOS-407 Sample title</a></h6>
    <p class="sub-title">120 000 views · 450 favorites</p>
  </div>
</div>
<nav class="pagination">
  <a href="/hot/2/" data-parameters="sort_by:video_viewed_month;from:02">2</a>
</nav>
''';

const _videoHtml = '''
<meta property="og:image" content="https://cdn.example.test/poster.jpg">
<div class="video-info">
  <h4>SNOS-407 Sample title</h4>
  <div class="header-right"><span class="inactive-color">発売された 2026-11-05</span></div>
  <h5 class="tags">
    <a class="cat" href="/categories/roleplay/">ロールプレイ</a>
    <a href="/tags/facial/">顔射</a>
  </h5>
  <div class="models">
    <a href="/models/sakura-mio/"><span data-original-title="Sakura Mio"></span></a>
  </div>
</div>
<video id="player" poster="https://cdn.example.test/poster.jpg" src="blob:https://example.test/player"></video>
<script>const hlsUrl = "https://media.example.test/master.m3u8?token=signed";</script>
''';
