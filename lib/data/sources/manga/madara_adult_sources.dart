import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

typedef MadaraHtmlLoader = Future<String> Function(
  Uri uri,
  String userAgent,
);

abstract class MadaraAdultSource
    implements
        MangaSource,
        VariantCatalogMangaSource,
        TaxonomyBrowsableMangaSource {
  static const userAgent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client client;
  final Uri siteUri;

  MadaraAdultSource({required Uri baseUri, http.Client? client})
      : client = client ?? http.Client(),
        siteUri = baseUri;

  String get catalogPath;
  List<MangaCatalogVariant> get variants;
  String pathForVariant(String variantId) => catalogPath;

  @override
  Uri get baseUri => siteUri;
  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': siteUri.toString(),
        'User-Agent': userAgent,
      };
  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': siteUri.toString(),
        'User-Agent': userAgent,
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
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      variants;

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) =>
      browseVariant(filter, variants.first.id, cursor: cursor);

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    final order = switch (filter) {
      MangaCatalogFilter.alphabetical => 'alphabet',
      MangaCatalogFilter.popular => 'rating',
      MangaCatalogFilter.trending => 'trending',
      MangaCatalogFilter.updated => 'views',
      MangaCatalogFilter.added => 'new-manga',
      _ => 'latest',
    };
    return catalog(pathForVariant(variantId), cursor, {'m_orderby': order});
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return catalog('/', cursor, {'s': value, 'post_type': 'wp-manga'});
  }

  Future<MangaCatalogPage> catalog(
    String path,
    String? cursor,
    Map<String, String> query,
  ) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final normalized = path.endsWith('/') ? path : '$path/';
    final route = page == 1 ? normalized : '${normalized}page/$page/';
    final document = await getDocument(
      siteUri.resolve(route).replace(queryParameters: query),
    );
    final found = <String, MangaCatalogItem>{};
    final roots = <Element>{
      ...document.querySelectorAll('.page-item-detail.manga'),
      ...document.querySelectorAll('.c-tabs-item__content'),
      ...document.querySelectorAll('.row.c-tabs-item__content'),
      ...document.querySelectorAll('.slider__item'),
    };
    for (final root in roots) {
      final anchor = root.querySelector('.post-title a[href]') ??
          root.querySelector('.item-thumb a[href]') ??
          root.querySelector('.slider__thumb a[href]');
      final href = anchor?.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final uri = siteUri.resolve(href);
      if (uri.host != siteUri.host || _isChapter(uri.path)) continue;
      final title =
          root.querySelector('.post-title a')?.text.trim().isNotEmpty == true
              ? root.querySelector('.post-title a')!.text.trim()
              : anchor?.attributes['title']?.trim() ??
                  root.querySelector('img')?.attributes['alt']?.trim() ??
                  '';
      if (title.isEmpty) continue;
      final chapter = root
          .querySelector('.list-chapter .chapter a, .chapter-item .chapter a')
          ?.text
          .trim();
      final badge = root.querySelector('.manga-title-badges')?.text.trim();
      final rating =
          double.tryParse(root.querySelector('.score')?.text.trim() ?? '');
      found[uri.path] = MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri:
            image(root.querySelector('.item-thumb img, .slider__thumb img')),
        subtitle: [
          if (badge != null && badge.isNotEmpty) badge,
          mangaCatalogSubtitle(latestChapter: chapter, rating: rating),
        ].where((value) => value.isNotEmpty).join(' • '),
      );
    }
    final hasNext = document.querySelector(
          'a[href*="/page/${page + 1}/"], a.next, .wp-pagenavi .nextpostslink',
        ) !=
        null;
    return MangaCatalogPage(
      items: found.values,
      nextCursor: hasNext || found.length >= 20 ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final normalizedId = mangaId.endsWith('/') ? mangaId : '$mangaId/';
    final uri = siteUri.resolve(normalizedId);
    final document = await getDocument(uri);
    final title = document
            .querySelector('.post-title h1, .profile-manga h1, h1')
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';
    if (title.isEmpty) throw StateError('$name did not return $mangaId.');
    final taxonomy = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '.genres-content a, .tags-content a, .artist-content a, '
      '.author-content a, a[href*="manga-tag"], a[href*="manga-genre"]',
    )) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final kind = href.contains('artist') || href.contains('author')
          ? MangaTaxonomyKind.artist
          : MangaTaxonomyKind.tag;
      taxonomy['${kind.name}:$href'] =
          MangaTaxonomyLink(kind: kind, id: href, name: label);
    }
    final chapters = <MangaChapter>[];
    final chapterRoots = document.querySelectorAll(
      '.wp-manga-chapter, .listing-chapters_wrap li',
    );
    for (final root in chapterRoots) {
      final anchor = root.querySelector('a[href]');
      if (anchor == null) continue;
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
      if (!_isChapter(href) || chapters.any((item) => item.id == href)) {
        continue;
      }
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final dateNode = root.querySelector('.chapter-release-date');
      final publishedAt = _normalizedChapterDate(
        dateNode?.querySelector('[title]')?.attributes['title']?.trim() ??
            dateNode?.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
      );
      chapters.add(MangaChapter(
        id: href,
        title: label,
        number: RegExp(r'[\d.]+').firstMatch(label)?.group(0) ?? label,
        language: 'en',
        publishedAt: publishedAt,
      ));
    }
    final statusText = metadata(document, 'Status').toLowerCase();
    final status = statusText.contains('complete')
        ? MangaStatus.completed
        : statusText.contains('hiatus')
            ? MangaStatus.hiatus
            : statusText.contains('drop')
                ? MangaStatus.cancelled
                : MangaStatus.ongoing;
    final creators = taxonomy.values
        .where((item) => item.kind == MangaTaxonomyKind.artist)
        .map((item) => item.name)
        .toSet()
        .join(', ');
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: image(
            document.querySelector('.summary_image img, .tab-summary img')),
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          status: status,
        ),
      ),
      description: document
              .querySelector(
                  '.description-summary, .summary__content, .manga-excerpt')
              ?.text
              .trim() ??
          '',
      genres: taxonomy.values
          .where((item) => item.kind == MangaTaxonomyKind.tag)
          .map((item) => item.name),
      taxonomyLinks: taxonomy.values,
      author: creators.isEmpty ? metadata(document, 'Author') : creators,
      artist: creators.isEmpty ? metadata(document, 'Artist') : creators,
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
    final uri = siteUri.resolve(chapterId);
    final document = await getDocument(uri);
    final seen = <Uri>{};
    for (final node in document.querySelectorAll(
      '.reading-content img, .page-break img, .chapter-content img',
    )) {
      final page = image(node);
      if (page != null && seen.add(page)) {
        yield MangaReaderPage.network(page, headers: {
          ...coverImageHeaders,
          'Referer': uri.toString(),
        });
      }
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
    final document = await getDocument(siteUri.resolve(catalogPath));
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll(
      'a[href*="manga-genre"], a[href*="manga-tag"], .genres_wrap a',
    )) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
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
      catalog(taxonomyId, cursor, const {});

  Future<Document> getDocument(Uri uri) async {
    final response = await client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$name returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri? image(Element? node) {
    for (final key in const ['data-src', 'data-lazy-src', 'src']) {
      final value = node?.attributes[key]?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('data:')) {
        return siteUri.resolve(value);
      }
    }
    return null;
  }

  String metadata(Document document, String heading) {
    for (final item in document.querySelectorAll('.post-content_item')) {
      final key = item
              .querySelector('.summary-heading')
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '';
      if (key.toLowerCase().replaceAll(':', '') == heading.toLowerCase()) {
        return item.querySelector('.summary-content')?.text.trim() ?? '';
      }
    }
    return '';
  }

  bool _isChapter(String path) =>
      path.contains('/chapter-') || RegExp(r'/chapter/[^/]+').hasMatch(path);

  String? _normalizedChapterDate(String? value) {
    final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (text.isEmpty) return null;
    final match = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})$',
    ).firstMatch(text);
    if (match == null) return text;
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = months[match.group(2)!.substring(0, 3).toLowerCase()];
    if (month == null) return text;
    final day = int.parse(match.group(1)!);
    final year = int.parse(match.group(3)!);
    return '$year-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}

