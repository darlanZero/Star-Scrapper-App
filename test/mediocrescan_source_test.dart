import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/manga/mediocrescan_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('email login exchanges credentials for a validated bearer session',
      () async {
    final requests = <http.Request>[];
    final source = MediocrescanSource(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/login') {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'email': 'reader@example.com',
            'senha': 'secret',
          });
          return http.Response(
            jsonEncode({
              'data': {
                'token': 'access-one',
                'refresh_token': 'refresh-one',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/usuarios/me') {
          expect(request.headers['authorization'], 'Bearer access-one');
          return http.Response('{}', 200);
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );

    await source.authenticateWithCredentials(
      ' reader@example.com ',
      'secret',
    );

    expect(source.isAuthenticated, isTrue);
    expect(requests.map((request) => request.url.host).toSet(), {
      'back2.mediocrescan.com',
    });
  });

  test('401 refreshes the token once and retries the catalog request',
      () async {
    SharedPreferences.setMockInitialValues({
      'scrapper_session_mediocrescan': jsonEncode({
        'token': 'expired-token',
        'refresh_token': 'refresh-one',
      }),
    });
    var catalogCalls = 0;
    var refreshCalls = 0;
    final source = MediocrescanSource(
      client: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          expect(jsonDecode(request.body), {'refresh_token': 'refresh-one'});
          return http.Response(
            jsonEncode({
              'access_token': 'access-two',
              'refresh_token': 'refresh-two',
            }),
            200,
          );
        }
        if (request.url.path == '/obras/buscar') {
          catalogCalls++;
          if (catalogCalls == 1) {
            expect(
              request.headers['authorization'],
              'Bearer expired-token',
            );
            return http.Response('{}', 401);
          }
          expect(request.headers['authorization'], 'Bearer access-two');
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 7, 'nome': 'Obra atualizada', 'imagem': 'cover.webp'},
              ],
            }),
            200,
          );
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final page = await source.browse();

    expect(page.items.single.title, 'Obra atualizada');
    expect(refreshCalls, 1);
    expect(catalogCalls, 2);
  });

  test('updated catalog uses the Vite API with pagination and normalized cards',
      () async {
    late http.Request captured;
    final source = MediocrescanSource(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 18379,
                'nome': 'Garoto da Ressurreição',
                'imagem': 'cover.webp',
                'total_capitulos': 45,
                'capitulo_numero': 45,
                'formato': {'id': 5, 'nome': 'Comic'},
                'status': {'id': 1, 'nome': 'Em andamento'},
                'reacoes': {'amei': 2},
              },
            ],
            'pagination': {'hasNextPage': true},
          }),
          200,
        );
      }),
    );

    final page = await source.browse(
      filter: MangaCatalogFilter.recent,
      cursor: '2',
    );

    expect(captured.url.path, '/obras/atualizadas-recentes');
    expect(captured.url.queryParameters['limit'], '24');
    expect(captured.url.queryParameters['offset'], '24');
    expect(captured.url.queryParameters['formato'], '1,3,4,5,13');
    expect(captured.headers['x-app-key'], 'toons-mediocre-app');
    expect(captured.headers['x-client-platform'], 'app');
    expect(page.nextCursor, '3');
    expect(page.items.single.subtitle, '45 Ch • Comic • Ongoing • 10');
    expect(
      page.items.single.coverUri.toString(),
      'https://back2.mediocrescan.com/media/obras/18379/capa?f=cover.webp&w=520&q=75&fit=cover',
    );
  });

  test('search sends string instead of the obsolete q parameter', () async {
    late http.Request captured;
    final source = MediocrescanSource(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    await source.search('Solo Leveling', cursor: '3');

    expect(captured.url.path, '/obras/buscar');
    expect(captured.url.queryParameters['string'], 'Solo Leveling');
    expect(captured.url.queryParameters['q'], isNull);
    expect(captured.url.queryParameters['pagina'], '3');
    expect(captured.url.queryParameters['ordenarPor'], 'criada_em_desc');
  });

  test('details expose source metadata and accept current chapter field names',
      () async {
    final source = MediocrescanSource(
      client: MockClient((request) async {
        if (request.url.path == '/obras/7') {
          return http.Response(
            jsonEncode({
              'data': {
                'obr_id': 7,
                'obr_nome': 'Obra completa',
                'obr_imagem': 'cover.jpg',
                'obr_descricao': 'Descrição da obra',
                'total_capitulos': 12,
                'formato': {'formt_nome': 'Manga'},
                'obr_status': {'stt_nome': 'Finalizado'},
                'tags': [
                  {'tag_nome': 'Ação'},
                  {'tag_nome': 'Fantasia'},
                ],
                'nota': 8.7,
                'capitulos': [
                  {
                    'cap_id': 99,
                    'cap_num': 12,
                    'cap_nome': 'Final',
                    'cap_paginas_count': 18,
                    'cap_lancado_em': '2026-10-26T10:00:00Z',
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

    final details = await source.getDetails('7');

    expect(details.item.subtitle, '12 Ch • Manga • Completed • 8.7');
    expect(details.genres, ['Ação', 'Fantasia']);
    expect(details.status, MangaStatus.completed);
    expect(details.chapters.single.id, '99');
    expect(details.chapters.single.number, '12');
    expect(details.chapters.single.pages, '18');
    expect(details.chapters.single.publishedAt, '2026-10-26T10:00:00Z');
  });

  test('resolves a current chapter manifest and streams its native pages',
      () async {
    final temp = Directory.systemTemp.createTempSync('mediocre-reader-test-');
    addTearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final source = MediocrescanSource(
      documentsDirectoryProvider: () async => temp,
      client: MockClient((request) async {
        if (request.url.path == '/capitulos/584269') {
          return http.Response(
            jsonEncode({
              'data': {
                'cap_id': 584269,
                'cap_num': 1,
                'cap_tipo': 'imagem',
                'cap_uuid': 'chapter-uuid',
                'obra': {'obr_id': 20684},
              },
            }),
            200,
          );
        }
        if (request.url.path == '/obras/20684/capitulos/1/chapter-uuid.json') {
          return http.Response(
            jsonEncode([
              {'url': 'obras/20684/capitulos/1/page-1.webp'},
              {'url': 'obras/20684/capitulos/1/page-2.webp'},
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('.webp')) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    final pages = await source
        .readChapter(mangaId: '20684', chapterId: '584269')
        .toList();

    expect(pages, hasLength(2));
    expect(pages.every((page) => page.isLocal), isTrue);
    expect(File(pages.first.filePath!).readAsBytesSync(), [1, 2, 3]);
  });

  test('imports paginated Continue Reading and marks chapters remotely',
      () async {
    SharedPreferences.setMockInitialValues({
      'scrapper_session_mediocrescan': jsonEncode({'token': 'access-one'}),
    });
    final requests = <http.Request>[];
    final source = MediocrescanSource(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/readings/continue/all') {
          final page = request.url.queryParameters['pagina'];
          return http.Response(
            jsonEncode({
              'data': page == '1'
                  ? [
                      {
                        'obra': {
                          'id': 7,
                          'nome': 'Obra sincronizada',
                          'imagem': 'cover.webp',
                        },
                        'ultimo_capitulo_lido': {
                          'cap_id': 33,
                          'cap_num': 3,
                          'cap_nome': 'Terceiro',
                        },
                        'total_lidos': 3,
                      }
                    ]
                  : [],
              'pagination': {
                'totalPages': 2,
                'totalItems': 1,
                'itemsPerPage': 30,
              },
            }),
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/readings/mark') {
          expect(jsonDecode(request.body), {'obr_id': 7, 'cap_id': 33});
          expect(request.headers['authorization'], 'Bearer access-one');
          return http.Response('{}', 201);
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final history = await source.fetchReadingHistory();
    await source.markChapterRead(mangaId: '7', chapterId: '33');

    expect(history, hasLength(1));
    expect(history.single.details.item.id, '7');
    expect(history.single.details.item.title, 'Obra sincronizada');
    expect(history.single.lastReadChapter.id, '33');
    expect(history.single.lastReadChapter.number, '3');
    expect(history.single.readChapterCount, 3);
    expect(
      requests.where((request) => request.url.path == '/readings/continue/all'),
      hasLength(2),
    );
  });

  test('recent variants use the dedicated AI and adult catalog endpoints',
      () async {
    final requests = <http.Request>[];
    final source = MediocrescanSource(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );
    final variants = source.catalogVariants(MangaCatalogFilter.recent);

    expect(
      variants.map((variant) => variant.label),
      containsAll([
        'Comic',
        'AI translated comics',
        'Shoujo',
        'AI translated shoujo',
        'Manga',
        'Yaoi',
        'Yuri',
        'NSFW',
        'English',
      ]),
    );

    await source.browseVariant(MangaCatalogFilter.recent, '50005');
    await source.browseVariant(MangaCatalogFilter.recent, '10');

    expect(requests[0].url.path, '/obras/atualizadas-recentes-ia');
    expect(requests[0].url.queryParameters['formato'], '5');
    expect(requests[0].url.queryParameters['ocultar_adulto'], '1');
    expect(requests[1].url.path, '/obras/atualizadas-recentes');
    expect(requests[1].url.queryParameters['formato'], '10');
    expect(requests[1].url.queryParameters['ocultar_adulto'], isNull);
  });

  test('loads catalog status and tag options from the current API', () async {
    final source = MediocrescanSource(
      client: MockClient((request) async {
        if (request.url.path == '/obra-status') {
          return http.Response(
            jsonEncode({
              'data': [
                {'stt_id': 1, 'stt_nome': 'Em lançamento'},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/tags') {
          expect(request.url.queryParameters['formato'], '1,4,5,8,9,10,13');
          return http.Response(
            jsonEncode({
              'data': [
                {'tag_id': 7, 'tag_nome': 'Ação'},
              ],
            }),
            200,
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    final options = await source.getSearchOptions();

    expect(options.formats.length, 9);
    expect(options.statuses.single.label, 'Em lançamento');
    expect(options.tags.single.label, 'Ação');
  });

  test('catalog filters send formats chapters status tags and sort', () async {
    late http.Request captured;
    final source = MediocrescanSource(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    await source.filterCatalog(
      MangaSearchRequest(
        formats: const {'5', '10'},
        statuses: const {'1'},
        tags: const {'7', '8'},
        minimumChapters: 50,
        maximumChapters: 150,
        sort: MangaSearchSort.chapterCount,
      ),
      cursor: '2',
    );

    expect(captured.url.path, '/obras/buscar');
    expect(captured.url.queryParameters['pagina'], '2');
    expect(captured.url.queryParameters['formato'], '5,10');
    expect(captured.url.queryParameters['status'], '1');
    expect(captured.url.queryParameters['tags'], '7,8');
    expect(captured.url.queryParameters['minCapitulos'], '50');
    expect(captured.url.queryParameters['maxCapitulos'], '150');
    expect(captured.url.queryParameters['ordenarPor'], 'capitulos_desc');
    expect(captured.url.queryParameters['ocultar_adulto'], isNull);
  });
}
