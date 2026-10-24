import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/hdoujin_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps requested API catalogs, search, metadata and pagination',
      () async {
    final requests = <Uri>[];
    final source = HDoujinSource(
      baseUri: Uri.parse('https://hdoujin.test'),
      apiUri: Uri.parse('https://api.hdoujin.test'),
      client: MockClient((request) async {
        requests.add(request.url);
        return _jsonResponse(_catalogJson);
      }),
    );

    final popular = await source.browse();
    await source.browse(filter: MangaCatalogFilter.updated);
    await source.browse(filter: MangaCatalogFilter.added);
    await source.browse(filter: MangaCatalogFilter.recent);
    await source.search('summer resort', cursor: '2');

    expect(requests[0].toString(), 'https://api.hdoujin.test/books/popular');
    expect(requests[1].queryParameters, {'cat': '4'});
    expect(requests[2].queryParameters, {'x': '1'});
    expect(requests[3].queryParameters, {'cat': '2'});
    expect(requests[4].queryParameters, {'s': 'summer resort', 'page': '2'});
    expect(popular.items.single.id, '237449/5e8652e20a66');
    expect(popular.items.single.subtitle, '41 pages • English');
    expect(popular.items.single.coverUri.toString(),
        'https://cdn.test/cover.webp');
    expect(popular.nextCursor, '2');
  });

  test('parses API details and keeps JavaScript reader as WebView fallback',
      () async {
    final source = HDoujinSource(
      baseUri: Uri.parse('https://hdoujin.test'),
      apiUri: Uri.parse('https://api.hdoujin.test'),
      client: MockClient((request) async => _jsonResponse(_detailsJson)),
    );

    final details = await source.getDetails('237449/5e8652e20a66');

    expect(details.item.title, 'Summer Resort');
    expect(details.item.subtitle, '2 pages • English • Doujinshi');
    expect(
        details.item.coverUri.toString(), 'https://cdn.test/thumb/cover.webp');
    expect(details.alternativeTitles.single[''], 'サマーリゾート');
    expect(details.genres, ['big ass', 'big breasts', 'rough translation']);
    expect(details.artist, 'Torifune');
    expect(details.author, 'Bird Circle');
    expect(details.status, MangaStatus.completed);
    expect(details.chapters.single.language, 'english');
    expect(details.chapters.single.pages, '2');
    expect(
      source.chapterWebUri(
        mangaId: details.item.id,
        chapterId: details.chapters.single.id,
      ),
      Uri.parse('https://hdoujin.test/g/237449/5e8652e20a66/read/1'),
    );
  });

  test('lists tags A-Z and searches one cached artist/circle index', () async {
    var filterRequests = 0;
    final requests = <Uri>[];
    final source = HDoujinSource(
      baseUri: Uri.parse('https://hdoujin.test'),
      apiUri: Uri.parse('https://api.hdoujin.test'),
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/books/tags') {
          return _jsonResponse(_tagsJson);
        }
        if (request.url.path == '/books/tags/filters') {
          filterRequests++;
          return _jsonResponse(_filtersJson);
        }
        return _jsonResponse(_catalogJson);
      }),
    );

    final tags = await source.getTaxonomy(MangaTaxonomyKind.tag);
    expect(tags.map((tag) => tag.name), ['ahegao', 'big breasts']);
    expect(tags.last.titleCount, 88100);
    expect(await source.getTaxonomy(MangaTaxonomyKind.artist, query: 'h'),
        isEmpty);

    final artists =
        await source.getTaxonomy(MangaTaxonomyKind.artist, query: 'hit');
    final cached =
        await source.getTaxonomy(MangaTaxonomyKind.artist, query: 'torif');
    expect(artists.map((artist) => artist.name), ['hitman', 'hitori']);
    expect(cached.map((artist) => artist.name), ['torifune']);

    final circles =
        await source.getTaxonomy(MangaTaxonomyKind.circle, query: 'bird');
    expect(circles.single.name, 'bird circle');
    expect(filterRequests, 1);

    await source.browseTaxonomy(MangaTaxonomyKind.artist, artists.first.id);
    expect(requests.last.queryParameters['s'], 'artist:hitman');
  });
}

http.Response _jsonResponse(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _catalogJson = {
  'entries': [
    {
      'id': 237449,
      'key': '5e8652e20a66',
      'title': 'Summer Resort',
      'language': 2,
      'pages': 41,
      'thumbnail': {'path': 'https://cdn.test/cover.webp'}
    }
  ],
  'page': 1,
  'limit': 1,
  'total': 2,
};

const _detailsJson = {
  'id': 237449,
  'key': '5e8652e20a66',
  'created_at': 1792125180000,
  'category': 2,
  'title': 'Summer Resort',
  'subtitle': 'サマーリゾート',
  'thumbnails': {
    'base': 'https://cdn.test/thumb',
    'main': {'path': '/cover.webp'},
    'entries': [
      {'path': '/1.webp'},
      {'path': '/2.webp'}
    ]
  },
  'tags': [
    {'namespace': 1, 'name': 'Torifune'},
    {'namespace': 2, 'name': 'Bird Circle'},
    {'namespace': 9, 'name': 'big ass'},
    {'namespace': 9, 'name': 'big breasts'},
    {'namespace': 11, 'name': 'english'},
    {'namespace': 11, 'name': 'translated'},
    {'namespace': 12, 'name': 'rough translation'},
  ]
};

const _tagsJson = [
  {'namespace': 9, 'name': 'big breasts', 'count': 88000},
  {'namespace': 8, 'name': 'ahegao', 'count': 26100},
  {'namespace': 8, 'name': 'big breasts', 'count': 100},
];

const _filtersJson = [
  {'id': 1, 'namespace': 1, 'name': 'hitman'},
  {'id': 2, 'namespace': 1, 'name': 'hitori'},
  {'id': 3, 'namespace': 1, 'name': 'torifune'},
  {'id': 4, 'namespace': 2, 'name': 'bird circle'},
];
