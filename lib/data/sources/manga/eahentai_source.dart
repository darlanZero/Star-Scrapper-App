import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

class EAHentaiSource
    implements
        MangaSource,
        TaxonomyBrowsableMangaSource,
        SortableTaxonomyMangaSource,
        PaginatedTaxonomyMangaSource,
        VariantCatalogMangaSource,
        VariantTaxonomyMangaSource {
  static final Uri _defaultBaseUri = Uri.parse('https://eahentai.com/');
  static const _imageOrigin = 'https://i.eahentai.com/file/ea-gallery/';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const _resultVariants = [
    MangaCatalogVariant(id: 'date_desc', label: 'Latest'),
    MangaCatalogVariant(id: 'views_daily', label: 'Today'),
    MangaCatalogVariant(id: 'views_weekly', label: 'Weekly'),
    MangaCatalogVariant(id: 'views_monthly', label: 'Monthly'),
    MangaCatalogVariant(id: 'views_alltime', label: 'All time'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, Future<MangaDetails>> _detailsCache = {};

  EAHentaiSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'eahentai';

  @override
  String get name => 'EAHentai';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/json,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.popular,
        MangaCatalogFilter.recent,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.added,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.popular
          ? _resultVariants.sublist(1, 4)
          : const [];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) =>
      switch (filter) {
        MangaCatalogFilter.popular =>
          browseVariant(filter, 'views_daily', cursor: cursor),
        MangaCatalogFilter.recent => _latest(cursor),
        MangaCatalogFilter.trending => _homeSection('discover'),
        MangaCatalogFilter.added => _mostSaved(),
        _ => _latest(cursor),
      };

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) async {
    if (filter != MangaCatalogFilter.popular) {
      return browse(filter: filter, cursor: cursor);
    }
    final order =
        {'views_daily', 'views_weekly', 'views_monthly'}.contains(variantId)
            ? variantId
            : 'views_daily';
    final page = int.tryParse(cursor ?? '') ?? 0;
    final data = await _json(_baseUri.resolve(
      '/api/image/popular/?page=$page&take=42&orderby=$order',
    ));
    return MangaCatalogPage(items: _catalogItems(data));
  }

  Future<MangaCatalogPage> _latest(String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 0;
    final data = await _json(
      _baseUri.resolve('/api/image/latest/?page=$page&take=42'),
    );
    return _catalogPage(data, page);
  }

  Future<MangaCatalogPage> _mostSaved() async {
    final data = await _json(
      _baseUri.resolve('/api/discovery/most-saved?take=42'),
    );
    return MangaCatalogPage(items: _catalogItems(data));
  }

  Future<MangaCatalogPage> _homeSection(String heading) async {
    final document = await _document(_baseUri);
    final normalized = heading.toLowerCase();
    Element? root;
    for (final element in document.querySelectorAll('h1, h2, h3')) {
      if (element.text.trim().toLowerCase() != normalized) continue;
      Element? candidate = element.parent;
      while (candidate != null) {
        final cards = candidate.querySelectorAll('a[href^="/a/"]');
        if (cards.length >= 2) {
          root = candidate;
          break;
        }
        candidate = candidate.parent;
      }
      if (root != null) break;
    }
    return MangaCatalogPage(
      items: _catalogItemsFromHtml(
        root ?? document.body ?? Element.tag('body'),
      ),
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final value = query.trim();
    if (value.isEmpty) return MangaCatalogPage(items: const []);
    final page = int.tryParse(cursor ?? '') ?? 0;
    final uri = _baseUri.resolve('/api/image/search/v2/').replace(
      queryParameters: {
        'type': 'gallery',
        'q': value,
        'take': '42',
        'page': '$page',
        'orderby': 'date_desc',
      },
    );
    return _catalogPage(await _json(uri), page);
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.parody,
        MangaTaxonomyKind.character,
        MangaTaxonomyKind.artist,
      ];

  @override
  List<MangaTaxonomySort> taxonomySorts(MangaTaxonomyKind kind) => const [
        MangaTaxonomySort.alphabetical,
      ];

  @override
  bool taxonomyRequiresQuery(MangaTaxonomyKind kind) => false;

  @override
  bool supportsTaxonomyPagination(MangaTaxonomyKind kind) =>
      taxonomyKinds.contains(kind);

  @override
  Future<MangaTaxonomyPage> getTaxonomyPage(
    MangaTaxonomyKind kind, {
    MangaTaxonomySort sort = MangaTaxonomySort.alphabetical,
    String? cursor,
  }) async {
    final letter = _indexLetter(cursor ?? 'A');
    final uri = _baseUri.resolve('/${_pluralPath(kind)}').replace(
      queryParameters: {'q': letter},
    );
    final options = _parseTaxonomy(await _document(uri), kind);
    final code = letter.codeUnitAt(0);
    return MangaTaxonomyPage(
      options: options,
      nextCursor:
          code < 'Z'.codeUnitAt(0) ? String.fromCharCode(code + 1) : null,
    );
  }

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) =>
      getSortedTaxonomy(kind, query: query);

  @override
  Future<List<MangaTaxonomyOption>> getSortedTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
    MangaTaxonomySort sort = MangaTaxonomySort.alphabetical,
  }) async {
    final normalized = query.trim().toLowerCase();
    final page = await getTaxonomyPage(
      kind,
      cursor: _indexLetter(normalized.isEmpty ? 'A' : normalized),
    );
    return page.options
        .where((option) =>
            normalized.isEmpty ||
            option.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  List<MangaTaxonomyOption> _parseTaxonomy(
    Document document,
    MangaTaxonomyKind kind,
  ) {
    final prefix =
        kind == MangaTaxonomyKind.tag ? '/search' : '/${_singularPath(kind)}/';
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll('main a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (!href.startsWith(prefix)) continue;
      String name;
      if (kind == MangaTaxonomyKind.tag) {
        name = anchor.querySelector('h2, h3, h4')?.text.trim() ?? '';
        if (name.isEmpty) {
          name = Uri.tryParse(href.replaceAll('&amp;', '&'))
                  ?.queryParameters['q']
                  ?.trim() ??
              '';
        }
      } else {
        name = anchor.querySelector('h2, h3, h4')?.text.trim() ?? '';
        if (name.isEmpty) {
          final text = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          name = text.replaceFirst(
            RegExp(r'\s+\d+\s+albums?$', caseSensitive: false),
            '',
          );
        }
      }
      if (name.isEmpty) continue;
      final count = RegExp(r'(\d+)\s+albums?', caseSensitive: false)
          .firstMatch(anchor.text)
          ?.group(1);
      found[href] = MangaTaxonomyOption(
        id: href.replaceAll('&amp;', '&'),
        name: name,
        titleCount: int.tryParse(count ?? ''),
      );
    }
    final values = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return values;
  }

  @override
  List<MangaCatalogVariant> taxonomyCatalogVariants(
    MangaTaxonomyKind kind,
  ) =>
      taxonomyKinds.contains(kind) ? _resultVariants : const [];

  @override
  String taxonomyVariantId(
    MangaTaxonomyKind kind,
    String taxonomyId,
    String variantId,
  ) {
    final uri = Uri.parse(taxonomyId.replaceAll('&amp;', '&'));
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'orderby': variantId,
    }).toString();
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) async {
    final route = Uri.parse(taxonomyId.replaceAll('&amp;', '&'));
    final page = int.tryParse(cursor ?? '') ?? 0;
    final order = route.queryParameters['orderby'] ?? 'date_desc';
    final name = route.pathSegments.isEmpty
        ? route.queryParameters['q'] ?? ''
        : Uri.decodeComponent(route.pathSegments.last);
    final Uri apiUri;
    if (kind == MangaTaxonomyKind.tag) {
      apiUri = _baseUri.resolve('/api/image/search/v2/').replace(
        queryParameters: {
          'type': 'gallery',
          'q': route.queryParameters['q'] ?? name,
          'take': '42',
          'page': '$page',
          'orderby': order,
        },
      );
    } else {
      apiUri = _baseUri.resolve('/api/image/entities/albums').replace(
        queryParameters: {
          'type': _singularPath(kind),
          'q': name,
          'take': '42',
          'page': '$page',
          'orderby': order,
        },
      );
    }
    return _catalogPage(await _json(apiUri), page);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final id = _albumId(mangaId);
    final cached = _detailsCache[id];
    if (cached != null) return cached;
    final pending = _loadDetails(id);
    _detailsCache[id] = pending;
    try {
      return await pending;
    } catch (_) {
      _detailsCache.remove(id);
      rethrow;
    }
  }

  Future<MangaDetails> _loadDetails(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'mangaId');
    final uri = _baseUri.resolve('/a/$id');
    final document = await _document(uri);
    final title = document.querySelector('main h1')?.text.trim() ?? '';
    if (title.isEmpty) {
      throw StateError('EAHentai did not return album $id.');
    }
    final cover = _imageUri(document
        .querySelector('main img[src*="/thumbnail/"]')
        ?.attributes['src']);
    final links = _detailTaxonomyLinks(document);
    final tags = links
        .where((link) => link.kind == MangaTaxonomyKind.tag)
        .map((link) => link.name)
        .toList(growable: false);
    final artists = links
        .where((link) => link.kind == MangaTaxonomyKind.artist)
        .map((link) => link.name)
        .toList(growable: false);
    final text = document.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final pageCount = int.tryParse(
          RegExp(r'(\d+)\s+pages?', caseSensitive: false)
                  .firstMatch(text)
                  ?.group(1) ??
              '',
        ) ??
        0;
    final uploaded = RegExp(
      r'Uploaded\s+(.+?)(?=\s+(?:Read Now|Bookmark|Add to List|Share|#\d+|Information))',
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.trim();

    return MangaDetails(
      item: MangaCatalogItem(
        id: id,
        title: title,
        coverUri: cover,
        subtitle: pageCount > 0 ? '$pageCount pages' : null,
      ),
      genres: tags,
      taxonomyLinks: links,
      artist: artists.isEmpty ? null : artists.join(', '),
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: '/a/$id/0',
          title: 'Complete gallery',
          number: '1',
          language: 'en',
          pages: pageCount > 0 ? '$pageCount' : null,
          publishedAt: uploaded,
        ),
      ],
    );
  }

  List<MangaTaxonomyLink> _detailTaxonomyLinks(Document document) {
    final found = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll('main a[href]')) {
      final href = anchor.attributes['href']?.replaceAll('&amp;', '&') ?? '';
      final name = anchor.text.trim();
      if (href.isEmpty || name.isEmpty) continue;
      final kind = href.startsWith('/artist/')
          ? MangaTaxonomyKind.artist
          : href.startsWith('/character/')
              ? MangaTaxonomyKind.character
              : href.startsWith('/parody/')
                  ? MangaTaxonomyKind.parody
                  : href.startsWith('/search') &&
                          Uri.tryParse(href)?.queryParameters['q'] != null &&
                          Uri.tryParse(href)?.queryParameters['type'] !=
                              'albumType'
                      ? MangaTaxonomyKind.tag
                      : null;
      if (kind == null) continue;
      found['${kind.name}:$href'] =
          MangaTaxonomyLink(kind: kind, id: href, name: name);
    }
    return found.values.toList(growable: false);
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final id = _albumId(mangaId);
    final details = await getDetails(id);
    final count = int.tryParse(details.chapters.first.pages ?? '') ?? 0;
    if (count <= 0) return;
    final reader = await _document(_baseUri.resolve('/a/$id/0'));
    final originals = reader
        .querySelectorAll('main img[src]')
        .map((image) => _imageUri(image.attributes['src']))
        .whereType<Uri>()
        .where((uri) =>
            uri.host.contains('eahentai.com') &&
            !uri.path.contains('/thumbnail/'))
        .toList(growable: false);
    if (originals.isEmpty) return;
    final template = originals.first;
    final filename = template.pathSegments.last;
    final match = RegExp(r'^(.*?)(\d+)(\.[^.]+)$').firstMatch(filename);
    if (match == null) {
      for (final page in originals.take(count)) {
        yield MangaReaderPage.network(page, headers: coverImageHeaders);
      }
      return;
    }
    final prefix = match.group(1)!;
    final number = match.group(2)!;
    final extension = match.group(3)!;
    final directory = template.pathSegments.sublist(
      0,
      template.pathSegments.length - 1,
    );
    for (var index = 1; index <= count; index++) {
      final pageNumber = '$index'.padLeft(number.length, '0');
      yield MangaReaderPage.network(
        template.replace(
          pathSegments: [...directory, '$prefix$pageNumber$extension'],
        ),
        headers: coverImageHeaders,
      );
    }
  }

  MangaCatalogPage _catalogPage(Object? data, int page) {
    final items = _catalogItems(data);
    final map = data is Map ? data : const {};
    final totalPages = _asInt(map['totalPages']);
    return MangaCatalogPage(
      items: items,
      nextCursor:
          totalPages != null && page + 1 < totalPages ? '${page + 1}' : null,
    );
  }

  List<MangaCatalogItem> _catalogItems(Object? data) {
    final raw = data is List
        ? data
        : data is Map && data['items'] is List
            ? data['items'] as List
            : const [];
    final found = <String, MangaCatalogItem>{};
    for (final value in raw.whereType<Map>()) {
      final id = value['albumID']?.toString() ?? '';
      final title =
          value['title']?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ??
              '';
      if (id.isEmpty || title.isEmpty) continue;
      final type = value['albumType']?.toString().split('|').first.trim() ?? '';
      final views = _asInt(value['views']);
      found[id] = MangaCatalogItem(
        id: id,
        title: title,
        coverUri: _imageUri(value['thumbnailUri']?.toString()),
        subtitle: [
          if (type.isNotEmpty) type,
          if (views != null) '$views views',
        ].join(' • '),
      );
    }
    return found.values.toList(growable: false);
  }

  List<MangaCatalogItem> _catalogItemsFromHtml(Element root) {
    final found = <String, MangaCatalogItem>{};
    for (final anchor in root.querySelectorAll('a[href^="/a/"]')) {
      final href = anchor.attributes['href'] ?? '';
      final id = _albumId(href);
      final title = anchor.attributes['aria-label']?.trim().isNotEmpty == true
          ? anchor.attributes['aria-label']!.trim()
          : anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (id.isEmpty || title.isEmpty) continue;
      final image = anchor.querySelector('img[src]');
      found[id] = MangaCatalogItem(
        id: id,
        title: title,
        coverUri: _imageUri(image?.attributes['src']),
      );
    }
    return found.values.toList(growable: false);
  }

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('EAHentai returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Future<Object?> _json(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('EAHentai returned HTTP ${response.statusCode}.');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Uri? _imageUri(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty || raw.startsWith('data:')) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed?.hasScheme == true) return parsed;
    if (raw.startsWith('galleries/')) {
      return Uri.parse('$_imageOrigin$raw');
    }
    return _baseUri.resolve(raw);
  }

  String _albumId(String value) =>
      RegExp(r'(?:^|/)a/(\d+)').firstMatch(value)?.group(1) ??
      (RegExp(r'^\d+$').hasMatch(value) ? value : '');

  String _indexLetter(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.isEmpty) return 'A';
    final letter = normalized[0];
    return RegExp(r'[A-Z]').hasMatch(letter) ? letter : 'A';
  }

  String _pluralPath(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tags',
        MangaTaxonomyKind.artist => 'artists',
        MangaTaxonomyKind.character => 'characters',
        MangaTaxonomyKind.parody => 'parodies',
        _ => '',
      };

  String _singularPath(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tag',
        MangaTaxonomyKind.artist => 'artist',
        MangaTaxonomyKind.character => 'character',
        MangaTaxonomyKind.parody => 'parody',
        _ => '',
      };

  int? _asInt(Object? value) => value is int
      ? value
      : value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
}
