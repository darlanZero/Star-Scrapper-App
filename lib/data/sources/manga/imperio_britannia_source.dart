import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Império da Britannia — public PT-BR catalog with optional authentication
/// for VIP chapters. The Vite frontend talks to the same JSON API used here.
class ImperioBritanniaSource
    implements
        MangaSource,
        CredentialAuthMangaSource,
        BrowserSessionMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        FilterableMangaSource,
        ProfileAuthMangaSource {
  static const _base = 'https://imperiodabritannia.net';
  static const _apiBase = 'https://api.imperiodabritannia.net';
  static const _cdnBase = 'https://cdn.imperiodabritannia.net';
  static const _apiToken = 'bunker_api_token_secreto_2025';
  static const _pageSize = 24;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'Imperio Britannia',
    baseUrl: _base,
    contentType: ContentType.spa,
    auth: const AuthConfig(
      loginUrl: '$_base/login',
      type: AuthType.webviewOAuth,
      successUrlFragment: _base,
      sessionCookieNames: ['token'],
      logoutUrl: null,
    ),
    buildDetailUrl: (id, base) => '$base/manga/$id',
    buildChapterUrl: (id, base) => '$base/manga/$id',
    buildListUrl: (filter, page, base) => '$base/obras?pagina=${page + 1}',
    extractId: (url) {
      final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
      final mangaIndex = segments.indexOf('manga');
      return mangaIndex >= 0 && mangaIndex + 1 < segments.length
          ? segments[mangaIndex + 1]
          : url;
    },
  );

  final http.Client _client;
  Map<String, String> _session = {};
  String? _bearerToken;

  ImperioBritanniaSource({http.Client? client})
      : _client = client ?? http.Client();

  @override
  String get id => 'imperio_britannia';

  @override
  String get name => 'Império da Britannia';

  @override
  String get sessionKey => 'imperio_britannia';

  @override
  ScrapperProfile get authProfile => _profile;

  @override
  Uri get baseUri => Uri.parse(_base);

  @override
  Uri get loginUri => Uri.parse(_profile.auth.loginUrl);

  @override
  bool get isAuthenticated => _bearerToken?.isNotEmpty == true;

  @override
  Map<String, String> get requestHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Origin': _base,
        'Referer': '$_base/',
        'X-API-Token': _apiToken,
        'X-Noencryptionbritta': '1',
        'X-Brit-Cache': 'true',
        if (isAuthenticated) 'Authorization': 'Bearer $_bearerToken',
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '$_base/',
        if (isAuthenticated) 'Authorization': 'Bearer $_bearerToken',
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.updated,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.added,
        MangaCatalogFilter.alphabetical,
      ];

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) async {
    _session = Map<String, String>.from(cookies);
    _bearerToken = _session['token'] ?? _session['access_token'];
    if (_bearerToken?.isNotEmpty == true) {
      _session['token'] = _bearerToken!;
      final validation = await _client.get(
        Uri.parse('$_apiBase/api/auth/me'),
        headers: requestHeaders,
      );
      if (validation.statusCode != 200) {
        _session = {};
        _bearerToken = null;
        throw const MangaSourceSessionRequired(
          'O Império da Britannia recusou a sessão recebida.',
        );
      }
    }
    await SessionManager.saveCookies(sessionKey, _session);
  }

  @override
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    final response = await _client.post(
      Uri.parse('$_apiBase/api/auth/login'),
      headers: {...requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': username.trim(), 'senha': password}),
    );
    final decoded = _decodeObject(response.body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(decoded['mensagem'] ?? 'E-mail ou senha inválidos.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        decoded['mensagem'] ?? 'Login falhou: HTTP ${response.statusCode}',
      );
    }
    final token = decoded['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('O Império da Britannia não retornou uma sessão.');
    }
    await updateBrowserSession({'token': token});
  }

  @override
  Future<void> restoreSession() async {
    if (_session.isNotEmpty) return;
    _session = await SessionManager.loadCookies(sessionKey);
    _bearerToken = _session['token'] ?? _session['access_token'];
  }

  @override
  Future<void> logout() async {
    await restoreSession();
    if (isAuthenticated) {
      try {
        await _client.post(
          Uri.parse('$_apiBase/api/auth/logout'),
          headers: {...requestHeaders, 'Content-Type': 'application/json'},
          body: '{}',
        );
      } catch (_) {}
    }
    _session = {};
    _bearerToken = null;
    await SessionManager.clearSession(sessionKey);
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    if (filter == MangaCatalogFilter.updated ||
        filter == MangaCatalogFilter.recent) {
      final response = await _apiGet(
        '/api/capitulos/recentes?pagina=$page&limite=$_pageSize',
      );
      _assertSuccess(response);
      return _catalogPage(jsonDecode(response.body), page, key: 'obras');
    }
    final order = switch (filter) {
      MangaCatalogFilter.alphabetical => 'nome_asc',
      MangaCatalogFilter.added => 'criada_em_desc',
      _ => 'views_desc',
    };
    return _browseCatalog(page: page, order: order);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    return _browseCatalog(
      page: int.tryParse(cursor ?? '') ?? 1,
      query: query.trim(),
      order: 'criada_em_desc',
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final responses = await Future.wait([
      _apiGet('/api/filtros/formatos'),
      _apiGet('/api/filtros/tags'),
    ]);
    for (final response in responses) {
      _assertSuccess(response);
    }
    return MangaSearchOptions(
      formats: _options(jsonDecode(responses[0].body), 'formatos'),
      tags: _options(jsonDecode(responses[1].body), 'tags'),
      sorts: const [
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.popular,
        MangaSearchSort.titleAscending,
        MangaSearchSort.titleDescending,
        MangaSearchSort.chapterCount,
      ],
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
      tags: request.tags,
      order: switch (request.sort) {
        MangaSearchSort.popular => 'views_desc',
        MangaSearchSort.titleAscending => 'nome_asc',
        MangaSearchSort.titleDescending => 'nome_desc',
        MangaSearchSort.chapterCount => 'capitulos_desc',
        _ => 'criada_em_desc',
      },
    );
  }

  Future<MangaCatalogPage> _browseCatalog({
    required int page,
    required String order,
    String query = '',
    Set<String> formats = const {},
    Set<String> tags = const {},
  }) async {
    final params = <String, String>{
      'pagina': '$page',
      'limite': '$_pageSize',
      'ordem': order,
      if (query.isNotEmpty) 'busca': query,
      if (formats.isNotEmpty) 'formato_ids': formats.join(','),
      if (tags.isNotEmpty) 'tag_ids': tags.join(','),
    };
    final response = await _apiGet(
      '/api/obras?${Uri(queryParameters: params).query}',
    );
    _assertSuccess(response);
    return _catalogPage(jsonDecode(response.body), page, key: 'obras');
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final numeric = int.tryParse(mangaId) != null;
    final path = numeric
        ? '/api/obras/$mangaId'
        : '/api/obras/by-slug/${Uri.encodeComponent(mangaId)}';
    final response = await _apiGet(path);
    _assertSuccess(response);
    final root = _decodeObject(response.body);
    final raw = root['obra'];
    if (raw is! Map) throw const FormatException('Obra inválida.');
    final data = Map<String, dynamic>.from(raw);
    final id = data['id'].toString();
    final status = mangaStatusFromString(data['status_nome']);
    final chapters = _chapters(data['capitulos']);
    final slug = data['slug']?.toString();
    return MangaDetails(
      item: MangaCatalogItem(
        id: id,
        title: data['nome']?.toString() ?? '',
        coverUri: _cdnUri(data['imagem']),
        subtitle: mangaCatalogSubtitle(
          totalChapters: _int(data['total_capitulos']),
          format: data['formato_nome']?.toString(),
          status: status,
          rating: _double(data['avaliacao_media']),
        ),
      ),
      description: data['descricao']?.toString() ?? '',
      genres: _names(data['tags']),
      status: status,
      externalUri:
          Uri.parse('$_base/manga/${slug?.isNotEmpty == true ? slug : id}'),
      chapters: chapters,
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final response = await _apiGet(
      '/api/obras/$mangaId/capitulos/${Uri.encodeComponent(chapterId)}',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      if (!isAuthenticated) {
        throw const MangaSourceSessionRequired(
          'Este capítulo é VIP. Entre com uma conta assinante para ler.',
        );
      }
      throw Exception('Este capítulo requer uma assinatura VIP ativa.');
    }
    _assertSuccess(response);
    final root = _decodeObject(response.body);
    final raw = root['capitulo'];
    if (raw is! Map) throw const FormatException('Capítulo inválido.');
    final chapter = Map<String, dynamic>.from(raw);
    if (chapter['paywall_bloqueado'] == true) {
      if (!isAuthenticated) {
        throw const MangaSourceSessionRequired(
          'Este capítulo é VIP. Entre com uma conta assinante para ler.',
        );
      }
      throw Exception('Este capítulo requer uma assinatura VIP ativa.');
    }
    final rawPages = chapter['paginas'];
    if (rawPages is! List) return;
    final pages = rawPages.whereType<Map>().toList()
      ..sort((a, b) => _int(a['numero']).compareTo(_int(b['numero'])));
    for (final rawPage in pages) {
      final uri = _cdnUri(rawPage['cdn_id'] ?? rawPage['url']);
      if (uri != null) {
        yield MangaReaderPage.network(uri, headers: coverImageHeaders);
      }
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      Uri.parse('$_base/manga/$mangaId/capitulo/$chapterId');

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
    await restoreSession();
    return _client.get(Uri.parse('$_apiBase$path'), headers: requestHeaders);
  }

  void _assertSuccess(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const MangaSourceSessionRequired('authentication_required');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Império da Britannia: HTTP ${response.statusCode}');
    }
  }

  MangaCatalogPage _catalogPage(dynamic decoded, int page,
      {required String key}) {
    final root = decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    final rawItems = root[key] is List ? root[key] as List : const [];
    final items = rawItems.whereType<Map>().map((raw) {
      final data = Map<String, dynamic>.from(raw);
      return _catalogItem(data);
    }).toList(growable: false);
    final pagination = root['pagination'];
    final hasMore = pagination is Map
        ? pagination['hasNextPage'] == true ||
            page < _int(pagination['totalPaginas'])
        : items.length >= _pageSize;
    return MangaCatalogPage(
      items: items,
      nextCursor: hasMore ? '${page + 1}' : null,
    );
  }

  MangaCatalogItem _catalogItem(Map<String, dynamic> data) {
    final status = mangaStatusFromString(data['status_nome']);
    return MangaCatalogItem(
      id: data['id']?.toString() ?? '',
      title: data['nome']?.toString() ?? '',
      coverUri: _cdnUri(data['imagem']),
      subtitle: mangaCatalogSubtitle(
        totalChapters: _int(data['total_capitulos']),
        format: data['formato_nome']?.toString(),
        status: status,
        rating: _double(data['avaliacao_media']),
      ),
    );
  }

  List<MangaChapter> _chapters(dynamic raw) {
    if (raw is! List) return const [];
    final chapters = raw.whereType<Map>().map((value) {
      final data = Map<String, dynamic>.from(value);
      final number = _chapterNumber(data['numero']);
      final paywall =
          data['paywall_bloqueado'] == true || data['paywall'] == true;
      final rawTitle = data['nome']?.toString().trim() ?? '';
      return MangaChapter(
        id: number,
        title: rawTitle.isEmpty ? 'Capítulo $number' : rawTitle,
        number: number,
        language: 'pt-br',
        pages: data['total_paginas']?.toString(),
        uploader: paywall ? 'VIP' : null,
        publishedAt: (data['liberado_em'] ?? data['criado_em'])?.toString(),
      );
    }).toList();
    chapters.sort((a, b) => _number(b.number).compareTo(_number(a.number)));
    return chapters;
  }

  List<MangaFilterOption> _options(dynamic decoded, String key) {
    if (decoded is! Map || decoded[key] is! List) return const [];
    return (decoded[key] as List)
        .whereType<Map>()
        .map((raw) {
          return MangaFilterOption(
            value: raw['id']?.toString() ?? '',
            label: raw['nome']?.toString() ?? '',
          );
        })
        .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static List<String> _names(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) {
          if (value is Map) return value['nome']?.toString() ?? '';
          return value.toString();
        })
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static Uri? _cdnUri(dynamic value) {
    final path = value?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    final direct = Uri.tryParse(path);
    if (direct?.hasScheme == true) return direct;
    return Uri.tryParse('$_cdnBase/${path.replaceFirst(RegExp(r'^/+'), '')}');
  }

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static double? _double(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static double _number(String value) => double.tryParse(value) ?? 0;

  static String _chapterNumber(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final number = double.tryParse(text);
    if (number == null) return text;
    return number == number.truncateToDouble()
        ? number.toInt().toString()
        : number.toString().replaceFirst(RegExp(r'0+$'), '');
  }
}
