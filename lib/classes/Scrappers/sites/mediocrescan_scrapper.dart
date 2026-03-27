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
/// Contexto técnico:
///   • Next.js 14 (App Router) com rendering híbrido (SSR + client hydration)
///   • Cloudflare Turnstile (bot detection) na página de login
///   • Auth: formulário React com email/password, Google OAuth, Discord OAuth
///   • Conteúdo: 18.2k obras, 439.3k capítulos, exige assinatura ativa
///
/// Estratégia de autenticação:
///   Por ser Next.js com Cloudflare Turnstile, o login VIA HTTP puro é inviável
///   sem resolver o desafio JS. A autenticação SEMPRE acontece via WebView:
///
///   ```dart
///   await showAuthWebView(
///     context: context,
///     profile: MediocreScanScrapper().scrapperProfile,
///     onSuccess: (cookies) async {
///       await scrapper.updateSession(cookies);
///     },
///   );
///   ```
///
/// Estratégia de conteúdo:
///   O Next.js faz chamadas a uma API interna. Os endpoints precisam ser
///   descobertos monitorando o network tab após login. As chamadas são
///   autenticadas por Bearer token (JWT em cookie ou localStorage).
///
///   Até os endpoints serem descobertos, este scrapper usa uma abordagem
///   de WebView-fetch: envia uma requisição fetch() pelo contexto JS do
///   WebView autenticado e parseia o JSON de retorno.
///
/// TODO (requer inspeção pós-login):
///   1. Abrir /pesquisar com DevTools → aba Network
///   2. Digitar algo na busca e observar as chamadas XHR/Fetch
///   3. Identificar: base URL da API, headers de auth, estrutura do JSON
///   4. Substituir [_ApiEndpoints] com os valores corretos
///   5. Implementar [getAll], [searchTitle], [getBookDetails], [getChapter]
///      usando HTTP direto com os endpoints descobertos

class MediocreScanScrapper extends Scrapper {
  static const String _base = 'https://mediocrescan.com';

  Map<String, String> _cookies = {};
  String? _bearerToken;

  // ─── Perfil (para AuthWebViewScreen) ──────────────────────────────────────

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'MediocreScan',
    baseUrl: _base,
    contentType: ContentType.spa,

    auth: AuthConfig(
      loginUrl: '$_base/entrar',
      type: AuthType.webviewForm,

      // Login detectado quando URL muda de /entrar para outra rota
      successUrlFragment: '/',

      // TODO: identificar os cookies/tokens reais após inspeção pós-login
      // Candidatos comuns em Next.js: '__Secure-next-auth.session-token',
      // 'next-auth.session-token', 'token', 'auth_token'
      sessionCookieNames: ['__Secure-next-auth.session-token',
                           'next-auth.session-token',
                           'token',
                           'auth'],

      logoutUrl: '$_base/api/auth/signout',
    ),

    // ── URL builders (TODO: confirmar após inspeção) ──
    buildDetailUrl: (id, base) => '$base/obra/$id',     // TODO
    buildChapterUrl: (id, base) => '$base/capitulo/$id', // TODO
    buildListUrl: (filter, page, base) =>
        '$base/pesquisar?page=${page + 1}',              // TODO

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

  bool get isAuthenticated => _cookies.isNotEmpty || _bearerToken != null;

  Future<void> updateSession(Map<String, String> cookies) async {
    _cookies = Map.from(cookies);
    // Extrai Bearer token se presente como cookie (comum em Next.js)
    _bearerToken = cookies['token'] ??
        cookies['auth_token'] ??
        cookies['access_token'];
    await SessionManager.saveCookies(siteKey, cookies);
  }

