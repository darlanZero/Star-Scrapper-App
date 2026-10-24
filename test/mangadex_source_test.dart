import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/mangadex_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  late MangadexSource source;

  setUp(() {
    source = MangadexSource(
      apiBaseUri: Uri.parse('https://api.mangadex.test'),
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/manga' && request.url.query.contains('relevance')) {
          return _json({
            'result': 'ok',
            'data': [
              {
                'id': 'manga-1',
                'type': 'manga',
                'attributes': {
                  'title': {'en': 'Example Manga'},
                },
                'relationships': [
                  {
                    'type': 'cover_art',
                    'attributes': {'fileName': 'cover.jpg'},
                  },
                ],
              },
            ],
          });
        }
        if (path == '/manga/manga-1') {
          return _json({
            'result': 'ok',
            'data': {
              'id': 'manga-1',
              'type': 'manga',
              'attributes': {
                'title': {'en': 'Example Manga'},
                'description': {'en': 'A description'},
                'status': 'ongoing',
                'altTitles': [
                  {'ja': '例'},
                ],
                'tags': [
                  {
                    'attributes': {
                      'name': {'en': 'Action'},
                    },
                  },
                ],
              },
              'relationships': [
                {
                  'type': 'cover_art',
                  'attributes': {'fileName': 'cover.jpg'},
                },
                {
                  'type': 'author',
                  'attributes': {'name': 'Jane Doe'},
                },
                {
                  'type': 'artist',
                  'attributes': {'name': 'John Roe'},
                },
              ],
            },
          });
        }
        if (path == '/manga/manga-1/feed') {
          return _json({
            'result': 'ok',
            'data': [
              {
                'id': 'ch-1',
                'attributes': {
                  'chapter': '1',
                  'title': 'Start',
                  'translatedLanguage': 'en',
                  'pages': 20,
                  'publishAt': '2026-01-01T00:00:00+00:00',
                },
              },
            ],
          });
        }
        if (path == '/at-home/server/ch-1') {
          return _json({
            'baseUrl': 'https://uploads.mangadex.test',
            'chapter': {
              'hash': 'chapter-hash',
              'data': ['1.jpg', '2.jpg', '3.jpg', '4.jpg', '5.jpg'],
            },
          });
        }
        return http.Response('Not found', 404);
      }),
    );
  });

  test('maps catalog items with cover URLs', () async {
    final page = await source.browse();
    expect(page.items.single.id, 'manga-1');
    expect(page.items.single.title, 'Example Manga');
    expect(
      page.items.single.coverUri.toString(),
      'https://uploads.mangadex.org/covers/manga-1/cover.jpg',
    );
  });

  test('maps details, author/artist and chapters', () async {
    final details = await source.getDetails('manga-1');
    expect(details.description, 'A description');
    expect(details.status, MangaStatus.ongoing);
    expect(details.genres, ['Action']);
    expect(details.author, 'Jane Doe');
    expect(details.artist, 'John Roe');
    expect(details.chapters.single.id, 'ch-1');
    expect(details.chapters.single.number, '1');
    expect(details.chapters.single.pages, '20');
  });

  test('round-trips details through the legacy book map', () async {
    final details = await source.getDetails('manga-1');
    final restored = MangaDetails.fromJson(details.toJson());
    expect(restored.item.id, 'manga-1');
    expect(restored.chapters.single.number, '1');
    expect(restored.author, 'Jane Doe');
  });

  test('emits the complete remote page manifest without serial downloads',
      () async {
    final pages = await source
        .readChapter(mangaId: 'manga-1', chapterId: 'ch-1')
        .toList();

    expect(pages, hasLength(5));
    expect(pages.every((page) => !page.isLocal), isTrue);
    expect(
      pages.map((page) => page.uri.toString()),
      [
        'https://uploads.mangadex.test/data/chapter-hash/1.jpg',
        'https://uploads.mangadex.test/data/chapter-hash/2.jpg',
        'https://uploads.mangadex.test/data/chapter-hash/3.jpg',
        'https://uploads.mangadex.test/data/chapter-hash/4.jpg',
        'https://uploads.mangadex.test/data/chapter-hash/5.jpg',
      ],
    );
    expect(pages.first.headers['Referer'], 'https://mangadex.org/');
  });
}

http.Response _json(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
