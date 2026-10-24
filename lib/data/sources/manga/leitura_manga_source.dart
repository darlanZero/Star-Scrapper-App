import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Leitura Manga (https://leituramanga.net) — catálogo brasileiro em Next.js
/// apoiado por uma API JSON pública.
///
/// Capas e páginas seguem caminhos determinísticos no CDN. A API de detalhes
/// informa o último capítulo, enquanto o conteúdo das páginas é serializado no
/// payload RSC da rota de leitura.
class LeituraMangaSource
    implements
        MangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        GenreBrowsableMangaSource {
  static final Uri _siteUri = Uri.parse('https://leituramanga.net');
  static final Uri _defaultApiUri =
      Uri.parse('https://api.leituramanga.net/api');
  static final Uri _defaultCdnUri = Uri.parse('https://cdn.leituramanga.net');

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _apiUri;
  final Uri _cdnUri;

  LeituraMangaSource({
    http.Client? client,
    Uri? apiUri,
    Uri? cdnUri,
  })  : _client = client ?? http.Client(),
        _apiUri = apiUri ?? _defaultApiUri,
        _cdnUri = cdnUri ?? _defaultCdnUri;

  @override
  String get id => 'leitura_manga';

  @override
  String get name => 'Leitura Manga';

  @override
  Uri get baseUri => _siteUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Origin': 'https://leituramanga.net',
        'Referer': 'https://leituramanga.net/',
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => const {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Referer': 'https://leituramanga.net/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
        MangaCatalogFilter.popular,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final page = _pageFromCursor(cursor);
    final payload = await _getApi('/manga/', {
      'page': '$page',
      'limit': '30',
      'sort': _sortFor(filter),
      'contentType': 'comic',
      // A fonte é mista. Os títulos adultos pertencem ao catálogo, mas não
      // tornam a fonte inteira uma source exclusivamente +18.
      'includeAdult': 'true',
    });
    return _catalogPage(payload, page);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return MangaCatalogPage(items: const []);

    final page = _pageFromCursor(cursor);
    final payload = await _getApi('/search/manga', {
      'q': normalized,
      'page': '$page',
      'limit': '30',
      'contentType': 'comic',
      'includeAdult': 'true',
    });
    return _catalogPage(payload, page);
  }

  @override
  Future<List<MangaGenre>> getGenres() async {
    final payload = await _getApi('/genre', {
      'page': '1',
      'limit': '200',
    });
    final container = _map(_unwrap(payload));
    return _list(container['data'])
        .map(_map)
        .map((genre) => MangaGenre(
              id: (genre['_id'] ?? '').toString(),
              name: (genre['name'] ?? '').toString(),
              isAdult: genre['isAdult'] == true,
            ))
        .where((genre) => genre.id.isNotEmpty && genre.name.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<MangaCatalogPage> browseGenre(
    String genreId, {
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final page = _pageFromCursor(cursor);
    final payload = await _getApi('/manga/', {
      'page': '$page',
      'limit': '30',
      'sort': _sortFor(filter),
      'contentType': 'comic',
      'includeAdult': 'true',
      'genre': genreId,
    });
    return _catalogPage(payload, page);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _slugFromId(mangaId);
    final payload = await _getApi('/manga/get-by-slug/$slug');
    final data = _map(_unwrap(payload));
    if (data.isEmpty) {
      throw StateError('Leitura Manga não retornou detalhes para "$slug".');
    }

    final title = (data['title'] ?? '').toString();
    final authors = _list(data['authors'])
        .map(_map)
        .map((author) => (author['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final genres = _list(data['genres'])
        .map(_map)
        .map((genre) => (genre['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final alternativeTitles = _list(data['alternativeTitles'])
        .map((title) => title.toString().trim())
        .where((title) => title.isNotEmpty)
        .map((title) => <String, String>{'': title})
        .toList(growable: false);

    return MangaDetails(
      item: MangaCatalogItem(
        id: slug,
        title: title,
        coverUri: _coverUri(slug),
        subtitle: _catalogSubtitle(data, includeTotal: true),
      ),
      description: (data['description'] ?? '').toString(),
      alternativeTitles: alternativeTitles,
      genres: genres,
      author: authors.isEmpty ? null : authors.join(', '),
      status: _status(data['status']),
      externalUri: _siteUri.resolve('/manga/$slug'),
      chapters: _chaptersFromDetails(data),
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final slug = _slugFromId(mangaId);
    final chapter = _chapterFromId(chapterId);
    final uri = _siteUri.resolve('/manga/$slug/chapter/$chapter');
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      'Accept': 'text/html,application/xhtml+xml',
    });
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Leitura Manga retornou HTTP ${response.statusCode}',
        uri,
      );
    }

    final seen = <String>{};
    for (final relativePath in _pagePaths(response.body)) {
      if (!seen.add(relativePath)) continue;
      yield MangaReaderPage.network(
        _cdnUri.resolve('/$relativePath'),
        headers: coverImageHeaders,
      );
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) {
    final slug = _slugFromId(mangaId);
    final chapter = _chapterFromId(chapterId);
    return _siteUri.resolve('/manga/$slug/chapter/$chapter');
  }

  @override
  Future<String?> nextChapterId(
    String mangaId,
    String currentChapterId,
  ) async {
    return _adjacentChapterId(mangaId, currentChapterId, 1);
  }

  @override
  Future<String?> previousChapterId(
    String mangaId,
    String currentChapterId,
  ) async {
    return _adjacentChapterId(mangaId, currentChapterId, -1);
  }

  Future<String?> _adjacentChapterId(
    String mangaId,
    String currentChapterId,
    int delta,
  ) async {
    final details = await getDetails(mangaId);
    final chapters = details.chapters;
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    if (index == -1) return null;
    final target = index + delta;
    if (target < 0 || target >= chapters.length) return null;
    return chapters[target].id;
  }

  Future<Map<String, dynamic>> _getApi(
    String path, [
    Map<String, String>? query,
  ]) async {
    final normalizedBase = _apiUri.toString().replaceFirst(RegExp(r'/$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath')
        .replace(queryParameters: query);
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Leitura Manga retornou HTTP ${response.statusCode}',
        uri,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Resposta inválida da Leitura Manga.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  MangaCatalogPage _catalogPage(Map<String, dynamic> payload, int page) {
    final container = _map(_unwrap(payload));
    final rows = _list(container['data']);
    final pagination = _map(container['pagination']);
    final totalPages = _asInt(pagination['totalPage']);
    final currentPage = _asInt(pagination['page']) ?? page;

    return MangaCatalogPage(
      items: rows.map(_catalogItem),
      nextCursor: totalPages != null && currentPage < totalPages
          ? '${currentPage + 1}'
          : null,
    );
  }

  MangaCatalogItem _catalogItem(dynamic raw) {
    final data = _map(raw);
    final slug = (data['slug'] ?? '').toString();
    return MangaCatalogItem(
      id: slug,
      title: (data['title'] ?? '').toString(),
      coverUri: slug.isEmpty ? null : _coverUri(slug),
      subtitle: _catalogSubtitle(data),
    );
  }

  List<MangaChapter> _chaptersFromDetails(Map<String, dynamic> data) {
    final latest = _asDouble(data['totalChapter']);
    if (latest == null || latest <= 0) return const [];

    final whole = latest.floor();
    final chapters = <MangaChapter>[
      for (var number = 1; number <= whole; number++)
        MangaChapter(
          id: '$number',
          title: 'Capítulo $number',
          number: '$number',
          language: 'pt-br',
        ),
    ];
    if (latest != whole) {
      final number = _numberText(latest);
      chapters.add(MangaChapter(
        id: number,
        title: 'Capítulo $number',
        number: number,
        language: 'pt-br',
      ));
    }
    return chapters;
  }

  Iterable<String> _pagePaths(String html) sync* {
    final escaped =
        RegExp(r'\\"url\\":\\"([^"\\]+\.(?:avif|jpe?g|png|webp))\\"');
    final plain = RegExp(r'"url"\s*:\s*"([^"\\]+\.(?:avif|jpe?g|png|webp))"');
    for (final pattern in [escaped, plain]) {
      for (final match in pattern.allMatches(html)) {
        final path = match.group(1)?.replaceAll(r'\/', '/') ?? '';
        if (path.isNotEmpty && !path.contains('/cover-')) yield path;
      }
    }
  }

  Uri _coverUri(String slug) => _cdnUri.resolve('/$slug/cover-md.webp');

  String? _catalogSubtitle(
    Map<String, dynamic> data, {
    bool includeTotal = false,
  }) {
    final chapters = _list(data['chapters']);
    String? latestChapter;
    if (chapters.isNotEmpty) {
      final chapter = _map(chapters.first);
      final number = _numberText(chapter['chapterNumber']);
      if (number.isNotEmpty) latestChapter = number;
    }
    final total = _asInt(data['totalChapter']);
    latestChapter ??= _numberText(data['totalChapter']);
    final genres = _list(data['genres']).map(_map).toList(growable: false);
    const formats = {'manga', 'manhwa', 'manhua', 'webtoon', 'novel'};
    final format = genres
        .map((genre) => (genre['name'] ?? '').toString())
        .where((name) => formats.contains(name.toLowerCase()))
        .firstOrNull;
    final rating = _asDouble(
      data['rating'] ?? data['averageRating'] ?? data['ratingAverage'],
    );
    final subtitle = mangaCatalogSubtitle(
      latestChapter: latestChapter,
      totalChapters: includeTotal ? total : null,
      format: format ?? _contentTypeLabel(data['contentType']),
      status: _status(data['status']),
      rating: rating,
      year: _asInt(data['releaseYear']),
    );
    return subtitle.isEmpty ? null : subtitle;
  }

  static String? _contentTypeLabel(dynamic value) =>
      switch (value?.toString().toLowerCase()) {
        'comic' => 'Comic',
        'novel' => 'Novel',
        _ => null,
      };

  static String _sortFor(MangaCatalogFilter filter) => switch (filter) {
        MangaCatalogFilter.added => 'created',
        MangaCatalogFilter.popular => 'view',
        _ => 'time',
      };

  static MangaStatus _status(dynamic value) => switch (_asInt(value)) {
        1 => MangaStatus.ongoing,
        2 => MangaStatus.completed,
        3 => MangaStatus.cancelled,
        4 => MangaStatus.hiatus,
        _ => MangaStatus.unknown,
      };

  static dynamic _unwrap(Map<String, dynamic> payload) =>
      payload.containsKey('data') ? payload['data'] : payload;

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<dynamic> _list(dynamic value) =>
      value is List ? List<dynamic>.from(value) : const [];

  static int _pageFromCursor(String? cursor) {
    final parsed = int.tryParse(cursor ?? '');
    return parsed != null && parsed > 0 ? parsed : 1;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String _numberText(dynamic value) {
    final number = _asDouble(value);
    if (number == null) return value?.toString() ?? '';
    return number == number.truncateToDouble()
        ? number.toInt().toString()
        : number.toString();
  }

  static String _slugFromId(String mangaId) {
    final uri = Uri.tryParse(mangaId);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final mangaIndex = uri.pathSegments.indexOf('manga');
      if (mangaIndex >= 0 && mangaIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[mangaIndex + 1];
      }
    }
    return mangaId.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static String _chapterFromId(String chapterId) {
    final uri = Uri.tryParse(chapterId);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final chapterIndex = uri.pathSegments.indexOf('chapter');
      if (chapterIndex >= 0 && chapterIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[chapterIndex + 1];
      }
    }
    return chapterId.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }
}
