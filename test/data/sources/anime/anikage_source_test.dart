import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/anikage_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  late AnikageSource source;

  setUp(() {
    source = AnikageSource(
      baseUri: Uri.parse('https://anikage.test/'),
      proxyUri: Uri.parse('https://proxy.test/'),
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/media/anime/browse') {
          final query = request.url.queryParameters;
          if (query['q'] == 'Example') {
            expect(query['genres'], 'Action,Drama');
            expect(query['tags'], 'Isekai');
            expect(query['format'], 'TV,MOVIE');
            expect(query['source'], 'MANGA');
            expect(query['yearMin'], '2024');
            expect(query['yearMax'], '2024');
            expect(query['season'], 'FALL');
            expect(query['status'], 'RELEASING');
            expect(query['country'], 'JP');
            expect(query['scoreMin'], '70');
            expect(query['epMin'], '2');
            expect(query['epMax'], '12');
            expect(query['sub'], 'true');
            expect(query['sort'], 'trending');
          }
          return _json({
            'data': [
              {
                'slug': 'example-slug',
                'title': {
                  'romaji': 'Example Romaji',
                  'english': 'Example Anime',
                },
                'coverImage': {
                  'extraLarge': 'https://images.test/example.jpg',
                },
                'format': 'TV',
                'year': 2024,
                'averageScore': 84,
                'subCount': 12,
                'dubCount': 8,
              },
            ],
            'hasNext': query['page'] == '1',
          });
        }
        if (path == '/api/media/anime/example-slug') {
          return _json({
            'anime': {
              'slug': 'example-slug',
              'anilistId': 123,
              'malId': 456,
              'title': {
                'romaji': 'Example Romaji',
                'english': 'Example Anime',
                'native': '例',
              },
              'synonyms': ['Example Alias'],
              'description': '<p>An <b>example</b> synopsis.</p>',
              'coverImage': {
                'extraLarge': 'https://images.test/example.jpg',
              },
              'fanart': 'https://images.test/banner.jpg',
              'format': 'TV',
              'year': 2024,
              'status': 'RELEASING',
              'genres': ['Action', 'Drama'],
              'studios': [
                {
                  'name': 'Example Studio',
                  'isAnimationStudio': true,
                },
                {
                  'name': 'Example Producer',
                  'isAnimationStudio': false,
                },
              ],
            },
          });
        }
        if (path == '/api/media/anime/example-slug/episodes') {
          return _json([
            {
              'id': 'example-slug-1',
              'number': 1,
              'seasonNumber': 1,
              'title': 'Pilot',
              'airDate': '2024-10-01',
              'image': 'https://images.test/episode.jpg',
            },
          ]);
        }
        if (path == '/api/media/anime/example-slug/episodes/1/servers') {
          return _json({
            'servers': [
              {
                'id': 'koto',
                'providerId': 'koto',
                'default': true,
                'subTypes': ['sub', 'dub'],
              },
            ],
          });
        }
        if (path == '/api/media/anime/example-slug/episodes/1/sources') {
          expect(request.url.queryParameters['provider'], 'koto');
          expect(request.url.queryParameters['lang'], 'sub');
          return _json({
            'sources': [
              {
                'url': 'signed-video-token',
                'quality': '1080p',
                'label': '1080p',
                'isM3U8': true,
              },
            ],
            'subtitles': [
              {
                'file': 'signed-subtitle-token',
                'label': 'English',
                'kind': 'captions',
                'default': true,
              },
            ],
            'intro': {'start': 10, 'end': 90},
            'outro': {'start': 1320, 'end': 1400},
          });
        }
        return http.Response('Not found: ${request.url}', 404);
      }),
    );
  });

  test('exposes AniKage as a filterable non-adult English source', () async {
    final options = await source.getSearchOptions();

    expect(source.id, 'anikage');
    expect(source.baseUri.toString(), 'https://anikage.test/');
    expect(source.catalogFilters, contains(AnimeCatalogFilter.popular));
    expect(source.isRRated, isFalse);
    expect(source.languageLabel, 'English (US)');
    expect(options.genres.map((option) => option.value), contains('Action'));
    expect(options.tags.map((option) => option.value), contains('Isekai'));
    expect(options.formats, hasLength(7));
    expect(options.sources.map((option) => option.value), contains('MANGA'));
    expect(options.origins.map((option) => option.value), contains('JP'));
    expect(options.episodeRanges.last.value, '65-');
    expect(options.sorts, [
      AnimeSearchSort.popularity,
      AnimeSearchSort.averageScore,
      AnimeSearchSort.trending,
      AnimeSearchSort.favorites,
      AnimeSearchSort.dateAdded,
      AnimeSearchSort.releaseDate,
    ]);
  });

  test('maps browse cards, pagination and every structured filter', () async {
    final page = await source.filter(
      AnimeSearchRequest(
        query: 'Example',
        genres: {'Action', 'Drama'},
        tags: {'Isekai'},
        formats: {'TV', 'MOVIE'},
        sources: {'MANGA'},
        year: '2024',
        season: 'FALL',
        status: 'RELEASING',
        origin: 'JP',
        score: '70',
        episodeRange: '2-12',
        audio: 'sub',
        sort: AnimeSearchSort.trending,
      ),
    );

    expect(page.items.single.id, 'example-slug');
    expect(page.items.single.title, 'Example Anime');
    expect(page.items.single.coverUri.toString(), contains('example.jpg'));
    expect(page.items.single.subtitle, 'TV · 2024 · 8.4 ★ · Sub 12 · Dub 8');
    expect(page.nextCursor, '2');
  });

  test('maps details, episodes and protected HLS playback', () async {
    final details = await source.getDetails('example-slug');
    final episodes = await source.getEpisodes('example-slug');
    final playback = await source.getPlayback(
      animeId: 'example-slug',
      episodeId: episodes.single.id,
    );

    expect(details.item.title, 'Example Anime');
    expect(details.description, 'An example synopsis.');
    expect(details.alternativeTitles, contains('Example Alias'));
    expect(details.genres, ['Action', 'Drama']);
    expect(details.status, AnimeStatus.ongoing);
    expect(details.externalIds, {'anilist': '123', 'mal': '456'});
    expect(details.studios, ['Example Studio']);
    expect(details.producers, ['Example Producer']);
    expect(episodes.single.title, 'Pilot');
    expect(episodes.single.releasedAt, DateTime(2024, 10, 1));
    expect(
      playback.streams.single.uri.toString(),
      'https://proxy.test/m3u8/signed-video-token',
    );
    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(playback.streams.single.headers, {
      'Accept': '*/*',
      'Origin': 'https://anikage.test',
      'Referer': 'https://anikage.test/',
      'User-Agent': contains('Mozilla/5.0'),
    });
    expect(playback.subtitles.single.language, 'en');
    expect(
      playback.subtitles.single.uri.toString(),
      'https://proxy.test/stream/signed-subtitle-token',
    );
    expect(playback.subtitles.single.headers, playback.streams.single.headers);
    expect(playback.skipSegments, hasLength(2));
    expect(playback.skipSegments.first.start, const Duration(seconds: 10));
  });
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
