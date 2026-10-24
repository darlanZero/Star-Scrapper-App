import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// MangaDex implementation of the typed [MangaSource] contract.
///
/// Uses the official MangaDex JSON API. Chapter pages are downloaded to the
/// application documents directory and streamed as [MangaReaderPage.file], which
/// preserves the previous reader behavior.
class MangadexSource
    implements MangaSource, ChapterNavigationMangaSource {
  static final Uri _defaultBaseUri = Uri.parse('https://api.mangadex.org');
  static final Uri _siteUri = Uri.parse('https://mangadex.org');

  static const _imageUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  final http.Client _client;
  final Uri _apiBaseUri;

  int _currentPage = 0;

  MangadexSource({http.Client? client, Uri? apiBaseUri})
      : _client = client ?? http.Client(),
        _apiBaseUri = apiBaseUri ?? _defaultBaseUri;

  @override
  String get id => 'mangadex';

  @override
  String get name => 'Mangadex';

  /// Public site, used for host matching and health checks. API requests use
  /// the separate [_apiBaseUri].
  @override
  Uri get baseUri => _siteUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  @override
  Map<String, String> get coverImageHeaders => const {
        'User-Agent': _imageUserAgent,
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Referer': 'https://mangadex.org/',
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.popular,
        MangaCatalogFilter.recent,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.alphabetical,
      ];

  // ─── Catalog ───────────────────────────────────────────────────────────────

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    _currentPage = int.tryParse(cursor ?? '') ?? 0;
    final order = _orderFor(filter);
    final uri = Uri.parse(
      '$_apiBaseUri/manga?order[$order]=${_orderDirection(filter)}'
      '&includes[]=cover_art&limit=60&offset=${_currentPage * 60}',
    );
    final payload = await _getJson(uri);
    final rows = _list(payload['data']);
    return MangaCatalogPage(
      items: rows.map(_catalogItemFromManga),
      nextCursor: rows.length == 60 ? '${_currentPage + 1}' : null,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return MangaCatalogPage(items: const []);
    final uri = Uri.parse(
      '$_apiBaseUri/manga?title=${Uri.encodeComponent(normalized)}'
      '&includes[]=cover_art&limit=20',
    );
    final payload = await _getJson(uri);
    return MangaCatalogPage(
      items: _list(payload['data']).map(_catalogItemFromManga),
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final detailUri = Uri.parse(
      '$_apiBaseUri/manga/$mangaId'
      '?includes[]=cover_art&includes[]=author&includes[]=artist',
    );
    final payload = await _getJson(detailUri);
    final data = _map(payload['data']);
    final attributes = _map(data['attributes']);
    final relationships = _list(data['relationships']);

    final coverArt = _relationship(relationships, 'cover_art');
    final author = _relationship(relationships, 'author');
    final artist = _relationship(relationships, 'artist');

    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaId,
        title: _localizedTitle(attributes['title']),
        coverUri: _coverUri(mangaId, coverArt),
      ),
      description: _localized(attributes['description']),
      alternativeTitles: _altTitles(attributes['altTitles']),
      genres: _tags(attributes['tags']),
      author: _nameOf(author),
      artist: _nameOf(artist),
      status: mangaStatusFromString(attributes['status']),
      externalUri: Uri.tryParse('https://mangadex.org/manga/$mangaId'),
      chapters: await _fetchChapters(mangaId),
    );
  }

  Future<List<MangaChapter>> _fetchChapters(String mangaId) async {
    final chapters = <MangaChapter>[];
    var offset = 0;
    var hasMore = true;
    while (hasMore) {
      final uri = Uri.parse(
        '$_apiBaseUri/manga/$mangaId/feed'
        '?order[volume]=desc&order[chapter]=desc'
        '&includes[]=scanlation_group&includes[]=user'
        '&limit=100&offset=$offset',
      );
      final payload = await _getJson(uri);
      final rows = _list(payload['data']);
      for (final row in rows) {
        final attributes = _map(row['attributes']);
        chapters.add(MangaChapter(
          id: row['id'].toString(),
          title: (attributes['title'] ?? '').toString(),
          number: (attributes['chapter'] ?? '').toString(),
          volume: _nullable(attributes['volume']),
          language: (attributes['translatedLanguage'] ?? 'en').toString(),
          pages: _nullable(attributes['pages']),
          uploader: _nullable(attributes['uploader']),
          publishedAt: _nullable(attributes['publishAt']),
        ));
      }
      offset += 100;
      hasMore = rows.length == 100;
    }
    return chapters;
  }

  // ─── Reading ─────────────────────────────────────────────────────────────

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final payload = await _getJson(
      Uri.parse('$_apiBaseUri/at-home/server/$chapterId'),
    );
    final baseUrl = (payload['baseUrl'] ?? '').toString();
    final chapterData = _map(payload['chapter']);
    final hash = (chapterData['hash'] ?? '').toString();
    // `data` is a flat list of file names, not maps.
    final imageNames = chapterData['data'] is List
        ? (chapterData['data'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    if (baseUrl.isEmpty || hash.isEmpty || imageNames.isEmpty) return;

    final tempDir = await _chapterTempDir(chapterId, hash);
    for (final fileName in imageNames) {
      final imageUri = Uri.parse('$baseUrl/data/$hash/$fileName');
      final response = await _client.get(imageUri);
      if (response.statusCode != 200) continue;
      final file = File(path.join(tempDir.path, fileName));
      await file.writeAsBytes(response.bodyBytes);
      yield MangaReaderPage.file(file.path);
    }
  }

  Future<Directory> _chapterTempDir(String chapterId, String hash) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDocDir.path, 'temp', chapterId, hash));
    await dir.create(recursive: true);
    return dir;
  }

  // ─── Chapter navigation ────────────────────────────────────────────────────

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapterId(mangaId, currentChapterId, true);

  @override
  Future<String?> previousChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapterId(mangaId, currentChapterId, false);

  Future<String?> _adjacentChapterId(
    String mangaId,
    String currentChapterId,
    bool isNext,
  ) async {
    final chapters = await _fetchChapters(mangaId);
    chapters.sort((a, b) =>
        (double.tryParse(a.number) ?? 0).compareTo(double.tryParse(b.number) ?? 0));
    final currentIndex =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    if (currentIndex == -1) return null;
    final language = chapters[currentIndex].language;
    final step = isNext ? 1 : -1;
    var index = currentIndex + step;
    while (index >= 0 && index < chapters.length) {
      if (chapters[index].language == language) return chapters[index].id;
      index += step;
    }
    return null;
  }

  // ─── HTTP ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw http.ClientException('$name returned HTTP ${response.statusCode}.',
          uri);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Mangadex returned invalid JSON.');
    }
    if (decoded['result'] == 'error') {
      throw StateError('Mangadex API error for $uri.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  // ─── Mapping ───────────────────────────────────────────────────────────────

  static String _orderFor(MangaCatalogFilter filter) => switch (filter) {
        MangaCatalogFilter.recent => 'latestUploadedChapter',
        MangaCatalogFilter.trending => 'rating',
        MangaCatalogFilter.alphabetical => 'title',
        _ => 'relevance',
      };

  static String _orderDirection(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.alphabetical ? 'asc' : 'desc';

  MangaCatalogItem _catalogItemFromManga(Map<String, dynamic> manga) {
    final mangaId = manga['id'].toString();
    final attributes = _map(manga['attributes']);
    final coverArt = _relationship(_list(manga['relationships']), 'cover_art');
    return MangaCatalogItem(
      id: mangaId,
      title: _localizedTitle(attributes['title']),
      coverUri: _coverUri(mangaId, coverArt),
    );
  }

  Uri? _coverUri(String mangaId, Map<String, dynamic>? coverArt) {
    final fileName = _map(coverArt?['attributes'])['fileName']?.toString();
    if (fileName == null || fileName.isEmpty) return null;
    return Uri.tryParse(
      'https://uploads.mangadex.org/covers/$mangaId/$fileName',
    );
  }

  static String _localizedTitle(Object? title) {
    if (title is Map && title.isNotEmpty) {
      return (title.values.first ?? 'Untitled').toString();
    }
    return 'Untitled';
  }

  static String _localized(Object? value) {
    if (value is Map) {
      return (value['en'] ?? (value.isNotEmpty ? value.values.first : ''))
          .toString();
    }
    return value?.toString() ?? '';
  }

  static List<Map<String, String>> _altTitles(Object? value) {
    if (value is! List) return const [];
    final result = <Map<String, String>>[];
    for (final entry in value) {
      if (entry is Map && entry.isNotEmpty) {
        final key = entry.keys.first.toString();
        result.add({key: entry[entry.keys.first].toString()});
      }
    }
    return result;
  }

  static List<String> _tags(Object? value) {
    if (value is! List) return const [];
    return value
        .map((tag) =>
            _map(_map(tag)['attributes'])['name'] is Map
                ? _map(_map(_map(tag)['attributes'])['name'])['en']?.toString()
                : null)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _relationship(
    List<Map<String, dynamic>> relationships,
    String type,
  ) {
    for (final relationship in relationships) {
      if (relationship['type'] == type) return relationship;
    }
    return null;
  }

  static String? _nameOf(Map<String, dynamic>? relationship) =>
      _nullable(_map(relationship?['attributes'])['name']);

  static String? _nullable(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];
}
