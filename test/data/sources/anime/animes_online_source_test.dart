import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/animes_online_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  late List<Uri> requests;
  late AnimesOnlineSource source;

  setUp(() {
    requests = [];
    source = AnimesOnlineSource(
      baseUri: Uri.parse('https://animesonline.test/'),
      client: MockClient((request) async {
        requests.add(request.url);
        switch (request.url.path) {
          case '/anime/':
            return _html(_catalogHtml);
          case '/lancamentos/':
            return _html(_scheduleHtml);
          case '/anime/sample/':
            return _html(_detailsHtml);
          case '/101/':
            return _html(_episodeHtml);
          case '/token/abc':
            return _html(_aniDriveHtml);
        }
        return http.Response('Not found', 404);
      }),
    );
  });

  test('exposes a non-adult PT-BR video source and weekday catalogs', () {
    expect(source.id, 'animes_online');
    expect(source.name, 'Animes Online');
    expect(source.isRRated, isFalse);
    expect(source.languageLabel, 'Português (Brasil)');
    expect(source.catalogFilters, contains(AnimeCatalogFilter.catalog));
    expect(source.catalogFilters, contains(AnimeCatalogFilter.scheduleSunday));
    expect(source.catalogFilters, contains(AnimeCatalogFilter.scheduleUnknown));
  });

  test('loads every catalog filter and source-specific sort label', () async {
    final options = await source.getSearchOptions();

    expect(options.genres.map((option) => option.value), ['action', 'comedy']);
    expect(
        options.languages.map((option) => option.value), ['sub', 'dub', 'raw']);
    expect(options.seasons.single.value, 'outono-2026');
    expect(options.studios.single.label, 'Studio Pierrot');
    expect(options.statuses.map((option) => option.value), [
      'ongoing',
      'completed',
      'upcoming',
      'incomplete',
      'hiatus',
    ]);
    expect(options.types.map((option) => option.value), ['tv', 'movie']);
    expect(
      options.sortLabelFor(AnimeSearchSort.defaultOrder, 'Default'),
      'A–Z',
    );
    expect(
      options.sortLabelFor(AnimeSearchSort.releaseDate, 'Release date'),
      'Último episódio publicado',
    );
  });

  test('maps catalog cards, pagination and repeated query filters', () async {
    final page = await source.filter(
      AnimeSearchRequest(
        query: 'black clover',
        genres: {'action', 'comedy'},
        language: 'dub',
        season: 'outono-2026',
        studio: 'studio-pierrot',
        status: 'ongoing',
        type: 'tv',
        sort: AnimeSearchSort.popularity,
      ),
      cursor: '2',
    );

    final uri = requests.single;
    expect(uri.queryParameters['keyword'], 'black clover');
    expect(
        uri.queryParametersAll['genre[]'], containsAll(['action', 'comedy']));
    expect(uri.queryParameters['sub'], 'dub');
    expect(uri.queryParametersAll['season[]'], ['outono-2026']);
    expect(uri.queryParametersAll['studio[]'], ['studio-pierrot']);
    expect(uri.queryParameters['status'], 'ongoing');
    expect(uri.queryParameters['type'], 'tv');
    expect(uri.queryParameters['order'], 'popular');
    expect(uri.queryParameters['page'], '2');
    expect(page.items.single.id, 'sample');
    expect(page.items.single.title, 'Anime Exemplo');
    expect(page.items.single.subtitle,
        'TV · 2026 · ★ 8,8 · Dublado · Em lançamento');
    expect(page.nextCursor, '3');
  });

  test('filters the releases page by weekday and includes undefined', () async {
    final all = await source.browse(filter: AnimeCatalogFilter.airing);
    final monday = await source.browse(
      filter: AnimeCatalogFilter.scheduleMonday,
    );
    final unknown = await source.browse(
      filter: AnimeCatalogFilter.scheduleUnknown,
    );

    expect(all.items.map((item) => item.id), ['monday-show', 'unknown-show']);
    expect(monday.items.single.title, 'Anime de Segunda');
    expect(monday.items.single.subtitle, 'EP 03 · às 10:30');
    expect(unknown.items.single.id, 'unknown-show');
  });

  test('maps details and orders episodes from oldest to newest', () async {
    final details = await source.getDetails('sample');
    final episodes = await source.getEpisodes('sample');

    expect(details.item.title, 'Anime Exemplo');
    expect(details.item.subtitle, 'TV · Dublado · Em lançamento · ★ 8.8');
    expect(details.description, 'Uma sinopse em português.');
    expect(details.alternativeTitles, ['Example Anime']);
    expect(details.genres, ['Ação', 'Fantasia']);
    expect(details.status, AnimeStatus.ongoing);
    expect(details.studios, ['Studio Pierrot']);
    expect(details.producers, ['Produtora A']);
    expect(episodes.map((episode) => episode.id), ['100', '101']);
    expect(episodes.first.number, 1);
  });

  test('decodes the AniDrive player config and returns its HLS URL', () async {
    final playback = await source.getPlayback(
      animeId: 'sample',
      episodeId: '101',
    );

    expect(
      playback.streams.single.uri,
      Uri.parse('https://media.test/master.m3u8?token=ok'),
    );
    final stream = playback.streams.single;
    expect(stream.protocol, VideoProtocol.hls);
    expect(stream.mimeType, 'application/vnd.apple.mpegurl');
    expect(stream.headers['Origin'], 'https://anidrive.test');
    expect(stream.headers['Referer'], 'https://anidrive.test/token/abc?prime');
    expect(requests.last.host, 'anidrive.test');
  });
}

