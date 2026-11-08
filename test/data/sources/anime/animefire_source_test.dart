import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/animefire_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  late AnimeFireSource source;

  setUp(() {
    source = AnimeFireSource(
      baseUri: Uri.parse('https://animefire.test/'),
      apiUri: Uri.parse('https://api.animefire.test/'),
      client: MockClient((request) async {
        if (request.url.host == 'media.test') {
          expect(request.headers['origin'], 'https://animefire.test');
          expect(request.headers['referer'], 'https://animefire.test/');
          return http.Response('#EXTM3U\n#EXT-X-ENDLIST\n', 200);
        }
        expect(request.url.queryParameters['v'], '3');
        expect(request.headers['origin'], 'https://animefire.test');
        expect(request.headers['referer'], 'https://animefire.test/');

        switch (request.url.path) {
          case '/home':
            return _json({
              'data': {
                'carousels': [
                  {
                    'key': 'new-episodes',
                    'items': [
                      {
                        'id': 'e1',
                        'titles': {'BR': 'Anime de exemplo'},
                        'audio': 'Legendado',
                        'season': 1,
                        'number': 3,
                        'poster_src': 'https://images.test/poster.jpg',
                      },
                    ],
                  },
                  {
                    'key': 'most-liked',
                    'items': [_catalogEntry()],
                  },
                  {
                    'key': 'new-animes-dubbed',
                    'items': [_catalogEntry(audio: 'Dublado & Legendado')],
                  },
                  {
                    'key': 'new-animes',
                    'items': [_catalogEntry()],
                  },
                ],
              },
            });
          case '/animes':
          case '/animes/filmes':
          case '/animes/pesquisar':
            if (request.url.path == '/animes/filmes') {
              expect(request.url.queryParameters['genre'], 'Ação');
              expect(request.url.queryParameters['audio'], 'dublado');
            }
            return _json({
              'data': [_catalogEntry()],
              'meta': {
                'current_page': 1,
                'last_page': 2,
                'genres': ['Ação', 'Comédia'],
              },
            });
          case '/animes/lancamentos':
            return _json({
              'data': {
                'animes': [
                  {
                    ..._catalogEntry(id: 'saturday'),
                    'next_air': {
                      'date': '2026-11-14',
                      'time': '13:15',
                    },
                  },
                  {
                    ..._catalogEntry(id: 'monday'),
                    'next_air': {
                      'date': '2026-11-09',
                      'time': '10:00',
                    },
                  },
                ],
                'upcoming': {
                  'items': [
                    {
                      ..._catalogEntry(id: 'future'),
                      'premieres_at': '2027-01-04',
                      'is_new_season': true,
                    },
                  ],
                },
              },
            });
          case '/anime/a1':
            return _json({
              'data': {
                'format': 'tv',
                'hero': {
                  ..._catalogEntry(),
                  'synopsis': 'Uma sinopse em português.',
                  'backdrop_src': 'https://images.test/backdrop.jpg',
                  'age_rating': '14',
                  'score': 8.5,
                  'genres': ['Ação', 'Aventura'],
                },
                'episodes': [
                  {
                    'id': 'e1',
                    'created_at': '2026-11-08T12:00:00Z',
                    'title': 'O começo',
                    'season': 1,
                    'number': 1,
                    'still_src': 'https://images.test/episode.jpg',
                  },
                ],
              },
            });
          case '/episode/e1':
            return _json({
              'data': {
                'id': 'e1',
                'anime': {
                  'id': 'a1',
                  'titles': {'BR': 'Anime de exemplo'},
                },
                'streams': [
                  {
                    'audio': 'dublado',
                    'is_offline': false,
                    'url': 'https://media.test/dub/h.jpg',
                    'qualities': ['720p', '1080p'],
                    'chapters': [
                      {'type': 'Intro', 'start': 10, 'end': 90},
                      {'type': 'Credits', 'start': 1300, 'end': 1380},
                      {'type': 'Chapter', 'start': 90, 'end': 1300},
                    ],
                  },
                  {
                    'audio': 'legendado',
                    'is_offline': false,
                    'url': 'https://media.test/sub/h.jpg',
                    'qualities': ['480p', '720p'],
                    'chapters': [
                      {'type': 'Intro', 'start': 10, 'end': 90},
                    ],
                  },
                  {
                    'audio': 'legendado',
                    'is_offline': true,
                    'url': 'https://media.test/offline/h.jpg',
                    'qualities': ['1080p'],
                  },
                ],
              },
            });
        }
        return http.Response('Not found: ${request.url}', 404);
      }),
    );
  });

  test('exposes the PT-BR non-adult catalog and its filters', () async {
    final options = await source.getSearchOptions();

    expect(source.id, 'animefire');
    expect(source.name, 'AnimeFire');
    expect(source.isRRated, isFalse);
    expect(source.languageLabel, 'Português (Brasil)');
    expect(source.catalogFilters, contains(AnimeCatalogFilter.movies));
    expect(source.catalogFilters, contains(AnimeCatalogFilter.upcoming));
    expect(options.genres.map((option) => option.value), ['Ação', 'Comédia']);
    expect(options.formats.map((option) => option.value), ['anime', 'movie']);
    expect(options.audioOptions.map((option) => option.value), [
      'legendado',
      'dublado',
    ]);
  });

  test('maps homepage sections and resolves episode cards to anime ids',
      () async {
    final latest = await source.browse(filter: AnimeCatalogFilter.recent);
    final popular = await source.browse(filter: AnimeCatalogFilter.popular);

    expect(latest.items.single.id, 'episode:e1');
    expect(latest.items.single.subtitle, 'T1 · EP.3 · Legendado');
    expect(popular.items.single.id, 'a1');

    final details = await source.getDetails(latest.items.single.id);
    expect(details.item.id, 'a1');
    expect(details.item.title, 'Anime de exemplo');
  });

  test('maps paginated anime and movie catalogs with genre and audio',
      () async {
    final catalog = await source.browse(filter: AnimeCatalogFilter.catalog);
    final movies = await source.filter(
      AnimeSearchRequest(
        genres: {'Ação'},
        formats: {'movie'},
        audio: 'dublado',
      ),
    );

    expect(catalog.items.single.title, 'Anime de exemplo');
    expect(catalog.nextCursor, '2');
    expect(movies.items.single.id, 'a1');
  });

  test('sorts releases by weekday and exposes announced premieres', () async {
    final releases = await source.browse(filter: AnimeCatalogFilter.airing);
    final upcoming = await source.browse(filter: AnimeCatalogFilter.upcoming);

    expect(releases.items.map((item) => item.id), ['monday', 'saturday']);
    expect(releases.items.first.subtitle, contains('Segunda-feira'));
    expect(upcoming.items.single.id, 'future');
    expect(upcoming.items.single.subtitle, contains('04/01/2027'));
    expect(upcoming.items.single.subtitle, contains('Nova temporada'));
  });

  test('maps details, episodes and signed jpg-shaped URLs as HLS', () async {
    final details = await source.getDetails('a1');
    final episodes = await source.getEpisodes('a1');
    final playback = await source.getPlayback(
      animeId: 'a1',
      episodeId: episodes.single.id,
    );

    expect(details.description, 'Uma sinopse em português.');
    expect(details.genres, ['Ação', 'Aventura']);
    expect(details.status, AnimeStatus.ongoing);
    expect(
        details.item.subtitle, 'Série · Dublado & Legendado · 8.5 ★ · 14 anos');
    expect(episodes.single.title, 'O começo');
    expect(playback.streams, hasLength(2));
    expect(playback.streams.first.protocol, VideoProtocol.hls);
    expect(playback.streams.first.mimeType, 'application/vnd.apple.mpegurl');
    expect(playback.streams.first.language, 'pt-BR');
    expect(playback.streams.last.language, 'ja');
    expect(playback.streams.first.uri.path, '/dub/h.jpg');
    expect(playback.streams.first.headers, {
      'Accept': '*/*',
      'Origin': 'https://animefire.test',
      'Referer': 'https://animefire.test/',
      'User-Agent': contains('Mozilla/5.0'),
    });
    expect(playback.skipSegments, hasLength(2));
    expect(playback.skipSegments.first.type, AnimeSkipType.intro);
    expect(playback.skipSegments.last.type, AnimeSkipType.outro);
  });

  test('reports the AnimeFire maintenance when an old stream is dead',
      () async {
    final unavailable = AnimeFireSource(
      baseUri: Uri.parse('https://animefire.test/'),
      apiUri: Uri.parse('https://api.animefire.test/'),
      client: MockClient((request) async {
        if (request.url.host == 'api.animefire.test') {
          return _json({
            'data': {
              'streams': [
                {
                  'audio': 'legendado',
                  'is_offline': false,
                  'url': 'https://media.test/old/h.jpg',
                  'qualities': ['720p'],
                },
              ],
            },
          });
        }
        return http.Response('Not found', 404);
      }),
    );

    await expectLater(
      unavailable.getPlayback(animeId: 'a1', episodeId: 'old'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('somente episódios novos'),
        ),
      ),
    );
  });
}

Map<String, dynamic> _catalogEntry({
  String id = 'a1',
  String audio = 'Dublado & Legendado',
}) =>
    {
      'id': id,
      'titles': {
        'BR': 'Anime de exemplo',
        'US': 'Example Anime',
        'JP': 'Rei',
      },
      'audio': audio,
      'poster_src': 'https://images.test/poster.jpg',
      'status': 'airing',
      'published_at': '2026-10-01',
      'last_episode_at': '2026-11-08',
      'most_liked': true,
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
