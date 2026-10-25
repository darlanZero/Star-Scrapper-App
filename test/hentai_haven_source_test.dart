import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/hentai_haven_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('exposes separate episode and series catalog sorts', () async {
    final requested = <Uri>[];
    final source = HentaiHavenSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _response(
          request.url.path == '/series/'
              ? _seriesCatalogHtml
              : _episodeCatalogHtml,
        );
      }),
    );

    final newestEpisodes = await source.browse();
    final popularEpisodes =
        await source.browse(filter: AnimeCatalogFilter.popular);
    final viewedEpisodes =
        await source.browse(filter: AnimeCatalogFilter.episodeMostViewed);
    final newestSeries =
        await source.browse(filter: AnimeCatalogFilter.seriesNewest);
    final popularSeries =
        await source.browse(filter: AnimeCatalogFilter.seriesPopular);
    final viewedSeries =
        await source.browse(filter: AnimeCatalogFilter.seriesMostViewed);

    expect(newestEpisodes.items, hasLength(2));
    expect(newestEpisodes.items.first.id, 'episode:example-title-episode-2');
    expect(newestEpisodes.items.first.title, 'Example Title');
    expect(newestEpisodes.items.first.subtitle, 'EP 2 · 16.1K views');
    expect(newestEpisodes.items.last.id, 'episode:streamed-title-episode-1');
    expect(newestEpisodes.items.last.title, 'Streamed Title');
    expect(newestEpisodes.nextCursor, '2');
    expect(popularEpisodes.items, isNotEmpty);
    expect(viewedEpisodes.items, isNotEmpty);
    expect(newestSeries.items.single.id, 'example-title');
    expect(popularSeries.items, isNotEmpty);
    expect(viewedSeries.items, isNotEmpty);
    expect(requested[0].path, '/');
    expect(requested[1].queryParameters['sort'], 'popular');
    expect(requested[2].queryParameters['sort'], 'viewed');
    expect(requested[3].path, '/series/');
    expect(requested[4].queryParameters['sort'], 'popular');
    expect(requested[5].queryParameters['sort'], 'viewed');
    expect(source.isRRated, isTrue);
    expect(source.capabilityLabel, startsWith('R-rated'));
  });

  test('searches works and filters them by genre and year', () async {
    final requested = <Uri>[];
    final source = HentaiHavenSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/genres/') return _response(_genresHtml);
        return _response(request.url.path == '/series/'
            ? _seriesCatalogHtml
            : _episodeCatalogHtml);
      }),
    );

    final search = await source.search('Example Title');
    final options = await source.getSearchOptions();
    await source.filter(
      AnimeSearchRequest(
        genres: {'vanilla'},
        year: '2026',
        sort: AnimeSearchSort.mostViewed,
      ),
    );

    expect(search.items.single.title, 'Example Title');
    expect(requested.first.path, '/series/');
    expect(requested.first.queryParameters['q'], 'Example Title');
    expect(options.genres.single.value, 'vanilla');
    expect(options.years.first.value, '2026');
    expect(requested.last.path, '/');
    expect(requested.last.queryParameters, {
      'genre': 'vanilla',
      'year': '2026',
      'sort': 'viewed',
    });
  });

  test('resolves an episode release to series details and episodes', () async {
    final source = HentaiHavenSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/example-title-episode-2/') {
          return _response(_episodeDetailsHtml);
        }
        if (request.url.path == '/series/example-title/') {
          return _response(_seriesDetailsHtml);
        }
        if (request.url.path == '/example-title-episode-1/') {
          return _response(_firstEpisodeDetailsHtml);
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final details = await source.getDetails('episode:example-title-episode-2');
    final episodes =
        await source.getEpisodes('episode:example-title-episode-2');

    expect(details.item.id, 'example-title');
    expect(details.item.title, 'Example Title');
    expect(details.item.coverUri.toString(), 'https://example.test/poster.jpg');
    expect(details.description, 'A useful episode description.');
    expect(details.genres, ['Vanilla', 'Uncensored']);
    expect(details.item.subtitle, contains('2 episodes'));
    expect(episodes, hasLength(2));
    expect(episodes.first.id, 'example-title-episode-1');
    expect(episodes.first.number, 1);
    expect(episodes.last.number, 2);
  });

  test('hands NHPlayer verification to WebView and keeps its subtitle',
      () async {
    final subtitle = base64.encode(
      utf8.encode('https://cdn.example.test/subtitles/example.srt'),
    );
    final source = HentaiHavenSource(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/example-title-episode-1/') {
          return _response('''
            <div class="player-stage">
              <iframe src="https://nhplayer.test/v/abc/"></iframe>
            </div>
          ''');
        }
        if (request.url.host == 'nhplayer.test') {
          return _response('''
            <div class="servers"><li
              data-id="/player.php?vid=signed&amp;s=$subtitle">Main</li></div>
          ''');
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    AnimePlaybackResolutionRequired? resolution;
    try {
      await source.getPlayback(
        animeId: 'example-title',
        episodeId: 'example-title-episode-1',
      );
    } on AnimePlaybackResolutionRequired catch (error) {
      resolution = error;
    }

    expect(resolution, isNotNull);
    expect(resolution!.provider, 'NHPlayer');
    expect(resolution.entryUri.host, 'nhplayer.test');
    expect(resolution.entryUri.path, '/v/abc/');

    final playback = await source.playbackFromResolvedUri(
      Uri.parse('https://r2.example.test/example.mp4?token=valid'),
      provider: 'NHPlayer',
    );
    expect(playback.streams.single.protocol, VideoProtocol.progressive);
    expect(playback.streams.single.headers['Referer'], 'https://nhplayer.com/');
    expect(playback.subtitles.single.language, 'en');
    expect(
      playback.subtitles.single.uri.toString(),
      'https://cdn.example.test/subtitles/example.srt',
    );
  });
}

