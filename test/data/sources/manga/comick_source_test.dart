import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/comick_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps popular Webtoon and Manga variants to exact API filters',
      () async {
    final requested = <Uri>[];
    final source = ComickSource(
      client: MockClient((request) async {
        requested.add(request.url);
        return _json({
          'data': [
            {
              'slug': 'solo-leveling',
              'title': 'Solo Leveling',
              'default_thumbnail': 'https://meo.test/cover.jpg',
            }
          ],
          'next_cursor': 'next-page',
        });
      }),
    );

    expect(
      source.catalogVariants(MangaCatalogFilter.popular).map((e) => e.id),
      ['all', 'webtoon', 'manga'],
    );
    final webtoon = await source.browseVariant(
      MangaCatalogFilter.popular,
      'webtoon',
    );
    expect(webtoon.items.single.title, 'Solo Leveling');
    expect(webtoon.nextCursor, 'next-page');
    expect(requested.last.queryParametersAll['genres'], ['long-strip']);
    expect(requested.last.queryParameters['time'], '180');

    await source.browseVariant(
      MangaCatalogFilter.popular,
      'manga',
      cursor: 'cursor-2',
    );
    expect(requested.last.queryParametersAll['country'], ['jp']);
    expect(requested.last.queryParameters['cursor'], 'cursor-2');
  });

  test('classifies metadata and maps every structured search filter', () async {
    late Uri searchUri;
    final source = ComickSource(
      client: MockClient((request) async {
        if (request.url.path == '/api/metadata') {
          return _json({
            'genres': [
              {'name': 'Action', 'slug': 'action'},
              {'name': 'Long Strip', 'slug': 'long-strip'},
              {'name': 'Reincarnation', 'slug': 'reincarnation'},
            ],
            'tags': [
              {'name': 'Strong Male Lead', 'slug': 'strong-male-lead'},
              {'name': 'Villainess', 'slug': 'villainess'},
            ],
          });
        }
        searchUri = request.url;
        return _json({'data': [], 'next_cursor': null});
      }),
    );

    final options = await source.getSearchOptions();
    expect(options.genres.map((e) => e.value), ['action']);
    expect(options.formats.map((e) => e.value), ['long-strip']);
    expect(options.themes.map((e) => e.value), ['reincarnation']);
    expect(
      options.tags.map((e) => e.value),
      ['strong-male-lead', 'villainess'],
    );
    expect(options.createdAtPresets.map((e) => e.value), contains('180'));

    await source.filterCatalog(
      MangaSearchRequest(
        types: {'kr'},
        formats: {'long-strip'},
        statuses: {'1'},
        tags: {'strong-male-lead'},
        genres: {'action'},
        themes: {'reincarnation'},
        demographics: {'1'},
        createdWithin: '180',
        minimumYear: 2018,
        maximumYear: 2026,
        minimumChapters: 25,
        sort: MangaSearchSort.rating,
        adultMode: MangaAdultMode.only,
        sortDirection: MangaSortDirection.ascending,
      ),
    );

    expect(
      searchUri.queryParametersAll['genres'],
      containsAll(['action', 'reincarnation', 'long-strip']),
    );
    expect(searchUri.queryParametersAll['tags'], ['strong-male-lead']);
    expect(searchUri.queryParametersAll['country'], ['kr']);
    expect(searchUri.queryParameters['demographic'], '1');
    expect(searchUri.queryParameters['time'], '180');
    expect(searchUri.queryParameters['minimum'], '25');
    expect(searchUri.queryParameters['status'], '1');
    expect(searchUri.queryParameters['from'], '2018');
    expect(searchUri.queryParameters['to'], '2026');
    expect(searchUri.queryParameters['content_rating'], 'erotica');
    expect(searchUri.queryParameters['order_by'], 'rating');
    expect(searchUri.queryParameters['order_direction'], 'asc');
  });

  test('maps embedded details, every chapter page and native reader images',
      () async {
    final source = ComickSource(
      client: MockClient((request) async {
        if (request.url.path == '/comic/test-work') {
          return _html('''
            <script type="application/json" id="comic-data">${jsonEncode({
                'title': 'Test Work',
                'slug': 'test-work',
                'default_thumbnail': 'https://meo.test/cover.jpg',
                'status': 2,
                'translation_completed': true,
                'authors': [
                  {'name': 'Author A'}
                ],
                'artists': [
                  {'name': 'Artist B'}
                ],
                'desc': '<p>First line.</p><p>Second line.</p>',
                'content_rating': 'suggestive',
                'country': 'jp',
                'md_comic_md_genres': [
                  {
                    'md_genres': {'name': 'Action'}
                  }
                ],
                'md_titles': {
                  'ja': {'title': 'テスト'}
                },
              })}</script>
          ''');
        }
        if (request.url.path == '/api/comics/test-work/chapter-list') {
          final page = request.url.queryParameters['page'];
          return _json({
            'data': [
              {
                'hid': page == '2' ? 'hid-1' : 'hid-2',
                'chap': page == '2' ? '1' : '2',
                'vol': '1',
                'lang': page == '2' ? 'pt-br' : 'en',
                'title': page == '2' ? 'Start' : null,
                'created_at': '2026-10-31T12:00:00Z',
                'group_name': ['Scan Test'],
              }
            ],
            'pagination': {
              'current_page': page == '2' ? 2 : 1,
              'last_page': 2,
            },
          });
        }
        if (request.url.path.contains('/hid-1-chapter-1-pt-br')) {
          return _html('''
            <script type="application/json" id="sv-data">${jsonEncode({
                'chapter': {
                  'images': [
                    {'url': 'https://meo.test/page-1.webp'},
                    {'url': 'https://meo.test/page-2.webp'},
                  ],
                },
              })}</script>
          ''');
        }
        fail('Unexpected request: ${request.url}');
      }),
    );

    final details = await source.getDetails('test-work');
    expect(details.status, MangaStatus.completed);
    expect(details.author, 'Author A');
    expect(details.artist, 'Artist B');
    expect(details.genres, ['Manga', 'Suggestive', 'Action']);
    expect(details.alternativeTitles.single['und'], 'テスト');
    expect(details.chapters, hasLength(2));
    expect(details.chapters.last.language, 'pt-br');
    expect(
      await source.nextChapterId('test-work', details.chapters.last.id),
      details.chapters.first.id,
    );

    final pages = await source
        .readChapter(
          mangaId: 'test-work',
          chapterId: details.chapters.last.id,
        )
        .toList();
    expect(pages, hasLength(2));
    expect(pages.last.uri, Uri.parse('https://meo.test/page-2.webp'));
    expect(pages.first.headers['Referer'], contains('hid-1-chapter-1-pt-br'));
  });

  test('recovers a Cloudflare-blocked API request through browser JSON',
      () async {
    final source = ComickSource(
      client: MockClient((_) async => http.Response('Just a moment...', 403)),
      browserHtmlLoader: (uri, userAgent) async => '''
        <html><body><pre>${jsonEncode({
            'data': [
              {
                'slug': 'browser-result',
                'title': 'Browser Result',
                'default_thumbnail': 'https://meo.test/browser.jpg',
              }
            ],
            'next_cursor': null,
          })}</pre></body></html>
      ''',
    );

    final page = await source.browse(filter: MangaCatalogFilter.updated);
    expect(page.items.single.id, 'browser-result');
  });

  test('retries the API after the browser establishes a clearance cookie',
      () async {
    var nativeRequests = 0;
    final source = ComickSource(
      client: MockClient((_) async => http.Response('Just a moment...', 403)),
      binaryLoader: (uri, headers) async {
        nativeRequests += 1;
        final body = nativeRequests == 1
            ? 'Performing security verification'
            : jsonEncode({
                'data': [
                  {
                    'slug': 'verified-result',
                    'title': 'Verified Result',
                    'default_thumbnail': 'https://meo.test/verified.jpg',
                  }
                ],
                'next_cursor': null,
              });
        return (
          statusCode: 200,
          body: Uint8List.fromList(utf8.encode(body)),
          headers: const <String, String>{},
        );
      },
      browserHtmlLoader: (_, __) async =>
          '<html><body>Performing security verification</body></html>',
    );

    final page = await source.browse(filter: MangaCatalogFilter.updated);
    expect(page.items.single.id, 'verified-result');
    expect(nativeRequests, 2);
  });
}

http.Response _json(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _html(String value) => http.Response(
      value,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
