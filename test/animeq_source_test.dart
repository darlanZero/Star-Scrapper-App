import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/animeq_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('exposes AnimeQ as a mixed PT-BR source with dedicated catalogs', () {
    final source = AnimeQSource(baseUri: Uri.parse('https://example.test/'));

    expect(source.languageLabel, 'Português (Brasil)');
    expect(source.isRRated, isFalse);
    expect(
        source.catalogFilters,
        containsAll([
          AnimeCatalogFilter.recent,
          AnimeCatalogFilter.featured,
          AnimeCatalogFilter.catalog,
          AnimeCatalogFilter.subtitled,
          AnimeCatalogFilter.dubbed,
          AnimeCatalogFilter.movies,
          AnimeCatalogFilter.adult,
        ]));
  });

  test('keeps featured titles separate from the complete catalog', () async {
    final requested = <Uri>[];
    final source = AnimeQSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _response(_catalogHtml);
      }),
    );

    final featured = await source.browse(filter: AnimeCatalogFilter.featured);
    final catalog = await source.browse(filter: AnimeCatalogFilter.catalog);
    final page2 = await source.browse(
      filter: AnimeCatalogFilter.catalog,
      cursor: catalog.nextCursor,
    );

    expect(featured.items.single.id, 'featured-title');
    expect(catalog.items.single.id, 'catalog-title');
    expect(catalog.items.single.subtitle, '24/10/26 · ★ 8.8');
    expect(catalog.nextCursor, '2');
    expect(page2.items.single.id, 'catalog-title');
    expect(requested.last.path, '/anime/page/2/');
  });

  test('maps all dedicated routes and parses latest episode releases',
      () async {
    final requested = <Uri>[];
    final source = AnimeQSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _response(
          request.url.path.startsWith('/episodio') ? _latestHtml : _catalogHtml,
        );
      }),
    );

    final latest = await source.browse();
    for (final filter in [
      AnimeCatalogFilter.subtitled,
      AnimeCatalogFilter.dubbed,
      AnimeCatalogFilter.manhwa,
      AnimeCatalogFilter.donghua,
      AnimeCatalogFilter.movies,
      AnimeCatalogFilter.subtitledMovies,
      AnimeCatalogFilter.dubbedMovies,
      AnimeCatalogFilter.adult,
    ]) {
      await source.browse(filter: filter);
    }

    expect(latest.items.single.id, 'episode:kyoufu-collector-episodio-03');
    expect(latest.items.single.title, 'Kyoufu Collector');
    expect(latest.items.single.subtitle,
        'Episódio 03 - O Garoto Sem Rosto · SD / HD / FHD · 24/10/26');
    expect(
      requested.map((uri) => uri.path),
      containsAll([
        '/tipo/legendado/',
        '/tipo/dublado/',
        '/genre/Manhwa/',
        '/genre/Donghua/',
        '/filme/',
        '/genre/Filme-Legendado/',
        '/genre/Filme-Dublado/',
        '/genre/hentai/',
      ]),
    );
  });

  test(
      'parses taxonomy archives without archive-content and retries a cut stream',
      () async {
    var attempts = 0;
    final source = AnimeQSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        attempts++;
        if (attempts < 3) {
          throw http.ClientException('stream could not be completed');
        }
        return _response(_taxonomyHtml);
      }),
    );

    final page = await source.browse(filter: AnimeCatalogFilter.adult);

    expect(attempts, 3);
    expect(page.items.single.id, 'adult-title');
    expect(page.items.single.title, 'Adult Title');
  });

  test('uses the catalog form for search and structured filters', () async {
    final requested = <Uri>[];
    final source = AnimeQSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _response(_catalogHtml);
      }),
    );

    final options = await source.getSearchOptions();
    await source.search('Kyoufu Collector');
    await source.filter(AnimeSearchRequest(
      genres: {'terror'},
      year: '2026',
      sort: AnimeSearchSort.score,
    ));

    expect(options.genres.single.label, 'Terror');
    expect(options.years.single.value, '2026');
    expect(requested[1].queryParameters['catalog_search'], 'Kyoufu Collector');
    expect(requested.last.queryParameters, {
      'catalog_genre': 'terror',
      'catalog_year': '2026',
      'catalog_order': 'rating',
    });
  });

  test('resolves a latest release into details, episodes and native MP4s',
      () async {
    final source = AnimeQSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/episodio/kyoufu-collector-episodio-03/') {
          return _response(_episodeHtml);
        }
        if (request.url.path == '/anime/kyoufu-collector/') {
          return _response(_detailsHtml);
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final details =
        await source.getDetails('episode:kyoufu-collector-episodio-03');
    final episodes =
        await source.getEpisodes('episode:kyoufu-collector-episodio-03');
    final playback = await source.getPlayback(
      animeId: 'kyoufu-collector',
      episodeId: 'kyoufu-collector-episodio-03',
    );

    expect(details.item.id, 'kyoufu-collector');
    expect(details.item.title, 'Kyoufu Collector');
    expect(details.item.subtitle, contains('12 episódios'));
    expect(details.alternativeTitles, ['Horror Collector']);
    expect(details.genres, ['Mistério', 'Terror']);
    expect(details.bannerUri.toString(), 'https://cdn.test/banner.jpg');
    expect(episodes, hasLength(2));
    expect(episodes.last.number, 3);
    expect(episodes.last.season, 1);
    expect(playback.streams, hasLength(2));
    expect(playback.streams.first.quality, 'SD');
    expect(playback.streams.last.quality, 'FHD');
    expect(playback.streams.last.protocol, VideoProtocol.progressive);
    expect(playback.streams.first.headers['Referer'],
        'https://example.test/episodio/kyoufu-collector-episodio-03/');
  });

  test('accepts extensionless Blogger GoogleVideo URLs from the WebView',
      () async {
    final source = AnimeQSource(baseUri: Uri.parse('https://example.test/'));
    final uri = Uri.parse(
      'https://rr1---sn-test.googlevideo.com/videoplayback'
      '?itag=22&mime=video%2Fmp4&expire=9999999999',
    );

    final playback = await source.playbackFromResolvedUri(
      uri,
      quality: 'HD',
      provider: 'Blogger',
    );

    expect(playback.streams.single.uri, uri);
    expect(playback.streams.single.protocol, VideoProtocol.progressive);
    expect(playback.streams.single.mimeType, 'video/mp4');
    expect(
        playback.streams.single.headers['Referer'], 'https://www.blogger.com/');
  });

  test('parses movie cards and resolves their AJAX player natively', () async {
    final source = AnimeQSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/filme/') return _response(_movieCatalogHtml);
        if (request.url.path == '/filme/grave-fireflies/') {
          return _response(_movieDetailsHtml);
        }
        if (request.url.path == '/wp-admin/admin-ajax.php') {
          expect(request.method, 'POST');
          expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
          expect(request.bodyFields, containsPair('action', 'doo_player_ajax'));
          expect(request.bodyFields, containsPair('post', '34845'));
          return _response(jsonEncode({
            'embed_url':
                'https://example.test/jwplayer?source=https%3A%2F%2Fvideo.test%2Fgrave.mp4',
            'type': 'mp4',
          }));
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final catalog = await source.browse(filter: AnimeCatalogFilter.movies);
    final details = await source.getDetails(catalog.items.single.id);
    final episodes = await source.getEpisodes(catalog.items.single.id);
    final playback = await source.getPlayback(
      animeId: details.item.id,
      episodeId: episodes.single.id,
    );

    expect(catalog.items.single.id, 'movie:grave-fireflies');
    expect(details.item.title, 'Grave of the Fireflies');
    expect(details.description, 'Two siblings try to survive the war.');
    expect(details.genres, ['Drama']);
    expect(episodes.single.title, 'Filme');
    expect(
        playback.streams.single.uri.toString(), 'https://video.test/grave.mp4');
    expect(playback.streams.single.quality, 'FHD');
  });
}

