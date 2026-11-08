import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/hentai_img_manga_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Adult mixed image/video source backed by hentai-img.com.
class HentaiImgSource
    implements
        AnimeSource,
        ReaderBackedAnimeSource,
        FilterableAnimeSource,
        TaxonomyBrowsableAnimeSource {
  static const _site = 'https://hentai-img.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _feedRoutes = <AnimeCatalogFilter, String>{
    AnimeCatalogFilter.recent: '/search/',
    AnimeCatalogFilter.added: '/recently-download/',
    AnimeCatalogFilter.updated: '/recently-like/',
    AnimeCatalogFilter.completed: '/recently-bookmark/',
    AnimeCatalogFilter.popular: '/ranking/',
    AnimeCatalogFilter.featured: '/ranking-download/',
    AnimeCatalogFilter.seriesPopular: '/ranking-like/',
    AnimeCatalogFilter.seriesMostViewed: '/ranking-bookmark/',
    AnimeCatalogFilter.movies: '/search-video/',
    AnimeCatalogFilter.episodeMostViewed: '/ranking-video/',
  };

  final http.Client _client;
  final Uri _baseUri;
  late final HentaiImgMangaSource _readerSource = HentaiImgMangaSource(
    client: _client,
    baseUri: _baseUri,
  );

  HentaiImgSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'hentai_img';

  @override
  String get name => 'Hentai-Img';

  @override
  Uri get baseUri => _baseUri;

  @override
  HentaiImgMangaSource get readerSource => _readerSource;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$_site/',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters =>
      _feedRoutes.keys.toList(growable: false);

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    final route =
        _feedRoutes[filter] ?? _feedRoutes[AnimeCatalogFilter.recent]!;
    return _catalogPage(
        cursor == null ? _baseUri.resolve(route) : _resolve(cursor));
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => filter(
        AnimeSearchRequest(query: query),
        cursor: cursor,
      );

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final tags = await _readerSource.getTaxonomy(MangaTaxonomyKind.tag);
    return AnimeSearchOptions(
      tags:
          tags.map((tag) => AnimeFilterOption(value: tag.id, label: tag.name)),
      sorts: const [AnimeSearchSort.defaultOrder],
      sortLabels: const {AnimeSearchSort.defaultOrder: 'Newest'},
      labels: const {'tags': 'Tags'},
    );
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final uri = cursor != null
        ? _resolve(cursor)
        : request.tags.isNotEmpty
            ? _tagUri(request.tags.first)
            : request.query.trim().isNotEmpty
                ? _keywordUri(request.query.trim())
                : _baseUri.resolve('/search/');
    return _catalogPage(uri);
  }

  @override
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) {
    if (kind != AnimeTaxonomyKind.tag) {
      return Future.value(AnimeCatalogPage(items: const []));
    }
    return _catalogPage(
        cursor == null ? _tagUri(taxonomyId) : _resolve(cursor));
  }

  @override
  Future<MangaDetails?> getReaderDetails(String itemId) {
    final uri = _resolve(itemId);
    if (!uri.path.startsWith('/image/')) return Future.value(null);
    return _readerSource.getDetails(itemId);
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final uri = _resolve(animeId);
    final document = await _getDocument(uri);
    final title = document.querySelector('#post_title')?.text.trim() ??
        document.querySelector('#title h2')?.text.trim() ??
        document.querySelector('#page > h2')?.text.trim() ??
        document.querySelector('#page #right_sidebar > h3')?.text.trim() ??
        document.querySelector('h1, h2')?.text.trim() ??
        _fallbackTitle(uri);
    final tags = _taxonomyLinks(document);
    final poster =
        _uri(document.querySelector('video[poster]')?.attributes['poster']) ??
            _imageUri(document.querySelector('#display_image_detail img'));
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: uri.path,
        title: title,
        coverUri: poster,
        subtitle: uri.path.startsWith('/video/') ? 'Video' : 'Images',
      ),
      description: document
              .querySelector('meta[name="description"]')
              ?.attributes['content']
              ?.trim() ??
          '',
      genres: tags.map((link) => link.name),
      taxonomyLinks: tags,
      status: AnimeStatus.completed,
      externalIds: {'hentai_img': uri.path},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final details = await getDetails(animeId);
    return [
      AnimeEpisode(
        id: details.item.id,
        animeId: details.item.id,
        title: details.item.title,
        number: 1,
        thumbnailUri: details.item.coverUri,
      ),
    ];
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final pageUri = _resolve(episodeId);
    final document = await _getDocument(pageUri);
    final mediaUri = _videoUri(document);
    if (mediaUri == null) {
      throw StateError('Hentai-Img did not expose a playable video URL.');
    }
    final hls = mediaUri.path.toLowerCase().endsWith('.m3u8');
    return AnimePlayback(
      streams: [
        AnimeVideoStream(
          uri: mediaUri,
          protocol: hls ? VideoProtocol.hls : VideoProtocol.progressive,
          quality: 'Auto',
          language: 'en',
          mimeType: hls ? 'application/vnd.apple.mpegurl' : 'video/mp4',
          headers: {
            'Referer': pageUri.toString(),
            'Origin': '${pageUri.scheme}://${pageUri.host}',
            'User-Agent': _userAgent,
          },
        ),
      ],
    );
  }

  Future<AnimeCatalogPage> _catalogPage(Uri uri) async {
    final document = await _getDocument(uri);
    final modernRoot = document.querySelector('#display_area_image');
    final responsiveRoot = document.querySelector(
          '#page #right_sidebar #entry_list',
        ) ??
        document.querySelector('#entry_list');
    final cards = modernRoot != null
        ? modernRoot.querySelectorAll('#image-list .image-list-item')
        : responsiveRoot?.children
                .where((element) => element.localName == 'li')
                .toList(growable: false) ??
            const <Element>[];
    final seen = <String>{};
    final items = cards
        .map((card) {
          final anchor = card.querySelector(
            '.image-list-item-image a[href], .image-list-item-title a[href], '
            'a[href^="/image/"], a[href^="/video/"]',
          );
          final href = anchor?.attributes['href']?.trim() ?? '';
          final path = Uri.tryParse(href)?.path ?? '';
          if ((!path.startsWith('/image/') && !path.startsWith('/video/')) ||
              !seen.add(href)) {
            return null;
          }
          final image = card.querySelector('img');
          final title =
              card.querySelector('.image-list-item-title a')?.text.trim() ??
                  image?.attributes['alt']?.trim() ??
                  '';
          if (title.isEmpty) return null;
          final date = card
              .querySelector('.image-list-item-regist-date, .posted')
              ?.text
              .trim();
          return AnimeCatalogItem(
            id: href,
            title: title,
            coverUri: _imageUri(image),
            subtitle: [path.startsWith('/video/') ? 'Video' : 'Images', date]
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .join(' • '),
          );
        })
        .whereType<AnimeCatalogItem>()
        .toList(growable: false);
    return AnimeCatalogPage(
      items: items,
      nextCursor: document
          .querySelector(
              '.wp-pagenavi a.nextpostslink[href], a[rel="next"][href]')
          ?.attributes['href']
          ?.trim(),
    );
  }

  List<AnimeTaxonomyLink> _taxonomyLinks(Document document) {
    final links = <String, AnimeTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '#detail_tag a[href*="/search/tag/"], #the_tags a[href*="/search/tag/"], '
      '#the_tags a[href*="/tag/"]',
    )) {
      final slug = _tagSlug(anchor.attributes['href'] ?? '');
      final name = anchor.text.trim();
      if (slug.isNotEmpty && name.isNotEmpty) {
        links[slug] = AnimeTaxonomyLink(
          kind: AnimeTaxonomyKind.tag,
          id: slug,
          name: name,
        );
      }
    }
    return links.values.toList(growable: false);
  }

  Uri? _videoUri(Document document) {
    final direct = document.querySelector('video source[src], video[src]');
    final directValue = direct?.attributes['src'];
    if (directValue != null &&
        directValue.isNotEmpty &&
        !directValue.startsWith('blob:')) {
      return _uri(directValue);
    }
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(script.text);
        if (decoded is Map && decoded['contentUrl'] != null) {
          return _uri(decoded['contentUrl'].toString());
        }
      } catch (_) {
        // Ignore unrelated structured-data blocks.
      }
    }
    return null;
  }

  Uri _keywordUri(String query) =>
      _baseUri.resolve('/search/keyword/${Uri.encodeComponent(query)}/');

  Uri _tagUri(String value) {
    final slug = _tagSlug(value);
    return _baseUri.resolve('/search/tag/${Uri.encodeComponent(slug)}/');
  }

  String _tagSlug(String value) {
    final path = Uri.tryParse(value)?.path ?? value;
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    final marker = segments.indexOf('tag');
    final slug = marker >= 0 && marker + 1 < segments.length
        ? segments[marker + 1]
        : (segments.isEmpty ? value : segments.last);
    return Uri.decodeComponent(slug).trim();
  }

  Future<Document> _getDocument(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Hentai-Img: HTTP ${response.statusCode}');
    }
    return html_parser.parse(response.body);
  }

  Uri _resolve(String value) => _baseUri.resolve(value);

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['src'] ??
            image?.attributes['data-src'] ??
            image?.attributes['data-original'],
      );

  String _fallbackTitle(Uri uri) =>
      uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull
          ?.replaceAll('-', ' ') ??
      'Hentai-Img';
}
