import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/aniwave_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  late AniwaveSource source;

  setUp(() {
    source = AniwaveSource(
      baseUri: Uri.parse('https://aniwave.test/'),
      playerUri: Uri.parse('https://megaplay.test/'),
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/latest-updated' || path == '/most-viewed') {
          return _html('''
            <div id="list-items" class="ani items">
              <div class="item"><div class="inner">
                <div class="ani poster"><a href="/watch/example-anime-ab123/ep-2">
                  <img src="https://images.test/cover.jpg" alt="Example Anime">
                </a></div>
                <div class="info">
                  <a class="name" href="/watch/example-anime-ab123/ep-2">Example Anime</a>
                  <div class="meta"><div class="m-item">2 Sub</div><div class="m-item">TV</div></div>
                </div>
              </div></div>
            </div>
            <a href="/latest-updated?page=2">2</a>
          ''');
        }
        if (path == '/filter') {
          if (request.url.queryParameters.isNotEmpty) {
            expect(request.url.queryParameters['keyword'], 'Example');
            expect(request.url.queryParametersAll['genre[]'], ['1']);
          }
          return _html('''
            <form>
              <input id="genre-action" name="genre[]" value="1"><label for="genre-action">Action</label>
              <input id="season-summer" name="season[]" value="summer"><label for="season-summer">Summer</label>
              <input id="year-2020" name="year[]" value="2020"><label for="year-2020">2020</label>
              <input id="type-tv" name="term_type[]" value="TV"><label for="type-tv">TV</label>
              <input id="status-airing" name="status[]" value="currently-airing"><label for="status-airing">Currently Airing</label>
              <input id="language-sub" name="language[]" value="sub"><label for="language-sub">Sub</label>
              <input id="rating-pg" name="rating[]" value="PG"><label for="rating-pg">PG</label>
            </form>
            <div id="list-items"></div>
          ''');
        }
        if (path == '/watch/example-anime-ab123') {
          return _html('''
            <div id="watch-main" data-id="42"></div>
            <div id="player" style="background-image: url('https://images.test/banner.jpg')"></div>
            <div id="w-info">
              <div class="poster"><img src="https://images.test/cover.jpg"></div>
              <h1 class="title">Example Anime</h1>
              <div class="names">Example; Sample</div>
              <div class="synopsis"><div class="content">Example synopsis.</div></div>
              <div class="bmeta">
                <div class="meta">
                  <div>Type: <span>TV</span></div>
                  <div>Status: <span>Currently Airing</span></div>
                  <div>Genres: <span><a href="/genre/action">Action</a></span></div>
                </div>
                <div class="meta">
                  <div>Studios: <span>Example Studio</span></div>
                  <div>Producers: <span>Example Producer</span></div>
                </div>
              </div>
            </div>
          ''');
        }
        if (path == '/ajax/episode/list/42') {
          return _json({
            'status': 200,
            'result':
                '''<div class="episodes"><ul><li title="Pilot"><a data-num="1" data-slug="1" data-mal="123" data-ids="server-token">1</a></li></ul></div>''',
          });
        }
        if (path == '/ajax/server/list') {
          expect(request.url.queryParameters['servers'], 'server-token');
          return _json({
            'status': 200,
            'result':
                '''<div class="servers"><div class="type" data-type="sub"><li data-link-id="link-token">HD-1</li></div></div>''',
          });
        }
        if (path == '/ajax/server') {
          expect(request.url.queryParameters['get'], 'link-token');
          return _json({
            'status': 200,
            'result': {
              'url': 'https://gogo.test/streaming.php?id=example',
              'skip_data': {
                'intro': [5, 90],
              },
            },
          });
        }
        if (request.url.host == 'gogo.test') {
          return _html(
            '<iframe src="https://megaplay.test/stream/s-2/777/sub"></iframe>',
          );
        }
        if (request.url.host == 'megaplay.test' &&
            path == '/stream/s-2/777/sub') {
          return _html('<div data-id="777"></div>');
        }
        if (request.url.host == 'megaplay.test' &&
            path == '/stream/getSourcesNew') {
          return _json({
            'sources': [
              {'file': 'https://media.test/master.m3u8', 'label': 'Auto'},
            ],
            'tracks': [
              {
                'file': 'https://media.test/sub_por.vtt',
                'label': 'Portuguese',
                'kind': 'captions',
              },
            ],
          });
        }
        return http.Response('Not found: ${request.url}', 404);
      }),
    );
  });

  test('maps catalog pages and source-specific categories', () async {
    final updated = await source.browse(filter: AnimeCatalogFilter.updated);
    final popular = await source.browse(filter: AnimeCatalogFilter.popular);

    expect(source.catalogFilters, contains(AnimeCatalogFilter.airing));
    expect(updated.items.single.id, 'example-anime-ab123');
    expect(updated.items.single.title, 'Example Anime');
    expect(updated.items.single.subtitle, contains('Sub'));
    expect(updated.nextCursor, '2');
    expect(popular.items.single.coverUri.toString(), contains('cover.jpg'));
  });

  test('loads dynamic filter options and sends selected filters', () async {
    final options = await source.getSearchOptions();
    final page = await source.filter(
      AnimeSearchRequest(query: 'Example', genres: {'1'}),
    );

    expect(options.genres.single.label, 'Action');
    expect(options.seasons.single.value, 'summer');
    expect(options.years.single.value, '2020');
    expect(page.items, isEmpty);
  });

  test('maps details, episodes and resolves MegaPlay playback', () async {
    final details = await source.getDetails('example-anime-ab123');
    final episodes = await source.getEpisodes(details.item.id);
    final playback = await source.getPlayback(
      animeId: details.item.id,
      episodeId: episodes.single.id,
    );

    expect(details.externalIds['mal'], '123');
    expect(details.studios, ['Example Studio']);
    expect(details.producers, ['Example Producer']);
    expect(details.genres, ['Action']);
    expect(episodes.single.title, 'Pilot');
    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(playback.subtitles.single.language, 'pt-BR');
    expect(playback.skipSegments.single.start, const Duration(seconds: 5));
  });
}

http.Response _html(String body) => http.Response(body, 200, headers: {
      'content-type': 'text/html; charset=utf-8',
    });

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
