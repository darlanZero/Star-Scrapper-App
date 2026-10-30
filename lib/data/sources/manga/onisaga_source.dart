import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/infrastructure/webview/browser_html_loader.dart';

typedef OniSagaHtmlLoader = Future<String> Function(Uri uri, String userAgent);
typedef OniSagaImageLoader = Future<Uint8List> Function(
  Uri uri,
  String userAgent,
);
typedef OniSagaInteractedHtmlLoader = Future<String> Function(
  Uri uri,
  String userAgent,
  String clickSelector, {
  required int maxClicks,
});

/// OniSaga — mixed English manga catalog rendered by Livewire.
class OniSagaSource
    implements
        MangaSource,
        FilterableMangaSource,
        VariantCatalogMangaSource,
        BrowserImageMangaSource,
        WebViewChapterMangaSource,
        ChapterNavigationMangaSource {
  static const _site = 'https://onisaga.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static const _pageSize = 24;

  static const _formats = [
    MangaFilterOption(value: 'MANGA', label: 'Manga'),
    MangaFilterOption(value: 'MANHWA', label: 'Manhwa'),
    MangaFilterOption(value: 'MANHUA', label: 'Manhua'),
    MangaFilterOption(value: 'NOVEL', label: 'Novel'),
    MangaFilterOption(value: 'ONE-SHOT', label: 'One-Shot'),
    MangaFilterOption(value: 'DOUJINSHI', label: 'Doujinshi'),
  ];
  static const _statuses = [
    MangaFilterOption(value: 'ongoing', label: 'Ongoing'),
    MangaFilterOption(value: 'completed', label: 'Completed'),
    MangaFilterOption(value: 'hiatus', label: 'Hiatus'),
    MangaFilterOption(value: 'cancelled', label: 'Cancelled'),
  ];
  static const _popularPeriods = [
    MangaCatalogVariant(id: 'day', label: 'Day'),
    MangaCatalogVariant(id: 'week', label: 'Week'),
    MangaCatalogVariant(id: 'month', label: 'Month'),
    MangaCatalogVariant(id: 'year', label: 'Year'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final OniSagaHtmlLoader? _browserHtmlLoader;
  final OniSagaImageLoader? _browserImageLoader;
  final OniSagaInteractedHtmlLoader? _interactedHtmlLoader;
  List<MangaFilterOption>? _genreCache;
  final Map<String, MangaDetails> _detailsCache = {};

  OniSagaSource({
    http.Client? client,
    Uri? baseUri,
    OniSagaHtmlLoader? browserHtmlLoader,
    OniSagaImageLoader? browserImageLoader,
    OniSagaInteractedHtmlLoader? interactedHtmlLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site),
        _browserHtmlLoader = browserHtmlLoader,
        _browserImageLoader = browserImageLoader,
        _interactedHtmlLoader = interactedHtmlLoader;

  @override
  String get id => 'onisaga';

  @override
  String get name => 'OniSaga';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
  Future<Uint8List> loadBrowserImage(Uri uri) {
    final loader = _browserImageLoader;
    if (loader == null) {
      throw StateError('OniSaga browser image loader is not configured.');
    }
    return loader(uri, _userAgent);
  }

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.updated,
      ];

  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      filter == MangaCatalogFilter.popular ? _popularPeriods : const [];

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) async {
    if (filter != MangaCatalogFilter.popular ||
        !_popularPeriods.any((period) => period.id == variantId)) {
      return browse(filter: filter, cursor: cursor);
    }
    final uri = _resolve('/home');
    final selector = 'button[wire\\:click="setPeriod(\'$variantId\')"]';
    final html = _interactedHtmlLoader == null
        ? await _loadHtml(uri)
        : await _interactedHtmlLoader(
            uri,
            _userAgent,
            selector,
            maxClicks: 1,
          );
    final document = html_parser.parse(html);
    final periodButton = document.querySelector(
      'button[wire\\:key="period-$variantId"]',
    );
    final section = _catalogSection(periodButton, 'Most Popular') ?? document;
    return MangaCatalogPage(items: _catalogItems(section));
  }

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    final sort = switch (filter) {
      MangaCatalogFilter.popular => 'like_count',
      MangaCatalogFilter.trending => 'view',
      MangaCatalogFilter.updated => 'release_date',
      _ => 'created_at',
    };
    return _browsePage({'sort': sort}, cursor);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return browse(cursor: cursor);
    final page = _page(cursor);
    final uri = _resolve('/search/${Uri.encodeComponent(normalized)}').replace(
      queryParameters: page > 1 ? {'page': '$page'} : null,
    );
    return _parseCatalog(await _loadHtml(uri), page);
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    return MangaSearchOptions(
      formats: _formats,
      statuses: _statuses,
      genres: await _genres(),
      sorts: const [
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.mostViewed,
        MangaSearchSort.releaseDate,
        MangaSearchSort.mostLiked,
        MangaSearchSort.titleAscending,
        MangaSearchSort.rating,
        MangaSearchSort.fanFavorites,
      ],
      supportsReleaseDateRange: true,
      supportsChapterRange: true,
    );
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    final parameters = <String, String>{
      if (request.formats.isNotEmpty) 'platform': request.formats.first,
      if (request.statuses.isNotEmpty) 'status': request.statuses.first,
      if (request.minimumChapters != null)
        'min_chapters': '${request.minimumChapters}',
      if (_date(request.releaseStart) case final date?) 'release_start': date,
      if (_date(request.releaseEnd) case final date?) 'release_end': date,
      'sort': switch (request.sort) {
        MangaSearchSort.mostViewed => 'view',
        MangaSearchSort.releaseDate => 'release_date',
        MangaSearchSort.mostLiked => 'like_count',
        MangaSearchSort.title || MangaSearchSort.titleAscending => 'title',
        MangaSearchSort.rating => 'vote_average',
        MangaSearchSort.fanFavorites => 'fan_favorites',
        _ => 'created_at',
      },
    };
    var genreIndex = 0;
    for (final genre in request.genres) {
      parameters['genre[${genreIndex++}]'] = genre;
    }
    return _browsePage(parameters, cursor);
  }

  Future<MangaCatalogPage> _browsePage(
    Map<String, String> parameters,
    String? cursor,
  ) async {
    final page = _page(cursor);
    final uri = _resolve('/browse').replace(queryParameters: {
      ...parameters,
      if (page > 1) 'page': '$page',
    });
    return _parseCatalog(await _loadHtml(uri), page);
  }

  MangaCatalogPage _parseCatalog(String html, int page) {
    final items = _catalogItems(html_parser.parse(html));
    return MangaCatalogPage(
      items: items,
      nextCursor: items.length >= _pageSize ? '${page + 1}' : null,
    );
  }

  List<MangaCatalogItem> _catalogItems(Node root) {
    final seen = <String>{};
    final items = <MangaCatalogItem>[];
    final anchors = root is Document
        ? root.querySelectorAll('a[href*="/manga/"]')
        : (root as Element).querySelectorAll('a[href*="/manga/"]');
    for (final anchor in anchors) {
      final uri = _uri(anchor.attributes['href']);
      if (uri == null || !uri.path.startsWith('/manga/')) continue;
      final slug = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
      final title = _text(anchor).isNotEmpty
          ? _text(anchor)
          : (anchor.attributes['aria-label'] ??
                  anchor.attributes['title'] ??
                  '')
              .trim();
      if (slug.isEmpty || title.isEmpty || !seen.add(slug)) continue;
      final container = _cardContainer(anchor);
      final cover = _uri(
        container?.querySelector('img')?.attributes['src'] ??
            container
                ?.querySelector('source')
                ?.attributes['srcset']
                ?.split(' ')
                .first,
      );
      final cardText = _text(container);
      final format = _formats.map((option) => option.label).firstWhere(
            (value) =>
                RegExp('\\b${RegExp.escape(value)}\\b', caseSensitive: false)
                    .hasMatch(cardText),
            orElse: () => '',
          );
      final status = _statusFromText(cardText);
      final rating = double.tryParse(
        RegExp(r'\b(10(?:\.0)?|[0-9](?:\.[0-9])?)\b')
                .firstMatch(cardText)
                ?.group(1) ??
            '',
      );
      items.add(MangaCatalogItem(
        id: slug,
        title: title,
        coverUri: cover,
        subtitle: mangaCatalogSubtitle(
          format: format.isEmpty ? null : format,
          status: status,
          rating: rating,
        ),
      ));
    }
    return items;
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _slug(mangaId);
    final cached = _detailsCache[slug];
    if (cached != null) return cached;
    final uri = _resolve('/manga/$slug');
    final html = _interactedHtmlLoader == null
        ? await _loadHtml(uri)
        : await _interactedHtmlLoader(
            uri,
            _userAgent,
            'button[wire\\:click="loadMoreChapters"]',
            maxClicks: 20,
          );
    final document = html_parser.parse(html);
    final h1 = document.querySelector('h1');
    final title = _text(h1);
    if (title.isEmpty) {
      throw StateError('OniSaga did not expose details for "$mangaId".');
    }
    final hero = h1?.parent;
    final heroText = _text(hero);
    final cover = _uri(
      document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'],
    );
    final description =
        hero?.querySelector('p[class*="leading-relaxed"]')?.text.trim() ??
            document
                .querySelector('meta[name="description"]')
                ?.attributes['content']
                ?.trim() ??
            '';
    final authors = hero
            ?.querySelectorAll('a[href*="/author/"]')
            .map(_text)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList() ??
        const <String>[];
    final genres = hero
            ?.querySelectorAll('a[href*="/genre/"]')
            .map(_text)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList() ??
        const <String>[];
    final altText =
        hero?.querySelector('p[class*="italic"]')?.text.trim() ?? '';
    final altTitles = altText
        .split('|')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != title)
        .map((value) => {'': value})
        .toList();
    final status = _statusFromText(heroText);
    final format = _formats.map((option) => option.label).firstWhere(
          (value) =>
              RegExp('\\b${RegExp.escape(value)}\\b', caseSensitive: false)
                  .hasMatch(heroText),
          orElse: () => '',
        );
    final chapters = _chapters(document, slug);
    final year = int.tryParse(
      RegExp(r'\b(19|20)\d{2}\b').firstMatch(heroText)?.group(0) ?? '',
    );
    final item = MangaCatalogItem(
      id: slug,
      title: title,
      coverUri: cover,
      subtitle: mangaCatalogSubtitle(
        totalChapters: chapters.length,
        format: format.isEmpty ? null : format,
        status: status,
        year: year,
      ),
    );
    return _detailsCache[slug] = MangaDetails(
      item: item,
      description: description,
      alternativeTitles: altTitles,
      genres: genres,
      author: authors.isEmpty ? null : authors.join(', '),
      status: status,
      externalUri: uri,
      chapters: chapters,
    );
  }

  List<MangaChapter> _chapters(Document document, String slug) {
    final seen = <String>{};
    final chapters = <MangaChapter>[];
    for (final anchor in document.querySelectorAll('a[href*="/read/$slug/"]')) {
      final uri = _uri(anchor.attributes['href']);
      if (uri == null || !seen.add(uri.toString())) continue;
      final text = _text(anchor);
      final number = RegExp(r'Chapter\s+([^\s·]+)', caseSensitive: false)
              .firstMatch(text)
              ?.group(1) ??
          RegExp(r'^\s*([\d.]+)').firstMatch(text)?.group(1) ??
          '';
      if (number.isEmpty) continue;
      final volume = RegExp(r'Vol\.\s*([^\s·]+)', caseSensitive: false)
          .firstMatch(text)
          ?.group(1);
      final pages =
          RegExp(r'(\d+)p\b', caseSensitive: false).firstMatch(text)?.group(1);
      chapters.add(MangaChapter(
        id: uri.toString(),
        title: 'Chapter $number',
        number: number,
        volume: volume,
        language: 'en',
        pages: pages,
      ));
    }
    chapters.sort((a, b) => _chapterNumber(b).compareTo(_chapterNumber(a)));
    return chapters;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = chapterWebUri(mangaId: mangaId, chapterId: chapterId);
    var pageCount = 0;
    try {
      final details = await getDetails(mangaId);
      final chapter = details.chapters
          .where((entry) => entry.id == uri.toString())
          .firstOrNull;
      pageCount = int.tryParse(chapter?.pages ?? '') ?? 0;
    } catch (_) {
      pageCount = 0;
    }
    yield* BrowserHtmlLoader.readerPages(uri, _userAgent, pageCount)
        .map(MangaReaderPage.file);
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) {
    final parsed = Uri.tryParse(chapterId);
    if (parsed != null && parsed.hasScheme) return parsed;
    if (chapterId.startsWith('/')) return _baseUri.resolve(chapterId);
    return _resolve('/read/${_slug(mangaId)}/$chapterId');
  }

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) async {
    final chapters = (await getDetails(mangaId)).chapters;
    final index = chapters.indexWhere((entry) => entry.id == currentChapterId);
    return index > 0 ? chapters[index - 1].id : null;
  }

  @override
  Future<String?> previousChapterId(
    String mangaId,
    String currentChapterId,
  ) async {
    final chapters = (await getDetails(mangaId)).chapters;
    final index = chapters.indexWhere((entry) => entry.id == currentChapterId);
    return index >= 0 && index + 1 < chapters.length
        ? chapters[index + 1].id
        : null;
  }

  Future<List<MangaFilterOption>> _genres() async {
    final cached = _genreCache;
    if (cached != null) return cached;
    final document = html_parser.parse(await _loadHtml(_resolve('/browse')));
    final genres = <MangaFilterOption>[];
    for (final input in document.querySelectorAll('input[name="genre[]"]')) {
      final value = input.attributes['value']?.trim() ?? '';
      final inputId = input.id;
      final label = inputId.isEmpty
          ? ''
          : _text(document.querySelector('label[for="$inputId"]'));
      if (value.isNotEmpty && label.isNotEmpty) {
        genres.add(MangaFilterOption(value: value, label: label));
      }
    }
    genres.sort((a, b) => a.label.compareTo(b.label));
    return _genreCache = List.unmodifiable(genres);
  }

  Future<String> _loadHtml(Uri uri) async {
    if (_browserHtmlLoader != null) {
      return _browserHtmlLoader(uri, _userAgent);
    }
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'OniSaga returned HTTP ${response.statusCode}',
        uri,
      );
    }
    return response.body;
  }

  Element? _cardContainer(Element anchor) {
    Element? current = anchor;
    for (var depth = 0; depth < 7 && current != null; depth++) {
      if (current.querySelector('img') != null &&
          current.querySelectorAll('a[href*="/manga/"]').isNotEmpty) {
        return current;
      }
      current = current.parent;
    }
    return anchor.parent;
  }

  Node? _catalogSection(Element? anchor, String heading) {
    Element? current = anchor;
    for (var depth = 0; depth < 8 && current != null; depth++) {
      if (_text(current).contains(heading) &&
          current.querySelectorAll('a[href*="/manga/"]').length >= 5) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  MangaStatus _statusFromText(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('completed')) return MangaStatus.completed;
    if (lower.contains('ongoing')) return MangaStatus.ongoing;
    if (lower.contains('hiatus')) return MangaStatus.hiatus;
    if (lower.contains('cancelled') || lower.contains('canceled')) {
      return MangaStatus.cancelled;
    }
    return MangaStatus.unknown;
  }

  String? _date(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (iso != null) return text;
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (us == null) return null;
    final month = int.tryParse(us.group(1)!);
    final day = int.tryParse(us.group(2)!);
    final year = int.tryParse(us.group(3)!);
    if (month == null || day == null || year == null) return null;
    final parsed = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );
    if (parsed == null || parsed.month != month || parsed.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  double _chapterNumber(MangaChapter chapter) =>
      double.tryParse(chapter.number) ?? -1;

  int _page(String? cursor) => int.tryParse(cursor ?? '') ?? 1;

  String _slug(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.pathSegments.contains('manga')) {
      final index = uri.pathSegments.indexOf('manga');
      if (index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }
    return value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  String _text(Node? node) =>
      node?.text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri _resolve(String path) => _baseUri.resolve(path);
}
