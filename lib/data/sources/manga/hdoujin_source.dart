import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/infrastructure/webview/browser_html_loader.dart';

/// Multilingual, adult-only HDoujin catalog.
///
/// The public site is a SPA. Catalogs and metadata come from its JSON API,
/// while the JavaScript/blob-based reader is opened through the shared WebView.
class HDoujinSource
    implements
        MangaSource,
        WebViewChapterMangaSource,
        TaxonomyBrowsableMangaSource {
  static final Uri _defaultBaseUri = Uri.parse('https://hdoujin.org');
  static final Uri _defaultApiUri = Uri.parse('https://api.hdoujin.org');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Uri _apiUri;
  final Map<MangaTaxonomyKind, List<MangaTaxonomyOption>> _taxonomyCache = {};
  Future<List<Map<String, dynamic>>>? _filterIndexFuture;

  HDoujinSource({http.Client? client, Uri? baseUri, Uri? apiUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _apiUri = apiUri ?? _defaultApiUri;

  @override
  String get id => 'hdoujin';
  @override
  String get name => 'HDoujin';
  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'application/json',
        'Accept-Language': 'en-US,en;q=0.9,*;q=0.5',
        'Origin': _baseUri.origin,
        'Referer': '${_baseUri.origin}/',
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Referer': '${_baseUri.origin}/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.popular,
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
        MangaCatalogFilter.recent,
      ];

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.artist,
        MangaTaxonomyKind.circle,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    final path =
        filter == MangaCatalogFilter.popular ? '/books/popular' : '/books';
    final parameters = <String, String>{
      if (filter == MangaCatalogFilter.updated) 'cat': '4',
      if (filter == MangaCatalogFilter.added) 'x': '1',
      if (filter == MangaCatalogFilter.recent) 'cat': '2',
    };
    return _loadCatalog(_apiPageUri(path, parameters, cursor));
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return MangaCatalogPage(items: const []);
    return _loadCatalog(_apiPageUri('/books', {'s': normalized}, cursor));
  }

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final normalized = query.trim().toLowerCase();
    if (kind != MangaTaxonomyKind.tag && normalized.length < 2) return const [];
    final entries = await _taxonomyEntries(kind);
    if (normalized.isEmpty) return entries;
    final matches = entries
        .where((entry) => entry.name.toLowerCase().contains(normalized))
        .toList(growable: false)
      ..sort((a, b) {
        final aStarts = a.name.toLowerCase().startsWith(normalized);
        final bStarts = b.name.toLowerCase().startsWith(normalized);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        final count = (b.titleCount ?? 0).compareTo(a.titleCount ?? 0);
        return count != 0
            ? count
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return kind == MangaTaxonomyKind.tag
        ? matches
        : matches.take(80).toList(growable: false);
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) {
    final prefix = switch (kind) {
      MangaTaxonomyKind.tag => 'tag:',
      MangaTaxonomyKind.artist => 'artist:',
      MangaTaxonomyKind.circle => 'circle:',
    };
    final search = taxonomyId.startsWith(prefix)
        ? taxonomyId
        : '$prefix${taxonomyId.trim()}';
    return _loadCatalog(_apiPageUri('/books', {'s': search}, cursor));
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final idParts = _galleryId(_galleryUri(mangaId)).split('/');
    if (idParts.length != 2 || idParts.any((part) => part.isEmpty)) {
      throw ArgumentError.value(
          mangaId, 'mangaId', 'Invalid HDoujin gallery id');
    }
    final json = await _getJson(
      _apiUri.resolve('/books/detail/${idParts[0]}/${idParts[1]}'),
    );
    if (json is! Map) {
      throw StateError('HDoujin returned invalid details for "$mangaId".');
    }
    final details = Map<String, dynamic>.from(json);
    final title = _string(details['title']);
    if (title.isEmpty) {
      throw StateError('HDoujin did not return details for "$mangaId".');
    }

    final tags = _mapList(details['tags']);
    final galleryId = '${details['id']}/${details['key']}';
    final galleryUri = _galleryUri(galleryId);
    final thumbnails = _map(details['thumbnails']);
    final pageTotal = _mapList(thumbnails?['entries']).length;
    final pageCount = pageTotal == 0 ? null : '$pageTotal';
    final languageTags = _namesForNamespace(tags, 11)
        .where((name) => name.toLowerCase() != 'translated')
        .toList(growable: false);
    final language = languageTags.firstOrNull ?? 'all';
    final format = switch (_int(details['category'])) {
      1 => 'Manga',
      2 => 'Doujinshi',
      _ => null,
    };
    final genres = <String>{
      ..._namesForNamespace(tags, 8),
      ..._namesForNamespace(tags, 9),
      ..._namesForNamespace(tags, 10),
      ..._namesForNamespace(tags, 12),
    }.toList(growable: false);
    final artists = _namesForNamespace(tags, 1);
    final circles = _namesForNamespace(tags, 2);
    final alternate = _string(details['subtitle']);
    final createdAt = _int(details['created_at']);
    final subtitleParts = <String>[
      if (pageCount != null) '$pageCount pages',
      if (language != 'all') _capitalize(language),
      if (format != null) format,
    ];

    return MangaDetails(
      item: MangaCatalogItem(
        id: galleryId,
        title: title,
        coverUri: _detailCoverUri(thumbnails),
        subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
      ),
      alternativeTitles: [
        if (alternate.isNotEmpty && alternate != title) {'': alternate},
      ],
      genres: genres,
      author: circles.isEmpty ? null : circles.join(', '),
      artist: artists.isEmpty ? null : artists.join(', '),
      status: MangaStatus.completed,
      externalUri: galleryUri,
      chapters: [
        MangaChapter(
          id: '${galleryUri.path}/read/1',
          title: 'Complete gallery',
          number: '1',
          language: language,
          pages: pageCount,
          publishedAt: createdAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true)
                  .toIso8601String(),
        ),
      ],
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final readerUri = _readerUri(mangaId, chapterId);
    var pageCount = 0;
    try {
      final details = await getDetails(mangaId);
      final chapter = details.chapters.firstOrNull;
      pageCount = int.tryParse(chapter?.pages ?? '') ?? 0;
    } catch (_) {
      // Fall back to letting the native driver discover the page count.
      pageCount = 0;
    }
    yield* BrowserHtmlLoader.readerPages(readerUri, _userAgent, pageCount)
        .map((path) => MangaReaderPage.file(path));
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) {
    final parsed = Uri.tryParse(chapterId);
    if (parsed != null && parsed.hasScheme) return parsed;
    if (chapterId.startsWith('/')) return _baseUri.resolve(chapterId);
    return _galleryUri(mangaId).resolve(chapterId);
  }

  /// Resolves the absolute reader URL (`.../g/{id}/{key}/read/{n}`), ensuring a
  /// concrete page segment so the SPA deep-links to the reader.
  Uri _readerUri(String mangaId, String chapterId) {
    final base = chapterWebUri(mangaId: mangaId, chapterId: chapterId);
    if (base.pathSegments.contains('read')) return base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '${path}read/1');
  }

  Future<MangaCatalogPage> _loadCatalog(Uri uri) async {
    final json = await _getJson(uri);
    if (json is! Map) {
      throw StateError('HDoujin returned an invalid catalog payload.');
    }
    final payload = Map<String, dynamic>.from(json);
    final items = _mapList(payload['entries'])
        .map((entry) {
          final id = _string(entry['id']);
          final key = _string(entry['key']);
          final pages = _int(entry['pages']);
          final language = _catalogLanguage(_int(entry['language']));
          final subtitle = <String>[
            if (pages != null && pages > 0) '$pages pages',
            if (language != null) language,
          ];
          return MangaCatalogItem(
            id: '$id/$key',
            title: _string(entry['title']),
            coverUri: _uri(_map(entry['thumbnail'])?['path']),
            subtitle: subtitle.isEmpty ? null : subtitle.join(' • '),
          );
        })
        .where((item) => item.id != '/' && item.title.isNotEmpty)
        .toList();

    final page =
        _int(payload['page']) ?? _pageFromCursor(uri.queryParameters['page']);
    final limit = _int(payload['limit']) ?? items.length;
    final total = _int(payload['total']) ?? items.length;
    return MangaCatalogPage(
      items: items,
      nextCursor: limit > 0 && page * limit < total ? '${page + 1}' : null,
    );
  }

  Future<List<MangaTaxonomyOption>> _taxonomyEntries(
    MangaTaxonomyKind kind,
  ) async {
    final cached = _taxonomyCache[kind];
    if (cached != null) return cached;
    late final List<MangaTaxonomyOption> entries;
    if (kind == MangaTaxonomyKind.tag) {
      final totals = <String, int>{};
      for (final tag
          in _mapList(await _getJson(_apiUri.resolve('/books/tags')))) {
        final name = _string(tag['name']).trim();
        if (name.isEmpty) continue;
        totals.update(
          name,
          (count) => count + (_int(tag['count']) ?? 0),
          ifAbsent: () => _int(tag['count']) ?? 0,
        );
      }
      entries = totals.entries
          .map((tag) => MangaTaxonomyOption(
                id: 'tag:${tag.key}',
                name: tag.key,
                titleCount: tag.value,
              ))
          .toList(growable: false);
    } else {
      final namespace = kind == MangaTaxonomyKind.artist ? 1 : 2;
      final prefix = kind == MangaTaxonomyKind.artist ? 'artist:' : 'circle:';
      entries = (await _filterIndex())
          .where((entry) => _int(entry['namespace']) == namespace)
          .map((entry) => _string(entry['name']).trim())
          .where((name) => name.isNotEmpty)
          .map((name) => MangaTaxonomyOption(id: '$prefix$name', name: name))
          .toList(growable: false);
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return _taxonomyCache[kind] = List.unmodifiable(entries);
  }

  Future<List<Map<String, dynamic>>> _filterIndex() {
    return _filterIndexFuture ??=
        _getJson(_apiUri.resolve('/books/tags/filters')).then(_mapList);
  }

  Future<dynamic> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw http.ClientException(
          'HDoujin returned HTTP ${response.statusCode}', uri);
    }
    return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  Uri _galleryUri(String mangaId) {
    final parsed = Uri.tryParse(mangaId);
    if (parsed != null && parsed.hasScheme) return parsed;
    final normalized = mangaId.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return _baseUri.resolve('/g/$normalized');
  }

  Uri _apiPageUri(
    String path,
    Map<String, String> parameters,
    String? cursor,
  ) {
    final page = _pageFromCursor(cursor);
    final queryParameters = <String, String>{
      ...parameters,
      if (page > 1) 'page': '$page',
    };
    final uri = _apiUri.resolve(path);
    return queryParameters.isEmpty
        ? uri
        : uri.replace(queryParameters: queryParameters);
  }

  Uri? _detailCoverUri(Map<String, dynamic>? thumbnails) {
    if (thumbnails == null) return null;
    final path = _string(_map(thumbnails['main'])?['path']);
    if (path.isEmpty) return null;
    final direct = _uri(path);
    if (direct != null && direct.hasScheme) return direct;
    final base = _string(thumbnails['base']).replaceFirst(RegExp(r'/$'), '');
    return _uri('$base${path.startsWith('/') ? '' : '/'}$path');
  }

  static List<String> _namesForNamespace(
    List<Map<String, dynamic>> tags,
    int namespace,
  ) =>
      tags
          .where((tag) => _int(tag['namespace']) == namespace)
          .map((tag) => _string(tag['name']).trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
  static String _string(dynamic value) => value?.toString() ?? '';
  static int? _int(dynamic value) => value is int
      ? value
      : value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
  static Uri? _uri(dynamic value) {
    final text = _string(value).trim();
    return text.isEmpty ? null : Uri.tryParse(text);
  }

  static String _galleryId(Uri uri) {
    final segments = uri.pathSegments;
    final index = segments.indexOf('g');
    if (index == -1 || index + 2 >= segments.length) return '';
    return '${segments[index + 1]}/${segments[index + 2]}';
  }

  static int _pageFromCursor(String? cursor) {
    final page = int.tryParse(cursor ?? '');
    return page != null && page > 0 ? page : 1;
  }

  static String? _catalogLanguage(int? value) => switch (value) {
        2 => 'English',
        4 => 'Japanese',
        8 => 'Chinese',
        16 => 'Korean',
        _ => null,
      };
  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
