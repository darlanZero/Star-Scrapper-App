import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

typedef HitomiHtmlLoader = Future<String> Function(Uri uri, String userAgent);

class HitomiSource
    implements
        MangaSource,
        VariantCatalogMangaSource,
        TaxonomyBrowsableMangaSource {
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static const _variants = [
    MangaCatalogVariant(id: 'date_added', label: 'Date added'),
    MangaCatalogVariant(id: 'published', label: 'Date published'),
    MangaCatalogVariant(id: 'today', label: 'Popular today'),
    MangaCatalogVariant(id: 'week', label: 'Popular this week'),
    MangaCatalogVariant(id: 'month', label: 'Popular this month'),
    MangaCatalogVariant(id: 'year', label: 'Popular this year'),
    MangaCatalogVariant(id: 'random', label: 'Random'),
  ];

  static String browserReadySelector(Uri uri) => RegExp(
        r'^/(?:doujinshi|manga|cg|imageset|gamecg|anime)/.+\.html$',
      ).hasMatch(uri.path)
          ? '#gallery-brand'
          : uri.path == '/search.html'
              ? '.gallery-content > div:not(#loader-content)'
              : '.gallery-content > div';

  final http.Client _client;
  final Uri _baseUri;
  final HitomiHtmlLoader? _browserHtmlLoader;

  HitomiSource({
    http.Client? client,
    Uri? baseUri,
    HitomiHtmlLoader? browserHtmlLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse('https://hitomi.la/'),
        _browserHtmlLoader = browserHtmlLoader;

  @override
  String get id => 'hitomi';
  @override
  String get name => 'Hitomi.la';
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
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
      ];
  @override
  List<MangaCatalogVariant> catalogVariants(MangaCatalogFilter filter) =>
      _variants;

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) =>
      browseVariant(
        filter,
        filter == MangaCatalogFilter.recent ? 'date_added' : 'week',
        cursor: cursor,
      );

  @override
  Future<MangaCatalogPage> browseVariant(
    MangaCatalogFilter filter,
    String variantId, {
    String? cursor,
  }) {
    final value = _variants.any((item) => item.id == variantId)
        ? variantId
        : 'date_added';
    if (value == 'random') {
      final query = cursor == null
          ? 'orderbydirection%3Arandom'
          : 'orderbydirection%3Arandom&page=$cursor';
      return _catalog(_baseUri.resolve('/search.html').replace(query: query));
    }
    final path = switch (value) {
      'published' => '/date/published-all.html',
      'today' => '/popular/today-all.html',
      'week' => '/popular/week-all.html',
      'month' => '/popular/month-all.html',
      'year' => '/popular/year-all.html',
      _ => '/',
    };
    final base = _baseUri.resolve(path);
    return _catalog(
      cursor == null ? base : base.replace(queryParameters: {'page': cursor}),
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return _catalog(_baseUri.resolve('/search.html').replace(queryParameters: {
      'q': value,
      if (cursor != null) 'page': cursor,
    }));
  }

  Future<MangaCatalogPage> _catalog(Uri uri) async {
    final document = await _document(uri);
    final found = <String, MangaCatalogItem>{};
    for (final root in document.querySelectorAll('.gallery-content > div')) {
      final anchor = root.querySelector('h1.lillie a[href]') ??
          root.querySelector('a.lillie[href]');
      final href = anchor?.attributes['href'] ?? '';
      if (href.isEmpty || !href.endsWith('.html')) continue;
      final title = root.querySelector('h1.lillie a')?.text.trim() ?? '';
      if (title.isEmpty) continue;
      final type = root
          .querySelector('.dj-desc tr:nth-child(2) td:last-child')
          ?.text
          .trim();
      final language = root
          .querySelector('.dj-desc tr:nth-child(3) td:last-child')
          ?.text
          .trim();
      found[href] = MangaCatalogItem(
        id: href,
        title: title,
        coverUri: _catalogCover(root),
        subtitle: [type, language]
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .join(' • '),
      );
    }
    final current = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
    return MangaCatalogPage(
      items: found.values,
      nextCursor:
          document.querySelector('a[href*="page=${current + 1}"]') == null
              ? null
              : '${current + 1}',
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final uri = _baseUri.resolve(mangaId);
    final galleryId = RegExp(r'(\d+)\.html$').firstMatch(uri.path)?.group(1);
    if (galleryId != null) {
      try {
        final gallery = await _fetchGalleryInfo(galleryId);
        final jsonTitle = gallery['title']?.toString().trim() ?? '';
        if (jsonTitle.isNotEmpty) {
          return _detailsFromGalleryJson(
            uri: uri,
            galleryId: galleryId,
            gallery: gallery,
            title: jsonTitle,
          );
        }
      } catch (_) {
        // Fall back to HTML/WebView parsing if galleryinfo is unavailable.
      }
    }

    final document = await _document(uri);
    final title = document.querySelector('#gallery-brand')?.text.trim() ?? '';
    if (title.isEmpty) throw StateError('Hitomi did not return $mangaId.');
    final links = <String, MangaTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '#artists a, #groups a, #series a, #characters a, #tags a',
    )) {
      final href = anchor.attributes['href'] ?? '';
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final kind = href.startsWith('/artist/')
          ? MangaTaxonomyKind.artist
          : href.startsWith('/character/')
              ? MangaTaxonomyKind.character
              : href.startsWith('/series/')
                  ? MangaTaxonomyKind.parody
                  : href.startsWith('/group/')
                      ? MangaTaxonomyKind.group
                      : MangaTaxonomyKind.tag;
      if (label.isNotEmpty) {
        links['${kind.name}:$href'] =
            MangaTaxonomyLink(kind: kind, id: href, name: label);
      }
    }
    final pageCount = document.querySelectorAll('.thumbnail-list li').length;
    final resolvedGalleryId = galleryId ?? uri.path;
    final language = document.querySelector('#language')?.text.trim() ?? 'und';
    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: _image(document.querySelector('#bigtn_img')),
        subtitle: mangaCatalogSubtitle(totalChapters: 1),
      ),
      description: '',
      genres: links.values
          .where((item) => item.kind == MangaTaxonomyKind.tag)
          .map((item) => item.name),
      taxonomyLinks: links.values,
      author: links.values
          .where((item) => item.kind == MangaTaxonomyKind.artist)
          .map((item) => item.name)
          .join(', '),
      artist: links.values
          .where((item) => item.kind == MangaTaxonomyKind.artist)
          .map((item) => item.name)
          .join(', '),
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: '$resolvedGalleryId:$pageCount',
          title: 'Gallery',
          number: '1',
          language: _languageCode(language),
          pages: '$pageCount',
        ),
      ],
    );
  }

  MangaDetails _detailsFromGalleryJson({
    required Uri uri,
    required String galleryId,
    required Map<String, dynamic> gallery,
    required String title,
  }) {
    final links = <String, MangaTaxonomyLink>{};

    void addLinks(
      Object? rawList,
      String nameKey,
      MangaTaxonomyKind kind,
    ) {
      if (rawList is! List) return;
      for (final entry in rawList.whereType<Map>()) {
        final name = entry[nameKey]?.toString().trim() ?? '';
        final href = entry['url']?.toString().trim() ?? '';
        if (name.isEmpty || href.isEmpty) continue;
        links['${kind.name}:$href'] =
            MangaTaxonomyLink(kind: kind, id: href, name: name);
      }
    }

    addLinks(gallery['artists'], 'artist', MangaTaxonomyKind.artist);
    addLinks(gallery['groups'], 'group', MangaTaxonomyKind.group);
    addLinks(gallery['parodys'], 'parody', MangaTaxonomyKind.parody);
    addLinks(gallery['characters'], 'character', MangaTaxonomyKind.character);
    addLinks(gallery['tags'], 'tag', MangaTaxonomyKind.tag);

    final files =
        (gallery['files'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final firstHash = files.isNotEmpty
        ? (files.first['hash']?.toString().trim() ?? '')
        : '';
    Uri? coverUri;
    if (firstHash.length >= 3) {
      final last = firstHash[firstHash.length - 1];
      final pair = firstHash.substring(firstHash.length - 3, firstHash.length - 1);
      coverUri = Uri.parse(
        'https://tn.gold-usergeneratedcontent.net/webpbigtn/$last/$pair/$firstHash.webp',
      );
    }

    final artists = links.values
        .where((item) => item.kind == MangaTaxonomyKind.artist)
        .map((item) => item.name)
        .join(', ');
    final language = gallery['language']?.toString() ?? 'und';

    return MangaDetails(
      item: MangaCatalogItem(
        id: uri.path,
        title: title,
        coverUri: coverUri,
        subtitle: mangaCatalogSubtitle(totalChapters: 1),
      ),
      description: '',
      genres: links.values
          .where((item) => item.kind == MangaTaxonomyKind.tag)
          .map((item) => item.name),
      taxonomyLinks: links.values,
      author: artists,
      artist: artists,
      status: MangaStatus.completed,
      externalUri: uri,
      chapters: [
        MangaChapter(
          id: '$galleryId:${files.length}',
          title: 'Gallery',
          number: '1',
          language: _languageCode(language),
          pages: '${files.length}',
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _fetchGalleryInfo(String galleryId) async {
    final galleryScript = await _text(
      Uri.parse(
        'https://ltn.gold-usergeneratedcontent.net/galleries/$galleryId.js',
      ),
    );
    final galleryMatch = RegExp(
      r'var\s+galleryinfo\s*=\s*(\{.*\})\s*;?\s*$',
      dotAll: true,
    ).firstMatch(galleryScript);
    if (galleryMatch == null) {
      throw StateError('Hitomi did not return gallery data for $galleryId.');
    }
    return jsonDecode(galleryMatch.group(1)!) as Map<String, dynamic>;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final galleryId = RegExp(r'(\d+)')
            .allMatches(chapterId)
            .map((match) => match.group(1)!)
            .firstOrNull ??
        RegExp(r'(\d+)\.html$').firstMatch(mangaId)?.group(1);
    if (galleryId == null) return;

    // Hitomi publishes the canonical file hashes separately from the HTML.
    // Its rotating image host is derived by gg.js; thumbnail-host string
    // replacement no longer works because `a.gold...`/`b.gold...` were
    // replaced by the current w1/w2 shards.
    final gallery = await _fetchGalleryInfo(galleryId);
    final files =
        (gallery['files'] as List?)?.whereType<Map>().toList() ?? const <Map>[];

    final ggScript = await _text(
      Uri.parse('https://ltn.gold-usergeneratedcontent.net/gg.js'),
    );
    final zeroCasesBlock = ggScript.split('o = 0;')[0];
    final w1Shards = RegExp(r'case\s+(\d+)\s*:')
        .allMatches(zeroCasesBlock)
        .map((match) => int.parse(match.group(1)!))
        .toSet();
    final pathPrefix =
        RegExp(r"\bb\s*:\s*'([^']+)'").firstMatch(ggScript)?.group(1) ?? '';
    if (pathPrefix.isEmpty) {
      throw StateError('Hitomi image routing data is unavailable.');
    }

    for (final file in files) {
      final hash = file['hash']?.toString() ?? '';
      if (hash.length < 3) continue;
      final tail = hash.substring(hash.length - 3);
      final shardKey =
          int.parse('${tail[2]}${tail.substring(0, 2)}', radix: 16);
      final imageHost = w1Shards.contains(shardKey) ? 'w1' : 'w2';
      final image = Uri.parse(
        'https://$imageHost.gold-usergeneratedcontent.net/'
        '$pathPrefix$shardKey/$hash.webp',
      );
      yield MangaReaderPage.network(image, headers: {
        ...coverImageHeaders,
        'Referer': _baseUri.resolve(mangaId).toString(),
      });
    }
  }

  @override
  List<MangaTaxonomyKind> get taxonomyKinds => const [
        MangaTaxonomyKind.tag,
        MangaTaxonomyKind.artist,
        MangaTaxonomyKind.parody,
        MangaTaxonomyKind.character,
      ];

  @override
  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  }) async {
    final prefix = switch (kind) {
      MangaTaxonomyKind.artist => 'artists',
      MangaTaxonomyKind.parody => 'series',
      MangaTaxonomyKind.character => 'characters',
      _ => 'tags',
    };
    final letter =
        query.trim().isEmpty ? 'a' : query.trim().substring(0, 1).toLowerCase();
    final document =
        await _document(_baseUri.resolve('/all$prefix-$letter.html'));
    final found = <String, MangaTaxonomyOption>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!href.contains(
          '/${prefix == 'series' ? 'series' : prefix.substring(0, prefix.length - 1)}/')) {
        continue;
      }
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final count = int.tryParse(
        RegExp(r'\((\d+)\)').firstMatch(label)?.group(1) ?? '',
      );
      found[href] = MangaTaxonomyOption(
        id: href,
        name: label.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), ''),
        titleCount: count,
      );
    }
    return found.values.toList(growable: false);
  }

  @override
  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) {
    final uri = _baseUri.resolve(taxonomyId).replace(queryParameters: {
      if (cursor != null) 'page': cursor,
    });
    return _catalog(uri);
  }

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Hitomi returned HTTP ${response.statusCode}.');
    }
    final document = html_parser.parse(utf8.decode(response.bodyBytes));
    final isDynamicCatalog = uri.path == '/' ||
        uri.path == '/search.html' ||
        RegExp(r'^/(?:tag|artist|series|character|popular|date)/')
            .hasMatch(uri.path);
    final isGallery = RegExp(
      r'/(?:doujinshi|manga|cg|imageset|gamecg|anime)/.+\.html$',
    ).hasMatch(uri.path);
    final galleryTitle =
        document.querySelector('#gallery-brand')?.text.trim() ?? '';
    final renderedContentMissing = (isDynamicCatalog &&
            document.querySelectorAll('.gallery-content h1.lillie a').isEmpty) ||
        (isGallery && galleryTitle.isEmpty);
    if (renderedContentMissing && _browserHtmlLoader != null) {
      return html_parser.parse(await _browserHtmlLoader(uri, _ua));
    }
    return document;
  }

  Future<String> _text(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Hitomi returned HTTP ${response.statusCode}.');
    }
    return utf8.decode(response.bodyBytes);
  }

  Uri? _catalogCover(Element root) {
    final direct = _image(
      root.querySelector('.dj-img1 img, .dj-img-cont img, img'),
    );
    if (direct != null) return direct;

    final sources = root.querySelectorAll(
      '.dj-img1 picture source, .dj-img-cont picture source, picture source',
    );
    // Prefer webp/jpg sources over avif when falling back to <source>.
    for (final source in sources) {
      final type = source.attributes['type']?.toLowerCase() ?? '';
      if (type.contains('avif')) continue;
      final candidate = _image(source);
      if (candidate != null) return candidate;
    }
    for (final source in sources) {
      final candidate = _image(source);
      if (candidate != null) return candidate;
    }
    return null;
  }

  Uri? _image(Element? node) {
    if (node == null) return null;
    for (final key in const [
      'data-src',
      'src',
      'data-original',
      'data-srcset',
      'srcset',
    ]) {
      final raw = node.attributes[key]?.trim() ?? '';
      if (raw.isEmpty || raw.startsWith('data:')) continue;
      final value = key.endsWith('srcset')
          ? raw.split(',').first.trim().split(RegExp(r'\s+')).first.trim()
          : raw;
      if (value.isEmpty || value.startsWith('data:')) continue;
      return value.startsWith('//')
          ? Uri.parse('https:$value')
          : _baseUri.resolve(value);
    }
    return null;
  }

  String _languageCode(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('english')) return 'en';
    if (normalized.contains('portugu')) return 'pt';
    if (normalized.contains('日本') || normalized.contains('japanese')) {
      return 'ja';
    }
    if (normalized.contains('한국') || normalized.contains('korean')) return 'ko';
    if (normalized.contains('中文') || normalized.contains('chinese')) {
      return 'zh';
    }
    return 'und';
  }
}
