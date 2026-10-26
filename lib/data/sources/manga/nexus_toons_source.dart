import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Nexus Toons — a public PT-BR catalog whose VIP chapters reuse the website
/// account session. The SPA encrypts selected JSON responses before returning
/// them; [_decodePayload] mirrors the public decoder shipped by its frontend.
class NexusToonsSource
    implements
        MangaSource,
        CredentialAuthMangaSource,
        BrowserSessionMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        FilterableMangaSource,
        ProfileAuthMangaSource {
  static const _base = 'https://nexustoons.com';
  static const _pageSize = 30;
  static const _cryptoSecret = 'OrionNexus2025CryptoKey!Secure';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const _formats = [
    MangaFilterOption(value: 'manga', label: 'Manga'),
    MangaFilterOption(value: 'manhwa', label: 'Manhwa'),
    MangaFilterOption(value: 'manhua', label: 'Manhua'),
    MangaFilterOption(value: 'webtoon', label: 'Webtoon'),
    MangaFilterOption(value: 'pornhwa', label: 'Pornhwa'),
    MangaFilterOption(value: 'hentai', label: 'Hentai'),
    MangaFilterOption(value: 'doujinshi', label: 'Doujinshi'),
    MangaFilterOption(value: 'novel', label: 'Novel'),
    MangaFilterOption(value: 'one-shot', label: 'One-shot'),
  ];

  static const _statuses = [
    MangaFilterOption(value: 'ongoing', label: 'Ongoing'),
    MangaFilterOption(value: 'completed', label: 'Completed'),
    MangaFilterOption(value: 'hiatus', label: 'Hiatus'),
    MangaFilterOption(value: 'cancelled', label: 'Cancelled'),
  ];

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'Nexus Toons',
    baseUrl: _base,
    contentType: ContentType.spa,
    auth: const AuthConfig(
      loginUrl: '$_base/login',
      type: AuthType.webviewOAuth,
      successUrlFragment: _base,
      // The authenticated session is an HttpOnly cookie. Keeping this empty
      // lets the WebView return the complete cookie jar regardless of its name.
      sessionCookieNames: [],
      logoutUrl: '$_base/api/logout',
    ),
    buildDetailUrl: (id, base) => '$base/manga/$id',
    buildChapterUrl: (id, base) => '$base/ler/$id',
    buildListUrl: (filter, page, base) =>
        '$base/biblioteca?page=${page + 1}&limit=$_pageSize',
    extractId: (url) {
      final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
      final index = segments.indexOf('manga');
      return index >= 0 && index + 1 < segments.length
          ? segments[index + 1]
          : url;
    },
  );

  final http.Client _client;
  Map<String, String> _cookies = {};
  bool _authenticated = false;

  NexusToonsSource({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get id => 'nexus_toons';

  @override
  String get name => 'Nexus Toons';

  @override
  String get sessionKey => id;

  @override
  ScrapperProfile get authProfile => _profile;

  @override
  Uri get baseUri => Uri.parse(_base);

  @override
  Uri get loginUri => Uri.parse(_profile.auth.loginUrl);

  @override
  bool get isAuthenticated => _authenticated;

  @override
  Map<String, String> get requestHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Origin': _base,
        'Referer': '$_base/',
        if (_cookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(_cookies),
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '$_base/',
        if (_cookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(_cookies),
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.alphabetical,
      ];

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) async {
    _cookies = Map<String, String>.from(cookies);
    final validation = await _client.get(
      Uri.parse('$_base/api/me'),
      headers: requestHeaders,
    );
    if (validation.statusCode != 200) {
      _cookies = {};
      _authenticated = false;
      throw const MangaSourceSessionRequired(
        'A Nexus Toons recusou a sessão recebida.',
      );
    }
    _authenticated = true;
    await SessionManager.saveCookies(sessionKey, _cookies);
  }

  @override
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    final response = await _client.post(
      Uri.parse('$_base/api/login'),
      headers: {...requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
      }),
    );
    final payload = _decodePayload(response.body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(_errorMessage(payload) ?? 'Usuário ou senha inválidos.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _errorMessage(payload) ?? 'Login falhou: HTTP ${response.statusCode}',
      );
    }
    final cookies = _parseSetCookie(response.headers['set-cookie']);
    if (cookies.isEmpty) {
      throw const MangaSourceSessionRequired(
        'A Nexus Toons exige a conclusão do login no navegador.',
      );
    }
    await updateBrowserSession(cookies);
  }

  @override
  Future<void> restoreSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(sessionKey);
    }
    if (_cookies.isEmpty) {
      _authenticated = false;
      return;
    }
    try {
      final response = await _client.get(
        Uri.parse('$_base/api/me'),
        headers: requestHeaders,
      );
      _authenticated = response.statusCode == 200;
      if (!_authenticated) {
        _cookies = {};
        await SessionManager.clearSession(sessionKey);
      }
    } catch (_) {
      // Keep the saved session during a temporary outage. Public catalog
      // requests still work and the next authenticated action will revalidate.
      _authenticated = true;
    }
  }

  @override
  Future<void> logout() async {
    await restoreSession();
    if (_cookies.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('$_base/api/logout'),
          headers: {...requestHeaders, 'Content-Type': 'application/json'},
          body: '{}',
        );
      } catch (_) {}
    }
    _cookies = {};
    _authenticated = false;
    await SessionManager.clearSession(sessionKey);
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.updated,
    String? cursor,
  }) {
    final (sortBy, sortOrder) = switch (filter) {
      MangaCatalogFilter.added => ('createdAt', 'desc'),
      MangaCatalogFilter.popular => ('views', 'desc'),
      MangaCatalogFilter.alphabetical => ('title', 'asc'),
      _ => ('updatedAt', 'desc'),
    };
    return _browseCatalog(
      page: int.tryParse(cursor ?? '') ?? 1,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    return _browseCatalog(
      page: int.tryParse(cursor ?? '') ?? 1,
      query: query.trim(),
      sortBy: 'updatedAt',
      sortOrder: 'desc',
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final response = await _apiGet('/api/categories');
    _assertSuccess(response);
    final decoded = _decodePayload(response.body);
    final categories = decoded is List
        ? decoded.whereType<Map>().toList()
        : <Map<dynamic, dynamic>>[];
    final genres = <MangaFilterOption>[];
    final themes = <MangaFilterOption>[];
    for (final raw in categories) {
      final data = Map<String, dynamic>.from(raw);
      final option = MangaFilterOption(
        value: data['id']?.toString() ?? '',
        label: data['name']?.toString() ?? '',
      );
      if (option.value.isEmpty || option.label.isEmpty) continue;
      if (data['type'] == 'theme') {
        themes.add(option);
      } else if (data['type'] == 'genre') {
        genres.add(option);
      }
    }
    return MangaSearchOptions(
      formats: _formats,
      statuses: _statuses,
      genres: genres,
      themes: themes,
      sorts: const [
        MangaSearchSort.updated,
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.title,
        MangaSearchSort.popular,
        MangaSearchSort.rating,
        MangaSearchSort.year,
        MangaSearchSort.chapterCount,
      ],
      supportsAuthor: true,
      supportsArtist: true,
      supportsYearRange: true,
      supportsChapterRange: true,
      supportsCategoryMode: true,
      supportsAdultMode: true,
      supportsSortDirection: true,
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    return _browseCatalog(
      page: int.tryParse(cursor ?? '') ?? 1,
      formats: request.formats,
      statuses: request.statuses,
      genres: request.genres,
      themes: request.themes,
      author: request.author.trim(),
      artist: request.artist.trim(),
      minimumYear: request.minimumYear,
      maximumYear: request.maximumYear,
      minimumChapters: request.minimumChapters,
      maximumChapters: request.maximumChapters,
      categoryMode:
          request.categoryMode == MangaCategoryMode.all ? 'and' : 'or',
      adultMode: request.adultMode,
      sortBy: switch (request.sort) {
        MangaSearchSort.updated => 'updatedAt',
        MangaSearchSort.recentlyAdded => 'createdAt',
        MangaSearchSort.title ||
        MangaSearchSort.titleAscending ||
        MangaSearchSort.titleDescending =>
          'title',
        MangaSearchSort.popular => 'views',
        MangaSearchSort.rating => 'rating',
        MangaSearchSort.year => 'releaseYear',
        MangaSearchSort.chapterCount => 'chapters',
      },
      sortOrder: request.sort == MangaSearchSort.titleAscending
          ? 'asc'
          : request.sort == MangaSearchSort.titleDescending
              ? 'desc'
              : request.sortDirection == MangaSortDirection.ascending
                  ? 'asc'
                  : 'desc',
    );
  }

  Future<MangaCatalogPage> _browseCatalog({
    required int page,
    required String sortBy,
    required String sortOrder,
    String query = '',
    Set<String> formats = const {},
    Set<String> statuses = const {},
    Set<String> genres = const {},
    Set<String> themes = const {},
    String author = '',
    String artist = '',
    int? minimumYear,
    int? maximumYear,
    int? minimumChapters,
    int? maximumChapters,
    String categoryMode = 'or',
    MangaAdultMode adultMode = MangaAdultMode.hide,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$_pageSize',
      if (query.isNotEmpty) 'search': query,
      if (statuses.isNotEmpty) 'status': statuses.join(','),
      if (formats.isNotEmpty) 'type': formats.join(','),
      if (genres.isNotEmpty) 'genres': genres.join(','),
      if (themes.isNotEmpty) 'themes': themes.join(','),
      if (author.isNotEmpty) 'author': author,
      if (artist.isNotEmpty) 'artist': artist,
      if (minimumYear != null) 'yearFrom': '$minimumYear',
      if (maximumYear != null) 'yearTo': '$maximumYear',
      if (minimumChapters != null) 'minChapters': '$minimumChapters',
      if (maximumChapters != null) 'maxChapters': '$maximumChapters',
      if (adultMode == MangaAdultMode.include) 'includeNsfw': 'true',
      if (adultMode == MangaAdultMode.only) 'onlyNsfw': 'true',
      'categoryMode': categoryMode,
      'sortBy': sortBy,
      'sortOrder': sortOrder,
    };
    final response = await _apiGet(
      '/api/mangas?${Uri(queryParameters: params).query}',
    );
    _assertSuccess(response);
    final decoded = _decodePayload(response.body);
    final root = decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    final rawItems = root['data'] is List ? root['data'] as List : const [];
    final items = rawItems
        .whereType<Map>()
        .map((raw) => _catalogItem(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
    final totalPages = _int(root['pages']);
    final hasMore =
        totalPages > 0 ? page < totalPages : items.length >= _pageSize;
    return MangaCatalogPage(
      items: items,
      nextCursor: hasMore ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final numeric = int.tryParse(mangaId) != null;
    final response = await _apiGet(
      numeric
          ? '/api/manga/id/$mangaId'
          : '/api/manga/${Uri.encodeComponent(mangaId)}',
    );
    _assertSuccess(response);
    final decoded = _decodePayload(response.body);
    if (decoded is! Map) throw const FormatException('Obra inválida.');
    final data = Map<String, dynamic>.from(decoded);
    final slug = data['slug']?.toString() ?? mangaId;
    final status = mangaStatusFromString(data['status']);
    return MangaDetails(
      item: MangaCatalogItem(
        id: slug,
        title: data['title']?.toString() ?? '',
        coverUri: Uri.tryParse(data['coverImage']?.toString() ?? ''),
        subtitle: mangaCatalogSubtitle(
          totalChapters: _int(data['chapterCount']) > 0
              ? _int(data['chapterCount'])
              : data['chapters'] is List
                  ? (data['chapters'] as List).length
                  : 0,
          format: data['type']?.toString(),
          status: status,
          rating: _double(data['rating']),
          year: _int(data['releaseYear']),
        ),
      ),
      description: data['description']?.toString() ?? '',
      alternativeTitles: _alternativeTitles(data['alternativeTitles']),
      genres: _categoryNames(data['categories']),
      author: _nullable(data['author']),
      artist: _nullable(data['artist']),
      status: status,
      externalUri: Uri.parse('$_base/manga/$slug'),
      chapters: _chapters(data['chapters']),
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final response = await _apiGet('/api/chapter/$chapterId');
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw MangaSourceSessionRequired(
        isAuthenticated
            ? 'Este capítulo requer uma assinatura VIP ativa.'
            : 'Este capítulo é VIP. Entre com uma conta assinante para ler.',
      );
    }
    _assertSuccess(response);
    final decoded = _decodePayload(response.body);
    if (decoded is! Map) throw const FormatException('Capítulo inválido.');
    final chapter = Map<String, dynamic>.from(decoded);
    final access = chapter['accessLevel']?.toString().toLowerCase();
    final rawPages = chapter['pages'];
    if ((access == 'vip' || access == 'coin') && rawPages is! List) {
      throw MangaSourceSessionRequired(
        isAuthenticated
            ? 'Este capítulo requer uma assinatura VIP ativa.'
            : 'Este capítulo é VIP. Entre com uma conta assinante para ler.',
      );
    }
    if (rawPages is! List) return;
    final pages = rawPages.whereType<Map>().toList()
      ..sort((a, b) => _int(a['pageNumber']).compareTo(_int(b['pageNumber'])));
    for (final raw in pages) {
      final uri = Uri.tryParse(raw['imageUrl']?.toString() ?? '');
      if (uri?.hasScheme == true) {
        yield MangaReaderPage.network(uri!, headers: coverImageHeaders);
      }
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      Uri.parse('$_base/ler/$mangaId/$chapterId');

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapter(mangaId, currentChapterId, 1);

  @override
  Future<String?> previousChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapter(mangaId, currentChapterId, -1);

  Future<String?> _adjacentChapter(
    String mangaId,
    String currentChapterId,
    int offset,
  ) async {
    final chapters = (await getDetails(mangaId)).chapters.toList()
      ..sort((a, b) => _number(a.number).compareTo(_number(b.number)));
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    final target = index + offset;
    return index < 0 || target < 0 || target >= chapters.length
        ? null
        : chapters[target].id;
  }

  Future<http.Response> _apiGet(String path) async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(sessionKey);
    }
    return _client.get(Uri.parse('$_base$path'), headers: requestHeaders);
  }

  void _assertSuccess(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const MangaSourceSessionRequired('authentication_required');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Nexus Toons: HTTP ${response.statusCode}');
    }
  }

  MangaCatalogItem _catalogItem(Map<String, dynamic> data) {
    final status = mangaStatusFromString(data['status']);
    final slug = data['slug']?.toString() ?? data['id']?.toString() ?? '';
    return MangaCatalogItem(
      id: slug,
      title: data['title']?.toString() ?? '',
      coverUri: Uri.tryParse(data['coverImage']?.toString() ?? ''),
      subtitle: mangaCatalogSubtitle(
        latestChapter: _latestChapter(data['chapters']),
        totalChapters: _int(data['chapterCount']),
        format: data['type']?.toString(),
        status: status,
        rating: _double(data['rating']),
        year: _int(data['releaseYear']),
      ),
    );
  }

  List<MangaChapter> _chapters(dynamic raw) {
    if (raw is! List) return const [];
    final chapters = raw.whereType<Map>().map((entry) {
      final data = Map<String, dynamic>.from(entry);
      final number = normalizeMangaChapterNumber(data['number']) ?? '';
      final access = data['accessLevel']?.toString().toLowerCase();
      final title = _nullable(data['title']);
      return MangaChapter(
        id: data['id']?.toString() ?? '',
        title: title ?? 'Chapter $number',
        number: number,
        language: 'pt-br',
        uploader: access == 'vip'
            ? 'VIP'
            : access == 'coin'
                ? 'Coins'
                : null,
        publishedAt: data['createdAt']?.toString(),
      );
    }).toList();
    chapters.sort((a, b) => _number(b.number).compareTo(_number(a.number)));
    return chapters;
  }

  static dynamic _decodePayload(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['d'] is! String || decoded['v'] is! num) {
      return decoded;
    }
    final keyIndex = _int(decoded['v']) == 1 ? 0 : _int(decoded['k']);
    if (keyIndex < 0 || keyIndex > 4) return decoded;
    final key = Uint8List.fromList(
      sha256
          .convert(utf8.encode('_orion_key_${keyIndex}_v2_$_cryptoSecret'))
          .bytes,
    );
    final sbox = List<int>.generate(256, (index) => index);
    var j = 0;
    for (var index = 0; index < 256; index++) {
      j = (j + sbox[index] + key[index % key.length]) % 256;
      final current = sbox[index];
      sbox[index] = sbox[j];
      sbox[j] = current;
    }
    final reverse = List<int>.filled(256, 0);
    for (var index = 0; index < 256; index++) {
      reverse[sbox[index]] = index;
    }
    final input = base64Decode(decoded['d'] as String);
    final output = Uint8List(input.length);
    for (var index = input.length - 1; index >= 0; index--) {
      var value = input[index];
      value ^= index > 0 ? input[index - 1] : key.last;
      value = reverse[value];
      final shift =
          (((key[(index + 3) % key.length] + (index & 255)) & 255) % 7) + 1;
      value = _rotateRight(value, shift);
      value ^= key[index % key.length];
      output[index] = value;
    }
    return jsonDecode(utf8.decode(output));
  }

  static int _rotateRight(int value, int bits) {
    final shift = bits % 8;
    return ((value >> shift) | ((value << (8 - shift)) & 255)) & 255;
  }

  static Map<String, String> _parseSetCookie(String? header) {
    if (header == null || header.isEmpty) return const {};
    final cookies = <String, String>{};
    final matches =
        RegExp(r'(?:^|,\s*)([A-Za-z0-9_-]+)=([^;,]*)').allMatches(header);
    for (final match in matches) {
      final name = match.group(1);
      if (name != null && name.isNotEmpty) cookies[name] = match.group(2) ?? '';
    }
    return cookies;
  }

  static String? _errorMessage(dynamic payload) {
    if (payload is! Map) return null;
    return _nullable(
        payload['error'] ?? payload['message'] ?? payload['mensagem']);
  }

  static List<String> _categoryNames(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((value) => value['name']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static List<Map<String, String>> _alternativeTitles(dynamic raw) {
    if (raw is String) {
      final encoded = raw.trim();
      if ((encoded.startsWith('[') && encoded.endsWith(']')) ||
          (encoded.startsWith('{') && encoded.endsWith('}'))) {
        try {
          return _alternativeTitles(jsonDecode(encoded));
        } on FormatException {
          // Fall through to the plain-text title parser below.
        }
      }
    }
    if (raw is List) {
      final titles = <Map<String, String>>[];
      for (final entry in raw) {
        if (entry is Map) {
          final language = _nullable(entry['lang'] ?? entry['language']) ?? '';
          final title = _nullable(entry['title'] ?? entry['name']);
          if (title != null) {
            titles.add({language: title});
            continue;
          }
          if (entry.isNotEmpty) {
            final key = entry.keys.first.toString();
            final mappedTitle = _nullable(entry[entry.keys.first]);
            if (mappedTitle != null) titles.add({key: mappedTitle});
          }
          continue;
        }
        final title = _nullable(entry);
        if (title != null) titles.add({'': title});
      }
      return titles;
    }
    if (raw is Map) {
      return raw.entries
          .map((entry) => MapEntry(
                entry.key.toString(),
                _nullable(entry.value),
              ))
          .where((entry) => entry.value != null)
          .map((entry) => {entry.key: entry.value!})
          .toList(growable: false);
    }
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return const [];
    return value
        .split(RegExp(r'[,;\n]'))
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .map((title) => {'': title})
        .toList(growable: false);
  }

  static String? _latestChapter(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final numbers = raw
        .whereType<Map>()
        .map((chapter) => chapter['number']?.toString() ?? '')
        .where((number) => number.isNotEmpty)
        .toList();
    if (numbers.isEmpty) return null;
    numbers.sort((a, b) => _number(b).compareTo(_number(a)));
    return numbers.first;
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static double? _double(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static double _number(String value) => double.tryParse(value) ?? 0;
}