class PornhwazSource extends MadaraAdultSource {
  PornhwazSource({super.client, Uri? baseUri})
      : super(
          baseUri: baseUri ?? Uri.parse('https://www.pornhwaz.com/'),
        );

  @override
  String get id => 'pornhwaz';
  @override
  String get name => 'Pornhwaz';
  @override
  String get catalogPath => '/webtoon/';
  @override
  List<MangaCatalogVariant> get variants => const [
        MangaCatalogVariant(id: 'webtoon', label: 'Webtoon'),
      ];

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
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    final order = switch (filter) {
      MangaCatalogFilter.alphabetical => 'alphabet',
      MangaCatalogFilter.popular => 'rating',
      MangaCatalogFilter.trending => 'trending',
      MangaCatalogFilter.updated => 'views',
      MangaCatalogFilter.added => 'new-manga',
      _ => 'latest',
    };
    return catalog(pathForVariant(variantId), cursor, {'m_orderby': order});
  }
}

class CartoonPornMangaSource extends MadaraAdultSource {
  final MadaraHtmlLoader? _browserHtmlLoader;

  CartoonPornMangaSource({
    super.client,
    Uri? baseUri,
    MadaraHtmlLoader? browserHtmlLoader,
  })  : _browserHtmlLoader = browserHtmlLoader,
        super(
          baseUri: baseUri ?? Uri.parse('https://cartoonporn.to/'),
        );

