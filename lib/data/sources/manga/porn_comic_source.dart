import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Adult, all-languages image catalog backed by porn-comic.com.
///
/// The provider has four image-oriented feeds and uses one HTML document per
/// reader page. Animation and cosplay videos are exposed by the sibling typed
/// anime source so they can use the native video player.
class PornComicMangaSource
    implements
        MangaSource,
        VariantCatalogMangaSource,
        TaxonomyBrowsableMangaSource {
  static const _site = 'https://porn-comic.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _feeds = [
    MangaCatalogVariant(id: 'h', label: 'Hentai manga'),
    MangaCatalogVariant(id: 'hentai', label: 'Doujin pictures'),
    MangaCatalogVariant(id: 'full_color', label: 'Full color'),
    MangaCatalogVariant(id: 'western', label: 'Western'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, MangaDetails> _detailsCache = {};

  PornComicMangaSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'porn_comic';

  @override
  String get name => 'Porn-Comic';

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
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      _feeds;

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) =>
      browseVariant(filter, 'h', cursor: cursor);

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) async {
    final feed = _feeds.any((item) => item.id == variantId) ? variantId : 'h';
    final page = int.tryParse(cursor ?? '') ?? 1;
    final document = await _getDocument(_feedUri(feed, page));
    final items = filter == MangaCatalogFilter.popular
        ? _sidebarItems(document, feed)
        : _catalogItems(document, feed: feed);
    return MangaCatalogPage(
      items: items,
      nextCursor: filter == MangaCatalogFilter.recent &&
              document.querySelector('.page a.a1[href*="${page + 1}"]') != null
          ? '${page + 1}'
          : null,
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return browse(cursor: cursor);
    final page = int.tryParse(cursor ?? '') ?? 1;
    final uri = _baseUri.resolve('/').replace(queryParameters: {
      'q': normalized,
      if (page > 1) 'page': '$page',
    });
    final document = await _getDocument(uri);
    final items = _catalogItems(document)
        .where((item) => !_isVideoPath(Uri.parse(item.id).path))
        .toList(growable: false);
    final hasNext =
        document.querySelector('.page a.a1[href*="${page + 1}"]') != null;
    return MangaCatalogPage(
      items: items,
      nextCursor: hasNext ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final cached = _detailsCache[mangaId];
    if (cached != null) return cached;
    final uri = _resolve(mangaId);
    final document = await _getDocument(uri);
    final details = uri.path.contains('/western/comic-')
        ? _westernDetails(document, uri)
        : _galleryDetails(document, uri);
    _detailsCache[mangaId] = details;
    return details;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final firstUri = _resolve(chapterId);
    final first = await _getDocument(firstUri);
    final pageCount = _readerPageCount(first);
    final firstImage = _imageUri(first.querySelector('.manga-picture img'));
    if (firstImage == null) return;
    yield MangaReaderPage.network(firstImage, headers: coverImageHeaders);

    for (var page = 2; page <= pageCount; page++) {
      // Gallery feeds use a stable `<gallery>_<page>.<extension>` convention.
      // Resolve the media CDN directly because the HTML reader starts
      // returning HTTP 429 after roughly 20 consecutive page requests.
      final direct = await _directGalleryPage(firstImage, page);
      if (direct != null) {
        yield MangaReaderPage.network(direct, headers: coverImageHeaders);
        continue;
      }

      // Western chapters have random per-page names, so retain a paced and
      // retryable HTML fallback for them.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final document = await _getDocument(
        _pagedReaderUri(firstUri, page),
        retryRateLimit: true,
      );
      final image = _imageUri(document.querySelector('.manga-picture img'));
      if (image != null) {
        yield MangaReaderPage.network(image, headers: coverImageHeaders);
      }
    }
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.artist,
        MangaTaxonomyKind.character,
        MangaTaxonomyKind.parody,
      ];

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final routes = switch (kind) {
      MangaTaxonomyKind.tag => const ['/h', '/tags/full-color.html'],
      MangaTaxonomyKind.artist => const ['/hentai', '/cos'],
      MangaTaxonomyKind.character || MangaTaxonomyKind.parody => const [
          '/tags/full-color.html'
        ],
      _ => const <String>[],
    };
    final prefix = switch (kind) {
      MangaTaxonomyKind.tag => '/tags/',
      MangaTaxonomyKind.artist => '/artist/',
      MangaTaxonomyKind.character => '/characters/',
      MangaTaxonomyKind.parody => '/anime/',
      _ => '',
    };
    final options = <String, MangaTaxonomyOption>{};
    for (final route in routes) {
      final document = await _getDocument(_baseUri.resolve(route));
      for (final anchor
          in document.querySelectorAll('.right a[href^="$prefix"]')) {
        final href = anchor.attributes['href']?.trim() ?? '';
        final name = anchor.text.trim().isNotEmpty
            ? anchor.text.trim()
            : anchor.attributes['title']?.trim() ?? '';
        if (href.isEmpty || name.isEmpty) continue;
        options[href] = MangaTaxonomyOption(
          id: href,
          name: name,
          imageUri: _imageUri(anchor.querySelector('img')),
        );
      }
    }
    final normalized = query.trim().toLowerCase();
    return options.values
        .where((item) =>
            normalized.isEmpty || item.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final base = _resolve(taxonomyId);
    final uri = page == 1
        ? base
        : base.replace(path: base.path.replaceFirst('.html', '-$page.html'));
    final document = await _getDocument(uri);
    return MangaCatalogPage(
      items: _catalogItems(document),
      nextCursor:
          document.querySelector('.page a.a1[href*="${page + 1}"]') != null
              ? '${page + 1}'
              : null,
    );
  }

  MangaDetails _galleryDetails(Document document, Uri uri) {
    final title = document.querySelector('h1.title')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        uri.pathSegments.last;
    final cover = _imageUri(document.querySelector('.manga-picture img'));
    final tags = document
        .querySelectorAll('.manga-tags a, .summary a')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final taxonomyLinks = _taxonomyLinks(document);
    final artist =
        document.querySelector('.summary a[href^="/artist/"]')?.text.trim();
    final language = document.querySelector('.info .lang_cat')?.text.trim() ??
        'All languages';
    final count = _readerPageCount(document);
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: cover,
        subtitle: '$count pages • $language',
      ),
      genres: tags,
      taxonomyLinks: taxonomyLinks,
      artist: artist,
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: uri.path,
          title: 'Gallery',
          number: '1',
          language: _languageCode(language),
          pages: '$count',
        ),
      ],
    );
  }

  MangaDetails _westernDetails(Document document, Uri uri) {
    final title = document.querySelector('.webtoon-desc h1')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        uri.pathSegments.last;
    final cover = _imageUri(document.querySelector('.webtoon-thumb img'));
    final description =
        document.querySelector('.webtoon-content')?.text.trim() ?? '';
    final chapters = document
        .querySelectorAll('dd.chapters')
        .map((element) {
          final anchor = element.querySelector('a.chapter-name[href]') ??
              element.querySelector('a[href]');
          final id = anchor?.attributes['href']?.trim() ?? '';
          final label = element.querySelector('h3')?.text.trim() ?? 'Chapter';
          final number = RegExp(r'[\d.]+').firstMatch(label)?.group(0) ?? label;
          return id.isEmpty
              ? null
              : MangaChapter(
                  id: id,
                  title: label,
                  number: number,
                  language: 'en',
                  publishedAt: element.querySelector('.time')?.text.trim(),
                );
        })
        .whereType<MangaChapter>()
        .toList(growable: false);
    final tags = document
        .querySelectorAll('.summary a[href^="/tags/"]')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final taxonomyLinks = _taxonomyLinks(document);
    final statusText = document.querySelector('.summary')?.text ?? '';
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: cover,
        subtitle: '${chapters.length} Ch • Western',
      ),
      description: description,
      genres: tags,
      taxonomyLinks: taxonomyLinks,
      artist:
          document.querySelector('.summary a[href^="/artist/"]')?.text.trim(),
      status: statusText.toLowerCase().contains('ongoing')
          ? MangaStatus.ongoing
          : MangaStatus.completed,
      externalUri: uri,
      chapters: chapters,
    );
  }

  List<MangaCatalogItem> _catalogItems(Document document, {String? feed}) {
    final elements = <Element>[
      ...document.querySelectorAll('#list > li'),
      ...document.querySelectorAll('#doujin_album > li.western'),
    ];
    final seen = <String>{};
    return elements
        .map((element) {
          final anchor = element.querySelector('a.thumb[href]') ??
              element.querySelector('h3 a[href]');
          final href = anchor?.attributes['href']?.trim() ?? '';
          if (href.isEmpty || !seen.add(href)) return null;
          final title = anchor?.attributes['title']?.trim().isNotEmpty == true
              ? anchor!.attributes['title']!.trim()
              : (element.querySelector('h3 a, span > a')?.text.trim() ??
                  anchor?.text.trim() ??
                  '');
          if (title.isEmpty) return null;
          final meta = [
            element.querySelector('.lang')?.text.trim(),
            element.querySelector('.media')?.text.trim(),
            element.querySelector('.view, .views')?.text.trim(),
          ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');
          return MangaCatalogItem(
            id: href,
            title: title,
            coverUri:
                _imageUri(element.querySelector('img, picture source[srcset]')),
            subtitle: meta.isEmpty ? _feedLabel(feed) : meta,
          );
        })
        .whereType<MangaCatalogItem>()
        .toList(growable: false);
  }

  List<MangaCatalogItem> _sidebarItems(Document document, String feed) {
    final selector = feed == 'western'
        ? '.right .special-ranking a.thumb[href], .right .ranking a[href]'
        : '.right .ranking a[href]';
    final seen = <String>{};
    final items = document
        .querySelectorAll(selector)
        .map((anchor) {
          final href = anchor.attributes['href']?.trim() ?? '';
          if (href.isEmpty || !seen.add(href)) return null;
          final title = anchor.attributes['title']?.trim().isNotEmpty == true
              ? anchor.attributes['title']!.trim()
              : anchor.querySelector('img')?.attributes['alt']?.trim() ??
                  anchor.text.trim();
          if (title.isEmpty) return null;
          return MangaCatalogItem(
            id: href,
            title: title,
            coverUri: _imageUri(anchor.querySelector('img')),
            subtitle: '${_feedLabel(feed)} • Popular',
          );
        })
        .whereType<MangaCatalogItem>()
        .toList(growable: false);
    return items.isEmpty ? _catalogItems(document, feed: feed) : items;
  }

  Uri _feedUri(String feed, int page) {
    final path = switch (feed) {
      'hentai' => page == 1 ? '/hentai' : '/hentai/index-$page.html',
      'full_color' =>
        page == 1 ? '/tags/full-color.html' : '/tags/full-color-$page.html',
      'western' => page == 1 ? '/western' : '/western/index-$page.html',
      _ => page == 1 ? '/h' : '/h/index-$page.html',
    };
    return _baseUri.resolve(path);
  }

  Uri _pagedReaderUri(Uri firstUri, int page) => firstUri.replace(
        path: firstUri.path.replaceFirst('.html', '-$page.html'),
      );

  int _readerPageCount(Document document) {
    var count = 1;
    for (final anchor in document.querySelectorAll('#pages a[href]')) {
      final match = RegExp(r'-(\d+)\.html$')
          .firstMatch(anchor.attributes['href']?.trim() ?? '');
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > count) count = value;
    }
    return count;
  }

  Future<Uri?> _directGalleryPage(Uri firstImage, int page) async {
    final match =
        RegExp(r'^(.*_)1\.([a-zA-Z0-9]+)$').firstMatch(firstImage.path);
    if (match == null) return null;
    final extensions = <String>{
      match.group(2)!.toLowerCase(),
      'webp',
      'jpg',
      'jpeg',
      'png',
      'gif',
    };
    for (final extension in extensions) {
      final candidate = firstImage.replace(
        path: '${match.group(1)}$page.$extension',
      );
      try {
        final response =
            await _client.head(candidate, headers: coverImageHeaders);
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            contentType.startsWith('image/')) {
          return candidate;
        }
      } catch (_) {
        // Missing candidates are normal when a page changes extension.
      }
    }
    return null;
  }

  Future<Document> _getDocument(
    Uri uri, {
    bool retryRateLimit = false,
  }) async {
    final attempts = retryRateLimit ? 4 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final response = await _client.get(uri, headers: requestHeaders);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return html_parser.parse(response.body);
      }
      if (response.statusCode != 429 || attempt == attempts - 1) {
        throw Exception('Porn-Comic: HTTP ${response.statusCode}');
      }
      await Future<void>.delayed(Duration(seconds: 2 << attempt));
    }
    throw StateError('Porn-Comic exhausted its reader retries.');
  }

  Uri _resolve(String value) => _baseUri.resolve(value);

  Uri? _imageUri(Element? image) {
    final value = image?.attributes['src']?.trim() ??
        image?.attributes['data-src']?.trim() ??
        image?.attributes['srcset']?.split(' ').first.trim() ??
        image?.parent
            ?.querySelector('source')
            ?.attributes['srcset']
            ?.split(' ')
            .first
            .trim();
    if (value == null || value.isEmpty) return null;
    return _baseUri.resolve(value);
  }

  List<MangaTaxonomyLink> _taxonomyLinks(Document document) {
    final links = <String, MangaTaxonomyLink>{};
    for (final anchor
        in document.querySelectorAll('.summary a, .manga-tags a')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final name = anchor.text.trim();
      if (href.isEmpty || name.isEmpty) continue;
      final kind = switch (href) {
        final value when value.startsWith('/tags/') => MangaTaxonomyKind.tag,
        final value when value.startsWith('/artist/') =>
          MangaTaxonomyKind.artist,
        final value when value.startsWith('/characters/') =>
          MangaTaxonomyKind.character,
        final value when value.startsWith('/anime/') =>
          MangaTaxonomyKind.parody,
        final value when value.startsWith('/circle/') =>
          MangaTaxonomyKind.circle,
        _ => null,
      };
      if (kind != null) {
        links['${kind.name}:$href'] =
            MangaTaxonomyLink(kind: kind, id: href, name: name);
      }
    }
    return links.values.toList(growable: false);
  }

  bool _isVideoPath(String path) =>
      path.startsWith('/gif/') || path.startsWith('/cos/');

  String _feedLabel(String? feed) => switch (feed) {
        'hentai' => 'Doujin pictures',
        'full_color' => 'Full color',
        'western' => 'Western',
        _ => 'Hentai manga',
      };

  String _languageCode(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('english')) return 'en';
    if (normalized.contains('japanese')) return 'ja';
    if (normalized.contains('chinese')) return 'zh';
    if (normalized.contains('korean')) return 'ko';
    return 'und';
  }
}
