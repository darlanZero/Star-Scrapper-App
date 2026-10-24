import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/goyabu_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses latest releases in episode publication order', () async {
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        expect(request.url.path, '/lancamentos');
        expect(request.headers['Referer'], 'https://example.test/');
        return _response(_latestHtml);
      }),
    );

    final page = await source.browse();

    expect(page.items, hasLength(2));
    expect(page.items.first.id, 'release:75217');
    expect(page.items.first.title, 'Kashita Maryoku');
    expect(page.items.first.subtitle, 'Episódio 2 · há 13 d');
    expect(page.items.last.title, 'Kyoufu Collector');
    expect(page.nextCursor, '2');
    expect(source.languageLabel, 'Português (Brasil)');
  });

  test('parses the dedicated popular endpoint', () async {
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        expect(request.url.path, '/wp-json/cronos/v1/views/ranking-all');
        expect(request.url.queryParameters, {'limit': '10', 'type': 'anime'});
        return _response(_popularJson);
      }),
    );

    final page = await source.browse(filter: AnimeCatalogFilter.popular);

    expect(page.items.first.id, 'cyberpunk-edgerunners-2');
    expect(page.items.first.subtitle, 'Legendado · ★ 5.0 · 1.2k views');
    expect(page.items.last.subtitle, contains('Dublado'));
  });

  test('loads popular results for today, week, and month', () async {
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _response(_popularJson)),
    );

    final today = await source.browse(filter: AnimeCatalogFilter.popular);
    final week = await source.browse(filter: AnimeCatalogFilter.popularWeek);
    final month = await source.browse(filter: AnimeCatalogFilter.popularMonth);

    expect(today.items.first.title, 'Cyberpunk: Edgerunners 2');
    expect(week.items.single.title, 'Weekly Hero');
    expect(month.items.single.title, 'Monthly Hero');
  });

  test('searches with the WordPress search page', () async {
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        expect(request.url.path, '/');
        expect(request.url.queryParameters['s'], 'Kyoufu Collector');
        return _response(_catalogHtml);
      }),
    );

    final page = await source.search('Kyoufu Collector');

    expect(page.items.first.title, 'Cyberpunk: Edgerunners 2');
  });

  test('parses details and loads the complete episode list through AJAX',
      () async {
    var calls = 0;
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        calls++;
        if (request.url.path == '/anime/kyoufu-collector') {
          return _response(_detailsHtml);
        }
        expect(request.url.path, '/wp-admin/admin-ajax.php');
        expect(request.url.queryParameters['action'], 'get_anime_episodes');
        expect(request.url.queryParameters['anime_id'], '75213');
        expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
        return _response(jsonEncode({
          'success': true,
          'data': [
            {
              'id': 75215,
              'episodio': '1',
              'episode_name': '',
              'imagem': '/episode.webp',
              'update': '2026-10-10T19:42:02+00:00',
            },
            {
              'id': 75313,
              'episodio': '2',
              'episode_name': 'O segundo mistério',
              'imagem': '/episode-2.webp',
            },
          ],
        }));
      }),
    );

    final details = await source.getDetails('kyoufu-collector');
    final episodes = await source.getEpisodes('kyoufu-collector');

    expect(calls, 3);
    expect(details.item.title, 'Kyoufu Collector');
    expect(details.item.subtitle, 'Legendado · 2026 · ★ 3.0');
    expect(details.description, contains('lendas são verdadeiras'));
    expect(details.genres, ['Mistério', 'Terror']);
    expect(details.status, AnimeStatus.ongoing);
    expect(details.externalIds['goyabu'], '75213');
    expect(episodes, hasLength(2));
    expect(episodes.first.id, '75215');
    expect(episodes.last.number, 2);
    expect(episodes.last.title, 'O segundo mistério');
  });

  test('resolves a latest-release episode id to its anime page', () async {
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/75215') {
          return _response('''
            <div class="episodes-controls">
              <a href="/anime/kyoufu-collector"><span class="lista">Lista</span></a>
            </div>
          ''');
        }
        expect(request.url.path, '/anime/kyoufu-collector');
        return _response(_detailsHtml);
      }),
    );

    final details = await source.getDetails('release:75215');

    expect(details.item.id, 'kyoufu-collector');
    expect(details.item.title, 'Kyoufu Collector');
  });

  test('resolves Blogger streams directly for native playback', () async {
    const player =
        'https://www.blogger.com/video.g?token=example-token-for-testing';
    final encrypted = base64.encode(utf8.encode(
      player.split('').reversed.join(),
    ));
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.host == 'www.blogger.com') {
          return _response(r'''
            <c-wiz data-p="https://rr1---sn-test.googlevideo.com/videoplayback?itag\u003d18\u0026mime\u003dvideo%2Fmp4"></c-wiz>
            <script>"https://rr1---sn-test.googlevideo.com/videoplayback?itag\u003d22\u0026mime\u003dvideo%2Fmp4"</script>
          ''');
        }
        return _response('''
          <div id="player"><iframe src="$player"></iframe></div>
          <button class="player-tab" data-blogger-url-encrypted="$encrypted">
            Player HD
          </button>
        ''');
      }),
    );

    final playback = await source.getPlayback(
      animeId: 'kyoufu-collector',
      episodeId: '75215',
    );

    expect(playback.streams, hasLength(2));
    expect(playback.streams.first.height, 720);
    expect(playback.streams.first.quality, '720p');
    expect(playback.streams.first.uri.host, contains('googlevideo.com'));
    expect(
        playback.streams.first.headers['Referer'], 'https://www.blogger.com/');
  });

  test('keeps the Blogger WebView as a playback fallback', () async {
    const player =
        'https://www.blogger.com/video.g?token=example-token-for-testing';
    final source = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.host == 'www.blogger.com') {
          return _response('<main>Blogger player changed</main>');
        }
        return _response(
            '<div id="player"><iframe src="$player"></iframe></div>');
      }),
    );

    await expectLater(
      source.getPlayback(animeId: 'test', episodeId: '75215'),
      throwsA(isA<AnimePlaybackResolutionRequired>()),
    );
  });

  test('reports Cloudflare browser verification and accepts browser fallback',
      () async {
    final blocked = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
    );
    await expectLater(
      blocked.browse(),
      throwsA(isA<AnimeSourceSessionRequired>()),
    );

    SharedPreferences.setMockInitialValues({
      'goyabu_browser_cookies': jsonEncode({'cf_clearance': 'valid'}),
      'goyabu_browser_user_agent': 'Verified WebView',
    });
    final fallback = GoyabuSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
      browserHtmlLoader: (uri, userAgent) async {
        expect(userAgent, 'Verified WebView');
        return _latestHtml;
      },
    );

    final page = await fallback.browse();
    expect(page.items, hasLength(2));
  });
}

