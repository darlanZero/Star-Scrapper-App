import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

typedef FsiComicsHtmlLoader = Future<String> Function(
  Uri uri,
  String userAgent,
);
typedef FsiComicsImageLoader = Future<Uint8List> Function(
  Uri uri,
  String userAgent,
);
typedef FsiComicsReaderLoader = Stream<String> Function(
  Uri uri,
  String userAgent,
  int pageCount,
);

/// Adult English comics hosted by fsicomics.com.
///
/// Every post is a self-contained comic. The site's grid, list and carousel
/// controls are only alternative presentations of the same protected gallery,
/// so the native reader always exposes the gallery images in document order.
class FsiComicsSource
    implements
        MangaSource,
        VariantCatalogMangaSource,
        TaxonomyBrowsableMangaSource,
        BrowserImageMangaSource,
        WebViewChapterMangaSource {
  static const _site = 'https://fsicomics.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static const _variants = [
    MangaCatalogVariant(id: 'all', label: 'All comics'),
    MangaCatalogVariant(id: '3d', label: '3D comics'),
    MangaCatalogVariant(id: 'western', label: 'Western comics'),
    MangaCatalogVariant(id: 'hentai', label: 'Hentai comics'),
    MangaCatalogVariant(id: 'ai', label: 'AI generated'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final FsiComicsHtmlLoader? _browserHtmlLoader;
  final FsiComicsImageLoader? _browserImageLoader;
  final FsiComicsReaderLoader? _readerPageLoader;
  final Map<String, Future<MangaDetails>> _detailsCache = {};
  final Map<String, MangaTaxonomyOption> _artists = {};

  FsiComicsSource({
    http.Client? client,
    Uri? baseUri,
    FsiComicsHtmlLoader? browserHtmlLoader,
    FsiComicsImageLoader? browserImageLoader,
    FsiComicsReaderLoader? readerPageLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site),
        _browserHtmlLoader = browserHtmlLoader,
        _browserImageLoader = browserImageLoader,
        _readerPageLoader = readerPageLoader;

  @override
  String get id => 'fsi_comics';

  @override
  String get name => 'FSI Comics';

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
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      _variants;

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) =>
      browseVariant(filter, 'all', cursor: cursor);

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) async {
    final page = _page(cursor);
    final basePath = switch (variantId) {
      '3d' => '/all-porn-comics/3d-porn-comics/',
      'western' => '/all-porn-comics/western-porn-comics/',
      'hentai' => '/all-porn-comics/hentai-porn-comics/',
      'ai' => '/ai-generated/',
      _ => '/all-porn-comics/',
    };
    return _catalogPage(
      await _document(_pagedUri(basePath, page)),
      page,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    final page = _page(cursor);
    final uri = _pagedUri('/', page).replace(queryParameters: {'s': value});
    return _catalogPage(await _document(uri), page);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final id = _relativeId(mangaId);
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
    final uri = _resolve(id);
    final document = await _document(uri);
    final title = _text(document.querySelector('h1.s-title'));
    if (title.isEmpty) {
      throw StateError('FSI Comics did not return details for $id.');
    }

    final gallery = document.querySelectorAll(
      '.entry-content .wp-block-gallery img[data-safe-src], '
      '.entry-content img[data-safe-src]',
    );
    final pageCount = gallery.map(_imageUri).whereType<Uri>().toSet().length;
    final cover = gallery.isEmpty ? null : _imageUri(gallery.first);
    final description = document
        .querySelectorAll('.entry-content > p.wp-block-paragraph')
        .take(2)
        .map(_text)
        .where((value) => value.isNotEmpty)
        .join('\n\n');

    final taxonomy = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll('.entry-content a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final name = _text(anchor);
      if (href.isEmpty || name.isEmpty) continue;
      final path = _relativeId(href);
      final kind = _taxonomyKind(path);
      if (kind == null) continue;
      final link = MangaTaxonomyLink(kind: kind, id: path, name: name);
      taxonomy['${kind.name}:$path'] = link;
      final option = MangaTaxonomyOption(id: path, name: name);
      if (kind == MangaTaxonomyKind.artist) {
        _artists[path] = option;
      }
    }
    final links = taxonomy.values.toList(growable: false);
    final artistLinks = links
        .where((link) => link.kind == MangaTaxonomyKind.artist)
        .toList(growable: false);
    final published = document
        .querySelector('time.date.published')
        ?.attributes['datetime']
        ?.trim();
    final chapterNumber = RegExp(
          r'chapter\s*([\d.]+)',
          caseSensitive: false,
        ).firstMatch(title)?.group(1) ??
        '1';

    return MangaDetails(
      item: MangaCatalogItem(
        id: id,
        title: title,
        coverUri: cover,
        subtitle: pageCount > 0 ? '$pageCount pages' : null,
      ),
      description: description,
      genres: links
          .where((link) => link.kind == MangaTaxonomyKind.tag)
          .map((link) => link.name)
          .toList(growable: false),
      taxonomyLinks: links,
      author: artistLinks.isEmpty ? null : artistLinks.first.name,
      artist: artistLinks.isEmpty ? null : artistLinks.first.name,
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: id,
          title: title,
          number: chapterNumber,
          language: 'en',
          pages: pageCount > 0 ? '$pageCount' : null,
          publishedAt: published,
        ),
      ],
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = chapterWebUri(mangaId: mangaId, chapterId: chapterId);
    final loader = _readerPageLoader;
    if (loader != null) {
      var pageCount = 0;
      try {
        final details = await getDetails(mangaId);
        pageCount = int.tryParse(details.chapters.first.pages ?? '') ?? 0;
      } catch (_) {
        pageCount = 0;
      }
      yield* loader(uri, _userAgent, pageCount).map(MangaReaderPage.file);
      return;
    }

    final document = await _document(uri);
    final headers = {...coverImageHeaders, 'Referer': uri.toString()};
    final seen = <Uri>{};
    for (final image in document.querySelectorAll(
      '.entry-content .wp-block-gallery img[data-safe-src], '
      '.entry-content img[data-safe-src]',
    )) {
      final imageUri = _imageUri(image);
      if (imageUri != null && seen.add(imageUri)) {
        yield MangaReaderPage.network(imageUri, headers: headers);
      }
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      _resolve(chapterId.isEmpty ? mangaId : chapterId);

  @override
  Future<Uint8List> loadBrowserImage(Uri uri) {
    final loader = _browserImageLoader;
    if (loader == null) {
      throw StateError('FSI Comics browser image loader is not configured.');
    }
    return loader(uri, _userAgent);
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.artist,
      ];

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final source = switch (kind) {
      MangaTaxonomyKind.artist => _artists.values,
      _ => const <MangaTaxonomyOption>[],
    };
    final normalized = query.trim().toLowerCase();
    final options = source
        .where((option) =>
            normalized.isEmpty ||
            option.name.toLowerCase().contains(normalized))
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return options;
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) async {
    if (kind != MangaTaxonomyKind.artist) {
      return MangaCatalogPage(items: const []);
    }
    final page = _page(cursor);
    final base = _resolve(taxonomyId);
    return _catalogPage(
      await _document(_pagedUri(base.path, page)),
      page,
    );
  }

  MangaCatalogPage _catalogPage(Document document, int page) {
    final found = <String, MangaCatalogItem>{};
    for (final root in document.querySelectorAll(
      '.blog-content .p-wrap.p-grid, .search-content .p-wrap.p-grid',
    )) {
      final anchor = root.querySelector('.entry-title a.p-url[href]') ??
          root.querySelector('.p-featured a[href]');
      final href = anchor?.attributes['href']?.trim() ?? '';
      final title = _text(root.querySelector('.entry-title a.p-url'));
      if (href.isEmpty || title.isEmpty) continue;
      final id = _relativeId(href);
      final category = _text(root.querySelector('.p-categories a.p-category'));
      found[id] = MangaCatalogItem(
        id: id,
        title: title,
        coverUri: _imageUri(root.querySelector('.p-featured img')),
        subtitle: category.isEmpty ? null : category,
      );
    }
    final items = found.values.toList(growable: false);
    final hasNext = document.querySelector(
          '.pagination a[href*="/page/${page + 1}/"], '
          '.pagination-wrap a[href*="/page/${page + 1}/"], '
          'a.next[href]',
        ) !=
        null;
    return MangaCatalogPage(
      items: items,
      nextCursor: hasNext ? '${page + 1}' : null,
    );
  }

  Future<Document> _document(Uri uri) async {
    final browserLoader = _browserHtmlLoader;
    if (browserLoader != null) {
      return html_parser.parse(await browserLoader(uri, _userAgent));
    }
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('FSI Comics returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri _pagedUri(String path, int page) {
    final normalized = path.endsWith('/') ? path : '$path/';
    return _baseUri.resolve(
      page == 1 ? normalized : '${normalized}page/$page/',
    );
  }

  MangaTaxonomyKind? _taxonomyKind(String path) {
    if (RegExp(
      r'^/all-porn-comics/(?:3d|western|hentai)-porn-comics/[^/]+/?$',
    ).hasMatch(path)) {
      return MangaTaxonomyKind.artist;
    }
    return null;
  }

  Uri? _imageUri(Element? image) {
    String? value;
    for (final attribute in const [
      'data-safe-src',
      'data-src',
      'data-lazy-src',
      'src',
    ]) {
      final candidate = image?.attributes[attribute]?.trim() ?? '';
      if (candidate.isNotEmpty && !candidate.startsWith('data:')) {
        value = candidate;
        break;
      }
    }
    if (value == null || value.isEmpty) return null;
    return _baseUri.resolve(value);
  }

  Uri _resolve(String value) => _baseUri.resolve(value.trim());

  String _relativeId(String value) {
    final uri = _resolve(value);
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  int _page(String? cursor) {
    final page = int.tryParse(cursor ?? '') ?? 1;
    return page < 1 ? 1 : page;
  }

  String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
}
