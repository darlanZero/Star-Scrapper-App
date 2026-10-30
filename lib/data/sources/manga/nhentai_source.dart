import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

class NHentaiSource implements MangaSource, TaxonomyBrowsableMangaSource {
  static final Uri _defaultBaseUri = Uri.parse('https://nhentai.to');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, Future<MangaDetails>> _detailsCache = {};

  NHentaiSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'nhentai';
  @override
  String get name => 'nHentai';
  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,*;q=0.5',
        'Referer': '${_baseUri.origin}/go',
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
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) {
    final path = filter == MangaCatalogFilter.popular ? '/popular' : '/go';
    return _catalog(_pageUri(path, cursor));
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return Future.value(MangaCatalogPage(items: const []));
    return _catalog(_pageUri('/search/', cursor, {'q': value}));
  }

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final plural = _pluralPath(kind);
    final normalized = query.trim().toLowerCase();
    if (kind != MangaTaxonomyKind.tag && normalized.length < 2) return const [];

    final index = await _document(_baseUri.resolve('/$plural/'));
    var startPage = 1;
    if (normalized.isNotEmpty) {
      final initial = normalized[0].toUpperCase();
      for (final anchor in index.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'];
        if (href == null) continue;
        final relativeUri = Uri.tryParse(href);
        if (relativeUri == null) continue;
        final uri = _baseUri.resolve('/$plural/').resolveUri(relativeUri);
        if (uri.pathSegments.where((part) => part.isNotEmpty).lastOrNull !=
                plural ||
            !uri.queryParameters.containsKey('page')) {
          continue;
        }
        if (anchor.text.trim().toUpperCase() == initial) {
          startPage = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
          break;
        }
      }
    }

    final found = <String, MangaTaxonomyOption>{};
    final maxPages = normalized.isEmpty ? 1 : 8;
    for (var offset = 0; offset < maxPages; offset++) {
      final page = offset == 0 && startPage == 1
          ? index
          : await _document(
              _baseUri.resolve('/$plural?page=${startPage + offset}'));
      for (final anchor
          in page.querySelectorAll('a[href*="/${_singularPath(kind)}/"]')) {
        final href = anchor.attributes['href'] ?? '';
        final nameNode = anchor.querySelector('.name');
        var name = (nameNode?.text ?? anchor.text).trim();
        final countNode = anchor.querySelector('.count');
        final count = _integer(countNode?.text ?? name);
        if (countNode == null) {
          name = name.replaceFirst(RegExp(r'\s+[\d,.]+$'), '').trim();
        }
        if (name.isEmpty ||
            (normalized.isNotEmpty &&
                !name.toLowerCase().contains(normalized))) {
          continue;
        }
        found[href] =
            MangaTaxonomyOption(id: href, name: name, titleCount: count);
      }
      if (normalized.isEmpty || found.length >= 80) break;
    }
    final values = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return values.take(100).toList(growable: false);
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
          .map((id) => Uri.parse(id)
              .pathSegments
              .where((part) => part.isNotEmpty)
              .lastOrNull)
          .whereType<String>()
          .map((slug) => slug.replaceAll('-', ' '))
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
    final uri = _baseUri.resolve('/g/$id/');
    final document = await _document(uri);
    final info = document.querySelector('#info');
    final title = info?.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) throw StateError('nHentai did not return gallery $id.');
    final alternate = info?.querySelector('h2')?.text.trim() ?? '';
    final cover = _uri(document.querySelector('#cover img')?.attributes['src']);
    final taxonomies = _detailTaxonomies(info);
    final tags = taxonomies[MangaTaxonomyKind.tag] ?? const [];
    final artists = taxonomies[MangaTaxonomyKind.artist] ?? const [];
    final groups = taxonomies[MangaTaxonomyKind.group] ?? const [];
    final pageCount = _detailPageCount(info, document);
    final language = _detailLanguage(info);
    final uploaded = info?.querySelector('time')?.attributes['datetime'];

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
        if (alternate.isNotEmpty) {'': alternate}
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
    final id = _galleryId(mangaId);
    final document = await _document(_baseUri.resolve('/g/$id/'));
    for (final image in document
        .querySelectorAll('#thumbnail-container .gallerythumb img')) {
      final thumbnail = image.attributes['data-src'] ?? image.attributes['src'];
      final uri = _uri(thumbnail);
      if (uri == null) continue;
      final full = uri.replace(
        path: uri.path.replaceFirstMapped(
          RegExp(r'(\d+)t(?=\.[^.]+$)'),
          (match) => match.group(1)!,
        ),
      );
      yield MangaReaderPage.network(full, headers: coverImageHeaders);
    }
  }

  Future<MangaCatalogPage> _catalog(Uri uri) async {
    final document = await _document(uri);
    final items = <MangaCatalogItem>[];
    final seen = <String>{};
    for (final card in document.querySelectorAll('.gallery')) {
      final anchor = card.querySelector('a.cover[href*="/g/"]') ??
          card.querySelector('a[href*="/g/"]');
      final href = anchor?.attributes['href'] ?? '';
      final id = _galleryId(href);
      if (id.isEmpty || !seen.add(id)) continue;
      final image = card.querySelector('img');
      final title = (card.querySelector('.caption')?.text ??
              image?.attributes['alt'] ??
              anchor?.text ??
              '')
          .trim();
      if (title.isEmpty) continue;
      items.add(MangaCatalogItem(
        id: id,
        title: title.replaceFirst(RegExp(r'^NEW\s+'), ''),
        coverUri:
            _uri(image?.attributes['data-src'] ?? image?.attributes['src']),
      ));
    }
    final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
    final enriched = await _enrichCatalogItems(items);
    return MangaCatalogPage(
      items: enriched,
      nextCursor: items.isEmpty ? null : '${page + 1}',
    );
  }

  Future<List<MangaCatalogItem>> _enrichCatalogItems(
    List<MangaCatalogItem> items,
  ) async {
    final enriched = <MangaCatalogItem>[];
    const batchSize = 5;
    for (var start = 0; start < items.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, items.length);
      final batch = items.sublist(start, end);
      final results = await Future.wait(batch.map((item) async {
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
      }));
      enriched.addAll(results);
    }
    return enriched;
  }

  Map<MangaTaxonomyKind, List<MangaTaxonomyOption>> _detailTaxonomies(
      Element? info) {
    final result = <MangaTaxonomyKind, List<MangaTaxonomyOption>>{};
    if (info == null) return result;
    for (final container in info.querySelectorAll('#tags .tag-container')) {
      final text = container.text.trim().toLowerCase();
      final kind = text.startsWith('tags')
          ? MangaTaxonomyKind.tag
          : text.startsWith('artists')
              ? MangaTaxonomyKind.artist
              : text.startsWith('characters')
                  ? MangaTaxonomyKind.character
                  : text.startsWith('parodies')
                      ? MangaTaxonomyKind.parody
                      : text.startsWith('groups')
                          ? MangaTaxonomyKind.group
                          : null;
      if (kind == null) continue;
      result[kind] = container
          .querySelectorAll('a.tag')
          .map((anchor) {
            final name = anchor.querySelector('.name')?.text.trim() ?? '';
            return MangaTaxonomyOption(
              id: anchor.attributes['href'] ?? '',
              name: name,
              titleCount: _integer(anchor.querySelector('.count')?.text ?? ''),
            );
          })
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList();
    }
    return result;
  }

  int _detailPageCount(Element? info, Document document) {
    for (final container in info?.querySelectorAll('#tags .tag-container') ??
        const <Element>[]) {
      if (container.text.trim().toLowerCase().startsWith('pages:')) {
        return _integer(container.querySelector('.name')?.text ?? '') ?? 0;
      }
    }
    return document
        .querySelectorAll('#thumbnail-container .gallerythumb')
        .length;
  }

  String _detailLanguage(Element? info) {
    for (final container in info?.querySelectorAll('#tags .tag-container') ??
        const <Element>[]) {
      if (container.text.trim().toLowerCase().startsWith('languages')) {
        final names = container
            .querySelectorAll('.name')
            .map((node) => node.text.trim().toLowerCase());
        return names.firstWhere((name) => name != 'translated',
            orElse: () => 'all');
      }
    }
    return 'all';
  }

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('nHentai request failed (${response.statusCode}): $uri');
    }
    return html_parser.parse(response.body);
  }

  Uri _pageUri(String path, String? cursor,
      [Map<String, String> extra = const {}]) {
    final page = int.tryParse(cursor ?? '') ?? 1;
    return _baseUri
        .resolve(path)
        .replace(queryParameters: {...extra, 'page': '$page'});
  }

  String _pluralPath(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tags',
        MangaTaxonomyKind.artist => 'artists',
        MangaTaxonomyKind.character => 'characters',
        MangaTaxonomyKind.parody => 'parodies',
        MangaTaxonomyKind.group => 'groups',
        MangaTaxonomyKind.circle => 'groups',
      };

  String _singularPath(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'tag',
        MangaTaxonomyKind.artist => 'artist',
        MangaTaxonomyKind.character => 'character',
        MangaTaxonomyKind.parody => 'parody',
        MangaTaxonomyKind.group || MangaTaxonomyKind.circle => 'group',
      };

  String _galleryId(String raw) =>
      RegExp(r'/g/(\d+)').firstMatch(raw)?.group(1) ??
      (RegExp(r'^\d+$').hasMatch(raw) ? raw : '');
  Uri? _uri(String? raw) =>
      raw == null || raw.isEmpty || raw.startsWith('data:')
          ? null
          : _baseUri.resolve(raw);
  int? _integer(String raw) =>
      int.tryParse(raw.replaceAll(RegExp(r'[^\d]'), ''));
  String _capitalize(String value) => value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}
