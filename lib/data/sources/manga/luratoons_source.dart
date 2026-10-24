import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// LuraToons (https://luratoons.net) — Vue.js SPA + Django REST backend.
///
/// Catalog/details come from the REST API; chapter images are DRM/WASM-encrypted
/// and can only be rendered by the site, so reading happens through the
/// authenticated WebView ([WebViewChapterMangaSource]). Login is Django-form or
/// Google OAuth (handled by the base + WebView).
class LuraToonsSource extends BaseHtmlMangaSource
    implements WebViewChapterMangaSource, ChapterNavigationMangaSource {
  static const String _base = 'https://luratoons.net';

  /// Google OAuth entry point (used by the auth WebView).
  static const String googleLoginUrl =
      '$_base/accounts/google/login/?process=login';

  List<MangaCatalogItem>? _cachedCatalog;

  LuraToonsSource({http.Client? client}) : super(_profile, client: client);

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
    buildDetailUrl: (id, base) => '$base/api/obra/$id/',
    buildChapterUrl: (id, base) => '$base/$id/',
    buildListUrl: (filter, page, base) =>
        filter.toLowerCase() == 'recent' ? '$base/api/main/' : '$base/api/obras/',
    extractId: (url) {
      try {
        final uri = Uri.parse(url);
        return uri.pathSegments.where((s) => s.isNotEmpty).join('/');
      } catch (_) {
        return url;
      }
    },
  );

  @override
  String get id => 'luratoons';

  @override
  String get name => 'LuraToons';

  @override
  Uri get baseUri => Uri.parse(_base);

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'application/json, text/plain, */*',
      };

  @override
  Map<String, String> get coverImageHeaders => const {'Referer': '$_base/'};

  @override
  List<MangaCatalogFilter> get catalogFilters =>
      const [MangaCatalogFilter.popular, MangaCatalogFilter.recent];

  // ─── Catalog ───────────────────────────────────────────────────────────────

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    if (filter == MangaCatalogFilter.recent) {
      final data = await _jsonGet('$_base/api/main/');
      final lancamentos = (data['lancamentos'] ?? []) as List<dynamic>;
      return MangaCatalogPage(
        items: lancamentos.map(_recentItem).whereType<MangaCatalogItem>(),
      );
    }
    final catalog = await _fetchCatalog();
    return MangaCatalogPage(items: catalog);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final catalog = await _fetchCatalog();
    final normalized = query.toLowerCase();
    return MangaCatalogPage(
      items: catalog.where(
        (item) => item.title.toLowerCase().contains(normalized),
      ),
    );
  }

  Future<List<MangaCatalogItem>> _fetchCatalog() async {
    if (_cachedCatalog != null) return _cachedCatalog!;
    final data = await _jsonGet('$_base/api/obras/');
    final obras = (data['obras'] ?? []) as List<dynamic>;
    final items = obras.map(_catalogItem).whereType<MangaCatalogItem>().toList();
    _cachedCatalog = items;
    return items;
  }

  MangaCatalogItem? _catalogItem(dynamic raw) {
    final obra = raw as Map<String, dynamic>;
    final slug = obra['slug']?.toString() ?? '';
    if (slug.isEmpty) return null;
    return MangaCatalogItem(
      id: slug,
      title: obra['title']?.toString() ?? '',
      coverUri: _coverUri(obra['capa']?.toString() ?? ''),
    );
  }

  MangaCatalogItem? _recentItem(dynamic raw) {
    final item = raw as Map<String, dynamic>;
    final slug = item['slug']?.toString() ?? '';
    if (slug.isEmpty) return null;
    final caps = (item['caps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final latest = caps.isNotEmpty ? caps.first : null;
    return MangaCatalogItem(
      id: slug,
      title: item['title']?.toString() ?? '',
      coverUri: _coverUri(item['capa']?.toString() ?? ''),
      subtitle: latest != null ? 'Cap. ${latest['num']}' : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final data = await _jsonGet('$_base/api/obra/$mangaId/');
    final caps = (data['caps'] ?? []) as List<dynamic>;
    final generos = (data['generos'] ?? []) as List<dynamic>;

    final chapters = caps
        .map((c) {
          final cap = c as Map<String, dynamic>;
          final slug = cap['slug']?.toString() ?? '';
          if (slug.isEmpty) return null;
          return MangaChapter(
            id: slug,
            number: cap['num']?.toString() ?? '',
            language: 'pt-br',
            publishedAt: cap['data']?.toString(),
          );
        })
        .whereType<MangaChapter>()
        .toList();

    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaId,
        title: data['titulo']?.toString() ?? '',
        coverUri: _coverUri(data['capa']?.toString() ?? ''),
      ),
      description: data['sinopse']?.toString() ?? '',
      genres: generos
          .map((g) => (g as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
      author: data['autor']?.toString(),
      status: mangaStatusFromString(data['status']),
      externalUri: Uri.tryParse('$_base/obra/$mangaId'),
      chapters: chapters,
    );
  }

  // ─── Reading (WebView only — DRM/WASM) ─────────────────────────────────────

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    // Images are DRM/WASM-encrypted; nothing to stream. The reader falls back to
    // [chapterWebUri].
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      Uri.parse('$_base/$mangaId/$chapterId/');

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
    final details = await getDetails(mangaId);
    final chapters = [...details.chapters]..sort((a, b) =>
        (double.tryParse(a.number) ?? 0)
            .compareTo(double.tryParse(b.number) ?? 0));
    final index = chapters.indexWhere((c) => c.id == currentChapterId);
    if (index == -1) return null;
    final target = isNext ? index + 1 : index - 1;
    if (target < 0 || target >= chapters.length) return null;
    return chapters[target].id;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _jsonGet(String url) async {
    final res = await httpGet(url);
    assertAuthResponse(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Uri? _coverUri(String path) {
    if (path.isEmpty) return null;
    return Uri.tryParse(path.startsWith('http') ? path : '$_base$path');
  }
}
