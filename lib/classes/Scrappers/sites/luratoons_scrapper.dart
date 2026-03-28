import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/classes/Scrappers/engine/base_html_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// LuraToonsScrapper
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Scrapper para https://luratoons.net
///
/// Stack: Vue.js 3 SPA + Django REST API backend.
///
/// Autenticação:
///   1. Form HTTP (email + senha):
///      ```dart
///      await scrapper.authenticateWithCredentials(email, senha);
///      ```
///   2. WebView (Google OAuth):
///      Após o OAuth, o sessionid HttpOnly fica na store do WebView2.
///      O proxy XHR (setHttpGetProxy) encaminha as requisições com withCredentials.
///
/// Endpoints REST confirmados (Playwright DevTools — março 2026):
///   GET /api/obras/             → { obras: [{id, slug, title, capa}] } — 268 itens, sem paginação
///   GET /api/obra/{slug}/       → detalhe: {titulo, sinopse, caps:[{num,slug,data,id}], generos, ...}
///   GET /{slug}/{cap_slug}/     → leitura via WebView (imagens cifradas por WASM/DRM)
///
/// Imagens de capítulo:
///   Cifradas em ArrayBuffer via WASM — não extraíveis sem o runtime JS/WASM do site.
///   A leitura usa a WebView autenticada (WebView2 possui o sessionid do OAuth).
class LuraToonsScrapper extends BaseHtmlScrapper {
  LuraToonsScrapper() : super(_profile);

  static const String _base = 'https://luratoons.net';

  // Cache de todas as obras (carregadas de uma só vez, sem paginação real).
  List<Map<String, dynamic>>? _cachedObras;

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'LuraToons',
    baseUrl: _base,
    contentType: ContentType.spa,

    auth: AuthConfig(
      loginUrl: '$_base/accounts/login/',
      type: AuthType.djangoForm,
      usernameFieldName: 'login',
      passwordFieldName: 'password',
      csrfFieldName: 'csrfmiddlewaretoken',
      csrfCookieName: 'csrftoken',
      successUrlFragment: '/',
      sessionCookieNames: ['sessionid', 'csrftoken'],
      logoutUrl: '$_base/accounts/logout/',
    ),

    // selectors: null — LuraToons é uma SPA com API REST; HTML scraping não é usado.