http.Response _response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

const _catalogHtml = '''
<article class="boxAN"><a href="/anime/cyberpunk-edgerunners-2">
  <figure class="thumb"><img class="cover" src="/cyberpunk.webp"
    title="Cyberpunk: Edgerunners 2"></figure>
  <div class="title">Cyberpunk: Edgerunners 2</div>
  <div class="rating-score-box"><span class="rating-poster">5.0</span></div>
</a></article>
<article class="boxAN"><a href="/anime/one-punch-man-3-dublado">
  <figure class="thumb"><div class="audio-box dublado">Dublado</div>
    <img class="cover" src="/opm.webp" title="One Punch Man 3 Dublado"></figure>
  <div class="title">One Punch Man 3 Dublado</div>
  <div class="rating-score-box"><span class="rating-poster">4.2</span></div>
</a></article>
<a href="/lista-de-animes?l=todos&amp;paged=2">2</a>
''';

String get _popularJson => jsonEncode({
      'success': true,
      'rankings': {
        'day': [
          {
            'post_id': 1,
            'title': 'Cyberpunk: Edgerunners 2',
            'audio': 'jap',
            'rating': '5.0',
            'poster': '/cyberpunk.webp',
            'permalink': '/anime/cyberpunk-edgerunners-2',
            'views_formatted': '1.2k',
          },
          {
            'post_id': 2,
            'title': 'One Punch Man 3 Dublado',
            'audio': 'ptBr',
            'rating': '4.2',
            'poster': '/opm.webp',
            'permalink': '/anime/one-punch-man-3-dublado',
            'views_formatted': '980',
          },
        ],
        'week': [
          {
            'title': 'Weekly Hero',
            'audio': 'jap',
            'poster': '/week.webp',
            'permalink': '/anime/weekly-hero',
          },
        ],
        'month': [
          {
            'title': 'Monthly Hero',
            'audio': 'ptBr',
            'poster': '/month.webp',
            'permalink': '/anime/monthly-hero',
          },
        ],
      },
    });

const _latestHtml = '''
<article class="boxEP grid-view"><a href="/75217">
  <figure class="thumb" data-thumb="/latest-1.webp"></figure>
  <div class="ep-type"><b>Episódio 2</b></div>
  <span class="timeAgo">há 13 d</span>
  <div class="title">Kashita Maryoku</div>
</a></article>
<article class="boxEP grid-view"><a href="/75215">
  <figure class="thumb" data-thumb="/latest-2.webp"></figure>
  <div class="ep-type"><b>Episódio 1</b></div>
  <span class="timeAgo">há 13 d</span>
  <div class="title">Kyoufu Collector</div>
</a></article>
<a href="/lancamentos?paged=2">2</a>
''';

const _detailsHtml = '''
<main>
  <div class="streamer-bg"><img src="/background.webp"></div>
  <div class="streamer-poster"><figure>
    <div class="audio-box legendado">Legendado</div>
    <img src="/cover.webp" title="Kyoufu Collector">
  </figure></div>
  <div class="streamer-info">
    <h1>Kyoufu Collector</h1>
    <span id="year">2026</span>
    <span class="status">Lançamento</span>
    <div class="rating-total">3.0</div>
    <div class="rating-stars" data-post-id="75213"></div>
    <div class="streamer-categories">
      <a href="/generos/misterio">Mistério</a>
      <a href="/generos/terror">Terror</a>
    </div>
    <div class="streamer-sinopse">
      <span class="sinopse-short">Resumo curto.</span>
      <span class="sinopse-full">Algumas lendas são verdadeiras.</span>
    </div>
  </div>
</main>
''';