http.Response _response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

const _episodeCatalogHtml = '''
<div class="post-grid">
  <article class="post-card">
    <div class="card-art"><a href="/example-title-episode-2/">
      <img src="/episode-2.jpg"></a><span class="episode-label">EP 2</span>
    </div>
    <div class="card-copy"><h3><a href="/example-title-episode-2/">
      Example Title Episode 2</a></h3><p class="card-meta">16.1K views</p></div>
  </article>
  <article class="post-card"><div class="card-art">
    <a aria-label="Streamed Title Episode 1" href="/streamed-title-episode-1/">
      <img src="/streamed.jpg"><template id="pending"></template>
    </a>
  </div><template id="pending-copy"></template></article>
</div>
<a aria-label="Next page" href="/?page=2">Next</a>
''';

const _seriesCatalogHtml = '''
<div class="chip-row-years"><a href="/series/?year=2026">2026</a></div>
<div class="post-grid">
  <article class="post-card">
    <div class="card-art"><a href="/series/example-title/">
      <img src="/poster.jpg"></a></div>
    <div class="card-copy"><h3><a href="/series/example-title/">
      Example Title</a></h3><p class="card-meta">2.8K views</p></div>
  </article>
</div>
''';

const _genresHtml = '''
<a class="genre-card" href="/genre/vanilla/">
  <h2>Vanilla</h2><span>101 episodes</span>
</a>
''';

const _episodeDetailsHtml = '''
<p class="watch-series"><a href="/series/example-title/">Example Title</a></p>
''';

const _seriesDetailsHtml = '''
<header class="detail-heading"><h1>Example Title</h1>
  <div class="detail-meta"><span>Oct 9, 2026</span><span>2.8K views</span></div>
</header>
<section class="detail-info"><img class="series-poster" src="/poster.jpg">
  <div class="detail-description"><div class="prose">
    <p>No description was provided for this title.</p>
  </div><div class="genre-tags"></div></div>
</section>
<section class="related-section"><div class="post-grid">
  <article class="post-card"><div class="card-art">
    <a href="/example-title-episode-1/"><img src="/ep1.jpg"></a>
    <span class="episode-label">EP 1</span></div>
    <div class="card-copy"><h3><a href="/example-title-episode-1/">
      Example Title Episode 1</a></h3></div></article>
  <article class="post-card"><div class="card-art">
    <a href="/example-title-episode-2/"><img src="/ep2.jpg"></a>
    <span class="episode-label">EP 2</span></div>
    <div class="card-copy"><h3><a href="/example-title-episode-2/">
      Example Title Episode 2</a></h3></div></article>
</div></section>
''';

const _firstEpisodeDetailsHtml = '''
<div class="watch-main"><div class="detail-description">
  <div class="prose">A useful episode description.</div>
  <div class="genre-tags">
    <a href="/genre/vanilla/">Vanilla</a>
    <a href="/genre/uncensored/">Uncensored</a>
    <a href="/release/2026/">2026</a>
  </div>
</div></div>
''';
