import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

enum _GallerySiteKind { vox, envy, era, threeHentai }

/// Shared implementation for the HentaiVox/HentaiEnvy/HentaiEra gallery
/// family. The sites share the same gallery model, while each skin gets its
/// own selectors and reader URL convention.
abstract class AdultGallerySource
    implements
        MangaSource,
        TaxonomyBrowsableMangaSource,
        SortableTaxonomyMangaSource,
        PaginatedTaxonomyMangaSource,
        VariantCatalogMangaSource,
        VariantTaxonomyMangaSource {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final _GallerySiteKind _kind;
  final Map<String, Future<MangaDetails>> _detailsCache = {};

  // The site flavor is intentionally internal; concrete public sources select
  // it so callers never need to construct this shared base directly.
  AdultGallerySource({
    required Uri baseUri,
    // ignore: library_private_types_in_public_api
    required _GallerySiteKind kind,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri,
        _kind = kind;

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
  List<MangaCatalogFilter> get catalogFilters => _kind == _GallerySiteKind.era
      ? const [
          MangaCatalogFilter.recent,
          MangaCatalogFilter.popular,
          MangaCatalogFilter.trending,
          MangaCatalogFilter.updated,
        ]
      : _kind == _GallerySiteKind.threeHentai
          ? const [MangaCatalogFilter.recent, MangaCatalogFilter.popular]
          : const [MangaCatalogFilter.recent];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) {
    if (_kind != _GallerySiteKind.era) return const [];
    if (filter == MangaCatalogFilter.recent) {
      return const [
        MangaCatalogVariant(id: 'all', label: 'All'),
        MangaCatalogVariant(id: 'mg', label: 'Manga'),
        MangaCatalogVariant(id: 'dj', label: 'Doujinshi'),
        MangaCatalogVariant(id: 'ws', label: 'Western'),
        MangaCatalogVariant(id: 'is', label: 'Image set'),
        MangaCatalogVariant(id: 'ac', label: 'Artist CG'),
        MangaCatalogVariant(id: 'gc', label: 'Game CG'),
      ];
    }
    return const [];
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) async {
    if (_kind == _GallerySiteKind.era) {
      final sort = switch (filter) {
        MangaCatalogFilter.popular => 'pp',
        MangaCatalogFilter.trending => 'tr',
        MangaCatalogFilter.updated => 'dl',
        _ => 'lt',
      };
      return _catalogAt(
        _pagedQueryUri('/search/', cursor, _eraQuery(sort: sort)),
        cursor,
      );
    }
    final page = _page(cursor);
    final path = _kind == _GallerySiteKind.threeHentai
        ? '/kai'
        : page > 1
            ? '/page/$page/'
            : '/';
    final document = await _document(
      _baseUri.resolve(path).replace(
            queryParameters: _kind == _GallerySiteKind.threeHentai && page > 1
                ? {'page': '$page'}
                : null,
          ),
    );
    if (_kind == _GallerySiteKind.threeHentai &&
        filter == MangaCatalogFilter.popular) {
      return MangaCatalogPage(
        items: _parseThreeHentaiCards(document, section: 'popular'),
      );
    }
    return _catalogPage(document, page);
  }

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    if (_kind != _GallerySiteKind.era || variantId == 'all') {
      return browse(filter: filter, cursor: cursor);
    }
    final sort = switch (filter) {
      MangaCatalogFilter.popular => 'pp',
      MangaCatalogFilter.trending => 'tr',
      MangaCatalogFilter.updated => 'dl',
      _ => 'lt',
    };
    return _catalogAt(
      _pagedQueryUri(
        '/search/',
        cursor,
        _eraQuery(sort: sort, onlyType: variantId),
      ),
      cursor,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    final key = _kind == _GallerySiteKind.vox
        ? 'q'
        : _kind == _GallerySiteKind.threeHentai
            ? 'q'
            : 'key';
    return _catalogAt(
      _pagedQueryUri(
        '/search/',
        cursor,
        _kind == _GallerySiteKind.era
            ? _eraQuery(sort: 'lt', key: value)
            : {key: value},
      ),
      cursor,
    );
  }

  Future<MangaSearchOptions> getSearchOptions() async {
    if (_kind != _GallerySiteKind.era) return MangaSearchOptions();
    return MangaSearchOptions(
      types: const [
        MangaFilterOption(value: 'mg', label: 'Manga'),
        MangaFilterOption(value: 'dj', label: 'Doujinshi'),
        MangaFilterOption(value: 'ws', label: 'Western'),
        MangaFilterOption(value: 'is', label: 'Image set'),
        MangaFilterOption(value: 'ac', label: 'Artist CG'),
        MangaFilterOption(value: 'gc', label: 'Game CG'),
      ],
      translatedLanguages: const [
        MangaFilterOption(value: 'en', label: 'English'),
        MangaFilterOption(value: 'jp', label: 'Japanese'),
        MangaFilterOption(value: 'es', label: 'Spanish'),
        MangaFilterOption(value: 'fr', label: 'French'),
        MangaFilterOption(value: 'kr', label: 'Korean'),
        MangaFilterOption(value: 'de', label: 'German'),
        MangaFilterOption(value: 'ru', label: 'Russian'),
      ],
      sorts: const [
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.popular,
        MangaSearchSort.rating,
        MangaSearchSort.mostViewed,
      ],
    );
  }

  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    final sort = switch (request.sort) {
      MangaSearchSort.popular => 'pp',
      MangaSearchSort.rating => 'tr',
      MangaSearchSort.mostViewed => 'dl',
      _ => 'lt',
    };
    final parameters = _eraQuery(
      sort: sort,
      selectedTypes: request.types,
      selectedLanguages: request.translatedLanguages,
    );
    return _catalogAt(_pagedQueryUri('/search/', cursor, parameters), cursor);
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.parody,
        MangaTaxonomyKind.character,
        MangaTaxonomyKind.artist,
        if (_kind != _GallerySiteKind.vox) MangaTaxonomyKind.group,
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
      taxonomyKinds.contains(kind);

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
    final page = await getTaxonomyPage(kind, sort: sort);
    final normalized = query.trim().toLowerCase();
    return page.options
        .where((option) =>
            normalized.isEmpty ||
            option.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  @override
  Future<MangaTaxonomyPage> getTaxonomyPage(
    MangaTaxonomyKind kind, {
    MangaTaxonomySort sort = MangaTaxonomySort.alphabetical,
    String? cursor,
  }) async {
    final route = _plural(kind);
    if (route.isEmpty) return MangaTaxonomyPage(options: const []);
    final page = _page(cursor);
    final suffix = sort == MangaTaxonomySort.popular ? '/popular/' : '/';
    final basePath = '/$route$suffix';
    final uri = _baseUri.resolve(
      page > 1 ? '${basePath}page/$page/' : basePath,
    );
    final document = await _document(uri);
    return MangaTaxonomyPage(
      options: _taxonomyOptions(document, kind),
      nextCursor: _hasNext(document, page) ? '${page + 1}' : null,
    );
  }

  List<MangaTaxonomyOption> _taxonomyOptions(
    Document document,
    MangaTaxonomyKind kind,
  ) {
    final singular = _singular(kind);
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = _relative(anchor.attributes['href'] ?? '');
      if (!href.startsWith('/$singular/')) continue;
      if (href.endsWith('/popular/')) continue;
      final nameNode = anchor.querySelector(
        '.hnv-legacy-taxonomy-item__name, .tag_name, .gallery_title, h2, h3',
      );
      var name = _text(nameNode ?? anchor);
      if (name.isEmpty || name.toLowerCase() == 'latest') continue;
      name = name.replaceFirst(RegExp(r'\s+\d[\d,]*$'), '');
      Element? root = anchor;
      while (root != null && !root.classes.contains('thumbnail')) {
        root = root.parent;
      }
      root ??= anchor.parent;
      final countText = '${_text(root?.querySelector(
        '.hnv-legacy-taxonomy-item__badge, .tag_count, .count, .inside_p',
      ))} ${root?.text ?? ''}';
      final count = int.tryParse(
        (RegExp(r'\b([\d,]+)\b').firstMatch(countText)?.group(1) ?? '')
            .replaceAll(',', ''),
      );
      final image = _imageUri(
        root?.querySelector('.inner_thumb img, img') ??
            anchor.querySelector('img'),
      );
      found[href] = MangaTaxonomyOption(
        id: href,
        name: name,
        titleCount: count,
        imageUri: image,
        popularId: '${href.endsWith('/') ? href : '$href/'}popular/',
      );
    }
    return found.values.toList(growable: false);
  }

  @override
  List<MangaCatalogVariant> taxonomyCatalogVariants(
    MangaTaxonomyKind kind,
  ) =>
      const [
        MangaCatalogVariant(id: 'latest', label: 'Latest'),
        MangaCatalogVariant(id: 'popular', label: 'Popular'),
      ];

  @override
  String taxonomyVariantId(
    MangaTaxonomyKind kind,
    String taxonomyId,
    String variantId,
  ) {
    final base = taxonomyId.replaceFirst(RegExp(r'/popular/?$'), '/');
    return variantId == 'popular'
        ? '${base.endsWith('/') ? base : '$base/'}popular/'
        : base;
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) =>
      _catalogAt(_pagedRouteUri(taxonomyId, cursor), cursor);

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final id = _workId(mangaId);
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
    final uri = _detailUri(id);
    final document = await _document(uri);
    final title = _text(document.querySelector(
      '#gallery-title, h1.text-left, .gallery_left h1, h1',
    ));
    if (title.isEmpty) throw StateError('$name did not return gallery $id.');
    final cover = _detailCover(document, id);
    final links = _detailTaxonomy(document);
    final pages = _pageCount(document, id);
    final language = _detailLanguage(document);
    final category = _detailCategory(document);
    final description = _text(document.querySelector(
      '.hnv-gallery-description, .gallery_description, .description',
    ));
    final artists = links
        .where((link) => link.kind == MangaTaxonomyKind.artist)
        .map((link) => link.name)
        .toList(growable: false);
    return MangaDetails(
      item: MangaCatalogItem(
        id: id,
        title: title,
        coverUri: cover,
        subtitle: [
          if (category.isNotEmpty) category,
          if (pages > 0) '$pages pages',
        ].join(' • '),
      ),
      description: description,
      genres: links
          .where((link) => link.kind == MangaTaxonomyKind.tag)
          .map((link) => link.name)
          .toList(growable: false),
      taxonomyLinks: links,
      author: artists.isEmpty ? null : artists.join(', '),
      artist: artists.isEmpty ? null : artists.join(', '),
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: id,
          title: 'Complete gallery',
          number: '1',
          language: language.isEmpty ? 'all' : language,
          pages: pages > 0 ? '$pages' : null,
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
    final detailCount = int.tryParse(details.chapters.first.pages ?? '') ?? 0;
    if (_kind == _GallerySiteKind.vox) {
      for (var page = 1; page <= detailCount; page++) {
        final readerUri = _baseUri.resolve('/view/$mangaId/$page');
        final document = await _document(readerUri);
        final pageUri = _imageUri(document.querySelector('.js-main-img'));
        if (pageUri != null) {
          yield MangaReaderPage.network(pageUri, headers: {
            ...coverImageHeaders,
            'Referer': readerUri.toString(),
          });
        }
      }
      return;
    }
    if (_kind == _GallerySiteKind.envy) {
      final firstReaderUri = _baseUri.resolve('/g/$mangaId/1/');
      final document = await _document(firstReaderUri);
      final reader = document.querySelector('#readerApp');
      final imageBase = reader?.attributes['data-reader-image-base']?.trim();
      final firstImage = _imageUri(document.querySelector('#readerImg'));
      final readerCount = int.tryParse(
        reader?.attributes['data-reader-total']?.trim() ?? '',
      );
      final count = readerCount ?? detailCount;
      for (var page = 1; page <= count; page++) {
        final pageUri = imageBase != null && imageBase.isNotEmpty
            ? Uri.parse('$imageBase/$page.webp')
            : page == 1
                ? firstImage
                : null;
        if (pageUri != null) {
          yield MangaReaderPage.network(pageUri, headers: {
            ...coverImageHeaders,
            'Referer': firstReaderUri.toString(),
          });
        }
      }
      return;
    }
    final count = detailCount;
    if (count <= 0) return;
    if (_kind == _GallerySiteKind.era && _baseUri.host.endsWith('.to')) {
      for (var page = 1; page <= count; page++) {
        final readerUri = _baseUri.resolve('/gallery/$mangaId/$page/');
        final document = await _document(readerUri);
        final pageUri = _imageUri(document.querySelector('#reader_img'));
        if (pageUri != null) {
          yield MangaReaderPage.network(pageUri, headers: {
            ...coverImageHeaders,
            'Referer': readerUri.toString(),
          });
        }
      }
      return;
    }
    final cover = details.item.coverUri;
    if (cover == null) return;
    final directory =
        cover.pathSegments.sublist(0, cover.pathSegments.length - 1);
    final extension = _kind == _GallerySiteKind.threeHentai
        ? (cover.pathSegments.last.endsWith('.webp') ? '.webp' : '.jpg')
        : '.jpg';
    for (var page = 1; page <= count; page++) {
      yield MangaReaderPage.network(
        cover.replace(pathSegments: [...directory, '$page$extension']),
        headers: {
          ...coverImageHeaders,
          'Referer': details.externalUri.toString()
        },
      );
    }
  }

  Future<MangaCatalogPage> _catalogAt(Uri uri, String? cursor) async {
    return _catalogPage(await _document(uri), _page(cursor));
  }

  MangaCatalogPage _catalogPage(Document document, int page) {
    final items = switch (_kind) {
      _GallerySiteKind.vox => _parseVoxCards(document),
      _GallerySiteKind.envy => _parseEnvyCards(document),
      _GallerySiteKind.era => _parseEraCards(document),
      _GallerySiteKind.threeHentai =>
        _parseThreeHentaiCards(document, section: 'newest'),
    };
    return MangaCatalogPage(
      items: items,
      nextCursor: _hasNext(document, page) ? '${page + 1}' : null,
    );
  }

  List<MangaCatalogItem> _parseVoxCards(Document document) {
    return _cards(document.querySelectorAll('.gallery'),
        link: '.gallery-name a[href*="/view/"]',
        image: '.gallery-thumb img',
        subtitle: '.gallery-type');
  }

  List<MangaCatalogItem> _parseEnvyCards(Document document) {
    return _cards(document.querySelectorAll('.hnv-gallery-card'),
        link: '.hnv-gallery-card__title a[href^="/gallery/"]',
        image: '.hnv-gallery-card__cover img',
        subtitle: '.hnv-gallery-card__category');
  }

  List<MangaCatalogItem> _parseEraCards(Document document) {
    return _cards(document.querySelectorAll('.thumb'),
        link: '.gallery_title a[href^="/gallery/"]',
        image: '.inner_thumb img',
        subtitle: '.gallery_cat',
        pages: '.inside_p');
  }

  List<MangaCatalogItem> _parseThreeHentaiCards(
    Document document, {
    required String section,
  }) {
    Element root = document.body ?? document.documentElement!;
    for (final heading in document.querySelectorAll('h1, h2, h3')) {
      final label = _text(heading).toLowerCase();
      if (!label.contains(section)) continue;
      final candidate = heading.nextElementSibling;
      if (candidate != null) {
        root = candidate;
        break;
      }
    }
    final found = <String, MangaCatalogItem>{};
    for (final anchor in root.querySelectorAll('a.cover[href^="/d/"]')) {
      final href = _relative(anchor.attributes['href'] ?? '');
      final title = _text(anchor.querySelector('.title')).isNotEmpty
          ? _text(anchor.querySelector('.title'))
          : anchor.querySelector('img')?.attributes['alt']?.trim() ?? '';
      if (href.isEmpty || title.isEmpty) continue;
      found[_workId(href)] = MangaCatalogItem(
        id: _workId(href),
        title: title,
        coverUri: _imageUri(anchor.querySelector('img')),
      );
    }
    return found.values.toList(growable: false);
  }

  List<MangaCatalogItem> _cards(
    List<Element> roots, {
    required String link,
    required String image,
    required String subtitle,
    String? pages,
  }) {
    final found = <String, MangaCatalogItem>{};
    for (final root in roots) {
      final anchor = root.querySelector(link);
      final href = _relative(anchor?.attributes['href'] ?? '');
      final title = _text(anchor);
      if (href.isEmpty || title.isEmpty) continue;
      final parts = <String>[
        if (_text(root.querySelector(subtitle)).isNotEmpty)
          _text(root.querySelector(subtitle)),
        if (pages != null && _text(root.querySelector(pages)).isNotEmpty)
          '${_text(root.querySelector(pages))} pages',
      ];
      found[_workId(href)] = MangaCatalogItem(
        id: _workId(href),
        title: title,
        coverUri: _imageUri(root.querySelector(image)),
        subtitle: parts.isEmpty ? null : parts.join(' • '),
      );
    }
    return found.values.toList(growable: false);
  }

  List<MangaTaxonomyLink> _detailTaxonomy(Document document) {
    final found = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = _relative(anchor.attributes['href'] ?? '');
      final name = _text(anchor.querySelector(
            '.hnv-gallery-tag__name, .tag_name',
          ) ??
          anchor);
      if (href.isEmpty || name.isEmpty) continue;
      final kind = href.startsWith('/tag/')
          ? MangaTaxonomyKind.tag
          : href.startsWith('/artist/')
              ? MangaTaxonomyKind.artist
              : href.startsWith('/character/')
                  ? MangaTaxonomyKind.character
                  : href.startsWith('/parody/')
                      ? MangaTaxonomyKind.parody
                      : href.startsWith('/group/')
                          ? MangaTaxonomyKind.group
                          : href.startsWith('/language/') ||
                                  href.startsWith('/category/')
                              ? MangaTaxonomyKind.tag
                              : null;
      if (kind == null) continue;
      found['${kind.name}:$href'] =
          MangaTaxonomyLink(kind: kind, id: href, name: name);
    }
    return found.values.toList(growable: false);
  }

  Uri? _detailCover(Document document, String id) {
    final selectors = switch (_kind) {
      _GallerySiteKind.vox => 'a[href*="/view/$id/"] img, img[src*="-cover."]',
      _GallerySiteKind.envy =>
        '.hnv-gallery-cover img, img[src\$="/cover.jpg"]',
      _GallerySiteKind.era =>
        'a[href*="/gallery/$id/1/"] img, a[href*="/view/$id/"] img, img[src\$="/cover.jpg"]',
      _GallerySiteKind.threeHentai =>
        'a[href^="/read/$id/"] img, img[src*="/cover."]',
    };
    return _imageUri(document.querySelector(selectors));
  }

  int _pageCount(Document document, String id) {
    final links = switch (_kind) {
      _GallerySiteKind.vox =>
        document.querySelectorAll('a[href*="/view/$id/"]'),
      _GallerySiteKind.envy => document.querySelectorAll('a[href^="/g/$id/"]'),
      _GallerySiteKind.era => document.querySelectorAll(
          'a[href*="/view/$id/"], a[href*="/gallery/$id/"]',
        ),
      _GallerySiteKind.threeHentai =>
        document.querySelectorAll('a[href*="/$id/"]'),
    };
    var max = 0;
    for (final link in links) {
      final value = int.tryParse(
        Uri.tryParse(link.attributes['href'] ?? '')
                ?.pathSegments
                .where((part) => RegExp(r'^\d+$').hasMatch(part))
                .lastOrNull ??
            '',
      );
      if (value != null && value > max && value != int.tryParse(id)) {
        max = value;
      }
    }
    final text = document.body?.text ?? '';
    // HentaiEnvy exposes the authoritative total on #readerApp. Its detail
    // page also contains category counters followed by the word "Pages", so a
    // broad text regex can mistake the category count for the gallery length.
    if (_kind == _GallerySiteKind.envy) return max;
    final labeled = int.tryParse(
      (RegExp(r'([\d,]+)\s+Pages?', caseSensitive: false)
                  .firstMatch(text)
                  ?.group(1) ??
              '')
          .replaceAll(',', ''),
    );
    return labeled != null && labeled > max ? labeled : max;
  }

  String _detailLanguage(Document document) {
    final href =
        document.querySelector('a[href^="/language/"]')?.attributes['href'] ??
            '';
    return Uri.tryParse(href)?.pathSegments.skip(1).firstOrNull ?? '';
  }

  String _detailCategory(Document document) =>
      _text(document.querySelector('a[href^="/category/"]'));

  Uri _detailUri(String id) => _baseUri.resolve(switch (_kind) {
        _GallerySiteKind.vox => '/view/$id',
        _GallerySiteKind.threeHentai => '/d/$id/',
        _ => '/gallery/$id/',
      });

  String _workId(String value) =>
      RegExp(r'/(?:view|gallery|d)/(\d+)').firstMatch(value)?.group(1) ??
      (RegExp(r'^\d+$').hasMatch(value) ? value : '');

  Uri _pagedQueryUri(
    String path,
    String? cursor,
    Map<String, String> parameters,
  ) {
    final page = _page(cursor);
    return _baseUri.resolve(path).replace(queryParameters: {
      ...parameters,
      if (page > 1) 'page': '$page',
    });
  }

  Uri _pagedRouteUri(String route, String? cursor) {
    final page = _page(cursor);
    final resolved = _baseUri.resolve(route);
    if (page == 1) return resolved;
    final path =
        resolved.path.endsWith('/') ? resolved.path : '${resolved.path}/';
    return resolved.replace(path: '${path}page/$page/');
  }

  Map<String, String> _eraQuery({
    required String sort,
    String? onlyType,
    String? key,
    Iterable<String> selectedTypes = const [],
    Iterable<String> selectedLanguages = const [],
  }) {
    const types = ['mg', 'dj', 'ws', 'is', 'ac', 'gc'];
    const languages = ['en', 'jp', 'es', 'fr', 'kr', 'de', 'ru'];
    final requestedTypes = selectedTypes.toSet();
    final requestedLanguages = selectedLanguages.toSet();
    final restrictTypes = onlyType != null || requestedTypes.isNotEmpty;
    final restrictLanguages = requestedLanguages.isNotEmpty;
    return {
      'key': key ?? '',
      'search': '',
      for (final type in types)
        type: (onlyType == type ||
                (!restrictTypes || requestedTypes.contains(type)))
            ? '1'
            : '0',
      for (final language in languages)
        language: (!restrictLanguages || requestedLanguages.contains(language))
            ? '1'
            : '0',
      for (final key in const ['lt', 'dl', 'pp', 'tr'])
        key: key == sort ? '1' : '0',
    };
  }

  bool _hasNext(Document document, int page) =>
      document.querySelector('a[rel="next"]') != null ||
      document.querySelector('a[href*="page=${page + 1}"]') != null ||
      document.querySelector('a[href*="/page/${page + 1}"]') != null;

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$name returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri? _imageUri(Element? image) {
    for (final key in const ['data-src', 'data-lazy-src', 'src']) {
      final raw = image?.attributes[key]?.trim() ?? '';
      if (raw.isEmpty || raw.startsWith('data:')) continue;
      return _baseUri.resolve(raw);
    }
    return null;
  }

  String _relative(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final uri = _baseUri.resolve(raw);
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  int _page(String? cursor) {
    final value = int.tryParse(cursor ?? '') ?? 1;
    return value < 1 ? 1 : value;
  }

  String _plural(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tags',
        MangaTaxonomyKind.artist => 'artists',
        MangaTaxonomyKind.character => 'characters',
        MangaTaxonomyKind.parody => 'parodies',
        MangaTaxonomyKind.group => 'groups',
        _ => '',
      };

  String _singular(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tag',
        MangaTaxonomyKind.artist => 'artist',
        MangaTaxonomyKind.character => 'character',
        MangaTaxonomyKind.parody => 'parody',
        MangaTaxonomyKind.group => 'group',
        _ => '',
      };

  String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
}