http.Response _response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

const _catalogHtml = '''
<div class="items featured"><article class="item tvshows">
  <div class="poster"><img src="/featured.jpg"><div class="rating">9.9</div></div>
  <div class="data"><h3><a href="/anime/featured-title">Featured Title</a></h3></div>
</article></div>
<select name="catalog_genre"><option value="">Todos</option><option value="terror">Terror</option></select>
<select name="catalog_year"><option value="">Todos</option><option value="2026">2026</option></select>
<div id="archive-content"><article class="item tvshows">
  <div class="poster"><img src="/catalog.jpg"><div class="rating">8.8</div>
    <span class="post-date-badge">24/10/26</span></div>
  <div class="data"><h3><a href="/anime/catalog-title">Catalog Title</a></h3></div>
</article></div>
<div class="pagination"><a href="/anime/page/2/">2</a></div>
''';

const _latestHtml = '''
<div id="archive-content"><article class="item se episodes">
  <div class="poster"><img src="/episode.jpg"><span class="quality">SD / HD / FHD</span>
    <span class="post-date-badge">24/10/26</span>
    <a href="/episodio/kyoufu-collector-episodio-03">Play</a></div>
  <div class="data"><h3>Episódio 03 - O Garoto Sem Rosto</h3>
    <span class="serie">Kyoufu Collector</span></div>
</article></div>
''';

