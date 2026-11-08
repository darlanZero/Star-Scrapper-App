import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Image-reader half of hentai-img.com's mixed image and video catalog.
class HentaiImgMangaSource
    implements MangaSource, TaxonomyBrowsableMangaSource {
  static const _site = 'https://hentai-img.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, MangaDetails> _detailsCache = {};
  List<MangaTaxonomyOption>? _tagCache;

  HentaiImgMangaSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'hentai_img_reader';

  @override
  String get name => 'Hentai-Img';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$_site/',
        'User-Agent': _userAgent,
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
        MangaCatalogFilter.popular,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) async {
    final route =
        filter == MangaCatalogFilter.popular ? '/ranking/' : '/search/';
    return _catalogPage(
        cursor == null ? _baseUri.resolve(route) : _resolve(cursor));
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return browse(cursor: cursor);
    final uri = cursor == null ? _keywordUri(normalized) : _resolve(cursor);
    return _catalogPage(uri);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final cached = _detailsCache[mangaId];
    if (cached != null) return cached;

    final uri = _resolve(mangaId);
    final document = await _getDocument(uri);
    final pageUris = _readerUris(document);
    if (pageUris.isEmpty) {
      throw StateError('Hentai-Img did not expose any gallery images.');
    }
    final title = document.querySelector('#title h2')?.text.trim() ??
        document.querySelector('#page #right_sidebar > h3')?.text.trim() ??
        document.querySelector('#page > h2')?.text.trim() ??
        document.querySelector('h1, h2')?.text.trim() ??
        _fallbackTitle(uri);
    final taxonomyLinks = _taxonomyLinks(document);
    final details = MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: pageUris.first,
        subtitle: '${pageUris.length} images',
      ),
      genres: taxonomyLinks.map((link) => link.name),
      taxonomyLinks: taxonomyLinks,
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: uri.path,
          title: 'Gallery',
          number: '1',
          language: 'en',
          pages: '${pageUris.length}',
        ),
      ],
    );
    _detailsCache[mangaId] = details;
    return details;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final document = await _getDocument(_resolve(chapterId));
    for (final uri in _readerUris(document)) {
      yield MangaReaderPage.network(uri, headers: coverImageHeaders);
    }
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [MangaTaxonomyKind.tag];

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    if (kind != MangaTaxonomyKind.tag) return const [];
    final all = _tagCache ??= await _loadAllTags();
    final normalized = query.trim().toLowerCase();
    return all
        .where((option) =>
            normalized.isEmpty ||
            option.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) {
    if (kind != MangaTaxonomyKind.tag) {
      return Future.value(MangaCatalogPage(items: const []));
    }
    final uri = cursor == null ? _tagUri(taxonomyId) : _resolve(cursor);
    return _catalogPage(uri);
  }

  Future<MangaCatalogPage> _catalogPage(Uri uri) async {
    final document = await _getDocument(uri);
    final modernRoot = document.querySelector('#display_area_image');
    final responsiveRoot = document.querySelector(
          '#page #right_sidebar #entry_list',
        ) ??
        document.querySelector('#entry_list');
    final cards = modernRoot != null
        ? modernRoot.querySelectorAll('#image-list .image-list-item')
        : responsiveRoot?.children
                .where((element) => element.localName == 'li')
                .toList(growable: false) ??
            const <Element>[];
    final seen = <String>{};
    final items = cards
        .map((card) {
          final anchor = card.querySelector(
            '.image-list-item-image a[href], .image-list-item-title a[href], '
            'a[href^="/image/"]',
          );
          final href = anchor?.attributes['href']?.trim() ?? '';
          if (!Uri.parse(href.isEmpty ? '/' : href)
                  .path
                  .startsWith('/image/') ||
              !seen.add(href)) {
            return null;
          }
          final image = card.querySelector('img');
          final title =
              card.querySelector('.image-list-item-title a')?.text.trim() ??
                  image?.attributes['alt']?.trim() ??
                  '';
          if (title.isEmpty) return null;
          return MangaCatalogItem(
            id: href,
            title: title,
            coverUri: _imageUri(image),
            subtitle: card
                .querySelector('.image-list-item-regist-date, .posted')
                ?.text
                .trim(),
          );
        })
        .whereType<MangaCatalogItem>()
        .toList(growable: false);
    return MangaCatalogPage(
      items: items,
      nextCursor: _nextCursor(document),
    );
  }

  List<MangaTaxonomyOption> _parseTags(Document document) {
    final seen = <String>{};
    return document
        .querySelectorAll('#tags li a[href*="/search/tag/"]')
        .map((a) {
          final slug = _tagSlug(a.attributes['href'] ?? '');
          if (slug.isEmpty || !seen.add(slug)) return null;
          final raw = a.text.trim();
          final countMatch = RegExp(r'\(([\d,]+)\)\s*$').firstMatch(raw);
          final name =
              raw.replaceFirst(RegExp(r'\s*\([\d,]+\)\s*$'), '').trim();
          if (name.isEmpty) return null;
          return MangaTaxonomyOption(
            id: slug,
            name: name,
            titleCount: int.tryParse(
              (countMatch?.group(1) ?? '').replaceAll(',', ''),
            ),
          );
        })
        .whereType<MangaTaxonomyOption>()
        .toList(growable: false);
  }

  Future<List<MangaTaxonomyOption>> _loadAllTags() async {
    final first = await _getDocument(_baseUri.resolve('/tag/'));
    var lastPage = 1;
    for (final anchor in first.querySelectorAll('a[href*="/tag/page/"]')) {
      final href = anchor.attributes['href'] ?? '';
      final page = int.tryParse(
        RegExp(r'/tag/page/(\d+)/').firstMatch(href)?.group(1) ?? '',
      );
      if (page != null && page > lastPage) lastPage = page;
    }

    final documents = lastPage <= 1
        ? const <Document>[]
        : await Future.wait([
            for (var page = 2; page <= lastPage; page++)
              _getDocument(_baseUri.resolve('/tag/page/$page/')),
          ]);
    final options = <String, MangaTaxonomyOption>{};
    for (final document in [first, ...documents]) {
      for (final option in _parseTags(document)) {
        options[option.id] = option;
      }
    }
    return options.values.toList(growable: false);
  }

  List<MangaTaxonomyLink> _taxonomyLinks(Document document) {
    final links = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '#detail_tag a[href*="/search/tag/"], #the_tags a[href*="/search/tag/"]',
    )) {
      final slug = _tagSlug(anchor.attributes['href'] ?? '');
      final name = anchor.text.trim();
      if (slug.isNotEmpty && name.isNotEmpty) {
        links[slug] = MangaTaxonomyLink(
          kind: MangaTaxonomyKind.tag,
          id: slug,
          name: name,
        );
      }
    }
    return links.values.toList(growable: false);
  }

  List<Uri> _readerUris(Document document) {
    final seen = <String>{};
    return document
        .querySelectorAll(
          '#display_image_detail a[data-modal-gallery-image-item][href], '
          '#detail_list a[data-modal-gallery-image-item][href]',
        )
        .map((anchor) => _uri(anchor.attributes['href']))
        .whereType<Uri>()
        .where((uri) => seen.add(uri.toString()))
        .toList(growable: false);
  }

  String? _nextCursor(Document document) => document
      .querySelector('.wp-pagenavi a.nextpostslink[href], a[rel="next"][href]')
      ?.attributes['href']
      ?.trim();

  Uri _keywordUri(String query) =>
      _baseUri.resolve('/search/keyword/${Uri.encodeComponent(query)}/');

  Uri _tagUri(String value) {
    final slug = _tagSlug(value);
    return _baseUri.resolve('/search/tag/${Uri.encodeComponent(slug)}/');
  }

  String _tagSlug(String value) {
    final path = Uri.tryParse(value)?.path ?? value;
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    final marker = segments.indexOf('tag');
    final slug = marker >= 0 && marker + 1 < segments.length
        ? segments[marker + 1]
        : (segments.isEmpty ? value : segments.last);
    return Uri.decodeComponent(slug).trim();
  }

  Future<Document> _getDocument(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Hentai-Img: HTTP ${response.statusCode}');
    }
    return html_parser.parse(response.body);
  }

  Uri _resolve(String value) => _baseUri.resolve(value);

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['src'] ??
            image?.attributes['data-src'] ??
            image?.attributes['data-original'],
      );

  String _fallbackTitle(Uri uri) =>
      uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull
          ?.replaceAll('-', ' ') ??
      'Gallery';
}
