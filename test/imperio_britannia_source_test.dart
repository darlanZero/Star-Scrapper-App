import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/manga/imperio_britannia_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('updated catalog uses public recent chapters API and normalizes cards',
      () async {
    late http.Request captured;
    final source = ImperioBritanniaSource(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'sucesso': true,
            'pagination': {
              'pagina': 1,
              'totalPaginas': 2,
              'hasNextPage': true,
            },
            'obras': [
              {
                'id': 2838,
                'nome': 'Coluna Escarlate',
                'imagem': 'obras/2838/cover.webp',
                'formato_nome': 'Manhwa',
                'status_nome': 'Em Andamento',
                'total_capitulos': 22,
                'avaliacao_media': 4.0,
              },
            ],
          }),
          200,
        );
      }),
    );

    final page = await source.browse(filter: MangaCatalogFilter.updated);

    expect(captured.url.path, '/api/capitulos/recentes');
    expect(captured.url.queryParameters['limite'], '24');
    expect(captured.headers['x-api-token'], isNotEmpty);
    expect(captured.headers['x-noencryptionbritta'], '1');
    expect(page.nextCursor, '2');
    expect(page.items.single.title, 'Coluna Escarlate');
    expect(page.items.single.coverUri.toString(),
        'https://cdn.imperiodabritannia.net/obras/2838/cover.webp');
    expect(page.items.single.subtitle, contains('22 Ch'));
    expect(page.items.single.subtitle, contains('Manhwa'));
  });

  test('catalog filters map formats, genres and sorting to API parameters',
      () async {
    final requests = <http.Request>[];
    final source = ImperioBritanniaSource(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/filtros/formatos') {
          return http.Response(
            jsonEncode({
              'sucesso': true,
              'formatos': [
                {'id': 25, 'nome': 'Manhwa'},
                {'id': 23, 'nome': 'Hentai'},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/filtros/tags') {
          return http.Response(
            jsonEncode({
              'sucesso': true,
              'tags': [
                {'id': 2, 'nome': 'Ação'},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/obras') {
          return http.Response(
            jsonEncode({
              'sucesso': true,
              'pagination': {'hasNextPage': false},
              'obras': [],
            }),
            200,
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.formats.map((option) => option.label),
        containsAll(['Manhwa', 'Hentai']));
    expect(options.tags.single.label, 'Ação');

    await source.filterCatalog(
      MangaSearchRequest(
        formats: {'25'},
        tags: {'2'},
        sort: MangaSearchSort.chapterCount,
      ),
    );
    final request = requests.last;
    expect(request.url.queryParameters['formato_ids'], '25');
    expect(request.url.queryParameters['tag_ids'], '2');
    expect(request.url.queryParameters['ordem'], 'capitulos_desc');
  });

  test('details and reader expose public chapters directly to native reader',
      () async {
    final source = ImperioBritanniaSource(
      client: MockClient((request) async {
        if (request.url.path == '/api/obras/2838') {
          return http.Response(
            jsonEncode({
              'sucesso': true,
              'obra': {
                'id': 2838,
                'slug': 'coluna-escarlate-6',
                'nome': 'Coluna Escarlate',
                'descricao': 'Sinopse',
                'imagem': 'obras/2838/cover.webp',
                'formato_nome': 'Manhwa',
                'status_nome': 'Em Andamento',
                'total_capitulos': 2,
                'tags': [
                  {'id': 2, 'nome': 'Ação'},
                ],
                'capitulos': [
                  {
                    'id': 10,
                    'numero': '1.00',
                    'nome': 'Capítulo 1',
                    'total_paginas': 2,
                  },
                  {
                    'id': 11,
                    'numero': '2.00',
                    'nome': 'Capítulo 2',
                    'total_paginas': 2,
                  },
                ],
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/obras/2838/capitulos/1') {
          return http.Response(
            jsonEncode({
              'sucesso': true,
              'capitulo': {
                'id': 10,
                'numero': '1.00',
                'paywall_bloqueado': false,
                'paginas': [
                  {
                    'numero': 2,
                    'cdn_id': 'https://cdn.imperiodabritannia.net/page-2.webp',
                  },
                  {
                    'numero': 1,
                    'cdn_id': 'https://cdn.imperiodabritannia.net/page-1.webp',
                  },
                ],
              },
            }),
            200,
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    final details = await source.getDetails('2838');
    expect(details.genres, ['Ação']);
    expect(details.chapters.map((chapter) => chapter.id), ['2', '1']);
    expect(await source.nextChapterId('2838', '1'), '2');

    final pages =
        await source.readChapter(mangaId: '2838', chapterId: '1').toList();
    expect(pages.map((page) => page.uri.toString()), [
      'https://cdn.imperiodabritannia.net/page-1.webp',
      'https://cdn.imperiodabritannia.net/page-2.webp',
    ]);
  });

  test('locked VIP chapter requests authenticated membership', () async {
    final source = ImperioBritanniaSource(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'sucesso': true,
              'capitulo': {
                'id': 99,
                'paywall_bloqueado': true,
                'paginas': [],
              },
            }),
            200,
          )),
    );

    expect(
      source.readChapter(mangaId: '1', chapterId: '99').drain<void>(),
      throwsA(isA<MangaSourceSessionRequired>()),
    );
  });

  test('email login stores a token after API validation', () async {
    final source = ImperioBritanniaSource(
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          expect(jsonDecode(request.body), {
            'email': 'reader@example.com',
            'senha': 'secret',
          });
          return http.Response(
            jsonEncode({'sucesso': true, 'token': 'brit-token'}),
            200,
          );
        }
        if (request.url.path == '/api/auth/me') {
          expect(request.headers['authorization'], 'Bearer brit-token');
          return http.Response(
            jsonEncode({
              'sucesso': true,
              'usuario': {'id': 1}
            }),
            200,
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    await source.authenticateWithCredentials(
      ' reader@example.com ',
      'secret',
    );

    expect(source.isAuthenticated, isTrue);
  });
}
