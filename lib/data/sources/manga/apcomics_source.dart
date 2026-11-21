import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Adult English manga catalog backed by the Madara installation at
/// apcomics.org.
class APComicsSource implements MangaSource, TaxonomyBrowsableMangaSource {
  static const _site = 'https://apcomics.org';
  static const _pageSize = 24;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _orders = <MangaCatalogFilter, String>{
    MangaCatalogFilter.recent: 'latest',
    MangaCatalogFilter.alphabetical: 'alphabet',
    MangaCatalogFilter.popular: 'rating',
    MangaCatalogFilter.trending: 'trending',
    MangaCatalogFilter.updated: 'views',
    MangaCatalogFilter.added: 'new-manga',
  };

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, Future<MangaDetails>> _detailsCache = {};
  final Map<String, String> _tagNames = {};
  Future<List<MangaTaxonomyOption>>? _tagIndex;

  APComicsSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'apcomics';

  @override
  String get name => 'APComics';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
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
        MangaCatalogFilter.alphabetical,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) async {
    final page = _page(cursor);
    final order = _orders[filter] ?? 'latest';
    final uri = _pagedUri('/', page, query: {'m_orderby': order});
    return _catalogPage(await _document(uri), page);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    final page = _page(cursor);
    final uri = _pagedUri(
      '/',
      page,
      query: {'s': value, 'post_type': 'wp-manga'},
    );
    return _catalogPage(await _document(uri), page);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final key = _mangaPath(mangaId);
    final cached = _detailsCache[key];
    if (cached != null) return await cached;
    final pending = _loadDetails(key);
    _detailsCache[key] = pending;
    try {
      return await pending;
    } catch (_) {
      _detailsCache.remove(key);
      rethrow;
    }
  }

  Future<MangaDetails> _loadDetails(String mangaPath) async {
    final uri = _resolve(mangaPath);
    final document = await _document(uri);
    final title = _text(document.querySelector('.post-title h1'));
    if (title.isEmpty) {
      throw StateError('APComics did not return manga details for $mangaPath.');
    }

    final taxonomyLinks = <MangaTaxonomyLink>[];
    for (final anchor in document.querySelectorAll(
      '.tags-content a[href*="/manga-tag/"]',
    )) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final name = _text(anchor);
      if (href.isEmpty || name.isEmpty) continue;
      final path = _relativeId(href);
      taxonomyLinks.add(MangaTaxonomyLink(
        kind: MangaTaxonomyKind.tag,
        id: path,
        name: name,
      ));
      _tagNames[path] = name;
    }

    final chapterDocument = await _postDocument(
      uri.resolve('${uri.path.endsWith('/') ? '' : '/'}ajax/chapters/'),
      referer: uri,
    );
    final chapters = chapterDocument
        .querySelectorAll('li.wp-manga-chapter')
        .map((element) {
          final anchor = element.querySelector('a[href]');
          final href = anchor?.attributes['href']?.trim() ?? '';
          final label = _text(anchor);
          if (href.isEmpty || label.isEmpty) return null;
          return MangaChapter(
            id: _relativeId(href),
            title: label,
            number: _chapterNumber(label),
            language: 'en',
            publishedAt: _text(element.querySelector('.chapter-release-date')),
          );
        })
        .whereType<MangaChapter>()
        .toList(growable: false)
        .reversed
        .toList(growable: false);

    final tags = taxonomyLinks
        .where((link) => link.kind == MangaTaxonomyKind.tag)
        .map((link) => link.name)
        .toList(growable: false);
    final artists = document
        .querySelectorAll('.artist-content a[href*="/manga-artist/"]')
        .map(_text)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final statusText = _metadata(document, 'Status');
    final alternative = _metadata(document, 'Alternative');
    final author = _metadata(document, 'Author(s)');
    final rating = double.tryParse(
      document.querySelector('#averagerate')?.text.trim() ?? '',
    );

    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaPath,
        title: title,
        coverUri: _imageUri(document.querySelector('.summary_image img')),
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          rating: rating,
          status: _status(statusText),
        ),
      ),
      description: _text(document.querySelector('.summary__content')),
      alternativeTitles:
          alternative.isEmpty || alternative.toLowerCase() == 'updating'
              ? const []
              : [
                  {'en': alternative}
                ],
      genres: tags,
      taxonomyLinks: taxonomyLinks,
      author: artists.isNotEmpty
          ? artists.join(', ')
          : author.isEmpty || author.toLowerCase() == 'updating'
              ? null
              : author,
      status: _status(statusText),
      externalUri: uri,
      chapters: chapters,
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = _resolve(chapterId);
    final document = await _document(uri);
    final headers = {
      ...coverImageHeaders,
      'Referer': uri.toString(),
    };
    final seen = <Uri>{};
    for (final image in document.querySelectorAll(
      '.reading-content .page-break img, .reading-content img.wp-manga-chapter-img',
    )) {
      final imageUri = _imageUri(image);
      if (imageUri != null && seen.add(imageUri)) {
        yield MangaReaderPage.network(imageUri, headers: headers);
      }
    }
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
      ];

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    if (kind != MangaTaxonomyKind.tag) return const [];
    final index = await (_tagIndex ??= _loadTagIndex());
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return index;
    return index
        .where((option) => option.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  Future<List<MangaTaxonomyOption>> _loadTagIndex() async {
    final response = await _get(_baseUri.resolve('/wp-manga-tag-sitemap.xml'));
    final body = utf8.decode(response.bodyBytes);
    final found = <String, MangaTaxonomyOption>{};
    for (final match
        in RegExp(r'<loc>([^<]+/manga-tag/[^<]+)</loc>').allMatches(body)) {
      final path = _relativeId(match.group(1)!);
      final slug = Uri.parse(path)
          .pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      found[path] = MangaTaxonomyOption(
        id: path,
        name: _tagNames[path] ?? _tagLabel(slug),
      );
    }
    final options = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(options);
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) async {
    if (kind != MangaTaxonomyKind.tag) {
      return MangaCatalogPage(items: const []);
    }
    final page = _page(cursor);
    final base = _resolve(taxonomyId);
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    final uri = page == 1
        ? base.replace(path: path)
        : base.replace(path: '${path}page/$page/');
    return _catalogPage(await _document(uri), page);
  }

  MangaCatalogPage _catalogPage(Document document, int page) {
    final found = <String, MangaCatalogItem>{};
    final roots = <Element>[
      ...document.querySelectorAll('.page-item-detail.manga'),
      ...document.querySelectorAll('.c-tabs-item__content'),
    ];
    for (final root in roots) {
      final anchor = root.querySelector(
        '.post-title a[href*="/manga/"], '
        '.item-thumb a[href*="/manga/"], '
        '.tab-thumb a[href*="/manga/"]',
      );
      final href = anchor?.attributes['href']?.trim() ?? '';
      final title = _text(root.querySelector('.post-title a'));
      if (href.isEmpty || title.isEmpty) continue;
      final id = _relativeId(href);
      final latest = _text(root.querySelector(
        '.list-chapter .chapter a, .latest-chap .chapter a',
      ));
      final rating = double.tryParse(_text(root.querySelector('.score')));
      found[id] = MangaCatalogItem(
        id: id,
        title: title,
        coverUri: _imageUri(root.querySelector(
          '.item-thumb img, .tab-thumb img',
        )),
        subtitle: mangaCatalogSubtitle(
          latestChapter: _chapterNumber(latest),
          rating: rating,
        ),
      );
    }
    final items = found.values.toList(growable: false);
    return MangaCatalogPage(
      items: items,
      nextCursor: items.length >= _pageSize ? '${page + 1}' : null,
    );
  }

  Uri _pagedUri(
    String path,
    int page, {
    Map<String, String> query = const {},
  }) {
    final normalized = path.endsWith('/') ? path : '$path/';
    return _baseUri
        .resolve(page == 1 ? normalized : '${normalized}page/$page/')
        .replace(queryParameters: query);
  }

  Future<Document> _document(Uri uri) async =>
      html_parser.parse(utf8.decode((await _get(uri)).bodyBytes));

  Future<Document> _postDocument(Uri uri, {required Uri referer}) async {
    final response = await _client.post(uri, headers: {
      ...requestHeaders,
      'Referer': referer.toString(),
      'X-Requested-With': 'XMLHttpRequest',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('APComics returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('APComics returned HTTP ${response.statusCode}.');
    }
    return response;
  }

  Uri _resolve(String value) => _baseUri.resolve(value.trim());

  String _relativeId(String value) {
    final uri = _baseUri.resolve(value.trim());
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  String _mangaPath(String value) {
    final path = _resolve(value).path;
    final match = RegExp(r'^/manga/[^/]+/?').firstMatch(path);
    if (match == null) throw ArgumentError.value(value, 'mangaId');
    final normalized = match.group(0)!;
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }

  Uri? _imageUri(Element? image) {
    String? value;
    for (final attribute in const ['data-src', 'data-lazy-src', 'src']) {
      final candidate = image?.attributes[attribute]?.trim() ?? '';
      if (candidate.isNotEmpty) {
        value = candidate;
        break;
      }
    }
    final srcset = image?.attributes['srcset']?.trim() ?? '';
    value ??= srcset.isEmpty ? null : srcset.split(RegExp(r'\s+')).first;
    if (value == null || value.isEmpty || value.startsWith('data:')) {
      return null;
    }
    return _baseUri.resolve(value.replaceAll(RegExp(r'^\s+|\s+$'), ''));
  }

  String _metadata(Document document, String heading) {
    final normalized = heading.toLowerCase();
    for (final item in document.querySelectorAll('.post-content_item')) {
      if (_text(item.querySelector('.summary-heading')).toLowerCase() ==
          normalized) {
        return _text(item.querySelector('.summary-content'));
      }
    }
    return '';
  }

  MangaStatus _status(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.contains('ongoing')) return MangaStatus.ongoing;
    if (normalized.contains('complete')) return MangaStatus.completed;
    if (normalized.contains('hiatus')) return MangaStatus.hiatus;
    if (normalized.contains('cancel')) return MangaStatus.cancelled;
    return MangaStatus.unknown;
  }

  String _chapterNumber(String label) {
    final chapter = RegExp(
      r'chapter\s*-?\s*([\d.]+)',
      caseSensitive: false,
    ).firstMatch(label)?.group(1);
    return chapter ?? RegExp(r'[\d.]+').firstMatch(label)?.group(0) ?? label;
  }

  String _tagLabel(String slug) {
    final words = slug.split('-').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return slug;
    String? qualifier;
    if (words.length > 1 && {'female', 'male'}.contains(words.last)) {
      qualifier = words.removeLast();
    }
    final label = words.join(' ');
    final titled =
        label.isEmpty ? slug : '${label[0].toUpperCase()}${label.substring(1)}';
    return qualifier == null ? titled : '$titled ($qualifier)';
  }

  int _page(String? cursor) {
    final value = int.tryParse(cursor ?? '') ?? 1;
    return value < 1 ? 1 : value;
  }

  String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
}
