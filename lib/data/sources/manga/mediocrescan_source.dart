import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// MediocreScan / MediocreToons (https://mediocrescan.com) — Vite SPA backed by
/// a separate authenticated REST API. The JWT lands in the `token` cookie and
/// is sent as a Bearer token together with the client headers expected by the
/// API. Chapter pages are downloaded and streamed as files.
class MediocrescanSource
    implements
        MangaSource,
        CredentialAuthMangaSource,
        BrowserSessionMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        ReadingHistoryMangaSource,
        VariantCatalogMangaSource,
        FilterableMangaSource,
        ProfileAuthMangaSource {
  static const String _base = 'https://mediocrescan.com';
  static const List<String> _apiBases = <String>[
    'https://back2.mediocrescan.com',
  ];
  static const String _cdnBase = 'https://cdn.mediocrescan.com';
  static const String _catalogFormats = '1,3,4,5,13';
  static const String _tagFormats = '1,4,5,8,9,10,13';
  static const int _pageSize = 24;

  static const List<MangaCatalogVariant> _recentVariants = [
    MangaCatalogVariant(id: '5', label: 'Comic'),
    MangaCatalogVariant(id: '50005', label: 'AI translated comics'),
    MangaCatalogVariant(id: '4', label: 'Shoujo'),
    MangaCatalogVariant(id: '50004', label: 'AI translated shoujo'),
    MangaCatalogVariant(id: '13', label: 'Manga'),
    MangaCatalogVariant(id: '8', label: 'Yaoi'),
    MangaCatalogVariant(id: '9', label: 'Yuri'),
    MangaCatalogVariant(id: '10', label: 'NSFW'),
    MangaCatalogVariant(id: '1', label: 'English'),
  ];

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'MediocreScan',
    baseUrl: _base,
    contentType: ContentType.spa,
    auth: AuthConfig(
      loginUrl: '$_base/entrar',
      type: AuthType.genericForm,
      successUrlFragment: '/',
      sessionCookieNames: ['token', 'refresh_token'],
      logoutUrl: null,
    ),
    buildDetailUrl: (id, base) => '$base/obra/$id',
    buildChapterUrl: (id, base) => '$base/capitulo/$id',
    buildListUrl: (filter, page, base) => base,
    extractId: (url) {
      try {
        final segments =
            Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
        return segments.isNotEmpty ? segments.last : url;
      } catch (_) {
        return url;
      }
    },
  );

  final http.Client _client;
  final Future<Directory> Function() _documentsDirectory;
  Map<String, String> _cookies = {};
  String? _bearerToken;
  Future<bool>? _refreshInFlight;

  MediocrescanSource({
    http.Client? client,
    Future<Directory> Function()? documentsDirectoryProvider,
  })  : _client = client ?? http.Client(),
        _documentsDirectory =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  @override
  ScrapperProfile get authProfile => _profile;

  @override
  String get sessionKey => 'mediocrescan';

  @override
  String get id => 'mediocrescan';

  @override
  String get name => 'MediocreScan';

  @override
  Uri get baseUri => Uri.parse(_base);

  @override
  Uri get loginUri => Uri.parse(_profile.auth.loginUrl);

  @override
  Map<String, String> get requestHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'application/json, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': '$_base/',
        'x-app-key': 'toons-mediocre-app',
        'x-client-platform': 'app',
        if (_bearerToken != null && _bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $_bearerToken',
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'image/webp,image/*,*/*',
        'Referer': '$_base/',
        'x-app-key': 'toons-mediocre-app',
        'x-client-platform': 'app',
        if (_bearerToken != null && _bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $_bearerToken',
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.popular,
        MangaCatalogFilter.recent,
        MangaCatalogFilter.added,
      ];

  // ─── Session ───────────────────────────────────────────────────────────────

  @override
  bool get isAuthenticated => _bearerToken != null && _bearerToken!.isNotEmpty;

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) async {
    _cookies = Map.from(cookies);
    _bearerToken = cookies['token'] ?? cookies['access_token'];
    if (_bearerToken != null && !_cookies.containsKey('token')) {
      _cookies['token'] = _bearerToken!;
    }
    await SessionManager.saveCookies('mediocrescan', _cookies);
  }

  @override
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    final response = await _client.post(
      Uri.parse('${_apiBases.first}/auth/login'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'x-app-key': 'toons-mediocre-app',
        'x-client-platform': 'app',
      },
      body: jsonEncode({'email': username.trim(), 'senha': password}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('E-mail ou senha inválidos.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Login falhou: HTTP ${response.statusCode}');
    }

    final payload = _unwrapObject(jsonDecode(response.body));
    final token = _readAccessToken(payload);
    final refreshToken = payload['refresh_token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('O MediocreScan não retornou um token de sessão.');
    }

    final validation = await _client.get(
      Uri.parse('${_apiBases.first}/usuarios/me'),
      headers: {
        'Accept': 'application/json',
        'x-app-key': 'toons-mediocre-app',
        'x-client-platform': 'app',
        'Authorization': 'Bearer $token',
      },
    );
    if (validation.statusCode != 200) {
      throw Exception('O MediocreScan recusou a sessão recebida.');
    }

    await updateBrowserSession({
      'token': token,
      if (refreshToken != null && refreshToken.isNotEmpty)
        'refresh_token': refreshToken,
    });
  }

  @override
  Future<void> restoreSession() => _ensureSession();

  @override
  Future<void> logout() async {
    _cookies = {};
    _bearerToken = null;
    await SessionManager.clearSession('mediocrescan');
  }

  Future<void> _ensureSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies('mediocrescan');
      _bearerToken = _cookies['token'] ?? _cookies['access_token'];
    }
  }

  // ─── Catalog ───────────────────────────────────────────────────────────────

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final response = await _fetchBooksPage(filter: filter, page: page);
    final decoded = jsonDecode(response.body);
    final items = _extractItems(decoded).map(_catalogItem).toList();
    return MangaCatalogPage(
      items: items,
      nextCursor: _hasMore(decoded, items.length, page) ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final params = <String, String>{
      'limite': '$_pageSize',
      'pagina': '$page',
      'temCapitulo': 'true',
      'formato': _catalogFormats,
      'ordenarPor': 'criada_em_desc',
      'ocultar_adulto': '1',
      if (query.trim().isNotEmpty) 'string': query.trim(),
    };
    final res = await _apiGetPath(
      '/obras/buscar?${Uri(queryParameters: params).query}',
    );
    _assertAuth(res);
    final decoded = jsonDecode(res.body);
    final items = _extractItems(decoded).map(_catalogItem).toList();
    return MangaCatalogPage(
      items: items,
      nextCursor: _hasMore(decoded, items.length, page) ? '${page + 1}' : null,
    );
  }

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.recent ? _recentVariants : const [];

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) async {
    if (filter != MangaCatalogFilter.recent ||
        !_recentVariants.any((variant) => variant.id == variantId)) {
      return browse(filter: filter, cursor: cursor);
    }
    final page = int.tryParse(cursor ?? '') ?? 1;
    final isAi = variantId == '50005' || variantId == '50004';
    final format = switch (variantId) {
      '50005' => '5',
      '50004' => '4',
      _ => variantId,
    };
    final params = <String, String>{
      'limit': '$_pageSize',
      'offset': '${(page - 1) * _pageSize}',
      'formato': format,
      if (variantId != '10') 'ocultar_adulto': '1',
    };
    final endpoint =
        isAi ? '/obras/atualizadas-recentes-ia' : '/obras/atualizadas-recentes';
    final response = await _apiGetPath(
      '$endpoint?${Uri(queryParameters: params).query}',
    );
    _assertAuth(response);
    return _catalogPage(jsonDecode(response.body), page);
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final responses = await Future.wait([
      _apiGetPath('/obra-status'),
      _apiGetPath('/tags?formato=$_tagFormats'),
    ]);
    for (final response in responses) {
      _assertAuth(response);
    }
    return MangaSearchOptions(
      formats: _recentVariants.map(
        (variant) => MangaFilterOption(
          value: variant.id,
          label: variant.label,
        ),
      ),
      statuses: _filterOptions(
        jsonDecode(responses[0].body),
        idKeys: const ['id', 'stt_id'],
        nameKeys: const ['nome', 'stt_nome'],
      ),
      tags: _filterOptions(
        jsonDecode(responses[1].body),
        idKeys: const ['id', 'tag_id'],
        nameKeys: const ['nome', 'tag_nome'],
      ),
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final formats =
        request.formats.isEmpty ? _catalogFormats : request.formats.join(',');
    final params = <String, String>{
      'limite': '$_pageSize',
      'pagina': '$page',
      'formato': formats,
      if (request.statuses.isNotEmpty) 'status': request.statuses.join(','),
      if (request.tags.isNotEmpty) 'tags': request.tags.join(','),
      if (request.minimumChapters != null)
        'minCapitulos': '${request.minimumChapters}',
      if (request.maximumChapters != null)
        'maxCapitulos': '${request.maximumChapters}',
      'ordenarPor': _sortValue(request.sort),
      if (!request.formats.contains('10')) 'ocultar_adulto': '1',
    };
    final response = await _apiGetPath(
      '/obras/buscar?${Uri(queryParameters: params).query}',
    );
    _assertAuth(response);
    return _catalogPage(jsonDecode(response.body), page);
  }

  Future<http.Response> _fetchBooksPage({
    required MangaCatalogFilter filter,
    required int page,
  }) async {
    late final String path;
    switch (filter) {
      case MangaCatalogFilter.recent:
      case MangaCatalogFilter.updated:
        path = '/obras/atualizadas-recentes?${Uri(queryParameters: {
              'limit': '$_pageSize',
              'offset': '${(page - 1) * _pageSize}',
              'formato': _catalogFormats,
              'ocultar_adulto': '1',
            }).query}';
      case MangaCatalogFilter.added:
        path = '/obras/adicionados-recentes?${Uri(queryParameters: {
              'limit': '$_pageSize',
              'offset': '${(page - 1) * _pageSize}',
              'formato': _catalogFormats,
              'ocultar_adulto': '1',
            }).query}';
      default:
        path = '/obras/buscar?${Uri(queryParameters: {
              'limite': '$_pageSize',
              'pagina': '$page',
              'temCapitulo': 'true',
              'formato': _catalogFormats,
              'ordenarPor': 'populares',
              'ocultar_adulto': '1',
            }).query}';
    }
    final res = await _apiGetPath(path);
    _assertAuth(res);
    return res;
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final res = await _apiGetPath('/obras/$mangaId');
    _assertAuth(res);
    final data = _unwrapObject(jsonDecode(res.body));

    final embeddedChapters = _chaptersFrom(data['capitulos']);
    final chapters = embeddedChapters.isNotEmpty
        ? embeddedChapters
        : await _fetchAllChapters(mangaId);
    final mangaDbId = (data['id'] ?? data['obr_id'] ?? mangaId).toString();
    final status = _statusFrom(data['status'] ?? data['obr_status']);
    final format = _nestedName(data['formato']);
    final totalChapters = _readInt(
      data['total_capitulos'] ?? data['capitulos_count'],
    );
    final rating = _readRating(data);
    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaDbId,
        title: (data['nome'] ?? data['obr_nome'] ?? data['titulo'] ?? '')
            .toString(),
        coverUri: _coverUri(
          mangaDbId,
          data['imagem'] ?? data['obr_imagem'],
        ),
        subtitle: mangaCatalogSubtitle(
          totalChapters: totalChapters,
          format: format,
          status: status,
          rating: rating,
        ),
      ),
      description: (data['descricao'] ??
              data['obr_descricao'] ??
              data['synopsis'] ??
              data['sinopse'] ??
              '')
          .toString(),
      alternativeTitles: _alternativeTitles(data),
      genres: _readNames(data['tags']),
      author: _personName(
        data['autor'] ?? data['autores'] ?? data['author'],
      ),
      artist: _personName(
        data['artista'] ?? data['artistas'] ?? data['artist'],
      ),
      status: status,
      externalUri: Uri.tryParse('$_base/obra/$mangaDbId'),
      chapters: chapters,
    );
  }

  Future<List<MangaChapter>> _fetchAllChapters(String mangaId) async {
    final response = await _apiGetPath('/obras/$mangaId');
    _assertAuth(response);
    final data = _unwrapObject(jsonDecode(response.body));
    return _chaptersFrom(data['capitulos']);
  }

  List<MangaChapter> _chaptersFrom(dynamic raw) {
    if (raw is! List) return const [];
    final chapters = <MangaChapter>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final chapter = Map<String, dynamic>.from(value);
      final chapterId = chapter['id'] ?? chapter['cap_id'];
      if (chapterId == null) continue;
      final number = _numToString(chapter['numero'] ?? chapter['cap_num']);
      final name = (chapter['nome'] ?? chapter['cap_nome'])?.toString() ?? '';
      chapters.add(MangaChapter(
        id: chapterId.toString(),
        title: name.isNotEmpty ? name : 'Capítulo $number',
        number: number,
        volume: (chapter['volume'] ?? chapter['cap_volume'])?.toString(),
        language: 'pt-br',
        pages: (chapter['cap_paginas_count'] ??
                chapter['paginas_count'] ??
                chapter['total_paginas'] ??
                (chapter['tem_paginas'] == true ? '?' : null))
            ?.toString(),
        uploader: (chapter['equipe']?['nome'] ??
                chapter['usuario']?['nome'] ??
                chapter['user']?['nome'] ??
                '')
            .toString(),
        publishedAt: (chapter['cap_lancado_em'] ??
                chapter['lancado_em'] ??
                chapter['publicado_em'] ??
                chapter['criada_em'])
            ?.toString(),
      ));
    }
    chapters.sort(
      (left, right) =>
          _numToDouble(right.number).compareTo(_numToDouble(left.number)),
    );
    return chapters;
  }

  // ─── Reading ─────────────────────────────────────────────────────────────

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final res = await _apiGetPath('/capitulos/$chapterId');
    _assertAuth(res);
    final data = _unwrapObject(jsonDecode(res.body));
    final chapterType =
        (data['tipo'] ?? data['cap_tipo'] ?? 'imagem').toString().toLowerCase();
    if (chapterType != 'imagem') return;

    final obra = data['obra'] is Map
        ? Map<String, dynamic>.from(data['obra'] as Map)
        : const <String, dynamic>{};
    final obraId =
        (obra['id'] ?? obra['obr_id'] ?? data['obr_id'] ?? mangaId).toString();
    final numStr = _numToString(data['cap_num'] ?? data['numero']);
    final chapterUuid = data['cap_uuid']?.toString().trim() ?? '';
    var pages = _extractPagePaths(data['paginas2']);
    if (pages.isEmpty) pages = _extractPagePaths(data['paginas']);
    if (pages.isEmpty && chapterUuid.isNotEmpty) {
      pages = await _fetchChapterManifest(
        obraId: obraId,
        chapterNumber: numStr,
        chapterUuid: chapterUuid,
      );
    }

    final appDocDir = await _documentsDirectory();
    final tempDir =
        Directory(p.join(appDocDir.path, 'temp', 'mediocrescan', chapterId));
    await tempDir.create(recursive: true);

    for (var i = 0; i < pages.length; i++) {
      final imageUri = _pageUri(
        pages[i],
        obraId: obraId,
        chapterNumber: numStr,
        chapterUuid: chapterUuid,
      );
      if (imageUri == null) continue;
      final ext = p.extension(imageUri.path);
      final fileName =
          '${(i + 1).toString().padLeft(3, '0')}${ext.isNotEmpty ? ext : '.jpg'}';
      final response = await _client.get(imageUri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'image/webp,image/*,*/*',
        'Referer': '$_base/',
        'x-app-key': 'toons-mediocre-app',
        'x-client-platform': 'app',
      });
      if (response.statusCode != 200) continue;
      final file = File(p.join(tempDir.path, fileName));
      await file.writeAsBytes(response.bodyBytes);
      yield MangaReaderPage.file(file.path);
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      Uri.parse('$_base/capitulo/$chapterId');

  // ─── Account reading history ─────────────────────────────────────────────

  @override
  Future<List<MangaReadingHistoryEntry>> fetchReadingHistory() async {
    await _ensureSession();
    if (!isAuthenticated) {
      throw const MangaSourceSessionRequired('authentication_required');
    }

    const pageSize = 30;
    const maximumPages = 100;
    final entriesByBook = <String, MangaReadingHistoryEntry>{};
    var page = 1;

    while (page <= maximumPages) {
      final query = Uri(queryParameters: {
        'limite': '$pageSize',
        'pagina': '$page',
      }).query;
      final response = await _apiGetPath('/readings/continue/all?$query');
      _assertAuth(response);
      final decoded = jsonDecode(response.body);
      final rawItems = _extractItems(decoded);

      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final progress = Map<String, dynamic>.from(raw);
        final nestedBook = progress['obra'];
        final book = nestedBook is Map
            ? Map<String, dynamic>.from(nestedBook)
            : progress;
        final bookId =
            (book['id'] ?? book['obr_id'] ?? progress['obr_id'])?.toString();
        if (bookId == null || bookId.isEmpty) continue;

        final lastRaw = progress['ultimo_capitulo_lido'] ??
            progress['ultimo_lido'] ??
            book['ultimo_capitulo_lido'] ??
            book['ultimo_lido'];
        if (lastRaw is! Map) continue;
        final last = Map<String, dynamic>.from(lastRaw);
        final chapterId = (last['cap_id'] ?? last['id'])?.toString();
        if (chapterId == null || chapterId.isEmpty) continue;
        final chapterNumber = _numToString(
          last['cap_num'] ?? last['numero'] ?? last['chapter'],
        );
        final chapterTitle =
            (last['cap_nome'] ?? last['nome'] ?? '').toString().trim();
        final count = _readInt(
              progress['total_lidos'] ?? book['total_lidos'],
            ) ??
            1;
        final item = _catalogItem({...progress, ...book, 'id': bookId});

        entriesByBook[bookId] = MangaReadingHistoryEntry(
          details: MangaDetails(
            item: item,
            status: _statusFrom(book['status'] ?? book['obr_status']),
            externalUri: Uri.parse('$_base/obra/$bookId'),
          ),
          lastReadChapter: MangaChapter(
            id: chapterId,
            title: chapterTitle,
            number: chapterNumber,
            language: 'pt-br',
          ),
          readChapterCount: count < 1 ? 1 : count,
        );
      }

      if (!_hasMore(decoded, rawItems.length, page, pageSize: pageSize)) break;
      page++;
    }

    return entriesByBook.values.toList(growable: false);
  }

  @override
  Future<void> markChapterRead({
    required String mangaId,
    required String chapterId,
  }) async {
    final response = await _apiPostPath(
      '/readings/mark',
      {
        'obr_id': int.tryParse(mangaId) ?? mangaId,
        'cap_id': int.tryParse(chapterId) ?? chapterId
      },
    );
    _assertAuth(response);
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
    final chapters = await _fetchAllChapters(mangaId);
    chapters.sort(
        (a, b) => _numToDouble(a.number).compareTo(_numToDouble(b.number)));
    final index = chapters.indexWhere((c) => c.id == currentChapterId);
    if (index == -1) return null;
    final target = isNext ? index + 1 : index - 1;
    if (target < 0 || target >= chapters.length) return null;
    return chapters[target].id;
  }

  // ─── HTTP ────────────────────────────────────────────────────────────────

  Future<http.Response> _apiGetPath(String pathWithQuery) async {
    await _ensureSession();
    Exception? lastError;
    for (final base in _apiBases) {
      final url = '$base$pathWithQuery';
      try {
        var res = await _client.get(Uri.parse(url), headers: requestHeaders);
        if ((res.statusCode == 401 || res.statusCode == 403) &&
            await _refreshSession()) {
          res = await _client.get(Uri.parse(url), headers: requestHeaders);
        }
        final transient = res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504;
        if (transient) {
          lastError = Exception('HTTP ${res.statusCode} ao acessar $url');
          continue;
        }
        return res;
      } catch (e) {
        lastError = Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Falha ao acessar API da MediocreScan');
  }

  Future<http.Response> _apiPostPath(
    String path,
    Map<String, dynamic> body,
  ) async {
    await _ensureSession();
    Exception? lastError;
    for (final base in _apiBases) {
      final url = '$base$path';
      try {
        var res = await _client.post(
          Uri.parse(url),
          headers: {...requestHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if ((res.statusCode == 401 || res.statusCode == 403) &&
            await _refreshSession()) {
          res = await _client.post(
            Uri.parse(url),
            headers: {...requestHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          );
        }
        final transient = res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504;
        if (transient) {
          lastError = Exception('HTTP ${res.statusCode} ao acessar $url');
          continue;
        }
        return res;
      } catch (error) {
        lastError = Exception(error.toString());
      }
    }
    throw lastError ?? Exception('Falha ao acessar API da MediocreScan');
  }

  Future<bool> _refreshSession() {
    final running = _refreshInFlight;
    if (running != null) return running;
    final future = _performRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _performRefresh() async {
    await _ensureSession();
    final refreshToken = _cookies['refresh_token'];
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _client.post(
        Uri.parse('${_apiBases.first}/auth/refresh'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'x-app-key': 'toons-mediocre-app',
          'x-client-platform': 'app',
        },
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await logout();
        }
        return false;
      }
      final payload = _unwrapObject(jsonDecode(response.body));
      final token = _readAccessToken(payload);
      if (token == null || token.isEmpty) return false;
      await updateBrowserSession({
        'token': token,
        'refresh_token': payload['refresh_token']?.toString() ?? refreshToken,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _unwrapObject(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    final data = decoded['data'];
    return data is Map<String, dynamic> ? data : decoded;
  }

  static String? _readAccessToken(Map<String, dynamic> payload) {
    final direct = payload['token'] ?? payload['access_token'];
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return (data['token'] ?? data['access_token'])?.toString();
    }
    return null;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  MangaCatalogPage _catalogPage(dynamic decoded, int page) {
    final items = _extractItems(decoded).map(_catalogItem).toList();
    return MangaCatalogPage(
      items: items,
      nextCursor: _hasMore(decoded, items.length, page) ? '${page + 1}' : null,
    );
  }

  List<MangaFilterOption> _filterOptions(
    dynamic decoded, {
    required List<String> idKeys,
    required List<String> nameKeys,
  }) {
    return _extractItems(decoded).map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      Object? id;
      Object? name;
      for (final key in idKeys) {
        id ??= item[key];
      }
      for (final key in nameKeys) {
        name ??= item[key];
      }
      return MangaFilterOption(
        value: id?.toString() ?? '',
        label: name?.toString() ?? '',
      );
    }).where((option) {
      return option.value.isNotEmpty && option.label.isNotEmpty;
    }).toList(growable: false);
  }

  String _sortValue(MangaSearchSort sort) => switch (sort) {
        MangaSearchSort.recentlyAdded => 'criada_em_desc',
        MangaSearchSort.popular => 'populares',
        MangaSearchSort.rating => 'rating_desc',
        MangaSearchSort.titleAscending => 'nome_asc',
        MangaSearchSort.titleDescending => 'nome_desc',
        MangaSearchSort.chapterCount => 'capitulos_desc',
      };

  MangaCatalogItem _catalogItem(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    final id = m['id'] ?? m['obr_id'];
    final latest = _latestChapter(m);
    final totalChapters = _readInt(
      m['total_capitulos'] ??
          m['total_capitulos_ativos'] ??
          m['capitulos_count'],
    );
    return MangaCatalogItem(
      id: id.toString(),
      title: (m['nome'] ?? m['obr_nome'] ?? m['titulo'] ?? '').toString(),
      coverUri: _coverUri(id, m['imagem'] ?? m['obr_imagem']),
      subtitle: mangaCatalogSubtitle(
        latestChapter: latest,
        totalChapters: totalChapters,
        format: _nestedName(m['formato']),
        status: _statusFrom(m['status']),
        rating: _readRating(m),
      ),
    );
  }

  void _assertAuth(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const MangaSourceSessionRequired('authentication_required');
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode} ao acessar ${res.request?.url}');
    }
    if (res.body.startsWith('{"message":"Token') ||
        res.body.startsWith('{"statusCode":401') ||
        res.body.startsWith('{"message":"Não autorizado') ||
        res.body.startsWith('{"message":"N\\u00e3o autorizado')) {
      throw const MangaSourceSessionRequired('authentication_required');
    }
  }

  List<dynamic> _extractItems(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in const ['data', 'obras', 'items']) {
        final value = decoded[key];
        if (value is List) return value;
        if (value is Map) {
          final nested = _extractItems(value);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return const <dynamic>[];
  }

  Uri? _coverUri(dynamic id, dynamic imagem) {
    var img = imagem?.toString().trim() ?? '';
    if (img.isEmpty) return null;
    final absolute = Uri.tryParse(img);
    if (absolute != null && absolute.hasScheme) {
      if (!absolute.path.contains('/obras/$id/')) return absolute;
      final segments = absolute.pathSegments.where((part) => part.isNotEmpty);
      if (segments.isEmpty) return absolute;
      img = segments.last;
    } else {
      img = img.replaceFirst(RegExp(r'^/+'), '').split('/').last;
    }
    if (img.isEmpty) return null;
    return Uri.parse('${_apiBases.first}/media/obras/$id/capa').replace(
      queryParameters: {
        'f': img,
        'w': '520',
        'q': '75',
        'fit': 'cover',
      },
    );
  }

  bool _hasMore(
    dynamic decoded,
    int itemCount,
    int page, {
    int pageSize = _pageSize,
  }) {
    if (decoded is Map) {
      final pagination = decoded['pagination'] ??
          decoded['paginacao'] ??
          (decoded['data'] is Map
              ? (decoded['data'] as Map)['pagination'] ??
                  (decoded['data'] as Map)['paginacao']
              : null);
      if (pagination is Map) {
        final explicit = pagination['hasNextPage'] ?? pagination['hasNext'];
        if (explicit is bool) return explicit;
        final totalPages = _readInt(
          pagination['totalPages'] ??
              pagination['totalPaginas'] ??
              pagination['paginas'],
        );
        if (totalPages != null) return page < totalPages;
        final totalItems = _readInt(
          pagination['totalItems'] ?? pagination['total'],
        );
        if (totalItems != null) return page * pageSize < totalItems;
      }
      final total = _readInt(decoded['total']);
      if (total != null) return page * pageSize < total;
    }
    return itemCount >= pageSize;
  }

  Future<List<String>> _fetchChapterManifest({
    required String obraId,
    required String chapterNumber,
    required String chapterUuid,
  }) async {
    final candidates = <Uri>[
      if (obraId.isNotEmpty && chapterNumber.isNotEmpty)
        Uri.parse(
          '$_cdnBase/obras/$obraId/capitulos/$chapterNumber/$chapterUuid.json',
        ),
      Uri.parse('$_cdnBase/capitulos/$chapterUuid.json'),
    ];
    for (final uri in candidates) {
      try {
        final response = await _client.get(uri, headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json, */*',
          'Referer': '$_base/',
          'x-app-key': 'toons-mediocre-app',
          'x-client-platform': 'app',
        });
        if (response.statusCode != 200) continue;
        final pages = _extractPagePaths(jsonDecode(response.body));
        if (pages.isNotEmpty) return pages;
      } catch (_) {
        // Try the alternate manifest layout used by older chapters.
      }
    }
    return const [];
  }

  List<String> _extractPagePaths(dynamic raw) {
    final items = raw is List
        ? raw
        : raw is Map
            ? (raw['pages'] ?? raw['paginas'] ?? raw['items'])
            : null;
    if (items is! List) return const [];
    final pages = <String>[];
    for (final item in items) {
      if (item is String && item.trim().isNotEmpty) {
        pages.add(item.trim());
        continue;
      }
      if (item is Map) {
        final path = item['src'] ??
            item['url'] ??
            item['pag_url'] ??
            item['path'] ??
            item['file'] ??
            item['filename'] ??
            item['nome'];
        if (path != null && path.toString().trim().isNotEmpty) {
          pages.add(path.toString().trim());
        }
      }
    }
    return pages;
  }

  Uri? _pageUri(
    String source, {
    required String obraId,
    required String chapterNumber,
    required String chapterUuid,
  }) {
    final value = source.trim();
    if (value.isEmpty) return null;
    final absolute = Uri.tryParse(value);
    if (absolute != null &&
        (absolute.scheme == 'http' || absolute.scheme == 'https')) {
      return absolute;
    }
    final relative = value.replaceFirst(RegExp(r'^/+'), '');
    if (relative.startsWith('obras/') || relative.startsWith('capitulos/')) {
      return Uri.tryParse('$_cdnBase/$relative');
    }
    final filename = relative.split('/').last;
    if (filename.isEmpty) return null;
    if (chapterUuid.isNotEmpty) {
      return Uri.tryParse('$_cdnBase/capitulos/$chapterUuid/$filename');
    }
    return Uri.tryParse(
      '$_cdnBase/obras/$obraId/capitulos/$chapterNumber/$filename',
    );
  }

  String _latestChapter(Map<String, dynamic> data) {
    final direct = data['capitulo_numero'] ??
        data['ultimo_capitulo_numero'] ??
        data['ultimo_cap_numero'];
    if (direct != null) return _numToString(direct);
    for (final key in const [
      'ultimo_capitulo',
      'ultimos_capitulos',
      'capitulos'
    ]) {
      final value = data[key];
      final item = value is List && value.isNotEmpty ? value.first : value;
      if (item is Map) {
        final number = item['numero'] ?? item['cap_num'];
        if (number != null) return _numToString(number);
      }
    }
    return '';
  }

  MangaStatus _statusFrom(dynamic value) {
    final name = _nestedName(value);
    return mangaStatusFromString(name);
  }

  String? _nestedName(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Map) {
      final name = value['nome'] ??
          value['name'] ??
          value['label'] ??
          value['formt_nome'] ??
          value['stt_nome'] ??
          value['tag_nome'] ??
          value['aut_nome'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    }
    return null;
  }

  double? _readRating(Map<String, dynamic> data) {
    final direct = _readDouble(data['nota'] ?? data['rating']);
    if (direct != null && direct > 0) return direct;
    final reactions = data['reacoes'];
    if (reactions is! Map) return null;
    const weights = <String, int>{
      'ruim': 1,
      'raiva': 2,
      'triste': 3,
      'fraco': 4,
      'gostei': 5,
      'uau': 6,
      'fogo': 7,
      'top': 8,
      'incrivel': 9,
      'amei': 10,
    };
    var weighted = 0.0;
    var votes = 0;
    for (final entry in weights.entries) {
      final count = _readInt(reactions[entry.key]) ?? 0;
      weighted += entry.value * count;
      votes += count;
    }
    return votes == 0 ? null : weighted / votes;
  }

  List<String> _readNames(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map(_nestedName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, String>> _alternativeTitles(Map<String, dynamic> data) {
    final raw = data['nomes_alternativos'] ??
        data['titulos_alternativos'] ??
        data['alternativos'] ??
        data['obr_nome_alternativo'] ??
        data['obr_nome_alt'];
    if (raw is String && raw.trim().isNotEmpty) {
      return [
        {'unknown': raw.trim()}
      ];
    }
    if (raw is! List) return const [];
    final titles = <Map<String, String>>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        titles.add({'unknown': item.trim()});
      } else if (item is Map) {
        final title = item['titulo'] ?? item['nome'] ?? item['title'];
        if (title != null && title.toString().trim().isNotEmpty) {
          titles.add({
            (item['idioma'] ?? item['language'] ?? 'unknown').toString():
                title.toString().trim(),
          });
        }
      }
    }
    return titles;
  }

  String? _personName(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List) {
      final names = value.map(_nestedName).whereType<String>().toList();
      return names.isEmpty ? null : names.join(', ');
    }
    return _nestedName(value);
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value?.toString() ?? '').replaceAll(',', '.'));
  }

  static String _numToString(dynamic numero) {
    if (numero == null) return '';
    if (numero is double) {
      return numero == numero.truncateToDouble()
          ? numero.toInt().toString()
          : numero.toString();
    }
    return numero.toString();
  }

  static double _numToDouble(dynamic numero) {
    if (numero == null) return 0;
    if (numero is num) return numero.toDouble();
    return double.tryParse(numero.toString().replaceAll(',', '.')) ?? 0;
  }
}
