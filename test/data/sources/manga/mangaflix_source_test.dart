import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/mangaflix_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps the Most Read and Trending home carousels', () async {
    final source = MangaFlixSource(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/browse');
        return _json({
          'data': [
            {
              'key': 'most-read',
              'items': [
                {
                  '_id': 'popular-1',
                  'name': 'Mais lido',
                  'poster': {'default_url': 'https://static.test/popular.jpg'},
                  'genres': [
                    {'name': 'Ação'}
                  ],
                }
              ],
            },
            {
              'key': 'trending',
              'items': [
                {
                  '_id': 'trend-1',
                  'name': 'Em alta',
                  'poster': {'default_url': 'https://static.test/trend.jpg'},
                }
              ],
            },
          ],
        });
      }),
    );

    final popular = await source.browse(filter: MangaCatalogFilter.popular);
    final trending = await source.browse(filter: MangaCatalogFilter.trending);

    expect(popular.items.single.id, 'popular-1');
    expect(popular.items.single.subtitle, 'Ação');
    expect(trending.items.single.title, 'Em alta');
  });

  test('exposes separately paginated General and Adult latest releases',
      () async {
    final requested = <Uri>[];
    final source = MangaFlixSource(
      client: MockClient((request) async {
        requested.add(request.url);
        final adult = request.url.queryParameters['type'] == 'adult';
        final page = request.url.queryParameters['page'] ?? '1';
        return http.Response(
          '''
          <html><body>
            <article>
              <a href="/br/manga/${adult ? 'adult' : 'general'}-$page">
                <img src="https://static.test/$page.jpg"
                     alt="Poster do Manga ${adult ? 'Obra adulta' : 'Obra geral'}">
              </a>
              <span>Capítulo 12</span>
            </article>
            <a href="/br/latest-releases?page=${int.parse(page) + 1}">Proxima</a>
          </body></html>
          ''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );

    expect(
      source.catalogVariants(MangaCatalogFilter.updated).map((e) => e.id),
      ['general', 'adult'],
    );
    final general = await source.browseVariant(
      MangaCatalogFilter.updated,
      'general',
    );
    final adult = await source.browseVariant(
      MangaCatalogFilter.updated,
      'adult',
      cursor: '2',
    );

    expect(general.items.single.id, 'general-1');
    expect(general.items.single.subtitle, '12 Ch');
    expect(adult.items.single.id, 'adult-2');
    expect(adult.nextCursor, '3');
    expect(requested.last.queryParameters, {'page': '2', 'type': 'adult'});
  });

  test('loads genre filters and paginates a category', () async {
    final source = MangaFlixSource(
      client: MockClient((request) async {
        if (request.url.path == '/v1/genres') {
          return _json({
            'data': [
              {'_id': 'action', 'name': 'Ação'},
              {'_id': 'adult', 'name': 'Adulto'},
            ],
          });
        }
        if (request.url.path == '/v1/genres/action/mangas/') {
          expect(request.url.queryParameters['offset'], '20');
          expect(request.url.queryParameters['limit'], '20');
          return _json({
            'data': [
              {'_id': 'm1', 'name': 'Obra de ação'}
            ],
            'metadata': {'total': 42},
          });
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final genres = await source.getGenres();
    expect(genres.singleWhere((genre) => genre.id == 'adult').isAdult, isTrue);
    final options = await source.getSearchOptions();
    expect(options.genres.map((genre) => genre.value), ['adult', 'action']);
    final page = await source.browseGenre('action', cursor: '2');
    expect(page.items.single.title, 'Obra de ação');
    expect(page.nextCursor, '3');
  });

  test('maps details, chapters and all native reader images', () async {
    final source = MangaFlixSource(
      client: MockClient((request) async {
        if (request.url.path == '/v1/mangas/work') {
          return _json({
            'data': {
              '_id': 'work',
              'name': 'Obra MangaFlix',
              'description': 'Descrição completa.',
              'poster': {'default_url': 'https://static.test/cover.jpg'},
              'genres': [
                {'name': 'Fantasia'}
              ],
              'chapters': [
                {
                  '_id': 'c2',
                  'name': '',
                  'number': '2',
                  'iso_date': '2026-10-31T12:00:00.000Z',
                  'owners': [
                    {'name': 'Scan Teste'}
                  ],
                },
                {
                  '_id': 'c1',
                  'name': 'Prólogo',
                  'number': '1',
                  'owners': [
                    {'name': 'Scan Teste'}
                  ],
                },
              ],
            },
          });
        }
        if (request.url.path == '/v1/chapters/c1') {
          expect(request.url.queryParameters['selected_language'], 'pt-br');
          return _json({
            'data': {
              'images': [
                {'default_url': 'https://static.test/page-1.webp'},
                {'default_url': 'https://static.test/page-2.webp'},
              ],
            },
          });
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final details = await source.getDetails('/br/manga/work');
    expect(details.description, 'Descrição completa.');
    expect(details.author, 'Scan Teste');
    expect(details.genres, ['Fantasia']);
    expect(details.chapters.first.title, 'Capítulo 2');
    expect(await source.nextChapterId('work', 'c1'), 'c2');

    final pages =
        await source.readChapter(mangaId: 'work', chapterId: 'c1').toList();
    expect(pages, hasLength(2));
    expect(pages.last.uri, Uri.parse('https://static.test/page-2.webp'));
    expect(pages.last.headers['Referer'], 'https://mangaflix.net/');
  });
}

http.Response _json(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
