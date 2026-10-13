import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/trackers/anilist_tracker_service.dart';
import 'package:star_scrapper_app/data/trackers/mal_tracker_service.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';

void main() {
  test('AniList home maps carousels and release calendar', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      final media = _aniListMedia();
      return http.Response(
        jsonEncode({
          'data': {
            'popular': {
              'media': [media],
            },
            'trending': {'media': []},
            'recent': {'media': []},
            'highestRated': {'media': []},
            'thisSeason': {'media': []},
            'upcomingSeason': {'media': []},
            'action': {'media': []},
            'romance': {'media': []},
            'fantasy': {'media': []},
            'comedy': {'media': []},
            'schedule': {
              'airingSchedules': [
                {'airingAt': 1791763200, 'episode': 3, 'media': media},
              ],
            },
          },
        }),
        200,
      );
    });
    final service = AniListTrackerService(client: client);

    final home = await service.loadHome(
      type: TrackedMediaType.anime,
      includeAdult: false,
      now: DateTime.utc(2026, 10, 12),
    );

    expect(home.sections.single.title, 'Popular');
    expect(home.sections.single.items.single.title.searchTerms,
        containsAll(['Example', 'Example Romaji', 'Example Native', 'Alias']));
    expect(home.schedule.single.releaseNumber, 3);
    expect(requestBody['query'], contains('isAdult: false'));
  });

  test('AniList search sends tags, type and selected ordering', () async {
    late Map<String, dynamic> variables;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      variables = body['variables'] as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'Page': {
              'pageInfo': {'hasNextPage': true},
              'media': [_aniListMedia(type: 'MANGA')],
            },
          },
        }),
        200,
      );
    });
    final service = AniListTrackerService(client: client);

    final results = await service.search(
      TrackerSearchRequest(
        query: 'example',
        type: TrackedMediaType.manga,
        tags: const ['Fantasy'],
        sort: TrackerSort.mostRecent,
        page: 2,
      ),
    );

    expect(results.items.single.type, TrackedMediaType.manga);
    expect(results.hasNextPage, isTrue);
    expect(variables['type'], 'MANGA');
    expect(variables['tags'], ['Fantasy']);
    expect(variables['sort'], ['START_DATE_DESC']);
    expect(variables['page'], 2);
  });

  test('AniList loads a historical season with pagination', () async {
    late Map<String, dynamic> variables;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      variables = body['variables'] as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'Page': {
              'pageInfo': {'hasNextPage': true},
              'media': [_aniListMedia()],
            },
          },
        }),
        200,
      );
    });

    final page = await AniListTrackerService(client: client).loadSeason(
      year: 2020,
      season: AnimeSeason.summer,
      sort: TrackerSort.popularity,
      includeAdult: false,
      page: 2,
    );

    expect(variables['seasonYear'], 2020);
    expect(variables['season'], 'SUMMER');
    expect(variables['page'], 2);
    expect(page.hasNextPage, isTrue);
    expect(page.items.single.title.preferred, 'Example Romaji');
  });

  test('AniList maps rich media details', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'Media': {
              ..._aniListMedia(),
              'format': 'TV',
              'status': 'FINISHED',
              'source': 'MANGA',
              'duration': 24,
              'volumes': null,
              'staff': {
                'edges': [
                  {
                    'role': 'Original Creator',
                    'node': {
                      'name': {'full': 'Creator Name'},
                      'image': {'large': 'https://img.example/creator.jpg'},
                    },
                  },
                ],
              },
              'characters': {
                'edges': [
                  {
                    'node': {
                      'name': {'full': 'Hero'},
                    },
                    'voiceActors': [
                      {
                        'name': {'full': 'Actor Name'},
                        'image': {'large': 'https://img.example/actor.jpg'},
                      },
                    ],
                  },
                ],
              },
              'studios': {
                'edges': [
                  {
                    'isMain': true,
                    'node': {'name': 'Example Studio'},
                  },
                ],
              },
              'reviews': {
                'nodes': [
                  {
                    'summary': 'Worth watching',
                    'body': 'A detailed review.',
                    'rating': 12,
                    'score': 80,
                    'user': {
                      'name': 'Reviewer',
                      'avatar': {'large': 'https://img.example/avatar.jpg'},
                    },
                  },
                ],
              },
            },
          },
        }),
        200,
      );
    });

    final seed = TrackerMedia(
      id: '1',
      malId: 2,
      tracker: TrackerKind.aniList,
      type: TrackedMediaType.anime,
      title: TrackerTitle(preferred: 'Example Romaji'),
    );
    final details =
        await AniListTrackerService(client: client).loadDetails(seed);

    expect(details.episodes, 24);
    expect(details.durationMinutes, 24);
    expect(details.creators.single.name, 'Creator Name');
    expect(details.voiceActors.single.role, 'Voice of Hero');
    expect(details.studios, ['Example Studio']);
    expect(details.reviews.single.username, 'Reviewer');
  });

  test('AniList omits the adult constraint when adult content is enabled',
      () async {
    late String query;
    final client = MockClient((request) async {
      query = (jsonDecode(request.body) as Map<String, dynamic>)['query']
          .toString();
      return http.Response(
        jsonEncode({
          'data': {
            'Page': {'media': []},
          },
        }),
        200,
      );
    });

    await AniListTrackerService(client: client).search(
      TrackerSearchRequest(
        type: TrackedMediaType.anime,
        includeAdult: true,
      ),
    );

    expect(query, isNot(contains('isAdult: false')));
  });

  test('AniList loads genres and filters adult tags dynamically', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'GenreCollection': ['Action', 'Fantasy', 'Hentai'],
            'MediaTagCollection': [
              {'name': 'Found Family', 'category': 'Theme', 'isAdult': false},
              {'name': 'Adult tag', 'category': 'Adult', 'isAdult': true},
            ],
          },
        }),
        200,
      );
    });
    final service = AniListTrackerService(client: client);

    final safe = await service.loadTaxonomy(includeAdult: false);
    final complete = await service.loadTaxonomy(includeAdult: true);

    expect(safe.genres, ['Action', 'Fantasy']);
    expect(complete.genres, contains('Hentai'));
    expect(safe.tags.map((tag) => tag.name), ['Found Family']);
    expect(complete.tags.map((tag) => tag.name),
        containsAll(['Found Family', 'Adult tag']));
  });

  test('AniList loads the connected user library with progress', () async {
    late String? authorization;
    final client = MockClient((request) async {
      authorization = request.headers['authorization'];
      return http.Response(
        jsonEncode({
          'data': {
            'MediaListCollection': {
              'lists': [
                {
                  'name': 'Watching',
                  'status': 'CURRENT',
                  'entries': [
                    {
                      'status': 'CURRENT',
                      'progress': 7,
                      'updatedAt': 1791763200,
                      'media': _aniListMedia(),
                    },
                  ],
                },
              ],
            },
          },
        }),
        200,
      );
    });
    final service = AniListTrackerService(
      accessToken: 'token',
      userId: '42',
      client: client,
    );

    final sections = await service.loadLibrary(type: TrackedMediaType.anime);

    expect(authorization, 'Bearer token');
    expect(sections.single.title, 'Watching');
    expect(sections.single.items.single.progress, 7);
    expect(sections.single.items.single.progressTotal, 24);
  });

  test('MAL requires a client id and sends it on public requests', () async {
    final unconfigured = MalTrackerService(clientId: '');
    expect(
      () => unconfigured.search(
        TrackerSearchRequest(type: TrackedMediaType.anime, query: 'Example'),
      ),
      throwsA(isA<TrackerRequestException>()),
    );

    late String? sentClientId;
    final client = MockClient((request) async {
      sentClientId = request.headers['x-mal-client-id'];
      return http.Response(
        jsonEncode({
          'data': [
            {
              'node': {
                'id': 1,
                'title': 'Example Romaji',
                'alternative_titles': {
                  'en': 'Example',
                  'ja': 'Example Native',
                  'synonyms': ['Alias'],
                },
                'main_picture': {'large': 'https://img.example/cover.jpg'},
                'genres': [
                  {'name': 'Fantasy'},
                ],
                'mean': 8.5,
                'nsfw': 'white',
              },
            },
          ],
        }),
        200,
      );
    });
    final configured =
        MalTrackerService(clientId: 'client-123', client: client);

    final results = await configured.search(
      TrackerSearchRequest(type: TrackedMediaType.anime, query: 'Example'),
    );

    expect(sentClientId, 'client-123');
    expect(results.items.single.title.preferred, 'Example Romaji');
    expect(results.items.single.title.display(preferEnglish: true), 'Example');
    expect(results.items.single.score, 85);
  });
}

Map<String, dynamic> _aniListMedia({String type = 'ANIME'}) => {
      'id': 1,
      'idMal': 2,
      'type': type,
      'title': {
        'english': 'Example',
        'romaji': 'Example Romaji',
        'native': 'Example Native',
      },
      'synonyms': ['Alias'],
      'description': '<b>Description</b>',
      'startDate': {'year': 2026, 'month': 10, 'day': 12},
      'endDate': {'year': null, 'month': null, 'day': null},
      'coverImage': {'extraLarge': 'https://img.example/cover.jpg'},
      'bannerImage': 'https://img.example/banner.jpg',
      'genres': ['Fantasy'],
      'tags': [
        {'name': 'Magic', 'rank': 80},
      ],
      'averageScore': 85,
      'popularity': 1000,
      'episodes': 24,
      'chapters': 100,
      'isAdult': false,
      'siteUrl': 'https://anilist.co/media/1',
      'nextAiringEpisode': {'airingAt': 1791763200, 'episode': 3},
    };
