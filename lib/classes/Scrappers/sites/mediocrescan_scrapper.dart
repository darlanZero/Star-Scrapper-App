import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/session_manager.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// MediocreScanScrapper
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Scrapper para https://mediocrescan.com (MediocreToons)
///
/// Stack: Next.js 14 (App Router), REST API separada.
/// Host atual observado: https://api.mediocretoons.net
/// Host legado: https://api.mediocrescan.com (fallback de compatibilidade)
///
/// Autenticação:
///   Next.js com Cloudflare Turnstile → login sempre via WebView.
///   O token JWT fica no cookie `token` (não-HttpOnly) em mediocrescan.com.
///   Após a WebView capturar os cookies, usa o Bearer token para a API.
///
/// Endpoints confirmados (inspeção DevTools — março 2026):
///   GET  /obras/atualizados?limite=24&pagina=N    → recentemente atualizados (requer auth)
///   GET  /obras/recentes?limite=24&pagina=N       → recentemente adicionados (público)
///   GET  /obras/novos?limite=24&pagina=N          → novos (requer auth)
///   GET  /obras/buscar?q={q}&limite=24&pagina=N   → busca
///   GET  /obras/{id}                              → detalhe da obra
///   GET  /capitulos?obr_id={id}&page=N&limite=50  → capítulos da obra
///   GET  /capitulos/{id}                          → detalhe + páginas
///
/// CDN de capas:
///   https://cdn.mediocretoons.site/obras/{id}/{hash}.webp
///
/// Imagens de capítulo:
///   https://cdn.mediocrescan.com/obras/{obra_id}/capitulos/{numero}/{src}
class MediocreScanScrapper extends Scrapper {
  static const String _base = 'https://mediocrescan.com';
  static const List<String> _apiBases = <String>[
    'https://api.mediocretoons.net',
    'https://api.mediocrescan.com',
  ];
  static const String _primaryApiBase = 'https://api.mediocretoons.net';
  static const String _cdnBase = 'https://cdn.mediocrescan.com';
  static const String _coverCdnBase = 'https://cdn.mediocretoons.site';

  Map<String, String> _cookies = {};
  String? _bearerToken;
  int _currentPage = 1;
  String _currentFilter = '';
  final Set<String> _seenBookIds = <String>{};

