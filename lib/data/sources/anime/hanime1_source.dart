import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/anime/hanime1_english_dictionary.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

typedef Hanime1BrowserHtmlLoader = Future<String> Function(
  Uri uri,
  String userAgent,
);
typedef Hanime1BrowserImageLoader = Future<Uint8List> Function(
  Uri uri,
  String userAgent,
);

/// Adult video source backed by Hanime1.me.
///
/// The provider exposes ordinary HTML catalogs and short-lived progressive MP4
/// URLs. The optional English layer is deliberately local and deterministic:
/// request values stay in Traditional Chinese while parsed labels are mapped
/// through [Hanime1EnglishDictionary].
class Hanime1Source
    implements
        AnimeSource,
        FilterableAnimeSource,
        TaxonomyBrowsableAnimeSource,
        BrowserSessionAnimeSource,
        BrowserImageAnimeSource,
        StaticMetadataTranslationAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://hanime1.me/');
  static const _translationPreferenceKey =
      'source.hanime1.staticEnglishTranslation';
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
  static const _cookiesKey = 'hanime1_browser_cookies';
  static const _userAgentKey = 'hanime1_browser_user_agent';

  final http.Client _client;
  final Uri _baseUri;
  final bool? _translationOverride;
  final Hanime1BrowserHtmlLoader? _browserHtmlLoader;
  final Hanime1BrowserImageLoader? _browserImageLoader;
  Map<String, String> _cookies = const {};
  String _userAgent = _defaultUserAgent;
  bool _sessionLoaded = false;
  final Map<bool, AnimeSearchOptions> _searchOptionsCache = {};
  final Map<String, Future<Document>> _metadataDocumentCache = {};

  Hanime1Source({
    http.Client? client,
    Uri? baseUri,
    bool? translateToEnglish,
    Hanime1BrowserHtmlLoader? browserHtmlLoader,
    Hanime1BrowserImageLoader? browserImageLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _translationOverride = translateToEnglish,
        _browserHtmlLoader = browserHtmlLoader,
        _browserImageLoader = browserImageLoader;

  @override
  String get id => 'hanime1';

  @override
  String get name => 'Hanime1';

  @override
  Uri get baseUri => _baseUri;

  @override
  Uri get sessionUri => _baseUri.resolve('search');

  @override
  String get staticTranslationLabel => 'Static English translation';

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.7',
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
        AnimeCatalogFilter.added,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularWeek,
        AnimeCatalogFilter.popularMonth,
        AnimeCatalogFilter.episodeMostViewed,
        AnimeCatalogFilter.seriesMostViewed,
        AnimeCatalogFilter.seriesNewest,
        AnimeCatalogFilter.updated,
      ];

  @override
  Future<Uint8List> loadBrowserImage(Uri uri) {
    final loader = _browserImageLoader;
    if (loader == null) {
      throw StateError('Hanime1 browser image loading is unavailable.');
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
  }

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    final sort = switch (filter) {
      AnimeCatalogFilter.added => '最新上市',
      AnimeCatalogFilter.popular => '本日排行',
      AnimeCatalogFilter.popularWeek => '本週排行',
      AnimeCatalogFilter.popularMonth => '本月排行',
      AnimeCatalogFilter.episodeMostViewed => '觀看次數',
      AnimeCatalogFilter.seriesMostViewed => '讚好比例',
      AnimeCatalogFilter.seriesNewest => '時長最長',
      AnimeCatalogFilter.updated => '他們在看',
      _ => '最新上傳',
    };
    return _catalog(_searchUri(cursor: cursor, parameters: {'sort': sort}));
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => _catalog(
        _searchUri(
          cursor: cursor,
          parameters: {'query': query.trim()},
        ),
      );

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final translated = await isStaticTranslationEnabled();
    final cached = _searchOptionsCache[translated];
    if (cached != null) return cached;
    final document = await _getDocument(_baseUri.resolve('search'));
    String label(String value) => translated
        ? Hanime1EnglishDictionary.translateLabel(value)
        : value.trim();

    final types = _uniqueOptions(document
        .querySelectorAll('.genre-option[data-value]')
        .map((element) => element.attributes['data-value']?.trim() ?? '')
        .where((value) => value.isNotEmpty && value != '全部')
        .map((value) => AnimeFilterOption(value: value, label: label(value))));
    final tags = _uniqueOptions(document
        .querySelectorAll('input[name="tags[]"]')
        .map((element) => element.attributes['value']?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .map((value) => AnimeFilterOption(value: value, label: label(value))));
    final dates = _uniqueOptions(document
        .querySelectorAll('.hentai-date-options-wrapper[data-value]')
        .map((element) => element.attributes['data-value']?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .map((value) => AnimeFilterOption(value: value, label: label(value))));
    final durations = _uniqueOptions(document
        .querySelectorAll('.hentai-duration-options-wrapper[data-value]')
        .map((element) => element.attributes['data-value']?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .map((value) => AnimeFilterOption(value: value, label: label(value))));

    final options = AnimeSearchOptions(
      genres: tags,
      years: dates,
      types: types,
      statuses: durations,
      ratings: const [
        AnimeFilterOption(value: 'broad', label: 'Match any selected tag'),
      ],
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.releaseDate,
        AnimeSearchSort.mostViewed,
        AnimeSearchSort.score,
      ],
      labels: const {
        'genres': 'Tags',
        'genresAny': 'Any tag',
        'years': 'Release date',
        'types': 'Video type',
        'statuses': 'Duration',
        'ratings': 'Tag matching',
        'sorts': 'Sort order',
      },
    );
    _searchOptionsCache[translated] = options;
    return options;
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final sort = switch (request.sort) {
      AnimeSearchSort.releaseDate => '最新上市',
      AnimeSearchSort.latestUpdated => '他們在看',
      AnimeSearchSort.mostViewed => '觀看次數',
      AnimeSearchSort.score => '讚好比例',
      _ => '最新上傳',
    };
    return _catalog(_searchUri(cursor: cursor, parameters: {
      if (request.query.trim().isNotEmpty) 'query': request.query.trim(),
      if (request.type?.isNotEmpty == true) 'genre': request.type!,
      if (request.genres.isNotEmpty) 'tags[]': request.genres.toList(),
      if (request.year?.isNotEmpty == true) 'date': request.year!,
      if (request.status?.isNotEmpty == true) 'duration': request.status!,
      if (request.rating == 'broad') 'broad': 'on',
      'sort': sort,
    }));
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final document = await _getMetadataDocument(_resolve(animeId));
    final translated = await isStaticTranslationEnabled();
    String present(String value) => translated
        ? Hanime1EnglishDictionary.translateMetadata(value.trim())
        : value.trim();
    final rawTitle = _title(document);
    final title = present(rawTitle);
    final poster = _uri(document.querySelector('video')?.attributes['poster']);
    final rawDescription =
        document.querySelector('.video-caption-text')?.text.trim() ?? '';
    final artist =
        document.querySelector('#video-artist-name')?.text.trim() ?? '';
    final genre = document
            .querySelector('#video-artist-name')
            ?.parent
            ?.parent
            ?.querySelector('a[href*="genre="]')
            ?.text
            .trim() ??
        '';
    final links = _taxonomyLinks(document, translated: translated);
    final genres = links
        .where((link) => link.kind == AnimeTaxonomyKind.tag)
        .map((link) => link.name)
        .toSet()
        .toList();
    if (genre.isNotEmpty) genres.insert(0, present(genre));
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: animeId,
        title: title,
        coverUri: poster,
        subtitle: artist.isEmpty ? null : artist,
      ),
      description: present(rawDescription),
      alternativeTitles: title == rawTitle ? const [] : [rawTitle],
      genres: genres,
      taxonomyLinks: links,
      status: AnimeStatus.completed,
      bannerUri: poster,
      studios: artist.isEmpty ? const [] : [artist],
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final document = await _getMetadataDocument(_resolve(animeId));
    final translated = await isStaticTranslationEnabled();
    final rawTitle = _title(document);
    final dateText =
        document.querySelector('.video-description-panel .hidden-xs')?.text ??
            '';
    final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(dateText);
    return [
      AnimeEpisode(
        id: animeId,
        animeId: animeId,
        title: translated
            ? Hanime1EnglishDictionary.translateMetadata(rawTitle)
            : rawTitle,
        number: 1,
        releasedAt: DateTime.tryParse(dateMatch?.group(0) ?? ''),
        thumbnailUri:
            _uri(document.querySelector('video')?.attributes['poster']),
      ),
    ];
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final pageUri = _resolve(episodeId);
    final document = await _getDocument(pageUri);
    var streams = _pageStreams(document, pageUri);
    if (streams.isEmpty) {
      final videoId = pageUri.queryParameters['v'];
      if (videoId != null && videoId.isNotEmpty) {
        final downloadUri = _baseUri.resolve('download').replace(
          queryParameters: {'v': videoId},
        );
        final downloadDocument = await _getDocument(downloadUri);
        streams = _downloadStreams(downloadDocument, downloadUri);
      }
    }
    if (streams.isEmpty) {
      throw StateError('Hanime1 did not expose a playable MP4 stream.');
    }
    return AnimePlayback(streams: streams);
  }

  @override
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) {
    final uri = _resolve(taxonomyId);
    final parameters = <String, dynamic>{...uri.queryParametersAll};
    return _catalog(
      _searchUri(
        cursor: cursor,
        parameters: parameters,
      ),
    );
  }

  Future<AnimeCatalogPage> _catalog(Uri uri) async {
    final document = await _getDocument(uri);
    final translated = await isStaticTranslationEnabled();
    final seen = <String>{};
    final catalogCards = <Element>[
      ...document.querySelectorAll('.video-item-container'),
      ...document.querySelectorAll(
        '.home-rows-videos-wrapper a[href*="/watch"]',
      ),
    ];
    final items = catalogCards
        .map(
          (container) {
            final isLegacyCard = container.localName == 'a';
            final anchor = isLegacyCard
                ? container
                : container.querySelector('a.video-link[href*="/watch"]');
            final href = anchor?.attributes['href']?.trim() ?? '';
            final resolved = _uri(href);
            if (resolved == null || resolved.host != _baseUri.host) return null;
            final id = '${resolved.path}'
                '${resolved.hasQuery ? '?${resolved.query}' : ''}';
            if (!seen.add(id)) return null;
            final rawTitle = (isLegacyCard
                        ? container.querySelector('.home-rows-videos-title')
                        : container.querySelector('.title'))
                    ?.text
                    .trim() ??
                container.attributes['title']?.trim() ??
                '';
            if (rawTitle.isEmpty) return null;
            final duration =
                container.querySelector('.duration')?.text.trim() ?? '';
            final stats = container
                .querySelectorAll('.stats-container .stat-item')
                .map((element) => element.text.trim())
                .where((value) => value.isNotEmpty)
                .join(' · ');
            final author =
                container.querySelector('.subtitle a')?.text.trim() ?? '';
            final time = container
                    .querySelector('.subtitle-time')
                    ?.text
                    .replaceAll(' ', ' ')
                    .replaceFirst('•', '')
                    .trim() ??
                '';
            final subtitle = [duration, stats, author, time]
                .where((value) => value.isNotEmpty)
                .join(' · ');
            return AnimeCatalogItem(
              id: id,
              title: translated
                  ? Hanime1EnglishDictionary.translateMetadata(rawTitle)
                  : rawTitle,
              coverUri: _imageUri(container.querySelector(
                isLegacyCard ? '.video-card-inner img' : 'img.main-thumb',
              )),
              subtitle: subtitle.isEmpty
                  ? null
                  : translated
                      ? Hanime1EnglishDictionary.translateMetadata(subtitle)
                      : subtitle,
            );
          },
        )
        .whereType<AnimeCatalogItem>()
        .toList(growable: false);
    final currentPage = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
    final hasNext = document
        .querySelectorAll('.pagination a[href]')
        .map((anchor) => _uri(anchor.attributes['href']))
        .whereType<Uri>()
        .any((link) => link.queryParameters['page'] == '${currentPage + 1}');
    return AnimeCatalogPage(
      items: items,
      nextCursor: hasNext ? '${currentPage + 1}' : null,
    );
  }

  List<AnimeTaxonomyLink> _taxonomyLinks(
    Document document, {
    required bool translated,
  }) {
    final links = <String, AnimeTaxonomyLink>{};
    for (final anchor
        in document.querySelectorAll('.video-tags-wrapper a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (!href.contains('/search?')) continue;
      final uri = _resolve(href);
      final isStructuredTag = uri.queryParametersAll.containsKey('tags[]');
      final rawName = anchor.text
          .replaceAll(RegExp(r'\(\d+\)\s*$'), '')
          .replaceAll('#', '')
          .trim();
      if (rawName.isEmpty) continue;
      final name = translated
          ? Hanime1EnglishDictionary.translateLabel(rawName)
          : rawName;
      final key = '${isStructuredTag ? 'tag' : 'topic'}:$href';
      links[key] = AnimeTaxonomyLink(
        kind: isStructuredTag ? AnimeTaxonomyKind.tag : AnimeTaxonomyKind.topic,
        id: href,
        name: name,
      );
    }
    return links.values.toList(growable: false);
  }

  String _title(Document document) =>
      document.querySelector('#shareBtn-title')?.text.trim() ??
      document
          .querySelector('meta[property="og:title"]')
          ?.attributes['content']
          ?.replaceFirst(RegExp(r'\s*-\s*H\S.*$'), '')
          .trim() ??
      'Hanime1 video';

  Uri _searchUri({
    String? cursor,
    Map<String, dynamic> parameters = const {},
  }) {
    final query = <String, dynamic>{...parameters};
    if (cursor?.isNotEmpty == true) query['page'] = cursor!;
    return _baseUri.resolve('search').replace(queryParameters: query);
  }

  Future<Document> _getDocument(Uri uri) async {
    await _loadSession();
    final response = await _client.get(uri, headers: requestHeaders);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (_isBrowserChallenge(response.statusCode, body)) {
      final loader = _browserHtmlLoader;
      if (loader != null) {
        final browserBody = await loader(uri, _userAgent);
        if (!_isBrowserChallenge(200, browserBody)) {
          return html_parser.parse(browserBody);
        }
      }
      throw const AnimeSourceSessionRequired(
        'Hanime1 requires its browser session to load this page.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Hanime1 returned HTTP ${response.statusCode}.',
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

  List<AnimeVideoStream> _pageStreams(Document document, Uri referer) {
    final candidates = <Element>[
      ...document.querySelectorAll('video#player source[src]'),
      ...document.querySelectorAll('video#player[src]'),
    ];
    return _sortedStreams(candidates.map((element) {
      final rawUri = element.attributes['src']?.trim() ?? '';
      if (!rawUri.startsWith('http://') && !rawUri.startsWith('https://')) {
        return null;
      }
      final size = element.attributes['size']?.trim();
      final height = int.tryParse(size ?? '') ??
          int.tryParse(
            RegExp(r'(\d{3,4})p').firstMatch(rawUri)?.group(1) ?? '',
          );
      return _videoStream(
        uri: Uri.parse(rawUri),
        referer: referer,
        height: height,
        mimeType: element.attributes['type'],
      );
    }).whereType<AnimeVideoStream>());
  }

  List<AnimeVideoStream> _downloadStreams(Document document, Uri referer) {
    return _sortedStreams(
      document.querySelectorAll('.download-table tr').map((row) {
        final rawUri = row.querySelector('a[data-url]')?.attributes['data-url'];
        final uri = Uri.tryParse(rawUri?.trim() ?? '');
        if (uri == null || !uri.hasScheme) return null;
        final height = int.tryParse(
          RegExp(r'(\d{3,4})p', caseSensitive: false)
                  .firstMatch(row.text)
                  ?.group(1) ??
              '',
        );
        return _videoStream(
          uri: uri,
          referer: referer,
          height: height,
          mimeType: 'video/mp4',
        );
      }).whereType<AnimeVideoStream>(),
    );
  }

  AnimeVideoStream _videoStream({
    required Uri uri,
    required Uri referer,
    required int? height,
    String? mimeType,
  }) =>
      AnimeVideoStream(
        uri: uri,
        protocol: VideoProtocol.progressive,
        quality: height == null ? 'Auto' : '${height}p',
        language: 'und',
        mimeType: mimeType ?? 'video/mp4',
        height: height,
        headers: {
          'Referer': referer.toString(),
          'Origin': '${_baseUri.scheme}://${_baseUri.host}',
          'User-Agent': _userAgent,
        },
      );

  List<AnimeVideoStream> _sortedStreams(
    Iterable<AnimeVideoStream> streams,
  ) {
    final result = streams.toList(growable: false);
    result.sort(
      (left, right) => (right.height ?? 0).compareTo(left.height ?? 0),
    );
    return result;
  }

  static bool _isBrowserChallenge(int statusCode, String body) {
    final normalized = body.toLowerCase();
    return statusCode == 403 ||
        normalized.contains('just a moment') ||
        normalized.contains('cf-chl-') ||
        normalized.contains('challenge-platform');
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

  Uri _resolve(String value) => _baseUri.resolve(value.trim());

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['src'] ?? image?.attributes['data-src'],
      );

  static List<AnimeFilterOption> _uniqueOptions(
    Iterable<AnimeFilterOption> options,
  ) =>
      Map<String, AnimeFilterOption>.fromEntries(
        options.map((option) => MapEntry(option.value, option)),
      ).values.toList(growable: false);
}
