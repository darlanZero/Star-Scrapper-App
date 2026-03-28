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
/// Stack: Next.js 14 (App Router), REST API separada em https://api.mediocrescan.com
///
/// Autenticação:
///   Next.js com Cloudflare Turnstile → login sempre via WebView.
///   O token JWT fica no cookie `token` (não-HttpOnly) em mediocrescan.com.
///   Após a WebView capturar os cookies, usa o Bearer token para a API.
///
/// Endpoints confirmados (inspeção DevTools — março 2026):
///   GET  /obras/recentes?limite=24&pagina=N       → listagem pública
///   GET  /obras/novos?limite=24&pagina=N          → novos (requer auth)
///   GET  /obras/buscar?q={q}&limite=24&pagina=N   → busca
///   GET  /obras/{id}                              → detalhe da obra
///   GET  /capitulos?obr_id={id}&page=N&limite=50  → capítulos da obra
///   GET  /capitulos/{id}                          → detalhe + páginas
///
/// Imagens de capítulo:
///   https://cdn.mediocrescan.com/obras/{obra_id}/capitulos/{numero}/{src}
class MediocreScanScrapper extends Scrapper {
  static const String _base = 'https://mediocrescan.com';
  static const String _apiBase = 'https://api.mediocrescan.com';
  static const String _cdnBase = 'https://cdn.mediocrescan.com';

  Map<String, String> _cookies = {};
  String? _bearerToken;
  int _currentPage = 1;

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

  Future<void> _ensureSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(siteKey);
      _bearerToken = _cookies['token'];
    }
  }

  Map<String, String> get _authHeaders => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': _base,
        if (_bearerToken != null && _bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $_bearerToken',
      };

  // ─── HTTP ─────────────────────────────────────────────────────────────────

  Future<http.Response> _apiGet(String url) async {
    await _ensureSession();
    return http.get(Uri.parse(url), headers: _authHeaders);
  }

  void _assertAuth(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('authentication_required');
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode} ao acessar ${res.request?.url}');
    }
    // Resposta 200 mas com payload de erro de auth (token ausente/inválido)
    // Verificação via startsWith para evitar falsos positivos em conteúdo de mangás
    if (res.body.startsWith('{"message":"Token') ||
        res.body.startsWith('{"statusCode":401')) {
      throw Exception('authentication_required');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _coverUrl(dynamic id, dynamic imagem) {
    final imgStr = imagem?.toString() ?? '';
    if (imgStr.isEmpty) return '';
    return '$_apiBase/storage/obras/$id/$imgStr?w=400';
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
    return {
      'id': id.toString(),
      'title': (m['nome'] ?? '').toString(),
      'coverImageUrl': _coverUrl(id, m['imagem']),
      'status': (m['status'] ?? '').toString(),
      'type': 'manga',
      'latestChapter': m['capitulo_numero']?.toString() ?? '',
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
          'translatedLanguage': 'pt-br',
        };
      }).toList(),
    };
  }

  // ─── Scrapper contract ────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getAll(String filter) async {
    _currentPage = 1;
    final endpoint = filter.toLowerCase() == 'recent'
        ? '$_apiBase/obras/novos?limite=24&pagina=1'
        : '$_apiBase/obras/recentes?limite=24&pagina=1';
    try {
      final res = await _apiGet(endpoint);
      _assertAuth(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['data'] ?? []) as List;
      return items.map(_normalizeBook).toList();
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] getAll erro: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> loadMore(String filter) async {
    _currentPage++;
    final endpoint = filter.toLowerCase() == 'recent'
        ? '$_apiBase/obras/novos?limite=24&pagina=$_currentPage'
        : '$_apiBase/obras/recentes?limite=24&pagina=$_currentPage';
    try {
      final res = await _apiGet(endpoint);
      _assertAuth(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['data'] ?? []) as List;
      return items.map(_normalizeBook).toList();
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] loadMore erro: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> searchTitle(String title) async {
    final url =
        '$_apiBase/obras/buscar?q=${Uri.encodeComponent(title)}&limite=24&pagina=1';
    try {
      final res = await _apiGet(url);
      _assertAuth(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['data'] ?? []) as List;
      return items.map(_normalizeBook).toList();
    } catch (e) {
      if (e.toString().contains('authentication_required')) rethrow;
      debugPrint('[MediocreScan] searchTitle erro: $e');
      return [];
    }
  }

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    final url = '$_apiBase/obras/$mangaID';
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
    final url = '$_apiBase/capitulos/$chapterID';
    try {
      final res = await _apiGet(url);
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