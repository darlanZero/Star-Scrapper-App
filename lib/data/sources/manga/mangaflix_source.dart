import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// MangaFlix — mixed PT-BR catalog backed primarily by the public v1 API.
///
/// The site's adult latest-releases tab is server rendered and is not exposed
/// by the public API, so both latest variants are parsed from the canonical web
/// route. Details, search, genres, chapters and reader images remain API based.
class MangaFlixSource
    implements
        MangaSource,
        GenreBrowsableMangaSource,
        FilterableMangaSource,
        VariantCatalogMangaSource,
        ChapterNavigationMangaSource {
  static const _site = 'https://mangaflix.net';
  static const _api = 'https://api.mangaflix.net/v1/';
  static const _pageSize = 20;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _latestVariants = [
    MangaCatalogVariant(id: 'general', label: 'Geral'),
    MangaCatalogVariant(id: 'adult', label: 'Adulto'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final Uri _apiUri;
  List<MangaGenre>? _genreCache;
  final Map<String, MangaDetails> _detailsCache = {};

  MangaFlixSource({http.Client? client, Uri? baseUri, Uri? apiUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site),
        _apiUri = apiUri ?? Uri.parse(_api);

  @override
  String get id => 'mangaflix';

  @override
  String get name => 'MangaFlix';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Origin': _baseUri.origin,
        'Referer': _baseUri.resolve('/br/browse').toString(),
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '${_baseUri.origin}/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.updated,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.updated ? _latestVariants : const [];

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    if (filter != MangaCatalogFilter.updated ||
        !_latestVariants.any((variant) => variant.id == variantId)) {
      return browse(filter: filter, cursor: cursor);
    }
    return _latest(adult: variantId == 'adult', cursor: cursor);
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    return switch (filter) {
      MangaCatalogFilter.popular => _browseSection('most-read'),
      MangaCatalogFilter.trending => _browseSection('trending'),
      MangaCatalogFilter.updated ||
      MangaCatalogFilter.recent ||
      MangaCatalogFilter.added =>
        _latest(adult: false, cursor: cursor),
      MangaCatalogFilter.alphabetical => filterCatalog(
          MangaSearchRequest(sort: MangaSearchSort.titleAscending),
          cursor: cursor,
        ),
    };
  }

  Future<MangaCatalogPage> _browseSection(String key) async {
    final payload = _map(await _getJson('/browse'));
    final sections = _list(payload['data']);
    final section = sections
        .map(_map)
        .where((candidate) => candidate['key']?.toString() == key)
        .firstOrNull;
    final items = _list(section?['items'])
        .map((raw) => _catalogItem(_map(raw)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    return MangaCatalogPage(items: items);
  }

  Future<MangaCatalogPage> _latest({
    required bool adult,
    String? cursor,
  }) async {
    final page = _page(cursor);
    final uri = _baseUri.resolve('/br/latest-releases').replace(
      queryParameters: {
        if (page > 1) 'page': '$page',
        if (adult) 'type': 'adult',
      },
    );
    final response = await _client.get(uri, headers: _htmlHeaders(uri));
    _ensureSuccess(response, uri);
    final document = html_parser.parse(response.body);
    final seen = <String>{};
    final items = <MangaCatalogItem>[];
    for (final article in document.querySelectorAll('article')) {
      final link = article.querySelector('a[href*="/manga/"]');
      final href = link?.attributes['href'];
      final mangaId = href == null ? '' : _idFromPath(href);
      if (mangaId.isEmpty || !seen.add(mangaId)) continue;
      final image = article.querySelector('img');
      final alt = image?.attributes['alt']?.trim() ?? '';
      final title = alt.replaceFirst(
        RegExp(r'^Poster do Mang[aá]\s*', caseSensitive: false),
        '',
      );
      final text = article.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final chapter = RegExp(
        r'Cap[ií]tulo\s+([^\s—-]+)',
        caseSensitive: false,
      ).firstMatch(text)?.group(1);
      items.add(
        MangaCatalogItem(
          id: mangaId,
          title: title.isNotEmpty ? title : link!.text.trim(),
          coverUri: _uri(image?.attributes['src']),
          subtitle: chapter == null ? null : '$chapter Ch',
        ),
      );
    }
    final nextHref = document
        .querySelectorAll('a')
        .where((anchor) => anchor.text.trim().toLowerCase() == 'proxima')
        .map((anchor) => anchor.attributes['href'])
        .whereType<String>()
        .firstOrNull;
    return MangaCatalogPage(
      items: items,
      nextCursor: nextHref == null ? null : '${page + 1}',
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return browse(filter: MangaCatalogFilter.updated);
    final payload = _map(
      await _getJson(
        '/search/mangas?query=${Uri.encodeQueryComponent(normalized)}&selected_language=pt-br',
      ),
    );
    final data = _map(payload['data']);
    final items = _list(data['works'])
        .map((raw) => _catalogItem(_map(raw)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    return MangaCatalogPage(items: items);
  }

  @override
  Future<List<MangaGenre>> getGenres() async {
    final cached = _genreCache;
    if (cached != null) return cached;
    final payload = _map(
      await _getJson('/genres?include_adult=true&selected_language=pt-br'),
    );
    final genres = _list(payload['data'])
        .map((raw) {
          final map = _map(raw);
          final name = map['name']?.toString().trim() ?? '';
          return MangaGenre(
            id: map['_id']?.toString() ?? '',
            name: name,
            isAdult: _adultGenre(name),
          );
        })
        .where((genre) => genre.id.isNotEmpty && genre.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _genreCache = List.unmodifiable(genres);
  }

  @override
  Future<MangaCatalogPage> browseGenre(
    String genreId, {
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final page = _page(cursor);
    final offset = (page - 1) * _pageSize;
    final payload = _map(
      await _getJson(
        '/genres/${Uri.encodeComponent(genreId)}/mangas/'
        '?offset=$offset&limit=$_pageSize&include_adult=true',
      ),
    );
    final items = _list(payload['data'])
        .map((raw) => _catalogItem(_map(raw)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    final total = _integer(_map(payload['metadata'])['total']) ?? items.length;
    return MangaCatalogPage(
      items: items,
      nextCursor: offset + items.length < total ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final genres = await getGenres();
    return MangaSearchOptions(
      genres: genres.map(
          (genre) => MangaFilterOption(value: genre.id, label: genre.name)),
      sorts: const [
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.popular,
      ],
      supportsChapterRange: false,
      supportsAdultMode: true,
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    if (request.genres.isNotEmpty) {
      return browseGenre(request.genres.first, cursor: cursor);
    }
    if (request.adultMode == MangaAdultMode.only) {
      return _latest(adult: true, cursor: cursor);
    }
    return switch (request.sort) {
      MangaSearchSort.popular => browse(filter: MangaCatalogFilter.popular),
      _ => _latest(adult: false, cursor: cursor),
    };
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final normalizedId = _idFromPath(mangaId);
    final cached = _detailsCache[normalizedId];
    if (cached != null) return cached;
    final payload = _map(await _getJson('/mangas/$normalizedId'));
    final data = _map(payload['data']);
    final chapters = _list(data['chapters'])
        .map((raw) => _chapter(_map(raw)))
        .where((chapter) => chapter.id.isNotEmpty)
        .toList(growable: false);
    final owners = chapters
        .map((chapter) => chapter.uploader)
        .whereType<String>()
        .where((owner) => owner.isNotEmpty)
        .toList();
    final details = MangaDetails(
      item: _catalogItem(data),
      description: data['description']?.toString().trim() ?? '',
      genres: _list(data['genres'])
          .map(_map)
          .map((genre) => genre['name']?.toString().trim() ?? '')
          .where((genre) => genre.isNotEmpty),
      author: owners.firstOrNull,
      externalUri: _baseUri.resolve('/br/manga/$normalizedId'),
      chapters: chapters,
    );
    _detailsCache[normalizedId] = details;
    return details;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final id = _idFromPath(chapterId);
    final payload = _map(
      await _getJson('/chapters/$id?selected_language=pt-br'),
    );
    final images = _list(_map(payload['data'])['images']);
    for (final raw in images) {
      final uri = _uri(_map(raw)['default_url']);
      if (uri != null) {
        yield MangaReaderPage.network(uri, headers: coverImageHeaders);
      }
    }
  }

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) async {
    final chapters = (await getDetails(mangaId)).chapters;
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    return index > 0 ? chapters[index - 1].id : null;
  }

  @override
  Future<String?> previousChapterId(
    String mangaId,
    String currentChapterId,
  ) async {
    final chapters = (await getDetails(mangaId)).chapters;
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    return index >= 0 && index + 1 < chapters.length
        ? chapters[index + 1].id
        : null;
  }

  MangaCatalogItem _catalogItem(Map<String, dynamic> data) {
    final chapters = _list(data['chapters']);
    final latest = chapters.isEmpty ? null : _map(chapters.first)['number'];
    final genres = _list(data['genres']);
    final genreLabel = genres.isEmpty
        ? null
        : (_map(genres.first)['name'] ?? genres.first)?.toString();
    final subtitle = mangaCatalogSubtitle(
      latestChapter: latest?.toString(),
      format: genreLabel,
    );
    return MangaCatalogItem(
      id: data['_id']?.toString() ?? '',
      title: data['name']?.toString().trim() ?? '',
      coverUri: _uri(_map(data['poster'])['default_url']),
      subtitle: subtitle.isEmpty ? null : subtitle,
    );
  }

  MangaChapter _chapter(Map<String, dynamic> data) {
    final number = data['number']?.toString().trim() ?? '';
    final name = data['name']?.toString().trim() ?? '';
    final owners = _list(data['owners'])
        .map(_map)
        .map((owner) => owner['name']?.toString().trim() ?? '')
        .where((owner) => owner.isNotEmpty)
        .join(', ');
    return MangaChapter(
      id: data['_id']?.toString() ?? '',
      title: name.isEmpty ? 'Capítulo $number' : name,
      number: number,
      language: 'pt-br',
      uploader: owners.isEmpty ? null : owners,
      publishedAt: data['iso_date']?.toString(),
    );
  }

  Future<Object?> _getJson(String path) async {
    final uri =
        _apiUri.resolve(path.startsWith('/') ? path.substring(1) : path);
    final response = await _client.get(uri, headers: requestHeaders);
    _ensureSuccess(response, uri);
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Map<String, String> _htmlHeaders(Uri uri) => {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': _baseUri.resolve('/br/browse').toString(),
        'User-Agent': _userAgent,
      };

  static void _ensureSuccess(http.Response response, Uri uri) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'MangaFlix request failed (${response.statusCode})',
        uri,
      );
    }
  }

  int _page(String? cursor) {
    final page = int.tryParse(cursor ?? '1') ?? 1;
    return page < 1 ? 1 : page;
  }

  String _idFromPath(String value) {
    final uri = Uri.tryParse(value);
    final segments = uri?.pathSegments.where((segment) => segment.isNotEmpty);
    return segments == null || segments.isEmpty ? value : segments.last;
  }

  Uri? _uri(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return _baseUri.resolve(text);
  }

  static bool _adultGenre(String value) => RegExp(
        r'^(?:\+18|adult|adulto|hentai|mature|maduro|doujinshi)$',
        caseSensitive: false,
      ).hasMatch(value.trim());

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<dynamic> _list(Object? value) =>
      value is List ? List<dynamic>.from(value) : const [];
}
