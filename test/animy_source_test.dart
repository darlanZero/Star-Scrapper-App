import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/animy_anime_source.dart';
import 'package:star_scrapper_app/data/sources/manga/animy_manga_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Animy manga exposes top variants, details and native pages', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/mangas/top')) {
        expect(request.url.queryParameters['period'], 'week');
        return _json({
          'items': [
            {
              'id': 7,
              't': 'Obra Animy',
              'cover': 'https://animy.net/files/cover',
              'type': 'manhwa',
              'ch': 2,
            }
          ],
        });
      }
      if (request.url.path.endsWith('/mangas/7')) {
        return _json({
          'id': 7,
          't': 'Obra Animy',
          'cover': 'https://animy.net/files/cover',
          'desc': 'Descrição',
          'status': 'ongoing',
          'g': ['Ação'],
          'chapters': [
            {'id': 10, 'number': 1, 'language': 'pt-br'},
            {'id': 11, 'number': 2, 'language': 'pt-br'},
          ],
        });
      }
      if (request.url.path.endsWith('/mangas/7/chapters/1')) {
        return _json({
          'pages': [
            {'number': 1, 'imageUrl': 'https://animy.net/files/page-1.avif'},
            {'number': 2, 'imageUrl': 'https://animy.net/files/page-2.avif'},
          ],
        });
      }
      fail('Unexpected request: ${request.url}');
    });
    final source = AnimyMangaSource(client: client);

    expect(
      source.catalogVariants(MangaCatalogFilter.popular).map((e) => e.id),
      ['day', 'week', 'month', 'all'],
    );
    expect(
      source.catalogVariants(MangaCatalogFilter.added).map((e) => e.id),
      ['all', 'manga', 'manhwa', 'manhua'],
    );
    final top = await source.browseVariant(
      MangaCatalogFilter.popular,
      'week',
    );
    expect(top.items.single.title, 'Obra Animy');

    final details = await source.getDetails('7');
    expect(details.status, MangaStatus.ongoing);
    expect(
        details.chapters.map((chapter) => chapter.id), ['1|pt-br', '2|pt-br']);
    expect(await source.nextChapterId('7', '1|pt-br'), '2|pt-br');

    final pages =
        await source.readChapter(mangaId: '7', chapterId: '1|pt-br').toList();
    expect(pages, hasLength(2));
    expect(pages.first.uri?.path, '/files/page-1.avif');
  });

  test('Animy manga maps library filters to the public API', () async {
    late Uri requested;
    final source = AnimyMangaSource(
      client: MockClient((request) async {
        requested = request.url;
        return _json({'items': [], 'total': 0});
      }),
    );

    await source.filterCatalog(MangaSearchRequest(
      formats: {'manhwa'},
      statuses: {'ongoing'},
      genres: {'Ação'},
      tags: {'demographic:shounen', 'rating:suggestive'},
      minimumYear: 2025,
      sort: MangaSearchSort.rating,
      adultMode: MangaAdultMode.include,
    ));

    expect(requested.queryParameters['type'], 'manhwa');
    expect(requested.queryParameters['status'], 'ongoing');
    expect(requested.queryParameters['genre'], 'Ação');
    expect(requested.queryParameters['demographic'], 'shounen');
    expect(requested.queryParameters['contentRating'], 'suggestive');
    expect(requested.queryParameters['sort'], 'rating');
    expect(requested.queryParameters['year'], '2025');
  });

  test('Animy separates chapter updates from newly added works', () async {
    final requests = <Uri>[];
    final source = AnimyMangaSource(
      client: MockClient((request) async {
        requests.add(request.url);
        return _json({'items': [], 'total': 0});
      }),
    );

    await source.browse(filter: MangaCatalogFilter.recent);
    await source.browseVariant(
      MangaCatalogFilter.added,
      'manhua',
      cursor: '2',
    );

    expect(requests[0].queryParameters['sort'], 'released');
    expect(requests[0].queryParameters['released'], '1');
    expect(requests[1].queryParameters['sort'], 'newest');
    expect(requests[1].queryParameters['released'], '0');
    expect(requests[1].queryParameters['type'], 'manhua');
    expect(requests[1].queryParameters['offset'], '24');
  });

  test('Animy anime exposes recent episode metadata and native HLS', () async {
    final source = AnimyAnimeSource(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/animes/recent-episodes')) {
          return _json([
            {
              'seriesId': 12,
              'seriesTitle': 'Anime Animy',
              'seriesCover': 'https://animy.net/files/anime-cover',
              'season': 2,
              'number': 5,
            }
          ]);
        }
        if (request.url.path.endsWith('/animes/12')) {
          return _json({
            'id': 12,
            't': 'Anime Animy',
            'cover': 'https://animy.net/files/anime-cover',
            'status': 'airing',
            'episodes': [
              {'id': 44, 'season': 2, 'number': 5, 'title': 'Retorno'},
            ],
          });
        }
        if (request.url.path.endsWith('/animes/12/episodes/2/5')) {
          return _json({
            'streams': [
              {
                'kind': 'hls',
                'url': 'https://feralstream.animy.net/files/video/index.m3u8',
                'audio': 'legendado',
                'skip': {'enabled': true, 'start': 10, 'end': 20},
              }
            ],
          });
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final recent = await source.browse(filter: AnimeCatalogFilter.recent);
    expect(recent.items.single.subtitle, 'Temporada 2 · Episódio 5');

    final episodes = await source.getEpisodes('12');
    expect(episodes.single.id, '2|5');
    final playback = await source.getPlayback(
      animeId: '12',
      episodeId: episodes.single.id,
    );
    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(playback.streams.single.language, 'legendado');
    expect(playback.skipSegments.single.start, const Duration(seconds: 10));
  });
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
