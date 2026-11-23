import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

typedef ToonLookBinaryLoader = Future<
        ({
          int statusCode,
          Uint8List body,
          Map<String, String> headers,
        })>
    Function(Uri uri, Map<String, String> headers);

typedef ToonLookImageDescrambler = Future<String> Function(
  Uint8List bytes,
  Uri imageUri,
  String language,
  int stripHeight,
  String salt,
);

class ToonLookSource
    implements
        MangaSource,
        VariantCatalogMangaSource,
        FilterableMangaSource,
        TaxonomyBrowsableMangaSource,
        WebViewChapterMangaSource {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static const _catalogSorts = [
    MangaCatalogVariant(id: 'latest', label: 'Latest release'),
    MangaCatalogVariant(id: 'new', label: 'New manhwa'),
    MangaCatalogVariant(id: 'az', label: 'A-Z'),
    MangaCatalogVariant(id: 'rating', label: 'Rating'),
    MangaCatalogVariant(id: 'bookmarks', label: 'Bookmarks'),
  ];
  static const _viewSorts = [
    MangaCatalogVariant(id: 'daily_top', label: 'Daily views'),
    MangaCatalogVariant(id: 'weekly_top', label: 'Weekly views'),
    MangaCatalogVariant(id: 'monthly_top', label: 'Monthly views'),
    MangaCatalogVariant(id: 'yearly_top', label: 'Yearly views'),
    MangaCatalogVariant(id: 'all_top', label: 'All-time views'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final ToonLookBinaryLoader? _binaryLoader;
  final ToonLookImageDescrambler? _imageDescrambler;

  ToonLookSource({
    http.Client? client,
    Uri? baseUri,
    ToonLookBinaryLoader? binaryLoader,
    ToonLookImageDescrambler? imageDescrambler,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse('https://toonlook.com/'),
        _binaryLoader = binaryLoader,
        _imageDescrambler = imageDescrambler;

  @override
  String get id => 'toonlook';
  @override
  String get name => 'ToonLook';
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
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.added,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.recent
          ? _catalogSorts
          : filter == MangaCatalogFilter.popular
              ? _viewSorts
              : const [];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) {
    if (filter == MangaCatalogFilter.added) {
      return browseVariant(MangaCatalogFilter.recent, 'new', cursor: cursor);
    }
    if (filter == MangaCatalogFilter.popular) {
      return browseVariant(filter, 'daily_top', cursor: cursor);
    }
    return browseVariant(filter, 'latest', cursor: cursor);
  }

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    final options =
        filter == MangaCatalogFilter.popular ? _viewSorts : _catalogSorts;
    final fallback =
        filter == MangaCatalogFilter.popular ? 'daily_top' : 'latest';
    final value =
        options.any((item) => item.id == variantId) ? variantId : fallback;
    return _catalog(
      filter == MangaCatalogFilter.popular ? '/top-manhwa/' : '/manhwa/',
      cursor,
      {'sortby': value},
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return _catalog('/manhwa/', cursor, {'s': value});
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async => MangaSearchOptions(
        statuses: const [
          MangaFilterOption(value: 'ongoing', label: 'Ongoing'),
          MangaFilterOption(value: 'completed', label: 'Completed'),
          MangaFilterOption(value: 'hiatus', label: 'Hiatus'),
          MangaFilterOption(value: 'dropped', label: 'Dropped'),
        ],
        sorts: const [
          MangaSearchSort.updated,
          MangaSearchSort.recentlyAdded,
          MangaSearchSort.titleAscending,
          MangaSearchSort.rating,
          MangaSearchSort.bookmarked,
          MangaSearchSort.mostViewed,
        ],
        supportsSortDirection: true,
      );

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    final sort = switch (request.sort) {
      MangaSearchSort.recentlyAdded => 'new',
      MangaSearchSort.titleAscending => 'az',
      MangaSearchSort.rating => 'rating',
      MangaSearchSort.bookmarked => 'bookmarks',
      MangaSearchSort.mostViewed => 'all_top',
      _ => 'latest',
    };
    return _catalog('/manhwa/', cursor, {
      'sortby': sort,
      'order': request.sortDirection == MangaSortDirection.ascending
          ? 'asc'
          : 'desc',
      if (request.statuses.isNotEmpty) 'status': request.statuses.first,
    });
  }

  Future<MangaCatalogPage> _catalog(
    String path,
    String? cursor,
    Map<String, String> query,
  ) async {
    final page = _page(cursor);
    final route = page == 1 ? path : '${path}page/$page/';
    final document = await _document(
      _baseUri.resolve(route).replace(queryParameters: query),
    );
    final found = <String, MangaCatalogItem>{};
    for (final root in document.querySelectorAll('.manga-item')) {
      final anchor = root.querySelector('a[href*="/manhwa/"]');
      final href = anchor?.attributes['href'] ?? '';
      final uri = _baseUri.resolve(href);
      if (!_isTitlePath(uri.path)) continue;
      final title = root.querySelector('.manga-item__title')?.text.trim() ??
          root.querySelector('img')?.attributes['alt']?.trim() ??
          '';
      if (title.isEmpty) continue;
      final latest = root
          .querySelector('a[href*="chapter-"]')
          ?.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final status = root.querySelector('.status')?.text.trim();
      found[uri.path] = MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: _image(root.querySelector('.manga-item__img img')),
        subtitle: [
          if (status != null && status.isNotEmpty) status,
          if (latest != null && latest.isNotEmpty) latest,
        ].join(' • '),
      );
    }
    return MangaCatalogPage(
      items: found.values,
      nextCursor: document.querySelector(
                'a[href*="/page/${page + 1}/"]',
              ) !=
              null
          ? '${page + 1}'
          : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final uri = _baseUri.resolve(mangaId);
    final document = await _document(uri);
    final title = document.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) throw StateError('ToonLook did not return $mangaId.');
    final taxonomy = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final kind = href.startsWith('/manga-tag/') ||
              (href == '/manhwa/' &&
                  Uri.tryParse(anchor.attributes['href'] ?? '')
                          ?.queryParameters['genre'] !=
                      null)
          ? MangaTaxonomyKind.tag
          : href.startsWith('/manga-author/') ||
                  href.startsWith('/publisher/') ||
                  href.startsWith('/artist/')
              ? MangaTaxonomyKind.artist
              : null;
      if (kind != null) {
        taxonomy['${kind.name}:$href'] =
            MangaTaxonomyLink(kind: kind, id: href, name: label);
      }
    }
    final chapters = <MangaChapter>[];
    for (final anchor in document.querySelectorAll(
      '#chaptersList a.chapter-item[href], .chapters-list a.chapter-item[href]',
    )) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = (anchor.querySelector('.chapter-item__name')?.text ??
              anchor.attributes['data-title-en'] ??
              '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (href.isEmpty ||
          label.isEmpty ||
          chapters.any((chapter) => chapter.id == href)) {
        continue;
      }
      chapters.add(MangaChapter(
        id: href,
        title: label,
        number: RegExp(r'Chapter\s+([\d.]+)', caseSensitive: false)
                .firstMatch(label)
                ?.group(1) ??
            label,
        language: anchor.attributes['data-langs']?.trim().isNotEmpty == true
            ? anchor.attributes['data-langs']!.trim()
            : 'en',
        publishedAt: _chapterDate(
          anchor.querySelector('.chapter-item__date')?.text ?? '',
        ),
      ));
    }
    final body = document.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final status = body.contains('COMPLETED')
        ? MangaStatus.completed
        : body.contains('HIATUS')
            ? MangaStatus.hiatus
            : MangaStatus.ongoing;
    final artists = taxonomy.values
        .where((link) => link.kind == MangaTaxonomyKind.artist)
        .map((link) => link.name)
        .toSet()
        .join(', ');
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: _image(document.querySelector(
          'img[alt*="${title.replaceAll('"', '')}"], .manga-cover img, main img',
        )),
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          status: status,
        ),
      ),
      description: document
              .querySelector(
                '#mangaDescContent, .description, .manga-description',
              )
              ?.text
              .trim() ??
          '',
      genres: taxonomy.values
          .where((link) => link.kind == MangaTaxonomyKind.tag)
          .map((link) => link.name)
          .toList(growable: false),
      taxonomyLinks: taxonomy.values,
      author: artists.isEmpty ? null : artists,
      artist: artists.isEmpty ? null : artists,
      status: status,
      externalUri: uri,
      chapters: chapters,
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = _baseUri.resolve(chapterId);
    final document = await _document(uri);
    final script = document
        .querySelectorAll('script')
        .map((element) => element.innerHtml)
        .firstWhere(
          (value) => value.contains('chapterData'),
          orElse: () => '',
        );
    final match = RegExp(
      r'chapterData\s*=\s*(\{.*?\})\s*;',
      dotAll: true,
    ).firstMatch(script);
    if (match == null) {
      throw StateError('ToonLook did not expose chapter data.');
    }
    final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final base =
        data['base']?.toString().replaceFirst(RegExp(r'/+$'), '') ?? '';
    final language = data['lang']?.toString() ?? '';
    final encoded = data['data']?.toString() ?? '';
    if (base.isEmpty || encoded.isEmpty) {
      throw StateError('ToonLook returned incomplete chapter data.');
    }
    final decoded = utf8.decode(base64.decode(base64.normalize(encoded)));
    final pages = (jsonDecode(decoded) as List).whereType<Map>().toList();
    final scramble =
        data['imageScramble'] is Map ? data['imageScramble'] as Map : null;
    final scrambled = scramble?['enabled'] == true;
    final stripHeight = (scramble?['stripHeight'] as num?)?.toInt() ?? 500;
    final salt = scramble?['salt']?.toString() ?? '';
    final headers = {
      ...coverImageHeaders,
      'Referer': uri.toString(),
    };
    for (final page in pages) {
      final source = page['src']?.toString() ?? '';
      if (source.isEmpty) continue;
      final imageUri =
          Uri.parse('$base/${source.replaceFirst(RegExp(r'^/+'), '')}');
      if (!scrambled) {
        yield MangaReaderPage.network(imageUri, headers: headers);
        continue;
      }
      final binaryLoader = _binaryLoader;
      final descrambler = _imageDescrambler;
      if (binaryLoader == null || descrambler == null || salt.isEmpty) {
        throw StateError('ToonLook image descrambling is unavailable.');
      }
      final response = await binaryLoader(imageUri, headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'ToonLook image returned HTTP ${response.statusCode}.',
        );
      }
      final filePath = await descrambler(
        response.body,
        imageUri,
        language,
        stripHeight,
        salt,
      );
      yield MangaReaderPage.file(filePath);
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      _baseUri.resolve(chapterId);

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.artist,
      ];
  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final document = await _document(_baseUri.resolve('/manhwa/'));
    final prefix = kind == MangaTaxonomyKind.tag ? '/manga-tag/' : '/artist/';
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll('a[href*="$prefix"]')) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isNotEmpty) {
        found[href] = MangaTaxonomyOption(id: href, name: label);
      }
    }
    final needle = query.trim().toLowerCase();
    return found.values
        .where((item) =>
            needle.isEmpty || item.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) =>
      _catalog(taxonomyId, cursor, const {});

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('ToonLook returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri? _image(Element? image) {
    for (final key in const ['data-src', 'src']) {
      final value = image?.attributes[key]?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('data:')) {
        return _baseUri.resolve(value);
      }
    }
    return null;
  }

  bool _isTitlePath(String path) => RegExp(r'^/manhwa/[^/]+/$').hasMatch(path);
  int _page(String? cursor) => int.tryParse(cursor ?? '') ?? 1;

  String? _chapterDate(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match =
        RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(normalized);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}