http.Response _html(String body) => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

const _catalogHtml = r'''
<html><body>
<form action="/anime/" class="catalog-filters">
  <label><input name="genre[]" value="action"> Ação</label>
  <label><input name="genre[]" value="comedy"> Comédia</label>
  <select name="sub">
    <option value="">Todos</option><option value="sub">Legendado</option>
    <option value="dub">Dublado</option><option value="raw">RAW</option>
  </select>
  <select name="status">
    <option value="">Todos</option><option value="ongoing">Lançamento</option>
    <option value="completed">Completo</option><option value="upcoming">Em Breve</option>
    <option value="incomplete">Incompleto</option><option value="hiatus">Hiato</option>
  </select>
  <select name="type">
    <option value="">Todos</option><option value="tv">Série de TV</option>
    <option value="movie">Filme</option>
  </select>
  <label><input name="season[]" value="outono-2026"> Outono 2026</label>
  <label><input name="studio[]" value="studio-pierrot"> Studio Pierrot</label>
</form>
<div id="catalog-results">
  <article class="catalog-card"><a href="/anime/sample/" title="Anime Exemplo">
    <div class="catalog-poster"><img src="https://images.test/sample.jpg"></div>
    <div class="catalog-card-info"><h2>Anime Exemplo</h2>
      <p class="catalog-card-meta">TV · 2026 · ★ 8,8</p>
      <div class="catalog-card-labels"><span>Dublado</span><span>Em lançamento</span></div>
    </div>
  </a></article>
</div>
<nav class="catalog-page-directions"><a rel="next" href="/anime/?page=3#catalog-results">Próxima</a></nav>
</body></html>
''';

const _scheduleHtml = r'''
<html><body>
<div class="schedulepage sch_monday"><div class="listupd">
  <div class="bs"><div class="bsx"><a href="/anime/monday-show/" title="Anime de Segunda">
    <div class="bt"><span class="epx">às 10:30</span><span class="sb">03</span></div>
    <img data-src="https://images.test/monday.jpg"><div class="tt">Anime de Segunda</div>
  </a></div></div>
</div></div>
<div class="schedulepage sch_unknown"><div class="listupd">
  <div class="bs"><div class="bsx"><a href="/anime/unknown-show/" title="Anime Indefinido">
    <span class="sb">01</span><img data-src="https://images.test/unknown.jpg">
  </a></div></div>
</div></div>
</body></html>
''';

const _detailsHtml = r'''
<html><body>
<div class="clean-anime-ficha">
  <div class="clean-anime-poster"><img src="https://images.test/poster.jpg"></div>
  <div class="clean-anime-status"><span class="clean-anime-status-label">Em lançamento</span>
    <span class="clean-anime-format">TV · Dublado</span></div>
  <h1 class="entry-title">Anime Exemplo</h1>
  <div class="clean-anime-alternative"><span>Títulos alternativos</span>Example Anime</div>
  <div class="clean-anime-rating"><strong>8.8</strong></div>
  <div class="clean-anime-genres"><a>Ação</a><a>Fantasia</a></div>
  <dl class="clean-anime-facts"><div><dt>Estúdio</dt><dd><a href="/studio/studio-pierrot/">Studio Pierrot</a></dd></div></dl>
  <details class="clean-anime-details"><dl><div><dt>Produtores</dt><dd><a href="/producer/a/">Produtora A</a></dd></div></dl></details>
</div>
<div id="clean-anime-synopsis-content"><p>Uma sinopse em português.</p></div>
<div class="eplister"><ul>
  <li data-episode-id="101"><a data-episode-label="02"><div class="epl-num">02</div><div class="epl-title">Anime Exemplo 02</div></a></li>
  <li data-episode-id="100"><a data-episode-label="01"><div class="epl-num">01</div><div class="epl-title">Anime Exemplo 01</div></a></li>
</ul></div>
</body></html>
''';

const _episodeHtml = r'''
<html><body><div class="player-embed">
  <iframe src="https://anidrive.test/token/abc?prime" title="Player de video"></iframe>
</div></body></html>
''';

final String _aniDriveHtml = (() {
  const script =
      'window.AniDrivePlayerConfig={"sources":[{"file":"https://media.test/master.m3u8?token=ok","label":"HLS","type":"hls"}]};';
  const key = 'test-key';
  final keyBytes = utf8.encode(key);
  final cipher = List<int>.generate(
    utf8.encode(script).length,
    (index) => utf8.encode(script)[index] ^ keyBytes[index % keyBytes.length],
    growable: false,
  );
  final encoded = base64Encode(cipher);
  final split = encoded.length ~/ 2;
  final chunks = [encoded.substring(split), encoded.substring(0, split)];
  return '''
<html><body><script>(function(){function _decode(a,i,k){
var c=atob(i.map(function(n){return a[n]}).join("")),key=atob(k);
}(0,Function)("")}_decode(${jsonEncode(chunks)},[1,0],"${base64Encode(keyBytes)}"))</script></body></html>
''';
})();
