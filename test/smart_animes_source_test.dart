import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/smart_animes_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses updated catalog and pagination', () async {
    final source = SmartAnimesSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        expect(request.url.path, '/anime/');
        expect(request.url.queryParameters['order'], 'update');
        return _response(_catalogHtml);
      }),
    );

    final page = await source.browse(filter: AnimeCatalogFilter.updated);

    expect(page.items, hasLength(1));
    expect(page.items.single.id, 'gensou-suikoden');
    expect(page.items.single.title, 'Gensou Suikoden');
    expect(page.items.single.subtitle, contains('Legendado'));
    expect(page.nextCursor, '2');
  });

  test('sends Smart Animes filters and parses dynamic options', () async {
    var calls = 0;
    final source = SmartAnimesSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        calls++;
        if (calls == 1) {
          final values = request.url.queryParametersAll;
          expect(values['genre[]'], ['acao', 'aventura']);
          expect(values['studio[]'], ['mappa']);
          expect(values['season[]'], ['summer-2020']);
          expect(values['sub'], ['legendado']);
          expect(values['order'], ['titlereverse']);
          return _response(_catalogHtml);
        }
        return _response(_filterHtml);
      }),
    );

    await source.filter(
      AnimeSearchRequest(
        query: 'One Piece',
        genres: {'acao', 'aventura'},
        season: 'summer-2020',
        studio: 'mappa',
        language: 'legendado',
        sort: AnimeSearchSort.nameDescending,
      ),
    );
    final options = await source.getSearchOptions();

    expect(options.genres.single.label, 'Ação');
    expect(options.studios.single.value, 'mappa');
    expect(options.types.single.label, 'TV');
    expect(options.statuses.single.value, 'ongoing');
    expect(options.languages.single.value, 'legendado');
  });

  test('parses details and episodes in Portuguese', () async {
    final source = SmartAnimesSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _response(_detailsHtml)),
    );

    final details = await source.getDetails('gensou-suikoden');
    final episodes = await source.getEpisodes('gensou-suikoden');

    expect(details.item.title, 'Gensou Suikoden');
    expect(details.status, AnimeStatus.ongoing);
    expect(details.studios, ['Konami Animation']);
    expect(details.producers, ['NBCUniversal']);
    expect(details.genres, ['Ação']);
    expect(episodes.single.id, '116072');
    expect(episodes.single.number, 2);
    expect(episodes.single.releasedAt, DateTime(2026, 10, 13));
  });

  test('offers SEND qualities and Google Drive before playback starts',
      () async {
    final source = SmartAnimesSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async => _response(_episodeHtml)),
    );

    await expectLater(
      source.getPlayback(animeId: 'gensou-suikoden', episodeId: '116072'),
      throwsA(
        isA<AnimePlaybackResolutionRequired>().having(
          (error) => error.choices.map((choice) => choice.label),
          'choices',
          ['SEND · 1080p', 'SEND · 720p', 'Google Drive · 720p'],
        ),
      ),
    );
  });

  test('uses provider-specific referer for resolved playback', () async {
    final source =
        SmartAnimesSource(baseUri: Uri.parse('https://example.test/'));

    final send = await source.playbackFromResolvedUri(
      Uri.parse('https://cdn.example.test/video.mp4'),
      quality: '1080p',
      provider: 'SEND',
    );
    final drive = await source.playbackFromResolvedUri(
      Uri.parse('https://video.googlevideo.com/videoplayback'),
      quality: '720p',
      provider: 'Google Drive',
    );

    expect(send.streams.single.headers['Referer'], 'https://send.now/');
    expect(send.streams.single.quality, '1080p');
    expect(
        drive.streams.single.headers['Referer'], 'https://drive.google.com/');
  });

  test('reports Cloudflare browser session requirement', () async {
    final source = SmartAnimesSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
    );

    await expectLater(
      source.browse(),
      throwsA(
        isA<AnimeSourceSessionRequired>().having(
          (error) => error.message,
          'message',
          'Smart Animes requires browser verification to continue.',
        ),
      ),
    );
  });

  test('falls back to the browser engine after Cloudflare verification',
      () async {
    SharedPreferences.setMockInitialValues({
      'smart_animes_browser_cookies': jsonEncode({'cf_clearance': 'valid'}),
      'smart_animes_browser_user_agent': 'Verified WebView',
    });
    Uri? loadedUri;
    String? loadedUserAgent;
    final source = SmartAnimesSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
      browserHtmlLoader: (uri, userAgent) async {
        loadedUri = uri;
        loadedUserAgent = userAgent;
        return _catalogHtml;
      },
    );

    final page = await source.browse();

    expect(loadedUri, Uri.parse('https://example.test/anime/?order=update'));
    expect(loadedUserAgent, 'Verified WebView');
    expect(page.items.single.title, 'Gensou Suikoden');
  });
}

http.Response _response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

const _catalogHtml = '''
<article class="bs"><div class="bsx">
  <a href="/anime/gensou-suikoden/">
    <div class="limit"><div class="typez TV">TV</div>
      <div class="bt"><span class="epx">Em andamento</span><span class="sb Sub">Legendado</span></div>
      <img src="/cover.avif" title="Gensou Suikoden">
    </div>
    <div class="tt"><h2>Gensou Suikoden</h2></div>
  </a>
</div></article>
<a class="next" href="/anime/?page=2&amp;order=update">Próximo</a>
''';

const _filterHtml = '''
<label for="genre-action">Ação</label>
<input id="genre-action" name="genre[]" value="acao">
<label for="season-summer">Verão 2020</label>
<input id="season-summer" name="season[]" value="summer-2020">
<label for="studio-mappa">MAPPA</label>
<input id="studio-mappa" name="studio[]" value="mappa">
<select name="type"><option value="">Todos</option><option value="tv">TV</option></select>
<select name="status"><option value="ongoing">Em andamento</option></select>
<select name="sub"><option value="legendado">Legendado</option></select>
''';

const _detailsHtml = '''
<h1 class="entry-title">Gensou Suikoden</h1>
<div class="thumbook"><img src="/suikoden.avif"></div>
<div class="alter">Suikoden: The Anime, 幻想水滸伝</div>
<div class="spe">
 <span>Status: Em andamento</span>
 <span>Estúdio: <a href="/studio/konami">Konami Animation</a></span>
 <span>Tipo: TV</span>
 <span>Produtores: <a href="/producer/nbc">NBCUniversal</a></span>
</div>
<div class="genxed"><a href="/genres/acao/">Ação</a></div>
<div class="bixbox synp"><div class="entry-content">Uma grande aventura.</div></div>
<div class="eplister"><ul><li><a href="/116072/">
  <div class="epl-num">02</div><div class="epl-title">Gensou Suikoden 02</div>
  <div class="epl-date">13 out 2026</div>
</a></li></ul></div>
''';

const _episodeHtml = '''
<ul>
<li><span class="q"><b>SEND</b></span><span class="w">1080p</span>
<span class="e"><a href="/?token=send1080">Assistir ou Baixar</a></span></li>
<li><span class="q"><b>SEND</b></span><span class="w">720p</span>
<span class="e"><a href="/?token=send720">Assistir ou Baixar</a></span></li>
<li><span class="q"><b>Google Drive</b></span><span class="w">720p</span>
<span class="e"><a href="/?token=drive">Assistir ou Baixar</a></span></li>
</ul>
''';
