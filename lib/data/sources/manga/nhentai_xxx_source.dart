import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

class NHentaiXxxSource
    implements
        MangaSource,
        TaxonomyBrowsableMangaSource,
        SortableTaxonomyMangaSource,
        PaginatedTaxonomyMangaSource {
  static final Uri _defaultBaseUri = Uri.parse('https://nhentai.xxx');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, Future<MangaDetails>> _detailsCache = {};

  NHentaiXxxSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'nhentai_xxx';

  @override
  String get name => 'nHentai.xxx';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,*;q=0.5',
        'Referer': '${_baseUri.origin}/',
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Referer': '${_baseUri.origin}/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.popular,
      ];

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.artist,
        MangaTaxonomyKind.character,
        MangaTaxonomyKind.parody,
        MangaTaxonomyKind.group,
      ];

  @override
  List<MangaTaxonomySort> taxonomySorts(MangaTaxonomyKind kind) => const [
        MangaTaxonomySort.alphabetical,
        MangaTaxonomySort.popular,
      ];

  @override
  bool taxonomyRequiresQuery(MangaTaxonomyKind kind) => false;

  @override
  bool supportsTaxonomyPagination(MangaTaxonomyKind kind) =>
      kind == MangaTaxonomyKind.character || kind == MangaTaxonomyKind.parody;

  @override
  Future<MangaTaxonomyPage> getTaxonomyPage(
    MangaTaxonomyKind kind, {
    MangaTaxonomySort sort = MangaTaxonomySort.alphabetical,
    String? cursor,
  }) async {
    final plural = _pluralPath(kind);
    final path =
        sort == MangaTaxonomySort.popular ? '/$plural/popular/' : '/$plural/';
    final page = int.tryParse(cursor ?? '') ?? 1;
    final document = await _document(_pageUri(path, '$page'));
    return MangaTaxonomyPage(
      options: _parseTaxonomyOptions(document, kind),
      nextCursor: _hasNextPage(document, page) ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) async {
    final uri = _pageUri('/', cursor);
    final document = await _document(uri);
    final heading =
        filter == MangaCatalogFilter.popular ? 'popular now' : 'new uploads';
    final section = document.querySelectorAll('.content_box').firstWhere(
          (element) =>
              (element.querySelector('h2')?.text ?? '').trim().toLowerCase() ==
              heading,
          orElse: () => document.body ?? Element.tag('body'),
        );
    return _catalogFromDocument(
      document,
      uri,
      root: section,
      paginate: filter != MangaCatalogFilter.popular,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return Future.value(MangaCatalogPage(items: const []));
    return _catalog(_pageUri('/search/', cursor, {'key': value}));
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
    final plural = _pluralPath(kind);
    final normalized = query.trim().toLowerCase();
    final path = normalized.isNotEmpty
        ? '/$plural/${_indexLetter(normalized)}/'
        : sort == MangaTaxonomySort.popular
            ? '/$plural/popular/'
            : '/$plural/';
    final found = <String, MangaTaxonomyOption>{};
    final maxPages = normalized.isEmpty ? 1 : 8;

    for (var page = 1; page <= maxPages; page++) {
      final document = await _document(_pageUri(path, '$page'));
      for (final option in _parseTaxonomyOptions(document, kind)) {
        if (normalized.isNotEmpty &&
            !option.name.toLowerCase().contains(normalized)) {
          continue;
        }
        found[option.id] = option;
      }
      if (normalized.isEmpty ||
          found.isNotEmpty ||
          !_hasNextPage(document, page)) {
        break;
      }
    }

    final values = found.values.toList();
    if (sort == MangaTaxonomySort.alphabetical || normalized.isNotEmpty) {
      values.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return values.take(120).toList(growable: false);
  }

  List<MangaTaxonomyOption> _parseTaxonomyOptions(
    Document document,
    MangaTaxonomyKind kind,
  ) {
    final options = <MangaTaxonomyOption>[];
    final visual =
        kind == MangaTaxonomyKind.character || kind == MangaTaxonomyKind.parody;
    if (visual) {
      for (final card in document.querySelectorAll('.tags_thumbs .thumb')) {
        final recentAnchor = card.querySelector('.ts_lat a[href]') ??
            card.querySelector('a[href*="/${_singularPath(kind)}/"]');
        final href = recentAnchor?.attributes['href'] ?? '';
        final name = (card.querySelector('.caption')?.text ?? '').trim();
        if (href.isEmpty || name.isEmpty) continue;
        final image = card.querySelector('img');
        options.add(MangaTaxonomyOption(
          id: href,
          popularId: card.querySelector('.ts_pop a[href]')?.attributes['href'],
          name: name,
          titleCount: _compactCount(card.querySelector('.c_num')?.text ?? ''),
          imageUri: _uri(
            image?.attributes['data-src'] ?? image?.attributes['src'],
          ),
        ));
      }
      return options;
    }
    for (final anchor in document.querySelectorAll('.tags_items a.tag_btn')) {
      final href = anchor.attributes['href'] ?? '';
      final name =
          (anchor.querySelector('.tag_name')?.text ?? anchor.text).trim();
      if (href.isEmpty || name.isEmpty) continue;
      options.add(MangaTaxonomyOption(
        id: href,
        popularId: _popularTaxonomyPath(href),
        name: name,
        titleCount: _compactCount(
          anchor.querySelector('.tag_count')?.text ?? '',
        ),
      ));
    }
    return options;
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) {
    if (taxonomyId.contains('|')) {
      final terms = taxonomyId
          .split('|')
          .map(_taxonomySlug)
          .where((value) => value.isNotEmpty)
          .map((value) => value.replaceAll('-', ' '))
          .join(', ');
      return search(terms, cursor: cursor);
    }
    final uri = _baseUri.resolve(taxonomyId);
    return _catalog(_pageUri(uri.path, cursor));
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final id = _galleryId(mangaId);
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
    final uri = _baseUri.resolve('/g/$id/');
    final document = await _document(uri);
    final top = document.querySelector('.gallery_top');
    final info = top?.querySelector('.info') ?? document.querySelector('.info');
    final title = info?.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) {
      throw StateError('nHentai.xxx did not return gallery $id.');
    }
    final alternate = info?.querySelector('h2')?.text.trim() ?? '';
    final cover = _uri(
      (top ?? document).querySelector('.cover img')?.attributes['data-src'] ??
          (top ?? document).querySelector('.cover img')?.attributes['src'],
    );
    final taxonomies = _detailTaxonomies(info);
    final tags = taxonomies[MangaTaxonomyKind.tag] ?? const [];
    final artists = taxonomies[MangaTaxonomyKind.artist] ?? const [];
    final groups = taxonomies[MangaTaxonomyKind.group] ?? const [];
    final pageCount = _detailPageCount(info, document);
    final language = _detailLanguage(info);
    final uploadedNode = info?.querySelector('.uploaded');
    final uploaded = uploadedNode?.attributes['data-uploaded-utc'] ??
        uploadedNode?.attributes['data-updated-utc'];

    return MangaDetails(
      item: MangaCatalogItem(
        id: id,
        title: title,
        coverUri: cover,
        subtitle: [
          if (pageCount > 0) '$pageCount pages',
          if (language != 'all') _capitalize(language),
        ].join(' • '),
      ),
      alternativeTitles: [
        if (alternate.isNotEmpty) {'': alternate},
      ],
      genres: tags.map((tag) => tag.name),
      author:
          groups.isEmpty ? null : groups.map((item) => item.name).join(', '),
      artist:
          artists.isEmpty ? null : artists.map((item) => item.name).join(', '),
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: '/g/$id/',
          title: 'Complete gallery',
          number: '1',
          language: language,
          pages: pageCount > 0 ? '$pageCount' : null,
          publishedAt: uploaded,
        ),
      ],
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final details = await getDetails(mangaId);
    final pageCount =
        int.tryParse(details.chapters.firstOrNull?.pages ?? '') ?? 0;
    final cover = details.item.coverUri;
    if (pageCount <= 0 || cover == null) return;
    final basePath = cover.path.replaceFirst(RegExp(r'/cover\.[^.]+$'), '');
    for (var page = 1; page <= pageCount; page++) {
      yield MangaReaderPage.network(
        cover.replace(path: '$basePath/$page.webp'),
        headers: coverImageHeaders,
      );
    }
  }

  Future<MangaCatalogPage> _catalog(Uri uri) async {
    final document = await _document(uri);
    return _catalogFromDocument(document, uri);
  }

  Future<MangaCatalogPage> _catalogFromDocument(
    Document document,
    Uri uri, {
    Element? root,
    bool paginate = true,
  }) async {
    final items = <MangaCatalogItem>[];
    final seen = <String>{};
    for (final card in (root ?? document).querySelectorAll('.gallery_item')) {
      final anchor = card.querySelector('a[href*="/g/"]');
      final href = anchor?.attributes['href'] ?? '';
      final id = _galleryId(href);
      if (id.isEmpty || !seen.add(id)) continue;
      final image =
          card.querySelector('picture img') ?? card.querySelector('img');
      final title = (card.querySelector('.caption')?.text ??
              anchor?.attributes['title'] ??
              image?.attributes['alt'] ??
              '')
          .trim();
      if (title.isEmpty) continue;
      items.add(MangaCatalogItem(
        id: id,
        title: title,
        coverUri: _uri(
          image?.attributes['data-src'] ?? image?.attributes['src'],
        ),
      ));
    }
    final enriched = await _enrichCatalogItems(items);
    final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
    return MangaCatalogPage(
      items: enriched,
      nextCursor: paginate && items.isNotEmpty ? '${page + 1}' : null,
    );
  }

  Future<List<MangaCatalogItem>> _enrichCatalogItems(
    List<MangaCatalogItem> items,
  ) async {
    final enriched = <MangaCatalogItem>[];
    const batchSize = 5;
    for (var start = 0; start < items.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, items.length);
      final results = await Future.wait(
        items.sublist(start, end).map((item) async {
          try {
            final details = await getDetails(item.id);
            return MangaCatalogItem(
              id: item.id,
              title: item.title,
              coverUri: item.coverUri ?? details.item.coverUri,
              subtitle: details.item.subtitle,
            );
          } catch (_) {
            return item;
          }
        }),
      );
      enriched.addAll(results);
    }
    return enriched;
  }

  Map<MangaTaxonomyKind, List<MangaTaxonomyOption>> _detailTaxonomies(
    Element? info,
  ) {
    final result = <MangaTaxonomyKind, List<MangaTaxonomyOption>>{};
    if (info == null) return result;
    for (final container in info.querySelectorAll('li.tags')) {
      final label =
          container.querySelector('.text')?.text.trim().toLowerCase() ?? '';
      final kind = label.startsWith('tags')
          ? MangaTaxonomyKind.tag
          : label.startsWith('artists')
              ? MangaTaxonomyKind.artist
              : label.startsWith('characters')
                  ? MangaTaxonomyKind.character
                  : label.startsWith('parodies')
                      ? MangaTaxonomyKind.parody
                      : label.startsWith('groups')
                          ? MangaTaxonomyKind.group
                          : null;
      if (kind == null) continue;
      result[kind] = container
          .querySelectorAll('a.tag_btn[href]')
          .map((anchor) => MangaTaxonomyOption(
                id: anchor.attributes['href'] ?? '',
                name: anchor.querySelector('.tag_name')?.text.trim() ?? '',
                titleCount: _compactCount(
                  anchor.querySelector('.tag_count')?.text ?? '',
                ),
              ))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
    }
    return result;
  }

  int _detailPageCount(Element? info, Document document) {
    final explicit = info?.querySelector('.tag_name.pages')?.text ?? '';
    final count = _compactCount(explicit);
    if (count != null && count > 0) return count;
    return document.querySelectorAll('.gallery_thumbs .gt_th').length;
  }

  String _detailLanguage(Element? info) {
    for (final container
        in info?.querySelectorAll('li.tags') ?? const <Element>[]) {
      final label =
          container.querySelector('.text')?.text.trim().toLowerCase() ?? '';
      if (!label.startsWith('languages')) continue;
      final language =
          container.querySelector('.tag_name')?.text.trim().toLowerCase();
      if (language != null && language.isNotEmpty) return language;
    }
    return 'all';
  }

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'nHentai.xxx request failed (${response.statusCode}): $uri',
      );
    }
    return html_parser.parse(response.body);
  }

  Uri _pageUri(
    String path,
    String? cursor, [
    Map<String, String> extra = const {},
  ]) {
    final page = int.tryParse(cursor ?? '') ?? 1;
    return _baseUri.resolve(path).replace(
      queryParameters: {...extra, 'page': '$page'},
    );
  }

  String _pluralPath(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tags',
        MangaTaxonomyKind.artist => 'artists',
        MangaTaxonomyKind.character => 'characters',
        MangaTaxonomyKind.parody => 'parodies',
        MangaTaxonomyKind.group || MangaTaxonomyKind.circle => 'groups',
      };

  String _singularPath(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tag',
        MangaTaxonomyKind.artist => 'artist',
        MangaTaxonomyKind.character => 'character',
        MangaTaxonomyKind.parody => 'parody',
        MangaTaxonomyKind.group || MangaTaxonomyKind.circle => 'group',
      };

  String _indexLetter(String query) =>
      RegExp(r'^[a-z]').hasMatch(query) ? query[0].toUpperCase() : 'NUM';

  String _popularTaxonomyPath(String href) {
    final path = _baseUri.resolve(href).path;
    return '${path.endsWith('/') ? path : '$path/'}popular/';
  }

  String _taxonomySlug(String id) {
    final parts = Uri.parse(id).pathSegments.where((part) => part.isNotEmpty);
    return parts.where((part) => part != 'popular').lastOrNull ?? '';
  }

  bool _hasNextPage(Document document, int currentPage) {
    final next = '${currentPage + 1}';
    return document.querySelector('a[rel="next"]') != null ||
        document.querySelectorAll('a[href]').any((anchor) {
          final href = anchor.attributes['href'];
          if (href == null) return false;
          final uri = Uri.tryParse(href);
          return uri?.queryParameters['page'] == next;
        });
  }

  String _galleryId(String raw) =>
      RegExp(r'/g/(\d+)').firstMatch(raw)?.group(1) ??
      (RegExp(r'^\d+$').hasMatch(raw) ? raw : '');

  Uri? _uri(String? raw) =>
      raw == null || raw.isEmpty || raw.startsWith('data:')
          ? null
          : _baseUri.resolve(raw);

  int? _compactCount(String raw) {
    final match = RegExp(r'([\d,.]+)\s*([km]?)', caseSensitive: false)
        .firstMatch(raw.trim());
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (value == null) return null;
    final multiplier = switch (match.group(2)?.toLowerCase()) {
      'k' => 1000,
      'm' => 1000000,
      _ => 1,
    };
    return (value * multiplier).round();
  }

  String _capitalize(String value) => value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}
