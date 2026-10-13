import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/anitube_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  late List<http.Request> requests;
  late AnitubeSource source;

  setUp(() {
    requests = [];
    source = AnitubeSource(
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path == '/api/recent-anime') {
          return _json({
            'data': [
              {
                'id': 8942,
                'mal_id': 21,
                'title': 'One Piece',
                'poster': 'https://images.example/one-piece.jpg',
                'episodes': 1100,
              },
            ],
            'pagination': {'page': 1, 'total_pages': 2},
          });
        }
        if (path == '/api/trending-anime') {
          return _json({
            'data': [
              {
                'id': 'one-piece',
                'mal_id': 21,
                'title': 'One Piece',
                'poster': 'https://images.example/one-piece.jpg',
                'episodes_count': 1100,
                'type': 'TV',
              },
            ],
          });
        }
        if (path == '/api/search') {
          return _json({
            'data': [
              {
                'id': 8942,
                'mal_id': 21,
                'title': 'One Piece',
                'poster': 'https://images.example/one-piece.jpg',
              },
            ],
          });
        }
        if (path == '/api/series/8942') {
          return _json({
            'data': {
              'anime': {
                'id': 8942,
                'title': 'One Piece',
                'alternative': 'OP',
                'description': '<p>Pirate adventure.</p>',
                'status': 'Currently Airing',
                'poster': 'https://images.example/one-piece.jpg',
                'background_image': 'https://images.example/banner.jpg',
                'ani_id': 999,
                'terms_by_type': {
                  'genre': [
                    {'name': 'Adventure'},
                  ],
                  'studios': ['Example Studio'],
                  'producers': ['Example Producer'],
                },
              },
              'episodes': [
                {
                  'id': 777,
                  'number': 1,
                  'title': 'Episode 1',
                  'embed_url': {
                    'sub': 'https://megaplay.test/stream/s-2/123/sub',
                  },
                },
              ],
            },
          });
        }
        if (request.url.host == 'megaplay.test' &&
            path == '/stream/s-2/123/sub') {
          return http.Response('<div data-id="177655"></div>', 200);
        }
        if (request.url.host == 'megaplay.test' &&
            path == '/stream/getSourcesNew') {
          return _json({
            'enc':
                'wdeBruh3qqn_i5wUNnyaPcXqidp1UWP84FfPHzGyKXBnUD7UUNs_fRsAX3wrCloYO_L8jeuhY9aoPe8VuM7csDC4dK7ITf9dZhu2LCBFKP8uROt0nTTrQ8FPaR39frfymLtr0-MY0TtP0BMRhLfDmxHd4RS9Ng1fg8jERv8ClmI',
            'tracks': [
              {
                'file': 'https://subs.example/episode_por.vtt',
                'label': 'Portuguese (Brazil)',
                'kind': 'captions',
                'default': true,
              },
            ],
            'intro': {'start': 75, 'end': 165},
            'outro': {'start': 1280, 'end': 1370},
          });
        }
        return http.Response('Not found', 404);
      }),
      catalogBaseUri: Uri.parse('https://anitube.test/'),
      playerBaseUri: Uri.parse('https://megaplay.test/'),
    );
  });

  test('maps latest catalog pagination and search', () async {
    final latest = await source.browse(filter: AnimeCatalogFilter.recent);
    final search = await source.search('One Piece');

    expect(latest.items.single.id, '8942');
    expect(latest.nextCursor, '2');
    expect(search.items.single.title, 'One Piece');
    expect(
      requests.first.url.queryParameters,
      {'page': '1', 'per_page': '30'},
    );
  });

  test('resolves a trending slug through its MAL identity', () async {
    final trending = await source.browse();
    final details = await source.getDetails(trending.items.single.id);

    expect(trending.items.single.id, startsWith('mal:21:'));
    expect(details.item.id, '8942');
    expect(details.description, 'Pirate adventure.');
    expect(details.genres, ['Adventure']);
    expect(details.studios, ['Example Studio']);
    expect(details.producers, ['Example Producer']);
    expect(details.externalIds['anilist'], '999');
    expect(details.status, AnimeStatus.ongoing);
  });

  test('resolves encrypted HLS, subtitles and skip markers', () async {
    final episodes = await source.getEpisodes('8942');
    final playback = await source.getPlayback(
      animeId: '8942',
      episodeId: episodes.single.id,
    );

    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(playback.streams.single.language, 'sub');
    expect(playback.streams.single.uri.host, 'fetch.nexabloom.top');
    expect(
        playback.streams.single.headers['Referer'], 'https://megaplay.test/');
    expect(playback.subtitles.single.language, 'pt-BR');
    expect(playback.skipSegments.map((item) => item.type), [
      AnimeSkipType.intro,
      AnimeSkipType.outro,
    ]);
    expect(playback.skipSegments.first.start, const Duration(seconds: 75));
  });
}

http.Response _json(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
