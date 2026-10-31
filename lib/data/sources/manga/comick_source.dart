import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

typedef ComickHtmlLoader = Future<String> Function(Uri uri, String userAgent);
typedef ComickBinaryLoader
    = Future<({int statusCode, Uint8List body, Map<String, String> headers})>
        Function(
  Uri uri,
  Map<String, String> headers,
);

/// ComicK — mixed all-languages manga, manhwa, manhua and webtoon catalog.
///
/// Catalogs and chapter manifests use the site's JSON API. Metadata and reader
/// manifests are embedded as JSON in the canonical pages. A browser loader is
/// used only when Cloudflare rejects the regular Android HTTP client.
class ComickSource
    implements
        MangaSource,
        FilterableMangaSource,
        VariantCatalogMangaSource,
        ChapterNavigationMangaSource {
  static const _site = 'https://comick.live';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _popularVariants = [
    MangaCatalogVariant(id: 'all', label: 'All'),
    MangaCatalogVariant(id: 'webtoon', label: 'Most Popular Webtoon'),
    MangaCatalogVariant(id: 'manga', label: 'Most Popular Manga'),
  ];

  static const _types = [
    MangaFilterOption(value: 'cn', label: 'Manhua'),
    MangaFilterOption(value: 'jp', label: 'Manga'),
    MangaFilterOption(value: 'kr', label: 'Manhwa'),
    MangaFilterOption(value: 'others', label: 'Others'),
  ];
  static const _demographics = [
    MangaFilterOption(value: '1', label: 'Shounen'),
    MangaFilterOption(value: '2', label: 'Josei'),
    MangaFilterOption(value: '3', label: 'Seinen'),
    MangaFilterOption(value: '4', label: 'Shoujo'),
    MangaFilterOption(value: '0', label: 'None'),
  ];
  static const _statuses = [
    MangaFilterOption(value: '1', label: 'Ongoing'),
    MangaFilterOption(value: '2', label: 'Completed'),
    MangaFilterOption(value: '3', label: 'Cancelled'),
    MangaFilterOption(value: '4', label: 'Hiatus'),
  ];
  static const _createdAt = [
    MangaFilterOption(value: '3', label: '3 days ago'),
    MangaFilterOption(value: '7', label: '7 days ago'),
    MangaFilterOption(value: '30', label: '30 days ago'),
    MangaFilterOption(value: '90', label: '3 months ago'),
    MangaFilterOption(value: '180', label: '6 months ago'),
    MangaFilterOption(value: '365', label: '1 year ago'),
    MangaFilterOption(value: '730', label: '2 years ago'),
  ];
  static const _formatSlugs = {
    '4-koma',
    'adaptation',
    'anthology',
    'award-winning',
    'doujinshi',
    'fan-colored',
    'full-color',
    'long-strip',
    'official-colored',
    'oneshot',
    'user-created',
    'web-comic',
  };
  static const _themeSlugs = {
    'aliens',
    'animals',
    'cooking',
    'crossdressing',
    'delinquents',
    'demons',
    'genderswap',
    'ghosts',
    'gyaru',
    'harem',
    'incest',
    'loli',
    'mafia',
    'magic',
    'martial-arts',
    'military',
    'monster-girls',
    'monsters',
    'music',
    'ninja',
    'office-workers',
    'police',
    'post-apocalyptic',
    'reincarnation',
    'reverse-harem',
    'samurai',
    'school-life',
    'shota',
    'supernatural',
    'survival',
    'time-travel',
    'traditional-games',
    'vampires',
    'video-games',
    'villainess',
    'virtual-reality',
    'zombies',
  };

  final http.Client _client;
  final Uri _baseUri;
  final ComickHtmlLoader? _browserHtmlLoader;
  final ComickBinaryLoader? _binaryLoader;
  Map<String, dynamic>? _metadataCache;
  final Map<String, MangaDetails> _detailsCache = {};

  ComickSource({
    http.Client? client,
    Uri? baseUri,
    ComickHtmlLoader? browserHtmlLoader,
    ComickBinaryLoader? binaryLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site),
        _browserHtmlLoader = browserHtmlLoader,
        _binaryLoader = binaryLoader;

  @override
  String get id => 'comick';

  @override
  String get name => 'ComicK';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': _baseUri.resolve('/search').toString(),
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '${_baseUri.origin}/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.popular ? _popularVariants : const [];

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    if (filter != MangaCatalogFilter.popular ||
        !_popularVariants.any((variant) => variant.id == variantId)) {
      return browse(filter: filter, cursor: cursor);
    }
    return _searchCatalog(
      cursor: cursor,
      orderBy: 'user_follow_count',
      extraParameters: switch (variantId) {
        'webtoon' => {
            'time': '180',
            'genres': ['long-strip'],
          },
        'manga' => {
            'time': '180',
            'country': ['jp'],
          },
        _ => const {},
      },
    );
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    final orderBy = switch (filter) {
      MangaCatalogFilter.updated || MangaCatalogFilter.recent => 'uploaded',
      MangaCatalogFilter.added => 'created_at',
      MangaCatalogFilter.popular => 'user_follow_count',
      MangaCatalogFilter.trending => 'rating',
      MangaCatalogFilter.alphabetical => 'title',
    };
    return _searchCatalog(cursor: cursor, orderBy: orderBy);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final normalized = query.trim();
    if (normalized.isEmpty) return browse(cursor: cursor);
    return _searchCatalog(
      cursor: cursor,
      orderBy: 'uploaded',
      query: normalized,
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final metadata = await _metadata();
    final genres = _options(metadata['genres']);
    final tags = _options(metadata['tags']);
    return MangaSearchOptions(
      types: _types,
      formats: genres.where((option) => _formatSlugs.contains(option.value)),
      statuses: _statuses,
      tags: tags,
      genres: genres.where(
        (option) =>
            !_formatSlugs.contains(option.value) &&
            !_themeSlugs.contains(option.value),
      ),
      themes: genres.where((option) => _themeSlugs.contains(option.value)),
      demographics: _demographics,
      createdAtPresets: _createdAt,
      sorts: const [
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.popular,
        MangaSearchSort.rating,
        MangaSearchSort.updated,
      ],
      supportsYearRange: true,
      supportsChapterRange: true,
      supportsAdultMode: true,
      supportsSortDirection: true,
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    final selectedGenres = {
      ...request.genres,
      ...request.themes,
      ...request.formats,
    };
    final parameters = <String, dynamic>{
      if (selectedGenres.isNotEmpty) 'genres': selectedGenres.toList(),
      if (request.tags.isNotEmpty) 'tags': request.tags.toList(),
      if (request.demographics.isNotEmpty)
        'demographic': request.demographics.toList(),
      if (request.types.isNotEmpty) 'country': request.types.toList(),
      if (request.createdWithin.isNotEmpty) 'time': request.createdWithin,
      if (request.minimumChapters != null)
        'minimum': '${request.minimumChapters}',
      if (request.statuses.isNotEmpty) 'status': request.statuses.first,
      if (request.minimumYear != null) 'from': '${request.minimumYear}',
      if (request.maximumYear != null) 'to': '${request.maximumYear}',
      if (request.adultMode == MangaAdultMode.hide) 'content_rating': 'safe',
      if (request.adultMode == MangaAdultMode.only) 'content_rating': 'erotica',
    };
    return _searchCatalog(
      cursor: cursor,
      orderBy: switch (request.sort) {
        MangaSearchSort.popular => 'user_follow_count',
        MangaSearchSort.rating => 'rating',
        MangaSearchSort.updated => 'uploaded',
        _ => 'created_at',
      },
      ascending: request.sortDirection == MangaSortDirection.ascending,
      extraParameters: parameters,
    );
  }

  Future<MangaCatalogPage> _searchCatalog({
    String? cursor,
    required String orderBy,
    String query = '',
    bool ascending = false,
    Map<String, dynamic> extraParameters = const {},
  }) async {
    final uri = _baseUri.resolve('/api/search').replace(
      queryParameters: <String, dynamic>{
        'order_by': orderBy,
        'order_direction': ascending ? 'asc' : 'desc',
        'showAll': 'false',
        'exclude_mylist': 'false',
        'type': 'comic',
        if (query.isNotEmpty) 'q': query,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        ...extraParameters,
      },
    );
    final payload = _map(await _getJson(uri));
    final items = _list(payload['data'])
        .map((raw) => _catalogItem(_map(raw)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    final next = payload['next_cursor']?.toString().trim();
    return MangaCatalogPage(
      items: items,
      nextCursor: next == null || next.isEmpty ? null : next,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _slug(mangaId);
    final cached = _detailsCache[slug];
    if (cached != null) return cached;
    final detailUri = _baseUri.resolve('/comic/$slug');
    final document = html_parser.parse(
      await _getHtml(detailUri, requiredSelector: '#comic-data'),
    );
    final data = _embeddedJson(document.querySelector('#comic-data'));
    final chapters = await _chapters(slug);
    final statusValue = _integer(data['status']);
    final translationCompleted = data['translation_completed'] == true;
    final genres = <String>[
      if (_countryLabel(data['country']) case final country?) country,
      if (_contentRatingLabel(data['content_rating']) case final rating?)
        rating,
      ..._list(data['md_comic_md_genres'])
          .map(_map)
          .map((entry) => _map(entry['md_genres'])['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty),
    ];
    final details = MangaDetails(
      item: MangaCatalogItem(
        id: data['slug']?.toString() ?? slug,
        title: data['title']?.toString().trim() ?? slug,
        coverUri: _uri(data['default_thumbnail']),
        subtitle: mangaCatalogSubtitle(
          totalChapters:
              chapters.map((chapter) => chapter.number).toSet().length,
          format: _countryLabel(data['country']),
          status: _status(statusValue, translationCompleted),
        ),
      ),
      description: _plainText(data['desc']),
      alternativeTitles: _alternativeTitles(data['md_titles']),
      genres: genres,
      author: _names(data['authors']),
      artist: _names(data['artists']),
      status: _status(statusValue, translationCompleted),
      externalUri: detailUri,
      chapters: chapters,
    );
    _detailsCache[slug] = details;
    return details;
  }

  Future<List<MangaChapter>> _chapters(String slug) async {
    final firstUri = _baseUri.resolve('/api/comics/$slug/chapter-list');
    final first = _map(await _getJson(firstUri));
    final chapters = <dynamic>[..._list(first['data'])];
    final lastPage = _integer(_map(first['pagination'])['last_page']) ?? 1;
    for (var page = 2; page <= lastPage; page++) {
      final payload = _map(
        await _getJson(firstUri.replace(queryParameters: {'page': '$page'})),
      );
      chapters.addAll(_list(payload['data']));
    }
    return chapters
        .map((raw) => _chapter(slug, _map(raw)))
        .where((chapter) => chapter.id.isNotEmpty)
        .toList(growable: false);
  }

  MangaChapter _chapter(String slug, Map<String, dynamic> data) {
    final hid = data['hid']?.toString() ?? '';
    final number = data['chap']?.toString().trim() ?? '';
    final language = data['lang']?.toString().trim() ?? 'und';
    final volume = data['vol']?.toString().trim();
    final title = data['title']?.toString().trim() ?? '';
    final groups = _list(data['group_name'])
        .map((group) => group.toString().trim())
        .where((group) => group.isNotEmpty)
        .join(', ');
    final label = [
      if (volume != null && volume.isNotEmpty) 'Vol. $volume',
      'Ch. $number',
      if (title.isNotEmpty) title,
    ].join(title.isEmpty ? ' ' : ': ');
    return MangaChapter(
      id: '/comic/$slug/$hid-chapter-$number-$language',
      title: label,
      number: number,
      volume: volume == null || volume.isEmpty ? null : volume,
      language: language,
      uploader: groups.isEmpty ? null : groups,
      publishedAt: data['created_at']?.toString(),
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final chapterUri = _baseUri.resolve(chapterId);
    final document = html_parser.parse(
      await _getHtml(chapterUri, requiredSelector: '#sv-data'),
    );
    final data = _embeddedJson(document.querySelector('#sv-data'));
    final images = _list(_map(data['chapter'])['images']);
    for (final raw in images) {
      final uri = _uri(_map(raw)['url']);
      if (uri != null) {
        yield MangaReaderPage.network(
          uri,
          headers: {...coverImageHeaders, 'Referer': chapterUri.toString()},
        );
      }
    }
  }

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) async {
    final chapters = (await getDetails(mangaId)).chapters;
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    return index > 0 ? chapters[index - 1].id : null;
  }

  @override
  Future<String?> previousChapterId(
    String mangaId,
    String currentChapterId,
  ) async {
    final chapters = (await getDetails(mangaId)).chapters;
    final index =
        chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    return index >= 0 && index + 1 < chapters.length
        ? chapters[index + 1].id
        : null;
  }

  Future<Map<String, dynamic>> _metadata() async {
    final cached = _metadataCache;
    if (cached != null) return cached;
    return _metadataCache = _map(
      await _getJson(_baseUri.resolve('/api/metadata')),
    );
  }

  Future<Object?> _getJson(Uri uri) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _client.get(uri, headers: requestHeaders);
      final body = utf8.decode(response.bodyBytes).trim();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          return jsonDecode(body);
        } catch (_) {
          // A Cloudflare interstitial may return 200 HTML.
        }
      }
      if (response.statusCode == 429 && attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      break;
    }
    final binaryLoader = _binaryLoader;
    if (binaryLoader != null) {
      final response = await binaryLoader(uri, requestHeaders);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          return jsonDecode(utf8.decode(response.body));
        } catch (_) {
          // Fall through to the interactive browser challenge.
        }
      }
    }
    final loader = _browserHtmlLoader;
    if (loader == null) {
      throw http.ClientException('ComicK API request was blocked', uri);
    }
    final browserHtml = await loader(uri, _userAgent);
    final browserJson = _tryDecodeJson(browserHtml);
    if (browserJson != null) return browserJson;

    final document = html_parser.parse(browserHtml);
    final raw = document.querySelector('pre')?.text.trim() ??
        document.body?.text.trim() ??
        '';
    final embeddedJson = _tryDecodeJson(raw);
    if (embeddedJson != null) return embeddedJson;

    // Completing the challenge can establish the clearance cookie even when
    // the WebView snapshot times out on the interstitial. Reuse that cookie
    // immediately instead of making the user press Retry once.
    if (binaryLoader != null) {
      final verified = await binaryLoader(uri, requestHeaders);
      if (verified.statusCode >= 200 && verified.statusCode < 300) {
        final verifiedJson = _tryDecodeJson(utf8.decode(verified.body));
        if (verifiedJson != null) return verifiedJson;
      }
    }
    throw StateError('ComicK browser fallback returned no JSON.');
  }

  Object? _tryDecodeJson(String value) {
    if (value.trim().isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  Future<String> _getHtml(Uri uri, {required String requiredSelector}) async {
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        html_parser.parse(body).querySelector(requiredSelector) != null) {
      return body;
    }
    final loader = _browserHtmlLoader;
    if (loader == null) {
      throw http.ClientException('ComicK page request was blocked', uri);
    }
    return loader(uri, _userAgent);
  }

  Map<String, dynamic> _embeddedJson(dynamic element) {
    final raw = element?.text?.toString().trim() ?? '';
    if (raw.isEmpty) throw StateError('ComicK did not expose embedded data.');
    return _map(jsonDecode(raw));
  }

  List<MangaFilterOption> _options(Object? value) => _list(value)
      .map(_map)
      .map(
        (entry) => MangaFilterOption(
          value: entry['slug']?.toString() ?? '',
          label: entry['name']?.toString() ?? '',
        ),
      )
      .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
      .toList(growable: false)
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  MangaCatalogItem _catalogItem(Map<String, dynamic> data) => MangaCatalogItem(
        id: data['slug']?.toString() ?? '',
        title: data['title']?.toString().trim() ?? '',
        coverUri: _uri(data['default_thumbnail']),
      );

  List<Map<String, String>> _alternativeTitles(Object? value) {
    final values = value is Map ? value.values : _list(value);
    return values
        .map(_map)
        .map((entry) => entry['title']?.toString().trim() ?? '')
        .where((title) => title.isNotEmpty)
        .map((title) => {'und': title})
        .toList(growable: false);
  }

  String? _names(Object? value) {
    final names = _list(value)
        .map(_map)
        .map((entry) => entry['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
    return names.isEmpty ? null : names;
  }

  String _plainText(Object? value) {
    final html = value?.toString() ?? '';
    return (html_parser.parseFragment(html).text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  MangaStatus _status(int? status, bool translationCompleted) =>
      switch (status) {
        1 => MangaStatus.ongoing,
        2 => translationCompleted ? MangaStatus.completed : MangaStatus.unknown,
        3 => MangaStatus.cancelled,
        4 => MangaStatus.hiatus,
        _ => MangaStatus.unknown,
      };

  String? _countryLabel(Object? value) => switch (value?.toString()) {
        'jp' => 'Manga',
        'cn' => 'Manhua',
        'kr' => 'Manhwa',
        _ => null,
      };

  String? _contentRatingLabel(Object? value) => switch (value?.toString()) {
        'suggestive' => 'Suggestive',
        'erotica' => 'Erotica',
        _ => null,
      };

  String _slug(String value) {
    final uri = Uri.tryParse(value);
    final segments = uri?.pathSegments.where((segment) => segment.isNotEmpty);
    return segments == null || segments.isEmpty ? value : segments.last;
  }

  Uri? _uri(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : _baseUri.resolve(text);
  }

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<dynamic> _list(Object? value) =>
      value is List ? List<dynamic>.from(value) : const [];
}
