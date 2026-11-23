import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

class Hentai20Source
    implements
        MangaSource,
        VariantCatalogMangaSource,
        TaxonomyBrowsableMangaSource {
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static const _variants = [
    MangaCatalogVariant(id: 'all', label: 'Manga list'),
    MangaCatalogVariant(id: 'manga', label: 'Manga hentai'),
    MangaCatalogVariant(id: 'manhwa', label: 'Manhwa hentai'),
    MangaCatalogVariant(id: 'raw', label: 'Manhwa raw'),
  ];

  final http.Client _client;
  final Uri _baseUri;

  Hentai20Source({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse('https://hentai20.lol/');

  @override
  String get id => 'hentai20';
  @override
  String get name => 'Hentai20';
  @override
  Uri get baseUri => _baseUri;
  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': _baseUri.toString(),
        'User-Agent': _ua,
      };
  @override
  Map<String, String> get coverImageHeaders => {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': _baseUri.toString(),
        'User-Agent': _ua,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.alphabetical,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.updated,
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
  }) {
    final path = switch (variantId) {
      'manga' => '/manga-hentai/',
      'manhwa' => '/manhwa-hentai/',
      'raw' => '/manhwa-raw/',
      _ => '/manga-lists/',
    };
    final order = switch (filter) {
      MangaCatalogFilter.alphabetical => 'alphabet',
      MangaCatalogFilter.popular => 'rating',
      MangaCatalogFilter.updated => 'views',
      _ => 'latest',
    };
    return _catalog(path, cursor, {'order': order});
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return _catalog('/search/', cursor, {'s': value});
  }

  Future<MangaCatalogPage> _catalog(
    String path,
    String? cursor,
    Map<String, String> query,
  ) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final route = page == 1 ? path : '${path}page/$page/';
    final document = await _document(
      _baseUri.resolve(route).replace(queryParameters: query),
    );
    final items = <MangaCatalogItem>[];
    for (final root in document.querySelectorAll('.latest-item')) {
      final anchor = root.querySelector('.mm-name a[href*="/manga/"]') ??
          root.querySelector('a[href*="/manga/"]');
      final href = anchor?.attributes['href'] ?? '';
      final uri = _baseUri.resolve(href);
      if (!RegExp(r'^/manga/[^/]+/$').hasMatch(uri.path)) continue;
      final title = anchor?.attributes['title']?.trim().isNotEmpty == true
          ? anchor!.attributes['title']!.trim()
          : root.querySelector('.title-smaller')?.text.trim() ?? '';
      if (title.isEmpty) continue;
      final latest = root.querySelector('a[href*="/chapter-"]')?.text.trim();
      final rating = double.tryParse(
        root.querySelector('.avgrate')?.text.trim() ?? '',
      );
      final raw = title.toLowerCase().contains('raw');
      items.add(MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: _image(root.querySelector('img.img-latest')),
        subtitle: [
          if (raw) 'Raw • Original language',
          mangaCatalogSubtitle(latestChapter: latest, rating: rating),
        ].where((value) => value.isNotEmpty).join(' • '),
      ));
    }
    final next = document.querySelector(
      'a[href*="/page/${page + 1}/"], a[href*="page=${page + 1}"]',
    );
    return MangaCatalogPage(
      items: items,
      nextCursor: next == null ? null : '${page + 1}',
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final uri = _baseUri.resolve(mangaId);
    final document = await _document(uri);
    final title = document
            .querySelector('h1.title-bigger, .manga-info h1, h1')
            ?.text
            .trim() ??
        '';
    if (title.isEmpty) throw StateError('Hentai20 did not return $mangaId.');
    final links = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final kind = href.startsWith('/genre/')
          ? MangaTaxonomyKind.tag
          : href.startsWith('/author/') || href.startsWith('/artist/')
              ? MangaTaxonomyKind.artist
              : null;
      if (kind != null && label.isNotEmpty) {
        links['${kind.name}:$href'] =
            MangaTaxonomyLink(kind: kind, id: href, name: label);
      }
    }
    final chapters = <MangaChapter>[];
    for (final root in document.querySelectorAll('.chapter-list li')) {
      final anchor = root.querySelector('a[href*="/chapter-"]');
      if (anchor == null) continue;
      final chapterUri = _baseUri.resolve(anchor.attributes['href'] ?? '');
      if (!chapterUri.path.startsWith('${uri.path}chapter-')) continue;
      final label = (anchor.querySelector('.chapter-name')?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (label.isEmpty || chapters.any((item) => item.id == chapterUri.path)) {
        continue;
      }
      chapters.add(MangaChapter(
        id: chapterUri.path,
        title: label,
        number: RegExp(r'[\d.]+').firstMatch(label)?.group(0) ?? label,
        language: title.toLowerCase().contains('raw') ? 'und' : 'en',
        publishedAt: _chapterDate(
          anchor.querySelector('.ct-update')?.text ?? '',
        ),
      ));
    }
    final metadata = document.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final status = metadata.toLowerCase().contains('completed')
        ? MangaStatus.completed
        : MangaStatus.ongoing;
    final creators = links.values
        .where((link) => link.kind == MangaTaxonomyKind.artist)
        .map((link) => link.name)
        .toSet()
        .join(', ');
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: _image(document.querySelector(
          '.manga-info img, .info-image img, img[src*="-cover"]',
        )),
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          status: status,
        ),
      ),
      description: document
              .querySelector('.manga-description, .description, .desc')
              ?.text
              .trim() ??
          '',
      genres: links.values
          .where((link) => link.kind == MangaTaxonomyKind.tag)
          .map((link) => link.name),
      taxonomyLinks: links.values,
      author: creators.isEmpty ? null : creators,
      artist: creators.isEmpty ? null : creators,
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
    final seen = <Uri>{};
    for (final image in document.querySelectorAll('.reading-content img')) {
      final page = _image(image);
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
    final document = await _document(_baseUri);
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll('a[href*="/genre/"]')) {
      final id = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isNotEmpty) {
        found[id] = MangaTaxonomyOption(id: id, name: label);
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
      _catalog(taxonomyId, cursor, const {'order': 'latest'});

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Hentai20 returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri? _image(Element? image) {
    for (final key in const ['data-src', 'data-lazy-src', 'src']) {
      final value = image?.attributes[key]?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('data:')) {
        return _baseUri.resolve(value);
      }
    }
    return null;
  }

  String? _chapterDate(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'new') return null;
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
    final match =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$').firstMatch(normalized);
    if (match == null) return null;
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    return '${match.group(3)}-${month.toString().padLeft(2, '0')}-'
        '${match.group(1)!.padLeft(2, '0')}';
  }
}