  @override
  String get id => 'cartoon_porn_manga';
  @override
  String get name => 'Cartoon Porn Comics';
  @override
  String get catalogPath => '/porncomic/';
  @override
  List<MangaCatalogVariant> get variants => const [
        MangaCatalogVariant(id: 'comics', label: 'Comics'),
      ];

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.parody,
        MangaTaxonomyKind.character,
        MangaTaxonomyKind.artist,
      ];

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final route = switch (kind) {
      MangaTaxonomyKind.parody => '/parodies/',
      MangaTaxonomyKind.character => '/characters/',
      MangaTaxonomyKind.artist => '/artists/',
      _ => '/tags/',
    };
    final document = await getDocument(siteUri.resolve(route));
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll(
      '.terms-list a.term-link[href], a.term-link[href]',
    )) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = (anchor.querySelector('.term-name')?.text ?? anchor.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (label.isEmpty) continue;
      final countText =
          anchor.querySelector('.term-count')?.text ?? anchor.text;
      final count = int.tryParse(
        (RegExp(r'([\d,]+)').firstMatch(countText)?.group(1) ?? '')
            .replaceAll(',', ''),
      );
      found[href] = MangaTaxonomyOption(
        id: href,
        name: label.replaceFirst(RegExp(r'\s*\(?[\d,]+\)?\s*$'), ''),
        titleCount: count,
      );
    }
    final needle = query.trim().toLowerCase();
    return found.values
        .where((item) =>
            needle.isEmpty || item.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final normalizedId = mangaId.endsWith('/') ? mangaId : '$mangaId/';
    final uri = siteUri.resolve(normalizedId);
    var document = await getDocument(uri);
    if (document.querySelector('#chapters li') == null &&
        _browserHtmlLoader != null) {
      document = html_parser.parse(
        await _browserHtmlLoader(uri, MadaraAdultSource.userAgent),
      );
    }
    final title = document
            .querySelector('.comic-hero__title, h1')
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';
    if (title.isEmpty) throw StateError('$name did not return $mangaId.');

    final taxonomy = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '.comic-hero__meta-grid a[href], .comic-hero a.meta-tag[href]',
    )) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final classes = anchor.classes;
      final kind = classes.contains('meta-tag--artist') ||
              href.startsWith('/artist/')
          ? MangaTaxonomyKind.artist
          : classes.contains('meta-tag--series') || href.startsWith('/series/')
              ? MangaTaxonomyKind.parody
              : classes.contains('meta-tag--character') ||
                      href.startsWith('/character/')
                  ? MangaTaxonomyKind.character
                  : classes.contains('meta-tag--genre') ||
                          href.startsWith('/tag/')
                      ? MangaTaxonomyKind.tag
                      : null;
      if (kind == null) continue;
      taxonomy['${kind.name}:$href'] =
          MangaTaxonomyLink(kind: kind, id: href, name: label);
    }

    final chapters = <MangaChapter>[];
    final chapterRoots = <Element>{
      ...document.querySelectorAll('#chapters li, .chapters-preview li'),
      ...document.querySelectorAll('.wp-manga-chapter'),
      ...document.querySelectorAll(
        '#chapters a[href*="-chapter-"], '
        '.chapters-preview a[href*="-chapter-"], '
        'a[href*="/chapter/"]',
      ),
    };
    for (final root in chapterRoots) {
      final anchor =
          root.localName == 'a' ? root : root.querySelector('a[href]');
      if (anchor == null) continue;
      final chapterUri = uri.resolve(anchor.attributes['href'] ?? '');
      final label = (anchor.querySelector('p.font-medium, p.truncate')?.text ??
              anchor.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (label.isEmpty ||
          chapters.any((chapter) => chapter.id == chapterUri.path)) {
        continue;
      }
      final date = _cartoonChapterDate(
        (root.localName == 'a' ? root.parent : root)
            ?.querySelector('.release p')
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      );
      chapters.add(MangaChapter(
        id: chapterUri.path,
        title: label,
        number: RegExp(r'(?:chapter\s*)?([\d.]+)', caseSensitive: false)
                .firstMatch(label)
                ?.group(1) ??
            label,
        language: 'en',
        publishedAt: date,
      ));
    }
    final artists = taxonomy.values
        .where((link) => link.kind == MangaTaxonomyKind.artist)
        .map((link) => link.name)
        .toSet()
        .join(', ');
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: image(document.querySelector(
          '.comic-hero__cover img, .comic-hero img, main article img',
        )),
        subtitle: mangaCatalogSubtitle(totalChapters: chapters.length),
      ),
      description: document
              .querySelector(
                '#about .prose, .comic-description, .comic-hero__description',
              )
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '',
      genres: taxonomy.values
          .where((link) => link.kind == MangaTaxonomyKind.tag)
          .map((link) => link.name),
      taxonomyLinks: taxonomy.values,
      author: artists.isEmpty ? null : artists,
      artist: artists.isEmpty ? null : artists,
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: chapters,
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = siteUri.resolve(chapterId);
    var document = await getDocument(uri);
    var pages = _extractCartoonPages(document, uri);
    if (pages.isEmpty && _browserHtmlLoader != null) {
      document = html_parser.parse(
        await _browserHtmlLoader(uri, MadaraAdultSource.userAgent),
      );
      pages = _extractCartoonPages(document, uri);
    }
    final headers = {
      ...coverImageHeaders,
      'Referer': uri.toString(),
    };
    for (final page in pages) {
      yield MangaReaderPage.network(page, headers: headers);
    }
  }

  List<Uri> _extractCartoonPages(Document document, Uri chapterUri) {
    final seen = <Uri>{};
    final pages = <Uri>[];

    void addCandidate(String? raw) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty || value.startsWith('data:')) return;
      final resolved = chapterUri.resolve(value);
      if (seen.add(resolved)) {
        pages.add(resolved);
      }
    }

    for (final script in document.querySelectorAll('script')) {
      final text = script.text;
      if (!text.contains('chapter_preloaded_images')) continue;
      final match = RegExp(
        r'chapter_preloaded_images\s*=\s*(\[[^\]]*\])',
        dotAll: true,
      ).firstMatch(text);
      if (match == null) continue;
      try {
        final decoded = jsonDecode(match.group(1)!) as List<dynamic>;
        for (final entry in decoded) {
          if (entry is Map) {
            addCandidate(entry['src']?.toString());
          } else if (entry is String) {
            addCandidate(entry);
          }
        }
      } catch (_) {
        // Fall through to DOM image extraction.
      }
    }

    for (final node in document.querySelectorAll(
      'figure.reader-page img, img.manga-img, '
      '.reading-content img, .page-break img, .chapter-content img',
    )) {
      final resolved = image(node);
      if (resolved != null && seen.add(resolved)) {
        pages.add(resolved);
      }
    }

    return pages;
  }

  String? _cartoonChapterDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final match = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})$',
    ).firstMatch(text);
    if (match == null) return text;
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = months[match.group(2)!.substring(0, 3).toLowerCase()];
    if (month == null) return text;
    return '${match.group(3)}-${month.toString().padLeft(2, '0')}-'
        '${int.parse(match.group(1)!).toString().padLeft(2, '0')}';
  }
}

