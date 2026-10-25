import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/leitura_manga_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps latest, recently added and popular to API sorts', () async {
    final requestedSorts = <String>[];
    final source = LeituraMangaSource(
      client: MockClient((request) async {
        requestedSorts.add(request.url.queryParameters['sort'] ?? '');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'data': [
                {
                  'slug': 'obra-teste',
                  'title': 'Obra Teste',
                  'status': 1,
                  'contentType': 'comic',
                  'genres': [
                    {'name': 'Manhwa'}
                  ],
                  'chapters': [
                    {'chapterNumber': 12.5}
                  ],
                }
              ],
              'pagination': {'page': 1, 'totalPage': 2},
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      apiUri: Uri.parse('https://api.example/api'),
      cdnUri: Uri.parse('https://cdn.example'),
    );

    final updated = await source.browse(filter: MangaCatalogFilter.updated);
    await source.browse(filter: MangaCatalogFilter.added);
    await source.browse(filter: MangaCatalogFilter.popular);

    expect(requestedSorts, ['time', 'created', 'view']);
    expect(updated.items.single.id, 'obra-teste');
    expect(updated.items.single.subtitle, '12.5 Ch • Manhwa • Ongoing');
    expect(
      updated.items.single.coverUri.toString(),
      'https://cdn.example/obra-teste/cover-md.webp',
    );
    expect(updated.nextCursor, '2');
  });

  test('search uses the dedicated multi-result endpoint', () async {
    late Uri requestedUri;
    final source = LeituraMangaSource(
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {'slug': 'martial-peak', 'title': 'Martial Peak'}
              ],
              'pagination': {'page': 1, 'totalPage': 1},
            },
          }),
          200,
        );
      }),
      apiUri: Uri.parse('https://api.example/api'),
    );

    final page = await source.search('Martial Peak');

    expect(requestedUri.path, '/api/search/manga');
    expect(requestedUri.queryParameters['q'], 'Martial Peak');
    expect(requestedUri.queryParameters['includeAdult'], 'true');
    expect(page.items.single.id, 'martial-peak');
  });

  test('details preserve PT-BR metadata and build chapter references',
      () async {
    final source = LeituraMangaSource(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'data': {
                'slug': 'obra-teste',
                'title': 'Obra Teste',
                'description': 'Sinopse',
                'alternativeTitles': ['Test Work'],
                'authors': [
                  {'name': 'Autora'}
                ],
                'genres': [
                  {'name': 'Ação'},
                  {'name': 'Adulto', 'isAdult': true},
                ],
                'status': 1,
                'totalChapter': 3.5,
              },
            }),
            200,
          )),
      apiUri: Uri.parse('https://api.example/api'),
      cdnUri: Uri.parse('https://cdn.example'),
    );

    final details = await source.getDetails('obra-teste');

    expect(details.author, 'Autora');
    expect(details.genres, ['Ação', 'Adulto']);
    expect(details.status, MangaStatus.ongoing);
    expect(details.alternativeTitles.single[''], 'Test Work');
    expect(details.chapters.map((chapter) => chapter.number),
        ['1', '2', '3', '3.5']);
    expect(
        details.chapters,
        everyElement(predicate<MangaChapter>(
          (chapter) => chapter.language == 'pt-br',
        )));
  });

  test('loads genres and browses with the API genre id', () async {
    final requestedUris = <Uri>[];
    final source = LeituraMangaSource(
      client: MockClient((request) async {
        requestedUris.add(request.url);
        if (request.url.path.endsWith('/genre')) {
          return http.Response(
            jsonEncode({
              'data': {
                'data': [
                  {
                    '_id': 'genre-action',
                    'name': 'Ação',
                    'isAdult': false,
                  },
                  {
                    '_id': 'genre-adult',
                    'name': 'Adulto',
                    'isAdult': true,
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {'slug': 'magic-emperor', 'title': 'Magic Emperor'}
              ],
              'pagination': {'page': 1, 'totalPage': 1},
            },
          }),
          200,
        );
      }),
      apiUri: Uri.parse('https://api.example/api'),
    );

    final genres = await source.getGenres();
    final page = await source.browseGenre(
      genres.first.id,
      filter: MangaCatalogFilter.updated,
    );

    expect(genres.map((genre) => genre.name), ['Adulto', 'Ação']);
    expect(genres.first.isAdult, isTrue);
    expect(requestedUris.last.queryParameters['genre'], 'genre-adult');
    expect(requestedUris.last.queryParameters['sort'], 'time');
    expect(page.items.single.title, 'Magic Emperor');
  });

  test('reader extracts ordered RSC image paths and keeps WebView fallback',
      () async {
    final source = LeituraMangaSource(
      client: MockClient((request) async => http.Response(
            r'''<script>self.__next_f.push([1,"{\"images\":[{\"url\":\"obra/capitulo-2/page-1.webp\"},{\"url\":\"obra/capitulo-2/page-2.webp\"}]}" ])</script>''',
            200,
          )),
      cdnUri: Uri.parse('https://cdn.example'),
    );

    final pages =
        await source.readChapter(mangaId: 'obra', chapterId: '2').toList();

    expect(pages.map((page) => page.uri.toString()), [
      'https://cdn.example/obra/capitulo-2/page-1.webp',
      'https://cdn.example/obra/capitulo-2/page-2.webp',
    ]);
    expect(pages.first.headers['Referer'], 'https://leituramanga.net/');
    expect(
      source.chapterWebUri(mangaId: 'obra', chapterId: '2').toString(),
      'https://leituramanga.net/manga/obra/chapter/2',
    );
  });

  test('reader accepts extensionless and absolute page URLs', () async {
    final source = LeituraMangaSource(
      client: MockClient((request) async => http.Response(
            r'''<script>self.__next_f.push([1,"{\"images\":[{\"url\":\"blue-lock/capitulo-01/page-1\"},{\"url\":\"blue-lock/capitulo-01/page-2\"},{\"url\":\"blue-lock/capitulo-01/page-3.webp\"},{\"url\":\"https://images.example/page-4?quality=90\"}],\"cover\":{\"url\":\"blue-lock/cover-md.webp\"}}" ])</script>''',
            200,
          )),
      cdnUri: Uri.parse('https://cdn.example'),
    );

    final pages =
        await source.readChapter(mangaId: 'blue-lock', chapterId: '1').toList();

    expect(pages.map((page) => page.uri.toString()), [
      'https://cdn.example/blue-lock/capitulo-01/page-1',
      'https://cdn.example/blue-lock/capitulo-01/page-2',
      'https://cdn.example/blue-lock/capitulo-01/page-3.webp',
      'https://images.example/page-4?quality=90',
    ]);
  });
}
