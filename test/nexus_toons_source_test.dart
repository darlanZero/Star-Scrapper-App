import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/manga/nexus_toons_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('updated catalog maps Nexus cards and pagination', () async {
    late http.Request captured;
    final source = NexusToonsSource(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 18487,
                'slug': 'coluna-escarlate',
                'title': 'Coluna Escarlate',
                'coverImage': 'https://img.nx-toons.xyz/cover.webp',
                'type': 'manhwa',
                'status': 'ongoing',
                'chapterCount': 11,
                'rating': 4.0,
                'chapters': [
                  {'id': 423819, 'number': '11'},
                ],
              },
            ],
            'pages': 2,
            'total': 31,
          }),
          200,
        );
      }),
    );

    final page = await source.browse(filter: MangaCatalogFilter.updated);

    expect(captured.url.path, '/api/mangas');
    expect(captured.url.queryParameters['page'], '1');
    expect(captured.url.queryParameters['limit'], '30');
    expect(captured.url.queryParameters['sortBy'], 'updatedAt');
    expect(captured.url.queryParameters['sortOrder'], 'desc');
    expect(page.nextCursor, '2');
    expect(page.items.single.id, 'coluna-escarlate');
    expect(page.items.single.subtitle, contains('11 Ch'));
    expect(page.items.single.subtitle, contains('manhwa'));
  });

  test('advanced catalog exposes and sends every modular filter', () async {
    final requests = <http.Request>[];
    final source = NexusToonsSource(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/categories') {
          return http.Response(
            jsonEncode([
              {'id': 2, 'name': 'Ação', 'type': 'genre'},
              {'id': 40, 'name': 'Artes Marciais', 'type': 'theme'},
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode({'data': [], 'pages': 1, 'total': 0}),
          200,
        );
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.formats.map((item) => item.value), contains('pornhwa'));
    expect(options.statuses.map((item) => item.value), contains('hiatus'));
    expect(options.genres.single.label, 'Ação');
    expect(options.themes.single.label, 'Artes Marciais');
    expect(options.supportsAuthor, isTrue);
    expect(options.supportsAdultMode, isTrue);
    expect(options.supportsSortDirection, isTrue);

    await source.filterCatalog(
      MangaSearchRequest(
        formats: {'manhwa', 'webtoon'},
        statuses: {'ongoing'},
        genres: {'2'},
        themes: {'40'},
        author: 'Autor Teste',
        artist: 'Artista Teste',
        minimumYear: 2018,
        maximumYear: 2026,
        minimumChapters: 10,
        maximumChapters: 200,
        categoryMode: MangaCategoryMode.all,
        adultMode: MangaAdultMode.only,
        sort: MangaSearchSort.year,
        sortDirection: MangaSortDirection.ascending,
      ),
    );
    final query = requests.last.url.queryParameters;
    expect(query['type'], 'manhwa,webtoon');
    expect(query['status'], 'ongoing');
    expect(query['genres'], '2');
    expect(query['themes'], '40');
    expect(query['author'], 'Autor Teste');
    expect(query['artist'], 'Artista Teste');
    expect(query['yearFrom'], '2018');
    expect(query['yearTo'], '2026');
    expect(query['minChapters'], '10');
    expect(query['maxChapters'], '200');
    expect(query['categoryMode'], 'and');
    expect(query['onlyNsfw'], 'true');
    expect(query['sortBy'], 'releaseYear');
    expect(query['sortOrder'], 'asc');
  });

  test('decrypts details and streams public chapter pages in order', () async {
    final detailsPayload = {
      'id': 18487,
      'slug': 'coluna-escarlate',
      'title': 'Coluna Escarlate',
      'description': 'Sinopse',
      'coverImage': 'https://img.nx-toons.xyz/cover.webp',
      'type': 'manhwa',
      'status': 'ongoing',
      'rating': 4.0,
      'alternativeTitles': jsonEncode([
        {
          'lang': 'ja',
          'title': 'Scarlet Column',
        },
      ]),
      'categories': [
        {'id': 7, 'name': 'Aventura', 'type': 'genre'},
      ],
      'chapters': [
        {
          'id': 423819,
          'number': '2',
          'accessLevel': 'public',
          'createdAt': '2026-10-26T18:01:40Z',
        },
        {
          'id': 423812,
          'number': '1',
          'accessLevel': 'public',
          'createdAt': '2026-10-26T18:00:13Z',
        },
      ],
    };
    final source = NexusToonsSource(
      client: MockClient((request) async {
        if (request.url.path == '/api/manga/coluna-escarlate') {
          return http.Response(_encrypted(detailsPayload), 200);
        }
        if (request.url.path == '/api/chapter/423812') {
          return http.Response(
            _encrypted({
              'id': 423812,
              'accessLevel': 'public',
              'pages': [
                {
                  'pageNumber': 2,
                  'imageUrl': 'https://img.nx-toons.xyz/page-2.webp',
                },
                {
                  'pageNumber': 1,
                  'imageUrl': 'https://img.nx-toons.xyz/page-1.webp',
                },
              ],
            }),
            200,
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    final details = await source.getDetails('coluna-escarlate');
    expect(details.genres, ['Aventura']);
    expect(details.alternativeTitles, [
      {'ja': 'Scarlet Column'},
    ]);
    expect(details.chapters.map((chapter) => chapter.id), ['423819', '423812']);
    expect(await source.nextChapterId('coluna-escarlate', '423812'), '423819');

    final pages = await source
        .readChapter(mangaId: 'coluna-escarlate', chapterId: '423812')
        .toList();
    expect(pages.map((page) => page.uri.toString()), [
      'https://img.nx-toons.xyz/page-1.webp',
      'https://img.nx-toons.xyz/page-2.webp',
    ]);
  });

  test('VIP chapters request an authenticated membership', () async {
    final source = NexusToonsSource(
      client: MockClient((request) async => http.Response(
            _encrypted({
              'id': 9,
              'accessLevel': 'vip',
              'pages': null,
            }),
            200,
          )),
    );

    expect(
      source.readChapter(mangaId: 'vip-title', chapterId: '9').drain<void>(),
      throwsA(isA<MangaSourceSessionRequired>()),
    );
  });

  test('credential login stores and validates the website cookie session',
      () async {
    final source = NexusToonsSource(
      client: MockClient((request) async {
        if (request.url.path == '/api/login') {
          expect(jsonDecode(request.body), {
            'username': 'reader@example.com',
            'password': 'secret',
          });
          return http.Response(
            jsonEncode({
              'user': {'id': 1}
            }),
            200,
            headers: {
              'set-cookie':
                  'nexus_session=abc; Path=/; HttpOnly, nexus_csrf=def; Path=/',
            },
          );
        }
        if (request.url.path == '/api/me') {
          expect(request.headers['cookie'], contains('nexus_session=abc'));
          return http.Response(jsonEncode({'id': 1}), 200);
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    await source.authenticateWithCredentials(' reader@example.com ', 'secret');

    expect(source.isAuthenticated, isTrue);
  });
}

String _encrypted(Object payload, {int keyIndex = 2}) {
  const secret = 'OrionNexus2025CryptoKey!Secure';
  final key =
      sha256.convert(utf8.encode('_orion_key_${keyIndex}_v2_$secret')).bytes;
  final sbox = List<int>.generate(256, (index) => index);
  var j = 0;
  for (var index = 0; index < 256; index++) {
    j = (j + sbox[index] + key[index % key.length]) % 256;
    final current = sbox[index];
    sbox[index] = sbox[j];
    sbox[j] = current;
  }
  final plain = utf8.encode(jsonEncode(payload));
  final encrypted = List<int>.filled(plain.length, 0);
  for (var index = 0; index < plain.length; index++) {
    var value = plain[index] ^ key[index % key.length];
    final shift =
        (((key[(index + 3) % key.length] + (index & 255)) & 255) % 7) + 1;
    value = _rotateLeft(value, shift);
    value = sbox[value];
    value ^= index > 0 ? encrypted[index - 1] : key.last;
    encrypted[index] = value;
  }
  return jsonEncode({
    'd': base64Encode(encrypted),
    'k': keyIndex,
    'v': 2,
  });
}

int _rotateLeft(int value, int bits) {
  final shift = bits % 8;
  return (((value << shift) & 255) | (value >> (8 - shift))) & 255;
}
