import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Rawkuma's Japanese manga catalog and native image reader.
class RawkumaSource implements MangaSource, FilterableMangaSource {
  static const _site = 'https://rawkuma.net';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, MangaDetails> _detailsCache = {};
  MangaSearchOptions? _searchOptionsCache;
  String? _searchNonce;

  RawkumaSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'rawkuma';

  @override
  String get name => 'Rawkuma';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,ja;q=0.8',
        'Referer': _baseUri.resolve('/').toString(),
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': _baseUri.resolve('/').toString(),
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.updated,
        MangaCatalogFilter.popular,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.updated,
    String? cursor,
  }) {
    if (filter == MangaCatalogFilter.updated) {
      return _latest(cursor == null
          ? _baseUri.resolve('/latest-update/')
          : _resolve(cursor));
    }
    return _library(
      MangaSearchRequest(sort: MangaSearchSort.popular),
      page: _page(cursor),
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    return _library(
      MangaSearchRequest(sort: MangaSearchSort.popular),
      query: query.trim(),
      page: _page(cursor),
    );
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final cached = _searchOptionsCache;
    if (cached != null) return cached;

    final document = await _getDocument(_baseUri.resolve('/library/'));
    final terms = _searchTerms(document);
    final options = MangaSearchOptions(
      genres: _termOptions(terms['genre']),
      types: _termOptions(terms['type']),
      statuses: _termOptions(terms['status']),
      authors: _termOptions(terms['series-author']),
      artists: _termOptions(terms['artist']),
      sorts: const [
        MangaSearchSort.popular,
        MangaSearchSort.rating,
        MangaSearchSort.updated,
        MangaSearchSort.bookmarked,
        MangaSearchSort.title,
      ],
      supportsAuthor: true,
      supportsArtist: true,
      supportsChapterRange: false,
      supportsCategoryMode: true,
      supportsGenreExclusion: true,
      supportsExclusionCategoryMode: true,
      supportsSortDirection: true,
    );
    _searchOptionsCache = options;
    return options;
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    return _library(request, page: _page(cursor));
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _slug(mangaId);
    final cached = _detailsCache[slug];
    if (cached != null) return cached;

    final uri = _baseUri.resolve('/manga/$slug/');
    final document = await _getDocument(uri);
    final schema = _seriesSchema(document);
    final title = _schemaString(schema?['name']) ??
        document.querySelector('h1[itemprop="name"]')?.text.trim() ??
        slug.replaceAll('-', ' ');
    final cover = _schemaImage(schema?['image']) ??
        _imageUri(document.querySelector('article img.wp-post-image'));
    final description = document
            .querySelector('[itemprop="description"][data-show="false"]')
            ?.text
            .trim() ??
        _schemaString(schema?['description']) ??
        '';
    final alternateName = _schemaString(schema?['alternateName']) ?? '';
    final genres = _schemaStrings(schema?['genre']);
    final status = mangaStatusFromString(schema?['creativeWorkStatus']);
    final chapters = _chapters(document, slug);
    final format = _metadataValue(document, 'Type');
    final year = int.tryParse(_schemaString(schema?['datePublished']) ?? '');
    final rating = _schemaNumber(
      schema?['aggregateRating'] is Map
          ? (schema?['aggregateRating'] as Map)['ratingValue']
          : null,
    );
    final details = MangaDetails(
      item: MangaCatalogItem(
        id: slug,
        title: title,
        coverUri: cover,
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          format: format,
          status: status,
          rating: rating,
          year: year,
        ),
      ),
      description: description,
      alternativeTitles: alternateName
          .split(RegExp(r'\s*,\s*'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && value != title)
          .map((value) => {'und': value}),
      genres: genres,
      author: _personName(schema?['author']),
      status: status,
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
    final uri = _resolve(chapterId);
    final document = await _getDocument(uri);
    final seen = <String>{};
    for (final image
        in document.querySelectorAll('section[data-image-data] img[src]')) {
      final pageUri = _uri(image.attributes['src']);
      if (pageUri == null || !seen.add(pageUri.toString())) continue;
      yield MangaReaderPage.network(
        pageUri,
        headers: {
          ...coverImageHeaders,
          'Referer': uri.toString(),
        },
      );
    }
  }

  Future<MangaCatalogPage> _latest(Uri uri) async {
    final document = await _getDocument(uri);
    final root = document.querySelector('#search-results');
    final items = _catalogItems(root?.children ?? const []);
    final currentPage =
        int.tryParse(uri.queryParameters['the_page'] ?? '') ?? 1;
    final nextPage = currentPage + 1;
    final hasNext = document
        .querySelectorAll('a[href*="the_page="]')
        .map((anchor) => _uri(anchor.attributes['href']))
        .whereType<Uri>()
        .any((candidate) =>
            int.tryParse(candidate.queryParameters['the_page'] ?? '') ==
            nextPage);
    return MangaCatalogPage(
      items: items,
      nextCursor: hasNext
          ? _baseUri
              .resolve('/latest-update/')
              .replace(queryParameters: {'the_page': '$nextPage'}).toString()
          : null,
    );
  }

  Future<MangaCatalogPage> _library(
    MangaSearchRequest request, {
    String query = '',
    int page = 1,
  }) async {
    final body = await _advancedSearch(
      request,
      query: query,
      page: page,
    );
    final fragment = html_parser.parseFragment(body);
    final roots = fragment.nodes.whereType<Element>();
    final items = _catalogItems(roots);
    return MangaCatalogPage(
      items: items,
      nextCursor: items.length >= 24 ? '${page + 1}' : null,
    );
  }

  Future<String> _advancedSearch(
    MangaSearchRequest request, {
    required String query,
    required int page,
    bool retry = true,
  }) async {
    final uri = _baseUri
        .resolve('/wp-admin/admin-ajax.php')
        .replace(queryParameters: {'action': 'advanced_search'});
    final response = await _client.post(
      uri,
      headers: {
        ...requestHeaders,
        'Referer': _baseUri.resolve('/library/').toString(),
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'nonce': await _nonce(),
        'page': '$page',
        'genre': jsonEncode(request.genres.toList(growable: false)),
        'genre_exclude':
            jsonEncode(request.excludedGenres.toList(growable: false)),
        'author': jsonEncode(_creatorValues(
          request.authorValues,
          request.author,
        )),
        'artist': jsonEncode(_creatorValues(
          request.artistValues,
          request.artist,
        )),
        'project': '0',
        'type': jsonEncode(request.types.toList(growable: false)),
        'status': jsonEncode(request.statuses.toList(growable: false)),
        'order': _sortOrder(request),
        'orderby': _sortValue(request.sort),
        'query': query,
        'inclusion':
            request.categoryMode == MangaCategoryMode.all ? 'AND' : 'OR',
        'exclusion': request.exclusionCategoryMode == MangaCategoryMode.all
            ? 'AND'
            : 'OR',
      },
    );
    final body = utf8.decode(response.bodyBytes);
    if ((response.statusCode < 200 ||
            response.statusCode >= 300 ||
            body.trim() == '-1') &&
        retry) {
      _searchNonce = null;
      return _advancedSearch(
        request,
        query: query,
        page: page,
        retry: false,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Rawkuma returned HTTP ${response.statusCode}.');
    }
    if (body.trim() == '-1') {
      throw StateError('Rawkuma rejected the catalog search nonce.');
    }
    return body;
  }

  Future<String> _nonce() async {
    final cached = _searchNonce;
    if (cached != null && cached.isNotEmpty) return cached;
    final uri = _baseUri.resolve('/wp-admin/admin-ajax.php').replace(
      queryParameters: {
        'type': 'search_form',
        'action': 'get_nonce',
      },
    );
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      'Referer': _baseUri.resolve('/library/').toString(),
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Rawkuma returned HTTP ${response.statusCode}.');
    }
    final match = RegExp(
      r'''name=["']search_nonce["'][^>]*value=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(utf8.decode(response.bodyBytes));
    final nonce = match?.group(1)?.trim() ?? '';
    if (nonce.isEmpty) {
      throw StateError('Rawkuma did not return a catalog search nonce.');
    }
    return _searchNonce = nonce;
  }

  List<MangaCatalogItem> _catalogItems(Iterable<Element> roots) {
    final seen = <String>{};
    return roots
        .map((card) {
          final mangaAnchors = card
              .querySelectorAll('a[href*="/manga/"]')
              .where(
                (anchor) =>
                    !(anchor.attributes['href'] ?? '').contains('/chapter-'),
              );
          if (mangaAnchors.isEmpty) return null;
          final href = mangaAnchors.first.attributes['href'] ?? '';
          final slug = _slug(href);
          if (slug.isEmpty || !seen.add(slug)) return null;
          final cover = card.querySelector('img.wp-post-image') ??
              card.querySelectorAll('img[src]').cast<Element?>().firstWhere(
                    (image) => !(image?.attributes['src'] ?? '')
                        .contains('/static/svg/'),
                    orElse: () => null,
                  );
          final titleAnchor = mangaAnchors.cast<Element?>().firstWhere(
                (anchor) => (anchor?.text.trim() ?? '').isNotEmpty,
                orElse: () => null,
              );
          final title = titleAnchor?.text.trim() ??
              cover?.attributes['alt']?.trim() ??
              slug.replaceAll('-', ' ');
          final chapter = card
              .querySelector('a[href*="/chapter-"]')
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final text = card.text.replaceAll(RegExp(r'\s+'), ' ');
          final status = RegExp(
            r'\b(Ongoing|Completed|On Hiatus|Cancelled|Unknown)\b',
            caseSensitive: false,
          ).firstMatch(text)?.group(1);
          final rating = double.tryParse(
            card.querySelector('.numscore')?.text.trim() ?? '',
          );
          final type = card
              .querySelector('img[src*="/static/svg/"]')
              ?.attributes['alt']
              ?.trim();
          return MangaCatalogItem(
            id: slug,
            title: title,
            coverUri: _imageUri(cover),
            subtitle: mangaCatalogSubtitle(
              latestChapter: chapter,
              format: type,
              status: mangaStatusFromString(status),
              rating: rating,
            ),
          );
        })
        .whereType<MangaCatalogItem>()
        .toList(growable: false);
  }

  List<MangaChapter> _chapters(Document document, String slug) {
    final seen = <String>{};
    final descending = document
        .querySelectorAll('#chapter-list a[href*="/chapter-"]')
        .map((anchor) {
          final href = anchor.attributes['href']?.trim() ?? '';
          if (href.isEmpty || !seen.add(href)) return null;
          final label = anchor.querySelector('span')?.text.trim() ??
              anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          final number = anchor.parent?.attributes['data-chapter-number'] ??
              normalizeMangaChapterNumber(label) ??
              '';
          return MangaChapter(
            id: href,
            title: label,
            number: number,
            language: 'ja',
            publishedAt: anchor.querySelector('time')?.attributes['datetime'],
          );
        })
        .whereType<MangaChapter>()
        .toList(growable: true);
    return descending.reversed.toList(growable: false);
  }

  Map<String, dynamic> _searchTerms(Document document) {
    for (final script in document.querySelectorAll('script')) {
      final match = RegExp(
        r'var\s+searchTerms\s*=\s*(\{.*\})\s*;\s*$',
        dotAll: true,
      ).firstMatch(script.text.trim());
      if (match == null) continue;
      final decoded = jsonDecode(match.group(1)!);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    }
    return const {};
  }

  List<MangaFilterOption> _termOptions(Object? raw) {
    final values = raw is Map
        ? raw.values
        : raw is List
            ? raw
            : const <Object>[];
    return values
        .whereType<Map>()
        .map((term) {
          final value = term['slug']?.toString().trim() ?? '';
          final label = term['name']?.toString().trim() ?? '';
          return value.isEmpty || label.isEmpty
              ? null
              : MangaFilterOption(value: value, label: label);
        })
        .whereType<MangaFilterOption>()
        .toList(growable: false);
  }

  Map<String, dynamic>? _seriesSchema(Document document) {
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(script.text);
        final candidates = decoded is List ? decoded : [decoded];
        for (final candidate in candidates.whereType<Map>()) {
          if (candidate['@type'] == 'CreativeWorkSeries') {
            return candidate.map((key, value) => MapEntry('$key', value));
          }
        }
      } catch (_) {
        // Ignore unrelated malformed schema blocks.
      }
    }
    return null;
  }

  String? _metadataValue(Document document, String label) {
    for (final node in document.querySelectorAll('h4, h1')) {
      if (node.text.trim().toLowerCase() != label.toLowerCase()) continue;
      return node.parent?.querySelector('p')?.text.trim();
    }
    return null;
  }

  String _sortValue(MangaSearchSort sort) => switch (sort) {
        MangaSearchSort.rating => 'rating',
        MangaSearchSort.updated => 'updated',
        MangaSearchSort.bookmarked ||
        MangaSearchSort.mostFollows =>
          'bookmarked',
        MangaSearchSort.title ||
        MangaSearchSort.titleAscending ||
        MangaSearchSort.titleDescending =>
          'title',
        _ => 'popular',
      };

  String _sortOrder(MangaSearchRequest request) {
    if (request.sort == MangaSearchSort.titleAscending) return 'asc';
    if (request.sort == MangaSearchSort.titleDescending) return 'desc';
    return request.sortDirection == MangaSortDirection.ascending
        ? 'asc'
        : 'desc';
  }

  List<String> _creatorValues(Set<String> selected, String typed) {
    if (selected.isNotEmpty) return selected.toList(growable: false);
    final value = typed.trim();
    if (value.isEmpty) return const [];
    return [_slugify(value)];
  }

  int _page(String? cursor) => int.tryParse(cursor ?? '') ?? 1;

  String _slug(String value) {
    final uri = Uri.tryParse(value.trim());
    final segments =
        uri?.pathSegments.where((part) => part.isNotEmpty).toList() ??
            const <String>[];
    final index = segments.indexOf('manga');
    return index >= 0 && index + 1 < segments.length
        ? segments[index + 1]
        : value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  String _slugify(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Uri _resolve(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return parsed;
    return _baseUri.resolve(trimmed);
  }

  Uri? _uri(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('//')) {
      return Uri.parse('${_baseUri.scheme}:$trimmed');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    return parsed.hasScheme ? parsed : _baseUri.resolveUri(parsed);
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['data-src'] ?? image?.attributes['src'],
      );

  Uri? _schemaImage(Object? raw) {
    if (raw is String) return _uri(raw);
    if (raw is Map) return _uri(raw['url']?.toString());
    return null;
  }

  String? _schemaString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  List<String> _schemaStrings(Object? value) {
    if (value is List) {
      return value
          .map(_schemaString)
          .whereType<String>()
          .toList(growable: false);
    }
    final text = _schemaString(value);
    return text == null ? const [] : [text];
  }

  String? _personName(Object? value) {
    if (value is Map) return _schemaString(value['name']);
    if (value is List) {
      return value.map(_personName).whereType<String>().join(', ');
    }
    return _schemaString(value);
  }

  double? _schemaNumber(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<Document> _getDocument(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Rawkuma returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }
}