    buildDetailUrl: (id, base) => '$base/api/obra/$id/',
    buildChapterUrl: (id, base) => '$base/$id/',
    buildListUrl: (filter, page, base) => '$base/api/obras/',
    extractId: (url) {
      try {
        final uri = Uri.parse(url);
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        return segments.join('/');
      } catch (_) {
        return url;
      }
    },
  );

  // ─── Getters públicos ─────────────────────────────────────────────────────

  /// URL para iniciar login via Google OAuth (para uso em AuthWebViewScreen).
  static const String googleLoginUrl =
      '$_base/accounts/google/login/?process=login';

  @override
  ScrapperProfile get scrapperProfile => _profile;

  // ─── HTTP helpers ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _jsonGet(String url) async {
    final res = await httpGet(url);
    assertAuthResponse(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ─── Normalização ──────────────────────────────────────────────────────────

  static String _absoluteCover(String path) =>
      path.startsWith('http') ? path : '$_base$path';

  List<Map<String, dynamic>> _normalizeObras(List<dynamic> obras) {
    return obras
        .map((o) {
          final obra = o as Map<String, dynamic>;
          final slug = obra['slug']?.toString() ?? '';
          if (slug.isEmpty) return null;
          return <String, dynamic>{
            'id': slug,
            'title': obra['title']?.toString() ?? '',
            'coverImageUrl': _absoluteCover(obra['capa']?.toString() ?? ''),
            'type': 'manga',
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchObras() async {
    final data = await _jsonGet('$_base/api/obras/');
    return _normalizeObras((data['obras'] ?? []) as List<dynamic>);
  }

  // ─── Contrato Scrapper ────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getAll(String filter) async {
    final all = await _fetchObras();
    _cachedObras = all;
    if (filter.toLowerCase() == 'recent') {
      // /api/recentes/ não existe — ordena por id descrescente (mais recente primeiro).
      final sorted = [...all];
      sorted.sort((a, b) => (b['id'] as String).compareTo(a['id'] as String));
      return sorted;
    }
    return all; // popular = ordem padrão da API
  }

  @override
  Future<List<dynamic>> loadMore(String filter) async {
    // Toda a listagem já vem em uma única requisição — nada mais a carregar.
    return [];
  }

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    // mangaID é o slug da obra (ex.: "minha-vida-escolar-fingindo")
    final data = await _jsonGet('$_base/api/obra/$mangaID/');

    final caps = (data['caps'] ?? []) as List<dynamic>;
    final generos = (data['generos'] ?? []) as List<dynamic>;

    final chapters = caps
        .map((c) {
          final cap = c as Map<String, dynamic>;
          final slug = cap['slug']?.toString() ?? '';
          if (slug.isEmpty) return null;
          return <String, dynamic>{
            'id': slug,
            'title': '',
            'chapter': cap['num']?.toString() ?? '',
            'translatedLanguage': 'pt-br',
            'publishedAt': cap['data']?.toString() ?? '',
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final capa = data['capa']?.toString() ?? '';
    return {
      'id': mangaID,
      'title': data['titulo']?.toString() ?? '',
      'coverImageUrl': _absoluteCover(capa),
      'description': data['sinopse']?.toString() ?? '',
      'tags': generos
          .map((g) =>
              ((g as Map<String, dynamic>)['name']?.toString()) ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
      'status': data['status']?.toString() ?? '',
      'author': data['autor']?.toString() ?? '',
      'chapters': chapters,
    };
  }

  @override
  Stream<Map<String, dynamic>> getChapter(
    String chapterID,
    String mangaID,
  ) async* {
    // As imagens de capítulo são cifradas por DRM/WASM e só podem ser
    // renderizadas pelo runtime JS/WASM do próprio site.
    // A leitura ocorre via WebView autenticada (WebView2 possui o sessionid).
    yield {
      'chapterID': chapterID,
      'chapterWebviewUrl': '$_base/$mangaID/$chapterID/',
    };
  }

  @override
  Stream<Map<String, dynamic>> retrieveLastChapter(
    String currentChapterId,
    String mangaId,
  ) async* {
    final adjacent =
        await _findAdjacentChapterId(currentChapterId, mangaId, false);
    if (adjacent != null) {
      yield* getChapter(adjacent, mangaId);
    } else {
      yield {'type': 'error', 'message': 'Não há capítulo anterior.'};
    }
  }

  @override
  Stream<Map<String, dynamic>> retrieveNextChapter(
    String currentChapterId,
    String mangaId,
  ) async* {
    final adjacent =
        await _findAdjacentChapterId(currentChapterId, mangaId, true);
    if (adjacent != null) {
      yield* getChapter(adjacent, mangaId);
    } else {
      yield {'type': 'error', 'message': 'Não há próximo capítulo.'};
    }
  }

  /// Retorna o slug do capítulo anterior ([isNext]=false) ou seguinte ([isNext]=true).
  /// Capítulos da API chegam em ordem crescente de [num].
  Future<String?> _findAdjacentChapterId(
    String currentChapterId,
    String mangaId,
    bool isNext,
  ) async {
    try {
      final details = await getBookDetails(mangaId) as Map<String, dynamic>;
      final chapters = (details['chapters'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      // Garante ordem crescente por número de capítulo.
      chapters.sort((a, b) =>
          (double.tryParse(a['chapter'] as String? ?? '0') ?? 0)
              .compareTo(double.tryParse(b['chapter'] as String? ?? '0') ?? 0));
      final idx = chapters.indexWhere((c) => c['id'] == currentChapterId);
      if (idx == -1) return null;
      final targetIdx = isNext ? idx + 1 : idx - 1;
      if (targetIdx < 0 || targetIdx >= chapters.length) return null;
      return chapters[targetIdx]['id'] as String;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<dynamic>> searchTitle(String title) async {
    // Busca client-side: filtra a lista em cache (ou refaz a requisição).
    final obras = _cachedObras ?? await _fetchObras();
    _cachedObras ??= obras;
    final q = title.toLowerCase();
    return obras
        .where((o) => (o['title'] as String).toLowerCase().contains(q))
        .toList();
  }

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
