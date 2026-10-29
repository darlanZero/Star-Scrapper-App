import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// MangaLivre.blog — catálogo PT-BR server-rendered em WordPress/SlimeRead.
///
/// A fonte possui conteúdo misto, inclusive alguns títulos adultos, mas não é
/// exclusivamente +18. Catálogo, detalhes, capítulos e páginas são públicos;
/// a autenticação é opcional e usa o formulário AJAX do próprio WordPress.
class MangaLivreSource
    implements
        MangaSource,
        CredentialAuthMangaSource,
        BrowserSessionMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        ProfileAuthMangaSource {
  static const _site = 'https://mangalivre.blog';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'MangaLivre',
    baseUrl: _site,
    contentType: ContentType.serverRenderedHtml,
    auth: const AuthConfig(
      loginUrl:
          '$_site/wp-login.php?redirect_to=https%3A%2F%2Fmangalivre.blog%2Fperfil%2F',
      type: AuthType.genericForm,
      usernameFieldName: 'log',
      passwordFieldName: 'pwd',
      successUrlFragment: '/perfil/',
      // WordPress suffixes this cookie with a site-specific hash. An empty
      // list tells the generic WebView flow to retain every cookie.
      sessionCookieNames: [],
      logoutUrl: null,
    ),
    buildDetailUrl: (id, base) => '$base/manga/$id/',
    buildChapterUrl: (id, base) =>
        id.startsWith('http') ? id : '$base/capitulo/$id/',
    buildListUrl: (filter, page, base) =>
        '$base/manga/${page > 0 ? 'page/${page + 1}/' : ''}',
    extractId: (url) => _slugAfter(url, 'manga'),
  );

  final http.Client _client;
  final Uri _baseUri;
  Map<String, String> _cookies = {};

  MangaLivreSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'manga_livre';

  @override
  String get name => 'MangaLivre';

  @override
  Uri get baseUri => _baseUri;

  @override
  String get sessionKey => 'manga_livre';

  @override
  ScrapperProfile get authProfile => _profile;

  @override
  Uri get loginUri => _resolve('/wp-login.php').replace(
        queryParameters: {'redirect_to': _resolve('/perfil/').toString()},
      );

  @override
  bool get isAuthenticated => _cookies.keys.any(
        (name) => name.startsWith('wordpress_logged_in_'),
      );

  @override
  Map<String, String> get requestHeaders => {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.7',
        'Referer': '${_baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/',
        if (_cookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(_cookies),
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'User-Agent': _userAgent,
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '${_baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/',
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.popular,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final order = filter == MangaCatalogFilter.popular ? 'popular' : 'recentes';
    final path = page == 1 ? '/manga/' : '/manga/page/$page/';
    final document = await _getDocument(
      _resolve(path).replace(queryParameters: {'ordem': order}),
    );
    return _catalogPage(document, page);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return MangaCatalogPage(items: const []);
    final page = int.tryParse(cursor ?? '') ?? 1;
    final path = page == 1 ? '/' : '/page/$page/';
    final document = await _getDocument(
      _resolve(path).replace(queryParameters: {'s': normalized}),
    );
    return _catalogPage(document, page);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _mangaSlug(mangaId);
    final uri = _resolve('/manga/$slug/');
    final document = await _getDocument(uri);
    final title = _text(document.querySelector('.manga-title'));
    if (title.isEmpty) {
      throw StateError('MangaLivre não retornou detalhes para "$slug".');
    }

    final chapters = <MangaChapter>[
      ..._chapters(document.querySelectorAll('.chapters-list .chapter-item')),
    ];
    final loadButton = document.querySelector('#sr-load-chapters');
    final mangaNumericId = loadButton?.attributes['data-manga'];
    var offset = int.tryParse(loadButton?.attributes['data-offset'] ?? '') ?? 0;
    final total = int.tryParse(loadButton?.attributes['data-total'] ?? '') ??
        chapters.length;
    while (
        mangaNumericId != null && mangaNumericId.isNotEmpty && offset < total) {
      final response = await _get(
        _resolve('/wp-json/slimeread/v1/chapters/$mangaNumericId')
            .replace(queryParameters: {'offset': '$offset'}),
        accept: 'application/json',
      );
      final payload = jsonDecode(_body(response));
      if (payload is! Map) break;
      final fragment = html_parser.parseFragment(payload['list']?.toString());
      chapters.addAll(
        _chapters(fragment.querySelectorAll('.chapters-list .chapter-item')),
      );
      final nextOffset = _asInt(payload['offset']);
      if (nextOffset == null || nextOffset <= offset) break;
      offset = nextOffset;
      if (payload['has_more'] == false) break;
    }

    final uniqueChapters = <String, MangaChapter>{};
    for (final chapter in chapters) {
      uniqueChapters[chapter.id] = chapter;
    }
    final sortedChapters = uniqueChapters.values.toList()
      ..sort((a, b) => _chapterValue(a.number).compareTo(
            _chapterValue(b.number),
          ));

    final metadata = <String, String>{};
    for (final item in document.querySelectorAll('.manga-meta-item')) {
      final label = _text(item.querySelector('.meta-label')).toLowerCase();
      final value = _text(item.querySelector('.meta-value'));
      if (label.isNotEmpty && value.isNotEmpty) metadata[label] = value;
    }
    final genres = document
        .querySelectorAll('.manga-tags .manga-tag')
        .map(_text)
        .where((value) => value.isNotEmpty && !RegExp(r'^\d+$').hasMatch(value))
        .toSet()
        .toList(growable: false);
    final cover = _imageUri(document.querySelector('.manga-cover-image'));
    final latestChapter =
        sortedChapters.isEmpty ? null : sortedChapters.last.number;

    return MangaDetails(
      item: MangaCatalogItem(
        id: slug,
        title: title,
        coverUri: cover,
        subtitle: mangaCatalogSubtitle(
          latestChapter: latestChapter,
          status: mangaStatusFromString(metadata['status']),
        ),
      ),
      description: _text(
        document.querySelector('.manga-synopsis .synopsis-content'),
      ),
      genres: genres,
      author: metadata['autor'] ?? metadata['author'],
      artist: metadata['artista'] ?? metadata['artist'],
      status: mangaStatusFromString(metadata['status']),
      externalUri: uri,
      chapters: sortedChapters,
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = chapterWebUri(mangaId: mangaId, chapterId: chapterId);
    final document = await _getDocument(uri);
    final seen = <String>{};
    for (final image in document.querySelectorAll(
      '.chapter-images img.chapter-image, .chapter-image-container img',
    )) {
      final value = image.attributes['data-src'] ??
          image.attributes['data-lazy-src'] ??
          image.attributes['src'] ??
          '';
      final pageUri = _absoluteUri(value);
      if (pageUri == null || !seen.add(pageUri.toString())) continue;
      yield MangaReaderPage.network(pageUri, headers: coverImageHeaders);
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) {
    final parsed = Uri.tryParse(chapterId);
    if (parsed != null && parsed.hasScheme) return parsed;
    return _resolve(
        '/capitulo/${chapterId.replaceAll(RegExp(r'^/+|/+$'), '')}/');
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
    final chapters = (await getDetails(mangaId)).chapters;
    final current = _canonicalChapterId(currentChapterId);
    final index = chapters.indexWhere(
      (chapter) => _canonicalChapterId(chapter.id) == current,
    );
    final target = index + delta;
    if (index < 0 || target < 0 || target >= chapters.length) return null;
    return chapters[target].id;
  }

  @override
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    final home = await _get(_resolve('/'));
    final nonce =
        RegExp(r'"loginNonce":"([^"]+)"').firstMatch(_body(home))?.group(1);
    if (nonce == null || nonce.isEmpty) {
      throw Exception('MangaLivre não expôs o token do formulário de login.');
    }
    final seedCookies = _cookiesFromResponse(home);
    final response = await _client.post(
      _resolve('/wp-admin/admin-ajax.php'),
      headers: {
        ...requestHeaders,
        'Accept': 'application/json, */*',
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
        if (seedCookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(seedCookies),
      },
      body: {
        'log': username.trim(),
        'pwd': password,
        'rememberme': 'forever',
        'redirect_to': _baseUri.toString(),
        'action': 'slimeread_ajax_login',
        'security': nonce,
      },
    );
    dynamic payload;
    try {
      payload = jsonDecode(_body(response));
    } catch (_) {
      throw Exception('Resposta inválida ao entrar no MangaLivre.');
    }
    final success = payload is Map && payload['success'] == true;
    if (!success) {
      final data = payload is Map ? payload['data'] : null;
      final message = data is Map ? data['message'] : null;
      throw Exception(message?.toString() ?? 'E-mail ou senha inválidos.');
    }
    final session = {
      ...seedCookies,
      ..._cookiesFromResponse(response),
    };
    await updateBrowserSession(session);
    if (!isAuthenticated) {
      throw Exception('MangaLivre não retornou o cookie de autenticação.');
    }
  }

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) async {
    _cookies = Map<String, String>.from(cookies);
    await SessionManager.saveCookies(sessionKey, _cookies);
  }

  @override
  Future<void> restoreSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(sessionKey);
    }
  }

  @override
  Future<void> logout() async {
    _cookies = {};
    await SessionManager.clearSession(sessionKey);
  }

  MangaCatalogPage _catalogPage(Document document, int page) {
    final cards = document.querySelectorAll(
      'article.home-manga-card, .search-results-grid .manga-card',
    );
    final items =
        cards.map(_catalogItem).whereType<MangaCatalogItem>().toList();
    final next = document.querySelector(
      '.pagination a.next, .nav-links a.next, a.next.page-numbers',
    );
    return MangaCatalogPage(
      items: items,
      nextCursor: next == null ? null : '${page + 1}',
    );
  }

  MangaCatalogItem? _catalogItem(Element card) {
    final link = card.querySelector(
      '.home-manga-cover, .home-card-body h3 a, a.manga-card-link',
    );
    final href = link?.attributes['href'] ?? '';
    final slug = _slugAfter(href, 'manga');
    final title = _text(
      card.querySelector('.home-card-body h3 a, .manga-card-title'),
    );
    if (slug.isEmpty || title.isEmpty) return null;
    final latest = _text(card.querySelector(
      '.home-card-chapters a, .latest-chapter .chapter-number',
    ));
    final ratingText = _text(card.querySelector('.manga-card-rating'));
    final rating = double.tryParse(
      RegExp(r'\d+(?:[.,]\d+)?')
              .firstMatch(ratingText)
              ?.group(0)
              ?.replaceAll(',', '.') ??
          '',
    );
    return MangaCatalogItem(
      id: slug,
      title: title,
      coverUri: _imageUri(card.querySelector('img.manga-cover-img')),
      subtitle: mangaCatalogSubtitle(
        latestChapter: latest,
        rating: rating == 0 ? null : rating,
      ),
    );
  }

  List<MangaChapter> _chapters(Iterable<Element> items) {
    return items
        .map((item) {
          final link = item.querySelector('a.chapter-link');
          final href = link?.attributes['href'] ?? '';
          final label = _text(item.querySelector('.chapter-number'));
          final number = RegExp(r'\d+(?:[.,]\d+)?')
                  .firstMatch(label)
                  ?.group(0)
                  ?.replaceAll(',', '.') ??
              '';
          return MangaChapter(
            id: href,
            title: label,
            number: number,
            language: 'pt-br',
            publishedAt: _text(item.querySelector('.chapter-date')),
          );
        })
        .where((chapter) => chapter.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Document> _getDocument(Uri uri) async {
    final response = await _get(uri);
    return html_parser.parse(_body(response));
  }

  Future<http.Response> _get(Uri uri, {String? accept}) async {
    await restoreSession();
    final response = await _client.get(
      uri,
      headers: {
        ...requestHeaders,
        if (accept != null) 'Accept': accept,
      },
    );
    if (response.statusCode != 200) {
      throw http.ClientException(
        'MangaLivre retornou HTTP ${response.statusCode}',
        uri,
      );
    }
    return response;
  }

  Map<String, String> _cookiesFromResponse(http.Response response) {
    final raw = response.headers['set-cookie'] ?? '';
    if (raw.isEmpty) return const {};
    final result = <String, String>{};
    for (final match in RegExp(
      r'(?:^|,\s*)([^=;,\s]+)=([^;,]*)',
    ).allMatches(raw)) {
      final name = match.group(1) ?? '';
      if (name.toLowerCase() == 'expires' || name.isEmpty) continue;
      result[name] = match.group(2) ?? '';
    }
    return result;
  }

  String _body(http.Response response) => utf8.decode(
        response.bodyBytes,
        allowMalformed: true,
      );

  Uri _resolve(String path) => _baseUri.resolve(path);

  Uri? _imageUri(Element? image) {
    final value = image?.attributes['data-src'] ??
        image?.attributes['data-lazy-src'] ??
        image?.attributes['src'] ??
        '';
    return _absoluteUri(value);
  }

  Uri? _absoluteUri(String value) {
    if (value.trim().isEmpty || value.startsWith('data:')) return null;
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    if (value.startsWith('//')) return Uri.tryParse('https:$value');
    return _resolve(value);
  }

  String _mangaSlug(String value) {
    final slug = _slugAfter(value, 'manga');
    return slug.isEmpty ? value.replaceAll(RegExp(r'^/+|/+$'), '') : slug;
  }

  String _canonicalChapterId(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return value.replaceAll(RegExp(r'^/+|/+$'), '');
    return uri.path.replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static String _slugAfter(String value, String segment) {
    final parts = Uri.tryParse(value)
            ?.pathSegments
            .where((part) => part.isNotEmpty)
            .toList() ??
        const <String>[];
    final index = parts.indexOf(segment);
    return index >= 0 && index + 1 < parts.length ? parts[index + 1] : '';
  }

  static String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static double _chapterValue(String value) =>
      double.tryParse(value.replaceAll(',', '.')) ?? -1;
}