  Future<void> _ensureSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(siteKey);
      _bearerToken = _cookies['token'] ??
          _cookies['auth_token'] ??
          _cookies['access_token'];
    }
  }

  Map<String, String> get _authHeaders => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': _base,
        if (_cookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(_cookies),
        if (_bearerToken != null)
          'Authorization': 'Bearer $_bearerToken',
      };

  // ─── API endpoints (TODO: preencher após inspeção de rede) ───────────────

  /// Candidatos de endpoints descobertos por análise de rotas Next.js:
  ///   /api/comics          → listagem
  ///   /api/comics/search   → busca
  ///   /api/comics/{id}     → detalhes
  ///   /api/chapters/{id}   → capítulo
  ///   /api/auth/session    → validação de sessão
  ///
  /// Para descobrir: depois de logado, abra o DevTools → Network →
  /// filtre por "Fetch/XHR" e navegue pelo site.
  static const _todoEndpoints = {
    'getAll': '$_base/api/comics',            // TODO
    'search': '$_base/api/comics/search',     // TODO
    'details': '$_base/api/comics/',          // TODO: + id
    'chapter': '$_base/api/chapters/',        // TODO: + id
    'session': '$_base/api/auth/session',     // TODO
  };

  Future<http.Response> _apiGet(String url) async {
    await _ensureSession();
    return http.get(Uri.parse(url), headers: _authHeaders);
  }

  void _assertAuth(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('authentication_required');
    }
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  // ─── Scrapper contract ────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getAll(String filter) async {
    // TODO: substituir pelo endpoint real após inspeção
    final url = _todoEndpoints['getAll']!;
    try {
      final res = await _apiGet(url);
      _assertAuth(res);
      final data = jsonDecode(res.body);
      // TODO: ajustar o caminho do JSON conforme a estrutura real
      final List<dynamic> items = data is List
          ? data
          : (data['data'] ?? data['comics'] ?? data['results'] ?? []);
      return items.map(_normalizeBook).toList();
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] getAll erro: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> loadMore(String filter) async {
    // TODO: implementar paginação real
    return getAll(filter);
  }

  @override
  Future<List<dynamic>> searchTitle(String title) async {
    // TODO: substituir pela URL real de busca
    final url = '${_todoEndpoints['search']}?q=${Uri.encodeComponent(title)}';
    try {
      final res = await _apiGet(url);
      _assertAuth(res);
      final data = jsonDecode(res.body);
      final List<dynamic> items = data is List
          ? data
          : (data['data'] ?? data['results'] ?? []);
      return items.map(_normalizeBook).toList();
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] searchTitle erro: $e');
      return [];
    }
  }

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    // TODO: ajustar endpoint e mapeamento JSON
    final url = '${_todoEndpoints['details']}$mangaID';
    try {
      final res = await _apiGet(url);
      _assertAuth(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _normalizeBookDetails(data);
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
    // TODO: ajustar endpoint e mapeamento JSON
    final url = '${_todoEndpoints['chapter']}$chapterID';
    try {
      final res = await _apiGet(url);
      _assertAuth(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // TODO: ajustar campo de imagens
      final images = (data['images'] ?? data['pages'] ?? []) as List;
      yield {
        'chapterID': chapterID,
        'chapterWebviewUrl': '$_base/capitulo/$chapterID', // fallback WebView
        'images': images.cast<String>(),
      };
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      // Fallback: abre o capítulo via WebView
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
    // TODO: implementar navegação de capítulos
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

  // ─── Normalização de dados ────────────────────────────────────────────────

  /// Normaliza um item de livro da API para o formato interno do app.
  /// TODO: ajustar os campos conforme a estrutura JSON real do site.
  Map<String, dynamic> _normalizeBook(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    return {
      'id': (m['id'] ?? m['slug'] ?? m['_id'] ?? '').toString(),
      'title': (m['title'] ?? m['name'] ?? m['nome'] ?? '').toString(),
      'coverImageUrl': (m['cover'] ??
              m['thumbnail'] ??
              m['coverUrl'] ??
              m['image'] ??
              '')
          .toString(),
      'status': (m['status'] ?? '').toString(),
      'type': 'manga',
    };
  }

  Map<String, dynamic> _normalizeBookDetails(Map<String, dynamic> m) {
    final chapters = (m['chapters'] ?? m['capitulos'] ?? []) as List;
    return {
      'id': (m['id'] ?? m['slug'] ?? '').toString(),
      'title': (m['title'] ?? m['name'] ?? '').toString(),
      'coverImageUrl': (m['cover'] ?? m['thumbnail'] ?? '').toString(),
      'description': (m['description'] ?? m['synopsis'] ?? m['sinopse'] ?? '').toString(),
      'chapters': chapters.map((c) {
        final ch = c as Map<String, dynamic>;
        return {
          'id': (ch['id'] ?? ch['slug'] ?? '').toString(),
          'title': (ch['title'] ?? ch['name'] ?? ch['numero'] ?? '').toString(),
          'translatedLanguage': 'pt-br',
        };
      }).toList(),
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
