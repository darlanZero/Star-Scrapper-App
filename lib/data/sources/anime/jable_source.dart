import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/jable_english_dictionary.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

typedef JableBrowserHtmlLoader = Future<String> Function(
  Uri uri,
  String userAgent,
  String? clickSelector,
  int maxClicks,
);
typedef JableBrowserImageLoader = Future<Uint8List> Function(
  Uri uri,
  String userAgent,
);

/// Adult Japanese video source backed by Jable.tv.
///
/// Jable protects its catalogs with Cloudflare and applies sorting through
/// AJAX controls. The browser loader therefore handles challenged pages and
/// performs the same sort click as the website before the DOM is parsed.
class JableSource
    implements
        AnimeSource,
        FilterableAnimeSource,
        TaxonomyBrowsableAnimeSource,
        BrowserSessionAnimeSource,
        BrowserImageAnimeSource,
        StaticMetadataTranslationAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://jp.jable.tv/');
  static const _translationPreferenceKey =
      'source.jable.staticEnglishTranslation';
  static const _cookiesKey = 'jable_browser_cookies';
  static const _userAgentKey = 'jable_browser_user_agent';
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final bool? _translationOverride;
  final JableBrowserHtmlLoader? _browserHtmlLoader;
  final JableBrowserImageLoader? _browserImageLoader;
  Map<String, String> _cookies = const {};
  String _userAgent = _defaultUserAgent;
  bool _sessionLoaded = false;
  final Map<bool, AnimeSearchOptions> _searchOptionsCache = {};
  final Map<String, Future<Document>> _metadataDocumentCache = {};

  JableSource({
    http.Client? client,
    Uri? baseUri,
    bool? translateToEnglish,
    JableBrowserHtmlLoader? browserHtmlLoader,
    JableBrowserImageLoader? browserImageLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _translationOverride = translateToEnglish,
        _browserHtmlLoader = browserHtmlLoader,
        _browserImageLoader = browserImageLoader;

  @override
  String get id => 'jable';

  @override
  String get name => 'Jable';

  @override
  Uri get baseUri => _baseUri;

  @override
  Uri get sessionUri => _baseUri.resolve('hot/');

  @override
  String get staticTranslationLabel => 'Static English translation';

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'ja,en;q=0.7',
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; '),
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularMonth,
        AnimeCatalogFilter.popularWeek,
        AnimeCatalogFilter.popularToday,
      ];

  @override
  Future<Uint8List> loadBrowserImage(Uri uri) {
    final loader = _browserImageLoader;
    if (loader == null) {
      throw StateError('Jable browser image loading is unavailable.');
    }
    return loader(uri, _userAgent);
  }

  @override
  Future<void> updateBrowserSession({
    required Map<String, String> cookies,
    required String userAgent,
  }) async {
    _cookies = Map.unmodifiable(cookies);
    _userAgent = userAgent.trim().isEmpty ? _defaultUserAgent : userAgent;
    _sessionLoaded = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_cookiesKey, jsonEncode(_cookies));
    await preferences.setString(_userAgentKey, _userAgent);
  }

  @override
  Future<bool> isStaticTranslationEnabled() async {
    if (_translationOverride case final value?) return value;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_translationPreferenceKey) ?? false;
  }

  @override
  Future<void> setStaticTranslationEnabled(bool enabled) async {
    if (_translationOverride != null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_translationPreferenceKey, enabled);
    _searchOptionsCache.clear();
  }

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    if (filter == AnimeCatalogFilter.recent) {
      return _catalog(_pagedUri('new-release/', cursor));
    }
    final sort = switch (filter) {
      AnimeCatalogFilter.popularMonth => 'video_viewed_month',
      AnimeCatalogFilter.popularWeek => 'video_viewed_week',
      AnimeCatalogFilter.popularToday => 'video_viewed_today',
      _ => 'video_viewed',
    };
    return _sortedCatalog('hot/', cursor, sort);
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => filter(
        AnimeSearchRequest(query: query.trim()),
        cursor: cursor,
      );

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final translated = await isStaticTranslationEnabled();
    final cached = _searchOptionsCache[translated];
    if (cached != null) return cached;
    final document = await _getDocument(_baseUri.resolve('hot/'));
    var group = '';
    final options = <AnimeFilterOption>[];
    for (final element in document
        .querySelectorAll('.app-nav .title-box h2, .app-nav a.tag')) {
      if (element.localName == 'h2') {
        group = element.text.trim();
        continue;
      }
      final uri = _uri(element.attributes['href']);
      final slug = _pathSegmentAfter(uri, 'tags');
      final raw = element.text.trim();
      if (slug == null || raw.isEmpty) continue;
      final displayedGroup =
          translated ? JableEnglishDictionary.groupLabel(group) : group;
      final displayedTag =
          translated ? JableEnglishDictionary.tagLabel(slug, raw) : raw;
      options.add(AnimeFilterOption(
        value: slug,
        label: displayedGroup.isEmpty
            ? displayedTag
            : '$displayedGroup · $displayedTag',
      ));
    }
    final result = AnimeSearchOptions(
      genres: _uniqueOptions(options),
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.latestUpdated,
        AnimeSearchSort.mostViewed,
        AnimeSearchSort.favorites,
      ],
      sortLabels: const {
        AnimeSearchSort.defaultOrder: 'Best recent',
        AnimeSearchSort.latestUpdated: 'Recently updated',
        AnimeSearchSort.mostViewed: 'Most popular',
        AnimeSearchSort.favorites: 'Most favorites',
      },
      labels: const {
        'genres': 'Tags by type',
        'genresAny': 'Any tag',
        'sorts': 'Sort order',
      },
    );
    _searchOptionsCache[translated] = result;
    return result;
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) async {
    final sort = _sortValue(request.sort);
    if (request.genres.isNotEmpty) {
      final pages = <AnimeCatalogPage>[];
      for (final slug in request.genres) {
        pages.add(await _sortedCatalog(
          'tags/${Uri.encodeComponent(slug)}/',
          cursor,
          sort,
        ));
      }
      final seen = <String>{};
      final items = pages
          .expand((page) => page.items)
          .where((item) => seen.add(item.id))
          .toList(growable: false);
      return AnimeCatalogPage(
        items: items,
        nextCursor: pages.any((page) => page.hasMore)
            ? '${(int.tryParse(cursor ?? '') ?? 1) + 1}'
            : null,
      );
    }
    final query = request.query.trim();
    final uri = query.isEmpty
        ? _pagedUri('new-release/', cursor)
        : _pagedUri(
            'search/${Uri.encodeComponent(query)}/',
            cursor,
          );
    if (query.isNotEmpty) {
      return _sortedCatalog(
        'search/${Uri.encodeComponent(query)}/',
        cursor,
        sort,
      );
    }
    return _catalog(uri);
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final document = await _getMetadataDocument(_videoUri(animeId));
    final translated = await isStaticTranslationEnabled();
    final title = _title(document);
    final poster = _poster(document);
    final links = _taxonomyLinks(document, translated: translated);
    final models = links
        .where((link) => link.kind == AnimeTaxonomyKind.model)
        .map((link) => link.name)
        .toList(growable: false);
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: animeId,
        title: title,
        coverUri: poster,
        subtitle: models.isEmpty ? null : models.join(' · '),
      ),
      genres: links
          .where((link) => link.kind != AnimeTaxonomyKind.model)
          .map((link) => link.name)
          .toList(growable: false),
      taxonomyLinks: links,
      status: AnimeStatus.completed,
      bannerUri: poster,
      externalIds: {'jable': animeId},
      studios: models,
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final document = await _getMetadataDocument(_videoUri(animeId));
    final dateText = document
            .querySelector('.video-info .header-right .inactive-color')
            ?.text ??
        '';
    final date = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(dateText)?.group(0);
    return [
      AnimeEpisode(
        id: animeId,
        animeId: animeId,
        title: _title(document),
        number: 1,
        releasedAt: DateTime.tryParse(date ?? ''),
        thumbnailUri: _poster(document),
      ),
    ];
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final pageUri = _videoUri(episodeId);
    final document = await _getDocument(pageUri);
    final candidates = <String>{};
    for (final element
        in document.querySelectorAll('video source[src], video[src]')) {
      final value = element.attributes['src']?.trim() ?? '';
      if (value.startsWith('http://') || value.startsWith('https://')) {
        candidates.add(value);
      }
    }
    final hlsPattern = RegExp(
      r'''https?://[^\s"'\\<>]+\.m3u8(?:\?[^\s"'\\<>]*)?''',
      caseSensitive: false,
    );
    candidates.addAll(
      hlsPattern.allMatches(document.outerHtml).map((match) => match.group(0)!),
    );
    final streams = candidates
        .map((value) {
          final uri = Uri.tryParse(value.replaceAll(r'\/', '/'));
          if (uri == null || !uri.hasScheme) return null;
          final hls = uri.path.toLowerCase().endsWith('.m3u8');
          return AnimeVideoStream(
            uri: uri,
            protocol: hls ? VideoProtocol.hls : VideoProtocol.progressive,
            quality: 'Auto',
            language: 'ja',
            mimeType: hls ? 'application/x-mpegURL' : 'video/mp4',
            headers: {
              'Referer': pageUri.toString(),
              'Origin': '${_baseUri.scheme}://${_baseUri.host}',
              'User-Agent': _userAgent,
              'Accept': '*/*',
            },
          );
        })
        .whereType<AnimeVideoStream>()
        .toList(growable: false);
    if (streams.isEmpty) {
      throw StateError('Jable did not expose a playable HLS stream.');
    }
    return AnimePlayback(streams: streams);
  }

  @override
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) =>
      _catalog(_pagedUri(_taxonomyPath(kind, taxonomyId), cursor));

  Future<AnimeCatalogPage> _catalog(
    Uri uri, {
    String? clickSelector,
    int maxClicks = 1,
    int? currentPage,
  }) async {
    final document = await _getDocument(
      uri,
      clickSelector: clickSelector,
      maxClicks: maxClicks,
    );
    final items = <AnimeCatalogItem>[];
    final seen = <String>{};
    for (final card in document.querySelectorAll('.video-img-box')) {
      final anchor =
          card.querySelector('.detail h6.title a[href*="/videos/"]') ??
              card.querySelector('a[href*="/videos/"]');
      final resolved = _uri(anchor?.attributes['href']);
      final id = _pathSegmentAfter(resolved, 'videos');
      final title = anchor?.text.trim() ?? '';
      if (id == null || title.isEmpty || !seen.add(id)) continue;
      final duration =
          card.querySelector('.absolute-bottom-right .label')?.text.trim() ??
              '';
      final stats = card.querySelector('.detail .sub-title')?.text.trim() ?? '';
      final subtitle =
          [duration, stats].where((value) => value.isNotEmpty).join(' · ');
      items.add(AnimeCatalogItem(
        id: id,
        title: title,
        coverUri: _imageUri(card.querySelector('.img-box img')),
        subtitle: subtitle.isEmpty ? null : subtitle,
      ));
    }
    final current = currentPage ??
        int.tryParse(uri.pathSegments.lastWhere(
          (segment) => int.tryParse(segment) != null,
          orElse: () => '1',
        )) ??
        1;
    final next = _nextPage(document, current);
    return AnimeCatalogPage(items: items, nextCursor: next?.toString());
  }

  List<AnimeTaxonomyLink> _taxonomyLinks(
    Document document, {
    required bool translated,
  }) {
    final links = <String, AnimeTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '.video-info h5.tags a[href], .video-info .models a[href]',
    )) {
      final uri = _uri(anchor.attributes['href']);
      if (uri == null) continue;
      AnimeTaxonomyKind? kind;
      String? slug;
      if (uri.path.contains('/tags/')) {
        kind = AnimeTaxonomyKind.tag;
        slug = _pathSegmentAfter(uri, 'tags');
      } else if (uri.path.contains('/categories/')) {
        kind = AnimeTaxonomyKind.topic;
        slug = _pathSegmentAfter(uri, 'categories');
      } else if (uri.path.contains('/models/')) {
        kind = AnimeTaxonomyKind.model;
        slug = _pathSegmentAfter(uri, 'models');
      }
      if (kind == null || slug == null) continue;
      var raw = anchor
              .querySelector('[data-original-title]')
              ?.attributes['data-original-title']
              ?.trim() ??
          anchor.attributes['title']?.trim() ??
          anchor.text.trim();
      if (raw.isEmpty) raw = slug;
      final name = !translated
          ? raw
          : kind == AnimeTaxonomyKind.tag
              ? JableEnglishDictionary.tagLabel(slug, raw)
              : kind == AnimeTaxonomyKind.topic
                  ? JableEnglishDictionary.categoryLabel(slug, raw)
                  : raw;
      final id = '${kind.name}:$slug';
      links[id] = AnimeTaxonomyLink(kind: kind, id: slug, name: name);
    }
    return links.values.toList(growable: false);
  }

  Future<Document> _getDocument(
    Uri uri, {
    String? clickSelector,
    int maxClicks = 1,
  }) async {
    await _loadSession();
    final loader = _browserHtmlLoader;
    if (clickSelector != null && loader != null) {
      final body = await loader(uri, _userAgent, clickSelector, maxClicks);
      if (!_isBrowserChallenge(200, body)) return html_parser.parse(body);
    }
    final response = await _client.get(uri, headers: requestHeaders);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (_isBrowserChallenge(response.statusCode, body)) {
      if (loader != null) {
        final browserBody =
            await loader(uri, _userAgent, clickSelector, maxClicks);
        if (!_isBrowserChallenge(200, browserBody)) {
          return html_parser.parse(browserBody);
        }
      }
      throw const AnimeSourceSessionRequired(
        'Jable requires its browser session to load this page.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Jable returned HTTP ${response.statusCode}.',
        uri,
      );
    }
    return html_parser.parse(body);
  }

  Future<Document> _getMetadataDocument(Uri uri) {
    final key = uri.toString();
    final cached = _metadataDocumentCache[key];
    if (cached != null) return cached;
    final pending = _getDocument(uri);
    _metadataDocumentCache[key] = pending;
    pending.catchError((Object _) {
      _metadataDocumentCache.remove(key);
      return html_parser.parse('');
    });
    return pending;
  }

  Future<void> _loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;
    final preferences = await SharedPreferences.getInstance();
    _userAgent = preferences.getString(_userAgentKey) ?? _defaultUserAgent;
    final encodedCookies = preferences.getString(_cookiesKey);
    if (encodedCookies == null || encodedCookies.isEmpty) return;
    try {
      final decoded = jsonDecode(encodedCookies);
      if (decoded is Map) {
        _cookies = decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      _cookies = const {};
    }
  }

  Uri _pagedUri(String path, String? cursor) {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final normalized = path.endsWith('/') ? path : '$path/';
    return _baseUri.resolve(page <= 1 ? normalized : '$normalized$page/');
  }

  Future<AnimeCatalogPage> _sortedCatalog(
    String path,
    String? cursor,
    String sort,
  ) {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final sortSelector = _sortSelector(sort, excludeActive: true);
    if (page <= 1) {
      return _catalog(
        _pagedUri(path, null),
        clickSelector: sortSelector,
      );
    }
    final from = page.toString().padLeft(2, '0');
    final pageSelector = '.pagination a[data-parameters*="sort_by:$sort"]'
        '[data-parameters*="from:$from"]';
    return _catalog(
      _pagedUri(path, null),
      clickSelector: '$sortSelector, $pageSelector',
      maxClicks: 2,
      currentPage: page,
    );
  }

  Uri _videoUri(String id) {
    final value = id.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.parse(value);
    }
    if (value.contains('/videos/')) return _baseUri.resolve(value);
    return _baseUri.resolve('videos/$value/');
  }

  String _taxonomyPath(AnimeTaxonomyKind kind, String id) => switch (kind) {
        AnimeTaxonomyKind.tag => 'tags/$id/',
        AnimeTaxonomyKind.model => 'models/$id/',
        _ => 'categories/$id/',
      };

  static String _sortValue(AnimeSearchSort sort) => switch (sort) {
        AnimeSearchSort.latestUpdated => 'post_date',
        AnimeSearchSort.mostViewed ||
        AnimeSearchSort.popularity =>
          'video_viewed',
        AnimeSearchSort.favorites => 'most_favourited',
        _ => 'post_date_and_popularity',
      };

  static String _sortSelector(
    String value, {
    bool excludeActive = false,
  }) =>
      excludeActive
          ? 'li:not(.active) > a[data-parameters*="sort_by:$value"]'
          : 'a[data-parameters*="sort_by:$value"]';

  static int? _nextPage(Document document, int current) {
    final pages = <int>{};
    for (final anchor in document.querySelectorAll('.pagination a')) {
      final href = anchor.attributes['href'] ?? '';
      final hrefPage = RegExp(r'/(\d+)/?(?:\?|$)').firstMatch(href)?.group(1);
      final parameters = anchor.attributes['data-parameters'] ?? '';
      final fromPage = RegExp(r'from:0*(\d+)').firstMatch(parameters)?.group(1);
      final page = int.tryParse(fromPage ?? hrefPage ?? '');
      if (page != null && page > current) pages.add(page);
    }
    if (pages.isEmpty) return null;
    final sorted = pages.toList()..sort();
    return sorted.first;
  }

  String _title(Document document) =>
      document.querySelector('.video-info h4')?.text.trim() ??
      document
          .querySelector('meta[property="og:title"]')
          ?.attributes['content']
          ?.trim() ??
      'Jable video';

  Uri? _poster(Document document) =>
      _uri(document.querySelector('video#player')?.attributes['poster']) ??
      _uri(document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content']);

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['data-src'] ?? image?.attributes['src'],
      );

  static String? _pathSegmentAfter(Uri? uri, String marker) {
    if (uri == null) return null;
    final index = uri.pathSegments.indexOf(marker);
    if (index < 0 || index + 1 >= uri.pathSegments.length) return null;
    final value = uri.pathSegments[index + 1].trim();
    return value.isEmpty ? null : value;
  }

  static bool _isBrowserChallenge(int statusCode, String body) {
    final normalized = body.toLowerCase();
    return statusCode == 403 ||
        normalized.contains('just a moment') ||
        normalized.contains('cf-chl-') ||
        normalized.contains('challenge-platform');
  }

  static List<AnimeFilterOption> _uniqueOptions(
    Iterable<AnimeFilterOption> options,
  ) =>
      Map<String, AnimeFilterOption>.fromEntries(
        options.map((option) => MapEntry(option.value, option)),
      ).values.toList(growable: false);
}
