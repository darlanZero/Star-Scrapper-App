import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show ProfileAuthMangaSource;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

typedef YomuHtmlLoader = Future<String> Function(Uri uri, String userAgent);
typedef YomuReaderPageLoader = Stream<String> Function(
  Uri uri,
  String userAgent,
);

/// Yomu Comics — catálogo misto PT-BR em Next.js.
///
/// O catálogo usa a API pública do próprio frontend. Detalhes e leitura ficam
/// atrás da sessão Auth.js (formulário, Google ou Discord), então o HTML é
/// resolvido pela WebView autenticada quando a requisição HTTP não preserva a
/// sessão. O leitor percorre os slots lazy antes de entregar todas as páginas.
class YomuSource
    implements
        MangaSource,
        BrowserSessionMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource,
        FilterableMangaSource,
        ProfileAuthMangaSource {
  static const _site = 'https://yomu.com.br';
  static const _pageSize = 20;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'Yomu',
    baseUrl: _site,
    contentType: ContentType.spa,
    auth: const AuthConfig(
      loginUrl: '$_site/login',
      type: AuthType.webviewOAuth,
      successUrlFragment: '/home',
      sessionValidationUrl: '$_site/api/auth/session',
      // Auth.js usa cookies HttpOnly e pode alternar o prefixo __Secure de
      // acordo com o ambiente. Vazio preserva o jar completo da WebView.
      sessionCookieNames: [],
      logoutUrl: null,
    ),
    buildDetailUrl: (id, base) => '$base/obra/$id',
    buildChapterUrl: (id, base) => '$base/ler/$id',
    buildListUrl: (filter, page, base) => '$base/biblioteca',
    extractId: (url) => _slugAfter(url, 'obra'),
  );

  static const _formats = [
    MangaFilterOption(value: 'manga', label: 'Mangá'),
    MangaFilterOption(value: 'manhwa', label: 'Manhwa'),
    MangaFilterOption(value: 'manhua', label: 'Manhua'),
    MangaFilterOption(value: 'novel', label: 'Novel'),
    MangaFilterOption(value: 'yaoi', label: 'Yaoi'),
    MangaFilterOption(value: 'yuri', label: 'Yuri'),
    MangaFilterOption(value: 'shoujo', label: 'Shoujo'),
    MangaFilterOption(value: 'english', label: 'English'),
    MangaFilterOption(value: 'webtoon', label: 'Webtoon'),
    MangaFilterOption(value: 'doujinshi', label: 'Doujinshi'),
    MangaFilterOption(value: 'hentai', label: 'Hentai'),
    MangaFilterOption(value: 'pornhwa', label: 'Pornhwa'),
  ];

  static const _statuses = [
    MangaFilterOption(value: 'ONGOING', label: 'Em lançamento'),
    MangaFilterOption(value: 'COMPLETED', label: 'Completo'),
    MangaFilterOption(value: 'HIATUS', label: 'Hiato'),
    MangaFilterOption(value: 'CANCELED', label: 'Cancelado'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final YomuHtmlLoader? _browserHtmlLoader;
  final YomuHtmlLoader? _scrolledHtmlLoader;
  final YomuReaderPageLoader? _readerPageLoader;
  Map<String, String> _cookies = {};
  final Map<String, MangaDetails> _detailsCache = {};

  YomuSource({
    http.Client? client,
    Uri? baseUri,
    YomuHtmlLoader? browserHtmlLoader,
    YomuHtmlLoader? scrolledHtmlLoader,
    YomuReaderPageLoader? readerPageLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site),
        _browserHtmlLoader = browserHtmlLoader,
        _scrolledHtmlLoader = scrolledHtmlLoader,
        _readerPageLoader = readerPageLoader;

  @override
  String get id => 'yomu';

  @override
  String get name => 'Yomu';

  @override
  Uri get baseUri => _baseUri;

  @override
  String get sessionKey => 'yomu';

  @override
  ScrapperProfile get authProfile => _profile;

  @override
  Uri get loginUri => _resolve('/login');

  @override
  bool get isAuthenticated => _cookies.keys.any(
        (name) => name.toLowerCase().contains('session-token'),
      );

  @override
  Map<String, String> get requestHeaders => {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
        'Referer': '$_site/',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'same-origin',
        'Upgrade-Insecure-Requests': '1',
        'User-Agent': _userAgent,
        if (_cookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(_cookies),
      };

  @override
  Map<String, String> get coverImageHeaders => const {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '$_site/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.added,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.alphabetical,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    return _catalog(
      page: _page(cursor),
      sort: switch (filter) {
        MangaCatalogFilter.popular => 'popular',
        MangaCatalogFilter.recent || MangaCatalogFilter.updated => 'recent',
        MangaCatalogFilter.added => 'new',
        MangaCatalogFilter.trending => 'rating',
        MangaCatalogFilter.alphabetical => 'alphabetical',
      },
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) => _catalog(
        page: _page(cursor),
        sort: 'popular',
        search: query.trim(),
      );

  Future<MangaCatalogPage> _catalog({
    required int page,
    required String sort,
    String type = 'all',
    String? genre,
    String? status,
    String search = '',
  }) async {
    final uri = _resolve('/api/library-proxy').replace(queryParameters: {
      'page': '$page',
      'limit': '$_pageSize',
      'sort': sort,
      'type': type,
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      if (status != null && status.isNotEmpty) 'status': status,
      if (search.isNotEmpty) 'search': search,
    });
    final payload = await _getJson(uri);
    final map = _map(payload);
    final items = _list(map['garimpo']).map(_catalogItem).toList();
    final pagination = _map(map['pagination']);
    final current = _int(pagination['page']) ?? page;
    final totalPages = _int(pagination['totalPages']) ?? current;
    return MangaCatalogPage(
      items: items,
      nextCursor: current < totalPages ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final payload = await _getJson(_resolve('/api/genres'));
    return MangaSearchOptions(
      formats: _formats,
      statuses: _statuses,
      genres: _list(payload)
          .map((genre) => genre.toString().trim())
          .where((genre) => genre.isNotEmpty)
          .map((genre) => MangaFilterOption(value: genre, label: genre)),
      sorts: const [
        MangaSearchSort.popular,
        MangaSearchSort.rating,
        MangaSearchSort.updated,
        MangaSearchSort.chapterCount,
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.titleAscending,
      ],
      supportsAdultMode: true,
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    var type = request.formats.isEmpty ? 'all' : request.formats.first;
    if (request.adultMode == MangaAdultMode.only && request.formats.isEmpty) {
      type = 'hentai';
    }
    return _catalog(
      page: _page(cursor),
      sort: switch (request.sort) {
        MangaSearchSort.popular => 'popular',
        MangaSearchSort.rating => 'rating',
        MangaSearchSort.updated => 'recent',
        MangaSearchSort.chapterCount => 'chapters',
        MangaSearchSort.title ||
        MangaSearchSort.titleAscending ||
        MangaSearchSort.titleDescending =>
          'alphabetical',
        _ => 'new',
      },
      type: type,
      genre: request.genres.firstOrNull,
      status: request.statuses.firstOrNull,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _mangaSlug(mangaId);
    final cached = _detailsCache[slug];
    if (cached != null) return cached;
    final uri = _resolve('/obra/$slug');
    final document = await _detailDocument(uri);
    final title = _text(document.querySelector('main h1'));
    if (title.isEmpty) {
      throw const MangaSourceSessionRequired(
        'Entre na Yomu para carregar detalhes e capítulos.',
      );
    }

    final detailImages = document.querySelectorAll('main img');
    final coverElement = detailImages.firstWhere(
      (image) => _textAttribute(image, 'alt') == title,
      orElse: () => detailImages.firstWhere(
        (image) {
          final src = image.attributes['src'] ?? '';
          return src.contains('/capa/') || src.contains('/uploads/media/');
        },
        orElse: () => Element.tag('img'),
      ),
    );
    final cover = coverElement.attributes['src'] ?? '';
    final chapters = <MangaChapter>[];
    final seen = <String>{};
    for (final anchor in document
        .querySelectorAll('main [role="tabpanel"] a[href*="/ler/"]')) {
      final href = anchor.attributes['href'] ?? '';
      final parsed = Uri.tryParse(href);
      final segments =
          parsed?.pathSegments.where((e) => e.isNotEmpty).toList() ??
              const <String>[];
      if (segments.length < 3 || segments[0] != 'ler') continue;
      final number = segments.last;
      if (!seen.add(number)) continue;
      final label = _chapterTitle(anchor, number);
      chapters.add(MangaChapter(
        id: '$slug|$number',
        title: label,
        number: number,
        language: 'pt-br',
        uploader: _chapterUploader(anchor),
        publishedAt: _chapterDate(anchor.text),
      ));
    }
    chapters.sort(
      (a, b) => _chapterValue(a.number).compareTo(_chapterValue(b.number)),
    );

    final statusText =
        document.querySelectorAll('main span').map(_text).firstWhere(
              (value) => RegExp(
                r'lançamento|lancamento|completo|hiato|cancelado',
                caseSensitive: false,
              ).hasMatch(value),
              orElse: () => '',
            );
    final rating = _rating(document.body?.text ?? '');
    final description = _description(document);
    final genreNames = (await _genreNames()).toSet();
    final genres = document
        .querySelectorAll('main span')
        .map(_text)
        .where(genreNames.contains)
        .toSet()
        .toList(growable: false);
    final details = MangaDetails(
      item: MangaCatalogItem(
        id: slug,
        title: title,
        coverUri: Uri.tryParse(cover),
        subtitle: mangaCatalogSubtitle(
          latestChapter: chapters.lastOrNull?.number,
          totalChapters: chapters.length,
          format: _workType(document),
          status: mangaStatusFromString(statusText),
          rating: rating,
        ),
      ),
      description: description,
      genres: genres,
      author: _metadataValue(document, 'autor'),
      artist: _metadataValue(document, 'artista'),
      status: mangaStatusFromString(statusText),
      externalUri: uri,
      chapters: chapters,
    );
    _detailsCache[slug] = details;
    return details;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = chapterWebUri(mangaId: mangaId, chapterId: chapterId);
    if (_readerPageLoader != null) {
      final seen = <String>{};
      await for (final rawUrl in _readerPageLoader(uri, _userAgent)) {
        final page = _absoluteUri(rawUrl);
        if (page == null ||
            !const {'http', 'https'}.contains(page.scheme) ||
            !seen.add(page.toString())) {
          continue;
        }
        yield MangaReaderPage.network(page, headers: {
          ...coverImageHeaders,
          'Referer': uri.toString(),
        });
      }
      if (seen.isEmpty) {
        throw StateError(
          'A Yomu não expôs imagens para este capítulo. Ele pode estar bloqueado para VIP.',
        );
      }
      return;
    }

    // Test/fallback path for platforms without the progressive Android bridge.
    final htmlLoader = _scrolledHtmlLoader ?? _browserHtmlLoader;
    if (htmlLoader == null) {
      throw const MangaSourceSessionRequired(
        'Entre na Yomu para preparar o leitor nativo.',
      );
    }
    final document = html_parser.parse(await htmlLoader(uri, _userAgent));
    final seen = <String>{};
    for (final image in document.querySelectorAll('main img[alt^="Página"]')) {
      final src = image.attributes['src'] ?? '';
      final page = _absoluteUri(src);
      if (page == null || !seen.add(page.toString())) continue;
      yield MangaReaderPage.network(page, headers: {
        ...coverImageHeaders,
        'Referer': uri.toString(),
      });
    }
    if (seen.isEmpty) {
      throw StateError(
        'A Yomu não expôs imagens para este capítulo. Ele pode estar bloqueado para VIP.',
      );
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) {
    final direct = Uri.tryParse(chapterId);
    if (direct != null && direct.hasScheme) return direct;
    final parts = chapterId.split('|');
    final slug = parts.length > 1 ? parts.first : _mangaSlug(mangaId);
    final chapter = parts.length > 1 ? parts.last : chapterId;
    return _resolve('/ler/$slug/$chapter');
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
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    final target = index + delta;
    return index < 0 || target < 0 || target >= chapters.length
        ? null
        : chapters[target].id;
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
    _detailsCache.clear();
    await SessionManager.clearSession(sessionKey);
  }

  Future<Document> _detailDocument(Uri uri) async {
    await restoreSession();
    if (_cookies.isNotEmpty) {
      try {
        final response = await _client.get(uri, headers: requestHeaders);
        final document = html_parser.parse(_body(response));
        if (response.statusCode == 200 &&
            _isExpectedDetailDocument(document, uri)) {
          return document;
        }
      } catch (_) {}
    }
    final loader = _browserHtmlLoader;
    if (loader == null) {
      throw const MangaSourceSessionRequired(
        'Conclua o login da Yomu nas configurações de sources.',
      );
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final target = attempt == 0
          ? uri
          : uri.replace(queryParameters: {
              ...uri.queryParameters,
              '_stars_refresh':
                  DateTime.now().millisecondsSinceEpoch.toString(),
            });
      final document = html_parser.parse(await loader(target, _userAgent));
      if (_isExpectedDetailDocument(document, uri)) return document;
    }
    throw StateError(
      'A Yomu retornou metadados de outra obra. Tente carregar novamente.',
    );
  }

  Future<dynamic> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      'Accept': 'application/json',
      'x-yomu-client': 'true',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
    });
    if (response.statusCode == 200) return jsonDecode(_body(response));
    if (_browserHtmlLoader != null) {
      final document = html_parser.parse(
        await _browserHtmlLoader(uri, _userAgent),
      );
      final jsonText = _text(document.querySelector('pre'));
      if (jsonText.isNotEmpty) return jsonDecode(jsonText);
    }
    throw StateError('Yomu retornou HTTP ${response.statusCode}.');
  }

  MangaCatalogItem _catalogItem(dynamic raw) {
    final item = _map(raw);
    final slug = (item['slug'] ?? item['id'] ?? '').toString();
    return MangaCatalogItem(
      id: slug,
      title: (item['title'] ?? '').toString(),
      coverUri: Uri.tryParse((item['cover'] ?? '').toString()),
      subtitle: mangaCatalogSubtitle(
        latestChapter: item['lastChapter'],
        totalChapters: _int(item['chapters']),
        format: _formatLabel(item['type']),
        rating: _double(item['rating']),
      ),
    );
  }

  Future<List<String>> _genreNames() async {
    try {
      return _list(await _getJson(_resolve('/api/genres')))
          .map((value) => value.toString())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String? _metadataValue(Document document, String label) {
    for (final span in document.querySelectorAll('main span')) {
      if (_text(span).toLowerCase() != label) continue;
      final values = span.parent?.querySelectorAll('span') ?? const <Element>[];
      for (final value in values.reversed) {
        final text = _text(value);
        if (text.isNotEmpty && text.toLowerCase() != label) return text;
      }
    }
    return null;
  }

  String? _workType(Document document) {
    final value = document.querySelectorAll('main span').map(_text).firstWhere(
          (value) => _formats.any(
            (option) => option.label.toLowerCase() == value.toLowerCase(),
          ),
          orElse: () => '',
        );
    return value.isEmpty ? null : value;
  }

  String? _chapterUploader(Element anchor) {
    final spans = anchor.querySelectorAll('span').map(_text);
    return spans
        .firstWhere(
          (value) =>
              value.isNotEmpty &&
              !value.toLowerCase().startsWith('capítulo') &&
              !RegExp(r'^\d').hasMatch(value),
          orElse: () => '',
        )
        .nullIfEmpty;
  }

  String _chapterTitle(Element anchor, String number) {
    final raw = _text(anchor.querySelector('span[title]'));
    if (raw.isEmpty) return '';
    return raw
        .replaceFirst(
          RegExp(
            '^cap[ií]tulo\\s*${RegExp.escape(number)}\\s*(?:[-:–—]\\s*)?',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String? _chapterDate(String text) {
    final match = RegExp(r'(\d{2})/(\d{2})/(\d{4})').firstMatch(text);
    if (match == null) return null;
    return '${match.group(3)}-${match.group(2)}-${match.group(1)}T00:00:00.000Z';
  }

  String _description(Document document) {
    final primary = _text(document.querySelector('main .whitespace-pre-wrap'));
    if (_isSynopsis(primary)) return primary;
    return document
        .querySelectorAll('main p, main div')
        .map(_text)
        .where(_isSynopsis)
        .fold<String>(
          '',
          (best, value) => value.length > best.length ? value : best,
        );
  }

  bool _isSynopsis(String value) {
    final normalized = value.toLowerCase();
    return value.length > 70 &&
        !normalized.startsWith('proibido comentários') &&
        !normalized.contains('adicione os links do mangaupdates') &&
        !normalized.contains('você ganha 1 moeda') &&
        !normalized.contains('capítulos comentários recentes');
  }

  bool _isExpectedDetailDocument(Document document, Uri requestedUri) {
    final slug = _mangaSlug(requestedUri.toString());
    if (slug.isEmpty || _text(document.querySelector('main h1')).isEmpty) {
      return false;
    }
    return document.querySelector(
          'main a[href^="/ler/$slug/"]',
        ) !=
        null;
  }

  double? _rating(String text) => double.tryParse(
        RegExp(r'Avaliação\s+(\d+(?:[.,]\d+)?)\s*/\s*10', caseSensitive: false)
                .firstMatch(text)
                ?.group(1)
                ?.replaceAll(',', '.') ??
            '',
      );

  Uri _resolve(String path) => _baseUri.resolve(path);

  Uri? _absoluteUri(String value) {
    if (value.trim().isEmpty || value.startsWith('data:')) return null;
    return _baseUri.resolve(value.trim());
  }

  String _mangaSlug(String value) {
    final fromUrl = _slugAfter(value, 'obra');
    if (fromUrl.isNotEmpty) return fromUrl;
    return value.split('|').first.replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static String _slugAfter(String value, String marker) {
    final uri = Uri.tryParse(value);
    final segments = uri?.pathSegments.where((e) => e.isNotEmpty).toList() ??
        const <String>[];
    final index = segments.indexOf(marker);
    return index >= 0 && index + 1 < segments.length ? segments[index + 1] : '';
  }

  String _body(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  int _page(String? cursor) => int.tryParse(cursor ?? '') ?? 1;
  Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : <String, dynamic>{};
  List<dynamic> _list(dynamic value) => value is List ? value : const [];
  int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  double? _double(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  String _textAttribute(Element element, String name) =>
      (element.attributes[name] ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  double _chapterValue(String value) =>
      double.tryParse(value.replaceAll(',', '.')) ?? 0;
  String? _formatLabel(dynamic value) {
    final raw = value?.toString().toLowerCase() ?? '';
    return _formats
        .where((option) => option.value == raw)
        .map((option) => option.label)
        .firstOrNull;
  }
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : trim();
}