class Hentai18MangaSource extends MadaraAdultSource {
  Hentai18MangaSource({super.client, Uri? baseUri})
      : super(
          baseUri: baseUri ?? Uri.parse('https://hentai18.net/'),
        );

  @override
  String get id => 'hentai18_manga';
  @override
  String get name => 'Hentai18';
  @override
  String get catalogPath => '/category/manhwa/';
  @override
  List<MangaCatalogVariant> get variants => const [
        MangaCatalogVariant(id: 'manhwa', label: 'Manhwa'),
        MangaCatalogVariant(id: 'manga', label: 'Manga'),
        MangaCatalogVariant(id: 'doujinshi', label: 'Doujinshi'),
        MangaCatalogVariant(id: 'porn-comics', label: 'Porn comics'),
      ];

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.added,
      ];

  @override
  String pathForVariant(String variantId) => '/category/$variantId/';

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    final sort = switch (filter) {
      MangaCatalogFilter.popular => 'popular',
      MangaCatalogFilter.trending => 'rating',
      MangaCatalogFilter.added => 'new',
      _ => 'latest',
    };
    return _hentai18Catalog(
      pathForVariant(variantId),
      cursor,
      sort == 'latest' ? const {} : {'sort': sort},
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return _hentai18Catalog('/search', cursor, {'q': value});
  }

  @override
  Future<MangaCatalogPage> catalog(
    String path,
    String? cursor,
    Map<String, String> query,
  ) =>
      _hentai18Catalog(path, cursor, query);

  Future<MangaCatalogPage> _hentai18Catalog(
    String path,
    String? cursor,
    Map<String, String> query,
  ) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final document = await getDocument(
      siteUri.resolve(path).replace(queryParameters: {
        ...query,
        if (page > 1) 'page': '$page',
      }),
    );
    final found = <String, MangaCatalogItem>{};
    for (final root in document.querySelectorAll('.hx-card')) {
      final anchor =
          root.querySelector('.hx-card-title a[href], .hx-card-cover');
      final href = anchor?.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final uri = siteUri.resolve(href);
      if (!uri.path.startsWith('/read-hentai/') ||
          _isHentai18Chapter(uri.path)) {
        continue;
      }
      final title = (anchor?.attributes['title'] ?? anchor?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      final latest = root.querySelector('.hx-card-chap-name')?.text.trim();
      final rating = double.tryParse(
        root.querySelector('.hx-card-star')?.text.trim() ?? '',
      );
      found[uri.path] = MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: image(root.querySelector('.hx-card-cover img')),
        subtitle: mangaCatalogSubtitle(
          latestChapter: latest,
          rating: rating,
        ),
      );
    }
    final hasNext = document.querySelector(
          'a[href*="page=${page + 1}"], a[rel="next"]',
        ) !=
        null;
    return MangaCatalogPage(
      items: found.values,
      nextCursor: hasNext ? '${page + 1}' : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final uri = siteUri.resolve(mangaId);
    final document = await getDocument(uri);
    final title =
        document.querySelector('.hx-detail-info h1')?.text.trim() ?? '';
    if (title.isEmpty) throw StateError('$name did not return $mangaId.');
    final links = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll('.hx-genres a[href]')) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isNotEmpty) {
        links[href] = MangaTaxonomyLink(
          kind: MangaTaxonomyKind.tag,
          id: href,
          name: label,
        );
      }
    }
    final chapters = <MangaChapter>[];
    for (final anchor in document.querySelectorAll('a.hx-ep[href]')) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = (anchor.querySelector('.hx-ep-name')?.text ?? anchor.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (label.isEmpty || chapters.any((item) => item.id == href)) continue;
      chapters.add(MangaChapter(
        id: href,
        title: label,
        number: RegExp(r'[\d.]+').firstMatch(label)?.group(0) ?? label,
        language: title.toLowerCase().contains('raw') ? 'und' : 'en',
        publishedAt: anchor.querySelector('time')?.attributes['datetime'],
      ));
    }
    final statusLabel =
        document.querySelector('.hx-pill-status')?.text.toLowerCase() ?? '';
    final status = statusLabel.contains('complete')
        ? MangaStatus.completed
        : statusLabel.contains('hiatus')
            ? MangaStatus.hiatus
            : MangaStatus.ongoing;
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: image(document.querySelector('.hx-detail-poster img')),
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          status: status,
        ),
      ),
      description:
          document.querySelector('.hx-synopsis-text')?.text.trim() ?? '',
      alternativeTitles: [
        for (final node in document.querySelectorAll('.hx-detail-alt'))
          if (node.text.replaceAll(RegExp(r'\s+'), ' ').trim().isNotEmpty)
            {'und': node.text.replaceAll(RegExp(r'\s+'), ' ').trim()},
      ],
      genres: links.values.map((link) => link.name),
      taxonomyLinks: links.values,
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
    final uri = siteUri.resolve(chapterId);
    final document = await getDocument(uri);
    final seen = <Uri>{};
    for (final node in document.querySelectorAll('.hx-pages img')) {
      final page = image(node);
      if (page != null && seen.add(page)) {
        yield MangaReaderPage.network(page, headers: {
          ...coverImageHeaders,
          'Referer': uri.toString(),
        });
      }
    }
  }

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    if (kind != MangaTaxonomyKind.tag) return const [];
    final document = await getDocument(siteUri.resolve('/tags'));
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll('a[href^="/tag/"]')) {
      final href = siteUri.resolve(anchor.attributes['href'] ?? '').path;
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

  bool _isHentai18Chapter(String path) =>
      RegExp(r'-(?:chapter-[\d-]+|oneshot)-ch\d+$').hasMatch(path);
}
