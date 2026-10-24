import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// MediocreScan / MediocreToons (https://mediocrescan.com) — Next.js 14 app with
/// a separate REST API. Login goes through a Cloudflare Turnstile WebView; the
/// JWT lands in the `token` cookie and is sent as a Bearer token.
///
/// "Recently updated" is read from the Next.js RSC stream; other listings and
/// details use the REST API. Chapter pages are downloaded and streamed as files.
class MediocrescanSource
    implements
        MangaSource,
        BrowserSessionMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        ProfileAuthMangaSource {
  static const String _base = 'https://mediocrescan.com';
  static const List<String> _apiBases = <String>[
    'https://api.mediocretoons.net',
    'https://api.mediocrescan.com',
  ];
  static const String _cdnBase = 'https://cdn.mediocrescan.com';
  static const String _coverCdnBase = 'https://cdn.mediocretoons.site';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'MediocreScan',
    baseUrl: _base,
    contentType: ContentType.spa,
    auth: AuthConfig(
      loginUrl: '$_base/entrar',
      type: AuthType.webviewForm,
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
  Map<String, String> _cookies = {};
  String? _bearerToken;

  int _currentPage = 1;
  String _currentFilter = '';
  final Set<String> _seenIds = <String>{};

  MediocrescanSource({http.Client? client})
      : _client = client ?? http.Client();

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
        'Referer': _base,
        if (_bearerToken != null && _bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $_bearerToken',
      };

  @override
  Map<String, String> get coverImageHeaders =>
      const {'User-Agent': _userAgent, 'Referer': '$_base/'};

  @override
  List<MangaCatalogFilter> get catalogFilters =>
      const [MangaCatalogFilter.popular, MangaCatalogFilter.recent];

  // ─── Session ───────────────────────────────────────────────────────────────

  @override
  bool get isAuthenticated => _bearerToken != null && _bearerToken!.isNotEmpty;

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) async {
    _cookies = Map.from(cookies);
    _bearerToken = cookies['token'];
    await SessionManager.saveCookies('mediocrescan', cookies);
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
      _bearerToken = _cookies['token'];
    }
  }

  // ─── Catalog ───────────────────────────────────────────────────────────────

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final filterKey = filter == MangaCatalogFilter.recent ? 'recent' : 'popular';
    if (_currentFilter != filterKey) {
      _currentFilter = filterKey;
      _currentPage = 1;
      _seenIds.clear();
    } else {
      _currentPage = int.tryParse(cursor ?? '') ?? _currentPage;
    }

    final items = await _fetchBooksPage(filter: filterKey, page: _currentPage);
    final deduped = <MangaCatalogItem>[];
    for (final item in items) {
      if (item.id.isEmpty || _seenIds.contains(item.id)) continue;
      _seenIds.add(item.id);
      deduped.add(item);
    }
    return MangaCatalogPage(
      items: deduped,
      nextCursor: items.isEmpty ? null : '${_currentPage + 1}',
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final path =
        '/obras/buscar?q=${Uri.encodeComponent(query)}&limite=24&pagina=1';
    final res = await _apiGetPath(path);
    _assertAuth(res);
    final items = _extractItems(jsonDecode(res.body)).map(_catalogItem);
    return MangaCatalogPage(items: items);
  }

  Future<List<MangaCatalogItem>> _fetchBooksPage({
    required String filter,
    required int page,
  }) async {
    if (filter == 'recent') return _fetchAtualizadosRsc(page);
    final res = await _apiGetPath('/obras/buscar?q=&limite=24&pagina=$page');
    _assertAuth(res);
    return _extractItems(jsonDecode(res.body)).map(_catalogItem).toList();
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final res = await _apiGetPath('/obras/$mangaId');
    _assertAuth(res);
    final decoded = jsonDecode(res.body);
    final data = decoded is Map<String, dynamic>
        ? (decoded['data'] is Map<String, dynamic>
            ? decoded['data'] as Map<String, dynamic>
            : decoded)
        : <String, dynamic>{};

    final chapters = await _fetchAllChapters(mangaId);
    final mangaDbId = (data['id'] ?? mangaId).toString();
    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaDbId,
        title: (data['nome'] ?? '').toString(),
        coverUri: _coverUri(mangaDbId, data['imagem']),
      ),
      description: (data['descricao'] ?? '').toString(),
      externalUri: Uri.tryParse('$_base/obra/$mangaDbId'),
      chapters: chapters,
    );
  }

  Future<List<MangaChapter>> _fetchAllChapters(String mangaId) async {
    const limit = 50;
    var page = 1;
    final chapters = <MangaChapter>[];
    while (true) {
      final res =
          await _apiGetPath('/capitulos?obr_id=$mangaId&page=$page&limite=$limit');
      _assertAuth(res);
      final decoded = jsonDecode(res.body);
      final items = _extractItems(decoded);
      if (items.isEmpty) break;
      for (final raw in items) {
        final ch = raw as Map<String, dynamic>;
        final numStr = _numToString(ch['numero']);
        final nome = ch['nome']?.toString() ?? '';
        chapters.add(MangaChapter(
          id: ch['id'].toString(),
          title: nome.isNotEmpty ? nome : 'Capítulo $numStr',
          number: numStr,
          volume: ch['volume']?.toString(),
          language: 'pt-br',
          pages: (ch['paginas'] ?? (ch['tem_paginas'] == true ? '?' : null))
              ?.toString(),
          uploader:
              (ch['equipe']?['nome'] ?? ch['usuario']?['nome'] ?? '').toString(),
          publishedAt: ch['lancado_em']?.toString(),
        ));
      }
      var hasNext = false;
      if (decoded is Map<String, dynamic>) {
        final pagination = decoded['pagination'];
        if (pagination is Map<String, dynamic>) {
          hasNext = pagination['hasNextPage'] == true;
        }
      }
      if (!hasNext && items.length < limit) break;
      page++;
    }
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
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final paginas = (data['paginas'] ?? []) as List;
    final obra = data['obra'] as Map<String, dynamic>?;
    final obraId = obra?['obr_id']?.toString() ?? mangaId;
    final numStr = _numToString(data['numero']);

    final appDocDir = await getApplicationDocumentsDirectory();
    final tempDir =
        Directory(p.join(appDocDir.path, 'temp', 'mediocrescan', chapterId));
    await tempDir.create(recursive: true);

    for (var i = 0; i < paginas.length; i++) {
      final src = (paginas[i] as Map<String, dynamic>)['src']?.toString() ?? '';
      if (src.isEmpty) continue;
      final imageUrl = '$_cdnBase/obras/$obraId/capitulos/$numStr/$src';
      final ext = p.extension(Uri.parse(src).path);
      final fileName =
          '${(i + 1).toString().padLeft(3, '0')}${ext.isNotEmpty ? ext : '.jpg'}';
      final response = await _client.get(Uri.parse(imageUrl), headers: {
        'User-Agent': _userAgent,
        'Referer': _base,
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
    chapters.sort((a, b) =>
        _numToDouble(a.number).compareTo(_numToDouble(b.number)));
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
        final res = await _client.get(Uri.parse(url), headers: requestHeaders);
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

  Future<List<MangaCatalogItem>> _fetchAtualizadosRsc(int page) async {
    final rscToken = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final url = '$_base/atualizados?pagina=$page&_rsc=$rscToken';
    await _ensureSession();
    final cookieHeader = SessionManager.buildCookieHeader(_cookies);
    final res = await _client.get(Uri.parse(url), headers: {
      'User-Agent': _userAgent,
      'Accept': 'text/x-component, */*',
      'RSC': '1',
      'Next-Router-State-Tree':
          '%5B%22%22%2C%7B%22children%22%3A%5B%22(main)%22%2C%7B%22children'
              '%22%3A%5B%22atualizados%22%2C%7B%22children%22%3A%5B%22__PAGE__%22'
              '%2C%7B%7D%5D%7D%5D%7D%5D%7D%5D',
      'Referer': _base,
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
    });
    if (res.statusCode != 200) {
      throw Exception('RSC fetch falhou: HTTP ${res.statusCode}');
    }
    return _parseRscObras(res.body, page);
  }

  List<MangaCatalogItem> _parseRscObras(String rscBody, int page) {
    for (final line in rscBody.split('\n')) {
      final obrasIdx = line.indexOf('"obras":[');
      if (obrasIdx == -1) continue;
      var objStart = obrasIdx - 1;
      while (objStart >= 0 && line[objStart] != '{') {
        objStart--;
      }
      if (objStart < 0) continue;
      final objEnd = line.lastIndexOf('}');
      if (objEnd <= objStart) continue;
      try {
        final parsed =
            jsonDecode(line.substring(objStart, objEnd + 1)) as Map<String, dynamic>;
        final obras = parsed['obras'] as List?;
        if (obras == null || obras.isEmpty) return const [];
        return obras.map(_rscItem).toList();
      } catch (e) {
        debugPrint('[MediocreScan] RSC parse erro: $e');
      }
    }
    return const [];
  }

  MangaCatalogItem _rscItem(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final id = m['id']?.toString() ?? '';
    final imagem = m['imagem']?.toString() ?? '';
    final capitulos = (m['capitulos'] as List?) ?? [];
    final capNum =
        m['capitulo_numero'] != null ? _numToString(m['capitulo_numero']) : '';
    final latest = capNum.isNotEmpty
        ? capNum
        : (capitulos.isNotEmpty
            ? _numToString((capitulos.first as Map)['numero'])
            : '');
    return MangaCatalogItem(
      id: id,
      title: (m['nome'] ?? '').toString(),
      coverUri: imagem.isEmpty
          ? null
          : Uri.tryParse('$_coverCdnBase/obras/$id/$imagem'),
      subtitle: latest.isEmpty ? null : 'Cap. $latest',
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  MangaCatalogItem _catalogItem(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final id = m['id'];
    final latest = m['capitulo_numero']?.toString() ??
        m['total_capitulos']?.toString() ??
        '';
    return MangaCatalogItem(
      id: id.toString(),
      title: (m['nome'] ?? '').toString(),
      coverUri: _coverUri(id, m['imagem']),
      subtitle: latest.isEmpty ? null : 'Cap. $latest',
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
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      return decoded['data'] as List;
    }
    return const <dynamic>[];
  }

  Uri? _coverUri(dynamic id, dynamic imagem) {
    final img = imagem?.toString() ?? '';
    if (img.isEmpty) return null;
    if (img.startsWith('http')) return Uri.tryParse(img);
    return Uri.tryParse('$_coverCdnBase/obras/$id/$img');
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