const _detailsHtml = '''
<div class="sheader animeq-single-cinematic has-backdrop"
 style="--aq-single-backdrop:url('https://cdn.test/banner.jpg')">
  <div class="poster"><img src="/poster.webp"></div><div class="data">
    <div class="animeq-single-overline">Horror Collector</div>
    <h1>Kyoufu Collector</h1>
    <div class="animeq-single-meta-pills"><span>2026</span><span>1 temporada</span><span>12 episódios</span></div>
    <div class="animeq-score-box"><strong>8.1</strong></div>
    <div class="sgeneros"><a href="/genre/misterio">Mistério</a><a href="/genre/terror">Terror</a><a href="/tipo/legendado">Legendado</a></div>
    <div class="animeq-single-overview">Uma coleção de histórias assustadoras.</div>
  </div>
</div>
<div id="seasons"><div class="se-c"><span class="se-t">1</span><div class="episodios-grid">
  <div class="episode-card" data-episode-number="1"><h3 class="episode-title"><a href="/episodio/kyoufu-collector-episodio-01">Episódio 01</a></h3><img src="/1.jpg"></div>
  <div class="episode-card" data-episode-number="3"><h3 class="episode-title"><a href="/episodio/kyoufu-collector-episodio-03">Episódio 03</a></h3><img src="/3.jpg"></div>
</div></div></div>
''';

const _episodeHtml = '''
<a href="/anime/kyoufu-collector">Todos os episódios</a>
<div class="animeq-player__source" data-animeq-source="0"><video><source src="https://video.test/03-sd.mp4" type="video/mp4"></video></div>
<div class="animeq-player__source" data-animeq-source="1"><iframe src="https://blogger.test/video"></iframe></div>
<div class="animeq-player__source" data-animeq-source="2"><video><source src="https://video.test/03-fhd.mp4" type="video/mp4"></video></div>
<button data-animeq-switch="0" data-source-name="SD">SD</button>
<button data-animeq-switch="1" data-source-name="HD">HD</button>
<button data-animeq-switch="2" data-source-name="FHD">FHD</button>
''';

const _taxonomyHtml = '''
<div class="items full"><article class="item tvshows">
  <div class="poster"><img src="/adult.jpg"><div class="rating">7</div></div>
  <div class="data"><h3><a href="/anime/adult-title">Adult Title</a></h3></div>
</article></div>
''';

const _movieCatalogHtml = '''
<div id="archive-content" class="items full"><article class="item movies">
  <div class="poster"><img src="/grave.jpg"><div class="rating">8.5</div></div>
  <div class="data"><h3><a href="/filme/grave-fireflies">Grave of the Fireflies</a></h3></div>
</article></div>
''';

const _movieDetailsHtml = '''
<div class="dooplay_player"><div id="playeroptions"><ul>
  <li class="dooplay_player_option" data-type="movie" data-post="34845" data-nume="1">
    <span class="title">FHD</span>
  </li>
</ul></div></div>
<div class="sheader"><div class="poster"><img src="/grave.jpg"></div><div class="data">
  <h1>Grave of the Fireflies</h1>
  <div class="extra"><span>1988</span><span>88 Min.</span></div>
  <div class="sgeneros"><a href="/genre/drama">Drama</a></div>
</div></div>
<div class="wp-content"><p>Two siblings try to survive the war.</p></div>
''';