class HentaiVoxSource extends AdultGallerySource {
  HentaiVoxSource({super.client, Uri? baseUri})
      : super(
          baseUri: baseUri ?? Uri.parse('https://hentaivox.com/'),
          kind: _GallerySiteKind.vox,
        );
  @override
  String get id => 'hentaivox';
  @override
  String get name => 'HentaiVox';
}

class HentaiEnvySource extends AdultGallerySource {
  HentaiEnvySource({super.client, Uri? baseUri})
      : super(
          baseUri: baseUri ?? Uri.parse('https://hentaienvy.com/'),
          kind: _GallerySiteKind.envy,
        );
  @override
  String get id => 'hentaienvy';
  @override
  String get name => 'HentaiEnvy';
}

class HentaiEraSource extends AdultGallerySource
    implements FilterableMangaSource {
  final String sourceId;
  final String sourceName;

  HentaiEraSource({
    this.sourceId = 'hentaiera_com',
    this.sourceName = 'HentaiEra.com',
    super.client,
    Uri? baseUri,
  }) : super(
          baseUri: baseUri ?? Uri.parse('https://hentaiera.com/'),
          kind: _GallerySiteKind.era,
        );
  @override
  String get id => sourceId;
  @override
  String get name => sourceName;
}

class ThreeHentaiSource extends AdultGallerySource {
  ThreeHentaiSource({super.client, Uri? baseUri})
      : super(
          baseUri: baseUri ?? Uri.parse('https://3hentai.to/'),
          kind: _GallerySiteKind.threeHentai,
        );
  @override
  String get id => 'three_hentai';
  @override
  String get name => '3Hentai';
}