  // ─── Perfil (para AuthWebViewScreen) ──────────────────────────────────────

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
        final uri = Uri.parse(url);
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        return segments.isNotEmpty ? segments.last : url;
      } catch (_) {
        return url;
      }
    },
  );

  @override
  ScrapperProfile get scrapperProfile => _profile;

  // ─── Sessão ───────────────────────────────────────────────────────────────

  String get siteKey => 'mediocrescan';

  bool get isAuthenticated => _bearerToken != null && _bearerToken!.isNotEmpty;

  @override
  Future<void> updateSession(Map<String, String> cookies) async {
    _cookies = Map.from(cookies);
    _bearerToken = cookies['token'];
    await SessionManager.saveCookies(siteKey, cookies);
  }

  @override
  Future<void> logout() async {
    _cookies = {};
    _bearerToken = null;
    await SessionManager.clearSession(siteKey);
  }

  /// Carrega cookies/token do [SessionManager] para a memória se ainda não carregados.
  Future<void> _ensureSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(siteKey);
      _bearerToken = _cookies['token'];
      debugPrint(
        '[MediocreScan] _ensureSession → '
        '${_cookies.length} cookies, '
        'authenticated=$isAuthenticated',
      );
    }
  }

  /// Restaura a sessão persistida para a memória antes das requests da biblioteca.
  ///
  /// Chamado por [FontBooksGalleryScreen] ao abrir o scrapper, garantindo que os
  /// tokens armazenados no [SessionManager] estejam disponíveis para a primeira request.
  @override
  Future<void> restoreSession() => _ensureSession();

  Map<String, String> get _authHeaders => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': _base,
        if (_bearerToken != null && _bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $_bearerToken',
      };

  Map<String, String> get _publicHeaders => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': _base,
      };

  // ─── HTTP ─────────────────────────────────────────────────────────────────

  Future<http.Response> _apiGet(String url) async {
    await _ensureSession();
    return http.get(Uri.parse(url), headers: _authHeaders);
  }

  Future<http.Response> _apiGetPublic(String url) async {
    return http.get(Uri.parse(url), headers: _publicHeaders);
  }

  Future<http.Response> _apiGetWithRetry(
    String url, {
    int maxAttempts = 2,
    bool usePublicHeaders = false,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = usePublicHeaders ? await _apiGetPublic(url) : await _apiGet(url);
        final transient = res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504;
        if (!transient || attempt == maxAttempts) {
          return res;
        }
      } catch (e) {
        lastError = e;
        if (attempt == maxAttempts) rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 350));
    }
    throw Exception('HTTP retry failed for $url ${lastError ?? ''}'.trim());
  }

  Future<http.Response> _apiGetPath(
    String pathWithQuery, {
    bool usePublicHeaders = false,
  }) async {
    Exception? lastError;
    for (final base in _apiBases) {
      final url = '$base$pathWithQuery';
      try {
        final res = await _apiGetWithRetry(
          url,
          usePublicHeaders: usePublicHeaders,
        );
        final isTransient =
            res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504;
        if (isTransient) {
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

  List<dynamic> _extractItems(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return data;
    }
    return <dynamic>[];
  }

  // ─── RSC fetch de "Recentemente Atualizados" ─────────────────────────────
  //
  // A página mediocrescan.com/atualizados usa Next.js App Router com streaming.
  // O HTML inicial é apenas um skeleton vazio — as obras chegam via React Server
  // Components (RSC), acessível com o parâmetro `_rsc=<token>` e header `RSC: 1`.
  //
  // O Next.js server chama api.mediocretoons.net/obras/atualizados com chave de
  // serviço (não token de usuário), então não há requisito de auth do lado cliente.
  //
  // Estrutura da linha RSC com obras (confirmada via DevTools):
  //   2:["$","$Ld",null,{"obras":[
  //     {"id":2330,"nome":"...","imagem":"hash.webp","capitulo_numero":32,
  //      "capitulos":[{"id":509151,"numero":32,"nome":"Capítulo 32",...},...]}
  //   ],"totalPaginas":89}]

  Future<List<dynamic>> _fetchAtualizadosRsc(int page) async {
    // Token de cache-busting (qualquer string aleatória)
    final rscToken = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final url = '$_base/atualizados?pagina=$page&_rsc=$rscToken';

    // Cookies de sessão (melhora cache hit no servidor se logado)
    await _ensureSession();
    final cookieHeader = SessionManager.buildCookieHeader(_cookies);

    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/x-component, */*',
        'RSC': '1',
        'Next-Router-State-Tree':
            '%5B%22%22%2C%7B%22children%22%3A%5B%22(main)%22%2C%7B%22children'
            '%22%3A%5B%22atualizados%22%2C%7B%22children%22%3A%5B%22__PAGE__%22'
            '%2C%7B%7D%5D%7D%5D%7D%5D%7D%5D',
        'Referer': _base,
        if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      },
    );

    if (res.statusCode == 503) {
      throw Exception('Serviço temporariamente indisponível (503)');
    }
    if (res.statusCode != 200) {
      throw Exception('RSC fetch falhou: HTTP ${res.statusCode}');
    }

    return _parseRscObras(res.body, page);
  }

  List<dynamic> _parseRscObras(String rscBody, int page) {
    // O payload RSC é newline-delimited. Procurar a linha com "obras":[
    for (final line in rscBody.split('\n')) {
      final obrasIdx = line.indexOf('"obras":[');
      if (obrasIdx == -1) continue;

      // Recuar até o { que abre o objeto pai de "obras"
      var objStart = obrasIdx - 1;
      while (objStart >= 0 && line[objStart] != '{') {
        objStart--;
      }
      if (objStart < 0) continue;

      // O objeto termina antes do ] final do wrapper RSC (ex: ...}])
      // Usar o último } da linha como fim do JSON
      final objEnd = line.lastIndexOf('}');
      if (objEnd <= objStart) continue;

      final jsonStr = line.substring(objStart, objEnd + 1);

      try {
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        final obras = parsed['obras'] as List?;
        if (obras == null || obras.isEmpty) {
          debugPrint('[MediocreScan] RSC p$page → lista vazia');
          return [];
        }
        final result = obras.map(_normalizeRscObra).toList();
        debugPrint('[MediocreScan] RSC p$page → ${result.length} obras');
        return result;
      } catch (e) {
        debugPrint('[MediocreScan] RSC parse erro: $e');
      }
    }

    debugPrint('[MediocreScan] RSC p$page → nenhuma linha com obras encontrada');
    return [];
  }

  Map<String, dynamic> _normalizeRscObra(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final id = m['id']?.toString() ?? '';
    final imagem = m['imagem']?.toString() ?? '';
    final capitulos = (m['capitulos'] as List?) ?? [];

    // Capítulo mais recente
    final capNumStr = m['capitulo_numero'] != null
        ? _numToString(m['capitulo_numero'])
        : '';
    String latestChapter = capNumStr;
    String latestChapterId = '';
    if (capitulos.isNotEmpty) {
      final cap = capitulos.first as Map<String, dynamic>;
      latestChapterId = cap['id']?.toString() ?? '';
      if (latestChapter.isEmpty) {
        latestChapter = _numToString(cap['numero']);
      }
    }

    return {
      'id': id,
      'title': (m['nome'] ?? '').toString(),
      'coverImageUrl': imagem.isNotEmpty
          ? '$_coverCdnBase/obras/$id/$imagem'
          : '',
      'status': '',
      'type': 'manga',
      'latestChapter': latestChapter,
      'latestChapterId': latestChapterId,
    };
  }

  Future<List<dynamic>> _fetchBooksPage({
    required String filter,
    required int page,
  }) async {
    final isRecent = filter.toLowerCase() == 'recent';

    if (isRecent) {
      // RSC fetch de mediocrescan.com/atualizados
      // (endpoint REST /obras/atualizados requer token de servidor — inacessível via token de usuário)
      // O Next.js server chama a API com sua própria chave de serviço; o RSC retorna as obras diretamente.
      return _fetchAtualizadosRsc(page);
    }

    // Popular / outros → API REST pública
    final res = await _apiGetPath('/obras/buscar?q=&limite=24&pagina=$page');
    _assertAuth(res);
    final decoded = jsonDecode(res.body);
    final items = _extractItems(decoded);
    return items.map(_normalizeBook).toList();
  }

  void _assertAuth(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('authentication_required');
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode} ao acessar ${res.request?.url}');
    }
    // Resposta 200 mas com payload de erro de auth (token ausente/inválido/expirado)
    // Verificação via startsWith para evitar falsos positivos em conteúdo de mangás
    if (res.body.startsWith('{"message":"Token') ||
        res.body.startsWith('{"statusCode":401') ||
        res.body.startsWith('{"message":"Não autorizado') ||
        res.body.startsWith('{"message":"N\\u00e3o autorizado')) {
      throw Exception('authentication_required');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _coverUrl(dynamic id, dynamic imagem) {
    final imgStr = imagem?.toString() ?? '';
    if (imgStr.isEmpty) return '';
    // CDN primário: cdn.mediocretoons.site/obras/{id}/{hash}
    // Fallback legado: api.mediocretoons.net/storage/obras/{id}/{imagem}
    if (imgStr.startsWith('http')) return imgStr;
    return '$_coverCdnBase/obras/$id/$imgStr';
  }

  String _numToString(dynamic numero) {
    if (numero == null) return '';
    if (numero is double) {
      return numero == numero.truncateToDouble()
          ? numero.toInt().toString()
          : numero.toString();
    }
    return numero.toString();
  }

  // ─── Normalização ─────────────────────────────────────────────────────────

  Map<String, dynamic> _normalizeBook(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final id = m['id'];
    final rawStatus = m['status'];
    final statusText = rawStatus is Map<String, dynamic>
        ? (rawStatus['nome'] ?? '').toString()
        : (rawStatus ?? '').toString();

    final latestChapter =
        m['capitulo_numero']?.toString() ?? m['total_capitulos']?.toString() ?? '';

    return {
      'id': id.toString(),
      'title': (m['nome'] ?? '').toString(),
      'coverImageUrl': _coverUrl(id, m['imagem']),
      'status': statusText,
      'type': 'manga',
      'latestChapter': latestChapter,
    };
  }

  Map<String, dynamic> _normalizeBookDetails(Map<String, dynamic> m) {
    final id = m['id'];
    final capitulos = (m['capitulos'] ?? []) as List;
    return {
      'id': id.toString(),
      'title': (m['nome'] ?? '').toString(),
      'coverImageUrl': _coverUrl(id, m['imagem']),
      'description': (m['descricao'] ?? '').toString(),
      'chapters': capitulos.map((c) {
        final ch = c as Map<String, dynamic>;
        final numStr = _numToString(ch['numero']);
        final nome = ch['nome']?.toString() ?? '';
        return {
          'id': ch['id'].toString(),
          'title': nome.isNotEmpty ? nome : 'Capítulo $numStr',
          'chapter': numStr,
          'volume': ch['volume']?.toString(),
          'pages': ch['paginas'] ?? (ch['tem_paginas'] == true ? '?' : null),
          'uploader': (ch['equipe']?['nome'] ?? ch['usuario']?['nome'] ?? '').toString(),
          'publishedAt': ch['lancado_em']?.toString() ?? '',
          'translatedLanguage': 'pt-br',
        };
      }).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> _fetchAllChapters(String mangaID) async {
    const int limit = 50;
    int page = 1;
    final List<Map<String, dynamic>> chapters = <Map<String, dynamic>>[];

    while (true) {
      final res = await _apiGetPath('/capitulos?obr_id=$mangaID&page=$page&limite=$limit');
      _assertAuth(res);
      final decoded = jsonDecode(res.body);
      final items = _extractItems(decoded).cast<dynamic>();
      if (items.isEmpty) break;

      for (final item in items) {
        final ch = item as Map<String, dynamic>;
        final numStr = _numToString(ch['numero']);
        final nome = ch['nome']?.toString() ?? '';
        chapters.add({
          'id': ch['id'].toString(),
          'title': nome.isNotEmpty ? nome : 'Capítulo $numStr',
          'chapter': numStr,
          'volume': ch['volume']?.toString(),
          'pages': ch['paginas'] ?? (ch['tem_paginas'] == true ? '?' : null),
          'uploader': (ch['equipe']?['nome'] ?? ch['usuario']?['nome'] ?? '').toString(),
          'publishedAt': ch['lancado_em']?.toString() ?? '',
          'translatedLanguage': 'pt-br',
        });
      }

      bool hasNext = false;
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

  // ─── Scrapper contract ────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getAll(String filter) async {
    _currentPage = 1;
    _currentFilter = filter.toLowerCase();
    _seenBookIds.clear();
    try {
      final firstPage = await _fetchBooksPage(filter: filter, page: 1);
      for (final b in firstPage) {
        final id = (b['id'] ?? '').toString();
        if (id.isNotEmpty) _seenBookIds.add(id);
      }
      return firstPage;
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] getAll erro: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> loadMore(String filter) async {
    if (_currentFilter != filter.toLowerCase()) {
      _currentFilter = filter.toLowerCase();
      _currentPage = 0;
      _seenBookIds.clear();
    }
    _currentPage++;
    try {
      final pageItems = await _fetchBooksPage(filter: filter, page: _currentPage);
      final deduped = <dynamic>[];
      for (final b in pageItems) {
        final id = (b['id'] ?? '').toString();
        if (id.isEmpty || _seenBookIds.contains(id)) continue;
        _seenBookIds.add(id);
        deduped.add(b);
      }
      return deduped;
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] loadMore erro: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> searchTitle(String title) async {
    final path =
        '/obras/buscar?q=${Uri.encodeComponent(title)}&limite=24&pagina=1';
    try {
      final res = await _apiGetPath(path);
      _assertAuth(res);
      final decoded = jsonDecode(res.body);
      final items = _extractItems(decoded);
      return items.map(_normalizeBook).toList();
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] searchTitle erro: $e');
      return [];
    }
  }

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    final path = '/obras/$mangaID';
    try {
      final res = await _apiGetPath(path);
      _assertAuth(res);
      final decoded = jsonDecode(res.body);
      final data = decoded is Map<String, dynamic>
          ? ((decoded['data'] is Map<String, dynamic>)
              ? decoded['data'] as Map<String, dynamic>
              : decoded)
          : <String, dynamic>{};

      final normalized = _normalizeBookDetails(data);
      final allChapters = await _fetchAllChapters(mangaID);
      normalized['chapters'] = allChapters;
      return normalized;
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      rethrow;
    }
  }

  @override
  Stream<Map<String, dynamic>> getChapter(
    String chapterID,
    String mangaID,
  ) async* {
    final path = '/capitulos/$chapterID';
    try {
      final res = await _apiGetPath(path);
      _assertAuth(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final paginas = (data['paginas'] ?? []) as List;
      final obra = data['obra'] as Map<String, dynamic>?;
      final obraId = obra?['obr_id']?.toString() ?? mangaID;
      final numStr = _numToString(data['numero']);

      final images = paginas
          .map((p) {
            final src = (p as Map<String, dynamic>)['src']?.toString() ?? '';
            if (src.isEmpty) return '';
            return '$_cdnBase/obras/$obraId/capitulos/$numStr/$src';
          })
          .where((u) => u.isNotEmpty)
          .toList();

      yield {
        'chapterID': chapterID,
        'chapterWebviewUrl': '$_base/capitulo/$chapterID',
        'images': images,
      };
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      yield {
        'chapterID': chapterID,
        'chapterWebviewUrl': '$_base/capitulo/$chapterID',
        'images': <String>[],
      };
    }
  }

  @override
  Stream<Map<String, dynamic>> retrieveLastChapter(
    String currentChapterId,
    String mangaId,
  ) async* {
    yield {
      'chapterID': currentChapterId,
      'chapterWebviewUrl': '$_base/capitulo/$currentChapterId',
    };
  }

  @override
  Stream<Map<String, dynamic>> retrieveNextChapter(
    String currentChapterId,
    String mangaId,
  ) async* {
    yield {
      'chapterID': currentChapterId,
      'chapterWebviewUrl': '$_base/capitulo/$currentChapterId',
    };
  }

  // ─── Identidade ───────────────────────────────────────────────────────────

  @override
  String getTitle(dynamic bookDetails) =>
      (bookDetails['title'] ?? '').toString();

  @override
  String getCoverImageUrl(dynamic bookDetails) =>
      (bookDetails['coverImageUrl'] ?? '').toString();

  @override
  String getBookId(dynamic bookDetails) =>
      (bookDetails['id'] ?? '').toString();
}