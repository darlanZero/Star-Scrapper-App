import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/animy/animy_session.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Animy.net manga provider backed by the site's public `/api/v1` API.
class AnimyMangaSource
    implements
        MangaSource,
        CredentialAuthMangaSource,
        BrowserSessionMangaSource,
        ReadingHistoryMangaSource,
        ChapterNavigationMangaSource,
        VariantCatalogMangaSource,
        FilterableMangaSource,
        ProfileAuthMangaSource {
  static const _site = 'https://animy.net';
  static const _api = '$_site/api/v1';
  static const _pageSize = 24;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'Animy',
    baseUrl: _site,
    contentType: ContentType.spa,
    auth: const AuthConfig(
      loginUrl: '$_site/mangas/inicio/',
      type: AuthType.genericForm,
      successUrlFragment: '/mangas/',
      sessionValidationUrl: '$_api/auth/me',
      sessionCookieNames: ['aniume.token'],
      logoutUrl: null,
    ),
    buildDetailUrl: (id, base) => '$base/mangas/obra/$id/',
    buildChapterUrl: (id, base) => '$base/mangas/ler/$id/',
    buildListUrl: (filter, page, base) => '$base/mangas/biblioteca/',
    extractId: (url) =>
        Uri.tryParse(url)?.pathSegments.lastWhere(
              (segment) => segment.isNotEmpty,
              orElse: () => url,
            ) ??
        url,
  );

  static const _popularVariants = [
    MangaCatalogVariant(id: 'day', label: 'Hoje'),
    MangaCatalogVariant(id: 'week', label: 'Semana'),
    MangaCatalogVariant(id: 'month', label: 'Mês'),
    MangaCatalogVariant(id: 'all', label: 'Geral'),
  ];
  static const _recentVariants = [
    MangaCatalogVariant(id: 'all', label: 'Todos'),
    MangaCatalogVariant(id: 'manga', label: 'Mangás'),
    MangaCatalogVariant(id: 'manhwa', label: 'Manhwas'),
    MangaCatalogVariant(id: 'manhua', label: 'Manhuas'),
  ];

  final http.Client _client;
  final AnimySession _session;
  final Uri _baseUri;
  final Map<String, List<MangaChapter>> _chapterCache = {};

  AnimyMangaSource({
    http.Client? client,
    AnimySession? session,
    Uri? baseUri,
  })  : _client = client ?? http.Client(),
        _session = session ?? AnimySession(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'animy_manga';
  @override
  String get name => 'Animy';
  @override
  Uri get baseUri => _baseUri;
  @override
  String get sessionKey => AnimySession.key;
  @override
  ScrapperProfile get authProfile => _profile;
  @override
  Uri get loginUri => _baseUri.resolve('/mangas/inicio/');
  @override
  bool get isAuthenticated => _session.isAuthenticated;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'application/json',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'User-Agent': _userAgent,
        'Referer': _baseUri.resolve('/mangas/inicio/').toString(),
        if (_session.token case final token?) 'Authorization': 'Bearer $token',
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'User-Agent': _userAgent,
        'Referer': '$_site/',
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.added,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      switch (filter) {
        MangaCatalogFilter.popular => _popularVariants,
        MangaCatalogFilter.recent ||
        MangaCatalogFilter.added =>
          _recentVariants,
        _ => const [],
      };

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    if (filter == MangaCatalogFilter.popular) {
      return _top(variantId);
    }
    return _catalog(
      page: _page(cursor),
      sort: filter == MangaCatalogFilter.added ? 'newest' : 'released',
      released: filter != MangaCatalogFilter.added,
      type: variantId == 'all' ? null : variantId,
    );
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    final page = _page(cursor);
    return switch (filter) {
      MangaCatalogFilter.popular => _top('day'),
      MangaCatalogFilter.recent =>
        _catalog(page: page, sort: 'released', released: true),
      MangaCatalogFilter.trending => _catalog(page: page, sort: 'followed'),
      MangaCatalogFilter.added =>
        _catalog(page: page, sort: 'newest', released: false),
      MangaCatalogFilter.updated =>
        _catalog(page: page, sort: 'released', released: true),
      MangaCatalogFilter.alphabetical => _catalog(page: page, sort: 'title'),
    };
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) => _catalog(
        page: _page(cursor),
        sort: 'popular',
        search: query.trim(),
      );

  Future<MangaCatalogPage> _top(String period) async {
    final payload = await _getJson('/mangas/top?period=$period&limit=20');
    final items = _list(payload is Map ? payload['items'] : payload)
        .map((raw) => _catalogItem(_map(raw)))
        .toList(growable: false);
    return MangaCatalogPage(items: items);
  }

  Future<MangaCatalogPage> _catalog({
    required int page,
    required String sort,
    String search = '',
    String? type,
    bool? released,
    Iterable<String> genres = const [],
    Iterable<String> demographics = const [],
    Iterable<String> contentRatings = const [],
    String? status,
    String? year,
  }) async {
    final params = <String, dynamic>{
      'limit': '$_pageSize',
      'offset': '${(page - 1) * _pageSize}',
      'sort': sort,
      if (search.isNotEmpty) 'search': search,
      if (type != null && type.isNotEmpty) 'type': type,
      if (released != null) 'released': released ? '1' : '0',
      if (status != null && status.isNotEmpty) 'status': status,
      if (year != null && year.isNotEmpty) 'year': year,
      if (genres.isNotEmpty) 'genre': genres,
      if (demographics.isNotEmpty) 'demographic': demographics,
      if (contentRatings.isNotEmpty) 'contentRating': contentRatings,
    };
    final payload = await _getJson('/mangas?${_query(params)}');
    final map = _map(payload);
    final items = _list(map['items'])
        .map((raw) => _catalogItem(_map(raw)))
        .toList(growable: false);
    final total = _int(map['total']) ?? items.length;
    return MangaCatalogPage(
      items: items,
      nextCursor: page * _pageSize < total ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final facets = _map(await _getJson('/mangas/meta/facets'));
    return MangaSearchOptions(
      formats: const [
        MangaFilterOption(value: 'manga', label: 'Mangá'),
        MangaFilterOption(value: 'manhwa', label: 'Manhwa'),
        MangaFilterOption(value: 'manhua', label: 'Manhua'),
        MangaFilterOption(value: 'webtoon', label: 'Webtoon'),
        MangaFilterOption(value: 'novel', label: 'Novel'),
        MangaFilterOption(value: 'comic', label: 'Quadrinho'),
      ],
      statuses: const [
        MangaFilterOption(value: 'ongoing', label: 'Em andamento'),
        MangaFilterOption(value: 'completed', label: 'Concluído'),
        MangaFilterOption(value: 'hiatus', label: 'Em hiato'),
        MangaFilterOption(value: 'cancelled', label: 'Cancelado'),
      ],
      genres: _options(facets['genres']),
      tags: [
        ..._options(facets['demographics'], prefix: 'demographic:'),
        ..._options(facets['contentRatings'], prefix: 'rating:'),
      ],
      sorts: const [
        MangaSearchSort.popular,
        MangaSearchSort.updated,
        MangaSearchSort.rating,
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.titleAscending,
      ],
      supportsAdultMode: true,
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    final demographics = request.tags
        .where((value) => value.startsWith('demographic:'))
        .map((value) => value.substring('demographic:'.length));
    final selectedRatings = request.tags
        .where((value) => value.startsWith('rating:'))
        .map((value) => value.substring('rating:'.length))
        .toSet();
    if (request.adultMode == MangaAdultMode.hide) {
      selectedRatings.removeAll(['erotica', 'pornographic']);
      if (selectedRatings.isEmpty) {
        selectedRatings.addAll(['safe', 'suggestive']);
      }
    } else if (request.adultMode == MangaAdultMode.only) {
      selectedRatings
        ..clear()
        ..addAll(['erotica', 'pornographic']);
    }
    final sort = switch (request.sort) {
      MangaSearchSort.updated => 'released',
      MangaSearchSort.rating => 'rating',
      MangaSearchSort.recentlyAdded => 'newest',
      MangaSearchSort.title || MangaSearchSort.titleAscending => 'title',
      _ => 'popular',
    };
    return _catalog(
      page: _page(cursor),
      sort: sort,
      type: request.formats.isEmpty ? null : request.formats.first,
      genres: request.genres,
      demographics: demographics,
      contentRatings: selectedRatings,
      status: request.statuses.isEmpty ? null : request.statuses.first,
      year: request.minimumYear?.toString(),
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final data = _map(await _getJson('/mangas/${_numericId(mangaId)}'));
    final chapters = _list(data['chapters']).map((raw) {
      final chapter = _map(raw);
      final number = _numberText(chapter['number']);
      final language = chapter['language']?.toString() ?? 'pt-br';
      return MangaChapter(
        id: '$number|$language',
        number: number,
        language: language,
        title: chapter['title']?.toString() ?? '',
        publishedAt: chapter['date']?.toString(),
      );
    }).toList(growable: false)
      ..sort((a, b) => _double(a.number).compareTo(_double(b.number)));
    final id = data['id']?.toString() ?? _numericId(mangaId);
    _chapterCache[id] = chapters;
    return MangaDetails(
      item: _catalogItem(data),
      description: data['desc']?.toString() ?? '',
      alternativeTitles: _list(data['altTitles']).map((raw) {
        final alt = _map(raw);
        return <String, String>{
          (alt['lang']?.toString().isNotEmpty == true
              ? alt['lang'].toString()
              : 'und'): alt['title']?.toString() ?? '',
        };
      }).where((entry) => entry.values.first.isNotEmpty),
      genres: _strings(data['g']),
      author: data['au']?.toString(),
      artist: data['ar']?.toString(),
      status: mangaStatusFromString(data['status']),
      externalUri: _baseUri.resolve('/mangas/obra/$id/'),
      chapters: chapters,
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final parts = chapterId.split('|');
    final number = parts.first;
    final language = parts.length > 1 ? parts[1] : 'pt-br';
    final payload = _map(await _getJson(
      '/mangas/${_numericId(mangaId)}/chapters/$number'
      '?legenda=${Uri.encodeQueryComponent(language)}',
    ));
    for (final raw in _list(payload['pages'])) {
      final page = _map(raw);
      final uri = Uri.tryParse(page['imageUrl']?.toString() ?? '');
      if (uri != null && uri.hasScheme) {
        yield MangaReaderPage.network(uri, headers: coverImageHeaders);
      }
    }
  }

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapter(mangaId, currentChapterId, 1);
  @override
  Future<String?> previousChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapter(mangaId, currentChapterId, -1);

  Future<String?> _adjacentChapter(
    String mangaId,
    String currentChapterId,
    int delta,
  ) async {
    final id = _numericId(mangaId);
    final chapters = _chapterCache[id] ?? (await getDetails(id)).chapters;
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    final target = index + delta;
    return index >= 0 && target >= 0 && target < chapters.length
        ? chapters[target].id
        : null;
  }

  @override
  Future<void> authenticateWithCredentials(
      String username, String password) async {
    Map<String, dynamic>? pow;
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = await _client.post(
        _uri('/auth/login'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'email': username.trim(),
          'password': password,
          if (pow != null) 'pow': pow,
        }),
      );
      final payload = _decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final token = _tokenFrom(payload);
        if (token == null) {
          throw Exception('A Animy não retornou um token de sessão.');
        }
        await _session.save(token);
        await _getJson('/auth/me', authenticated: true);
        return;
      }
      final error = _map(payload);
      final challenge = _map(error['pow'])['challenge']?.toString();
      final bits = _int(_map(error['pow'])['bits']);
      if (response.statusCode == 428 && challenge != null && bits != null) {
        pow = {'challenge': challenge, 'nonce': _solvePow(challenge, bits)};
        continue;
      }
      throw Exception(error['error']?.toString() ??
          'Login falhou: HTTP ${response.statusCode}');
    }
    throw Exception('A Animy não aceitou a prova de trabalho do login.');
  }

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) =>
      _session.update(cookies);
  @override
  Future<void> restoreSession() => _session.restore();
  @override
  Future<void> logout() => _session.clear();

  @override
  Future<List<MangaReadingHistoryEntry>> fetchReadingHistory() async {
    await _requireSession();
    final payload =
        await _getJson('/me/reading-positions?limit=100', authenticated: true);
    final rows = _list(
        payload is Map ? (payload['items'] ?? payload['positions']) : payload);
    final entries = <MangaReadingHistoryEntry>[];
    for (final raw in rows) {
      final row = _map(raw);
      final manga = _map(row['manga'] ?? row['work']);
      if (manga.isEmpty) continue;
      final id = manga['id']?.toString() ?? row['mangaId']?.toString();
      if (id == null) continue;
      final chapterNumber = _numberText(row['chapter'] ?? row['chapterNumber']);
      final language = row['language']?.toString() ?? 'pt-br';
      entries.add(MangaReadingHistoryEntry(
        details: MangaDetails(item: _catalogItem({...manga, 'id': id})),
        lastReadChapter: MangaChapter(
          id: '$chapterNumber|$language',
          number: chapterNumber,
          language: language,
        ),
        readChapterCount:
            _int(row['readChapterCount'] ?? row['chaptersRead']) ?? 1,
      ));
    }
    return entries;
  }

  @override
  Future<void> markChapterRead({
    required String mangaId,
    required String chapterId,
  }) async {
    await _requireSession();
    final chapter = chapterId.split('|').first;
    await _request(
      'PUT',
      '/me/reading-positions/${_numericId(mangaId)}',
      authenticated: true,
      body: {
        'chapter': double.tryParse(chapter) ?? chapter,
        'page': 1,
        'offset': 0,
        'totalPages': 1,
        'finished': true,
        'device': 'starslibrary',
      },
    );
  }

  Future<void> _requireSession() async {
    await _session.restore();
    if (!_session.isAuthenticated) {
      throw const MangaSourceSessionRequired(
          'authentication_required: Entre na Animy para sincronizar o histórico.');
    }
  }

  Future<dynamic> _getJson(String path, {bool authenticated = false}) async {
    if (authenticated) {
      await _requireSession();
    } else {
      await _session.restore();
    }
    final response = await _client.get(_uri(path), headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Animy: HTTP ${response.statusCode}');
    }
    return _decode(response.body);
  }

  Future<dynamic> _request(String method, String path,
      {required bool authenticated, Object? body}) async {
    if (authenticated) await _requireSession();
    final request = http.Request(method, _uri(path))
      ..headers.addAll({...requestHeaders, 'Content-Type': 'application/json'});
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Animy: HTTP ${response.statusCode}');
    }
    return response.body.isEmpty ? null : _decode(response.body);
  }

  Uri _uri(String path) =>
      _baseUri.resolve('/api/v1${path.startsWith('/') ? path : '/$path'}');

  MangaCatalogItem _catalogItem(Map<String, dynamic> item) {
    final chapters = _int(item['ch']);
    final latest = _list(item['latestChapters']).firstOrNull?.toString();
    return MangaCatalogItem(
      id: item['id']?.toString() ?? '',
      title: item['t']?.toString() ?? item['title']?.toString() ?? '',
      coverUri: Uri.tryParse(item['cover']?.toString() ?? ''),
      subtitle: mangaCatalogSubtitle(
        latestChapter: latest,
        totalChapters: chapters,
        format: item['type']?.toString(),
        status: mangaStatusFromString(item['status']),
        rating: _doubleOrNull(item['rating'] ?? item['r']),
        year: _int(item['y']),
      ),
    );
  }

  String _solvePow(String challenge, int bits) {
    for (var nonce = 0;; nonce++) {
      final bytes = sha512.convert(utf8.encode('$challenge:$nonce')).bytes;
      var zeros = 0;
      for (final byte in bytes) {
        if (byte == 0) {
          zeros += 8;
          continue;
        }
        zeros += 8 - byte.bitLength;
        break;
      }
      if (zeros >= bits) return '$nonce';
    }
  }

  static String? _tokenFrom(dynamic payload) {
    final map = _map(payload);
    return (map['token'] ?? map['accessToken'] ?? map['access_token'])
        ?.toString();
  }

  static int _page(String? cursor) => int.tryParse(cursor ?? '') ?? 1;
  static String _numericId(String id) => id.split('|').first;
  static double _double(String value) => double.tryParse(value) ?? 0;
  static double? _doubleOrNull(dynamic value) =>
      double.tryParse(value?.toString() ?? '');
  static int? _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static String _numberText(dynamic value) =>
      value?.toString().replaceFirst(RegExp(r'\.0$'), '') ?? '';
  static dynamic _decode(String body) => jsonDecode(body);
  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  static List<dynamic> _list(dynamic value) => value is List ? value : const [];
  static List<String> _strings(dynamic value) =>
      _list(value).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  static List<MangaFilterOption> _options(dynamic value,
          {String prefix = ''}) =>
      _strings(value)
          .map((entry) => MangaFilterOption(
              value: '$prefix$entry', label: _facetLabel(entry)))
          .toList();
  static String _facetLabel(String value) => switch (value) {
        'safe' => 'Livre',
        'suggestive' => 'Sugestivo',
        'erotica' => 'Erótico',
        'pornographic' => 'Adulto',
        'shounen' => 'Shounen',
        'shoujo' => 'Shoujo',
        'seinen' => 'Seinen',
        'josei' => 'Josei',
        _ => value,
      };
  static String _query(Map<String, dynamic> params) {
    final query = <String>[];
    for (final entry in params.entries) {
      final values = entry.value is Iterable && entry.value is! String
          ? entry.value as Iterable
          : [entry.value];
      for (final value in values) {
        if (value == null || value.toString().isEmpty) continue;
        query.add(
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value.toString())}');
      }
    }
    return query.join('&');
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
