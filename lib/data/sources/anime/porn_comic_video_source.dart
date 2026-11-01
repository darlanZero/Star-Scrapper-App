import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/porn_comic_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Video half of Porn-Comic's hybrid catalog.
class PornComicVideoSource
    implements
        AnimeSource,
        ReaderBackedAnimeSource,
        TaxonomyBrowsableAnimeSource {
  static const _site = 'https://porn-comic.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  late final PornComicMangaSource _readerSource = PornComicMangaSource(
    client: _client,
    baseUri: _baseUri,
  );

  PornComicVideoSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'porn_comic_video';

  @override
  String get name => 'Porn-Comic';

  @override
  Uri get baseUri => _baseUri;

  @override
  PornComicMangaSource get readerSource => _readerSource;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$_site/',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.updated,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularMonth,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) async {
    final cosplay = filter == AnimeCatalogFilter.updated ||
        filter == AnimeCatalogFilter.popularMonth;
    final page = int.tryParse(cursor ?? '') ?? 1;
    final path = cosplay ? '/cos' : '/gif';
    final uri = _baseUri.resolve(page == 1 ? path : '$path/index-$page.html');
    final document = await _getDocument(uri);
    final popular = filter == AnimeCatalogFilter.popular ||
        filter == AnimeCatalogFilter.popularMonth;
    final items =
        popular ? _sidebarItems(document, path) : _catalogItems(document, path);
    final hasNext = !popular &&
        document.querySelector('.page a.a1[href*="${page + 1}"]') != null;
    return AnimeCatalogPage(
      items: items,
      nextCursor: hasNext ? '${page + 1}' : null,
    );
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return browse(cursor: cursor);
    final page = int.tryParse(cursor ?? '') ?? 1;
    final uri = _baseUri.resolve('/').replace(queryParameters: {
      'q': normalized,
      if (page > 1) 'page': '$page',
    });
    final document = await _getDocument(uri);
    final items = _catalogItems(document, '')
        .where((item) =>
            Uri.parse(item.id).path.startsWith('/gif/') ||
            Uri.parse(item.id).path.startsWith('/cos/'))
        .toList(growable: false);
    return AnimeCatalogPage(items: items);
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final uri = _resolve(animeId);
    final document = await _getDocument(uri);
    final title = document.querySelector('h1.title')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        uri.pathSegments.last;
    final metadata = _videoMetadata(document);
    final poster = _uri(metadata['thumbnailUrl'] is List
        ? (metadata['thumbnailUrl'] as List).firstOrNull?.toString()
        : metadata['thumbnailUrl']?.toString());
    final genres = document
        .querySelectorAll('.summary a, .manga-tags a')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final taxonomyLinks = _taxonomyLinks(
      document,
      cosplay: uri.path.startsWith('/cos/'),
    );
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: uri.path,
        title: title,
        coverUri: poster,
        subtitle: uri.path.startsWith('/cos/') ? 'Cosplay' : 'Animation',
      ),
      description: metadata['description']?.toString() ?? '',
      genres: genres,
      taxonomyLinks: taxonomyLinks,
      status: AnimeStatus.completed,
      externalIds: {'porn_comic': uri.path},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final uri = _resolve(animeId);
    final document = await _getDocument(uri);
    final title = document.querySelector('h1.title')?.text.trim() ?? 'Video';
    return [
      AnimeEpisode(
        id: uri.path,
        animeId: uri.path,
        title: title,
        number: 1,
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
    final metadata = _videoMetadata(document);
    final mediaUri = _uri(metadata['contentUrl']?.toString());
    if (mediaUri == null) {
      throw StateError('Porn-Comic did not expose a playable video URL.');
    }
    final lower = mediaUri.path.toLowerCase();
    if (lower.endsWith('.m3u8')) {
      final variants = await _signedHlsVariants(mediaUri, pageUri);
      if (variants.isNotEmpty) return AnimePlayback(streams: variants);
    }
    return AnimePlayback(
      streams: [
        AnimeVideoStream(
          uri: mediaUri,
          protocol: lower.endsWith('.m3u8')
              ? VideoProtocol.hls
              : VideoProtocol.progressive,
          quality: 'Auto',
          language: 'und',
          mimeType: lower.endsWith('.m3u8')
              ? 'application/vnd.apple.mpegurl'
              : 'video/mp4',
          headers: {
            'Referer': pageUri.toString(),
            'User-Agent': _userAgent,
          },
        ),
      ],
    );
  }

  List<AnimeCatalogItem> _catalogItems(Document document, String feed) {
    final seen = <String>{};
    return document
        .querySelectorAll('#list > li, .grid > .grid-item')
        .map((element) {
          final anchor = element.querySelector('a.thumb[href]') ??
              element.querySelector('a[href]');
          final href = anchor?.attributes['href']?.trim() ?? '';
          if (href.isEmpty || !seen.add(href)) return null;
          final title = anchor?.attributes['title']?.trim().isNotEmpty == true
              ? anchor!.attributes['title']!.trim()
              : element.querySelector('span > a')?.text.trim() ??
                  element.querySelector('.title')?.text.trim() ??
                  '';
          if (title.isEmpty) return null;
          return AnimeCatalogItem(
            id: href,
            title: title,
            coverUri: _imageUri(element.querySelector('img')),
            subtitle: [
              feed == '/cos' ? 'Cosplay' : 'Animation',
              element.querySelector('.media')?.text.trim(),
              element.querySelector('.view')?.text.trim(),
            ]
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .join(' • '),
          );
        })
        .whereType<AnimeCatalogItem>()
        .toList(growable: false);
  }

  List<AnimeCatalogItem> _sidebarItems(Document document, String feed) {
    final seen = <String>{};
    return document
        .querySelectorAll('.right .ranking a[href]')
        .map((anchor) {
          final href = anchor.attributes['href']?.trim() ?? '';
          if (href.isEmpty || !seen.add(href)) return null;
          final title = anchor.attributes['title']?.trim().isNotEmpty == true
              ? anchor.attributes['title']!.trim()
              : anchor.querySelector('img')?.attributes['alt']?.trim() ?? '';
          if (title.isEmpty) return null;
          return AnimeCatalogItem(
            id: href,
            title: title,
            coverUri: _imageUri(anchor.querySelector('img')),
            subtitle: '${feed == '/cos' ? 'Cosplay' : 'Animation'} • Popular',
          );
        })
        .whereType<AnimeCatalogItem>()
        .toList(growable: false);
  }

  Map<String, dynamic> _videoMetadata(Document document) {
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final value = jsonDecode(script.text);
        if (value is Map<String, dynamic> && value['contentUrl'] != null) {
          return value;
        }
      } catch (_) {
        // Ignore unrelated or malformed structured data blocks.
      }
    }
    return const {};
  }

  @override
  Future<MangaDetails?> getReaderDetails(String itemId) async {
    final uri = _resolve(itemId);
    final document = await _getDocument(uri);
    if (_videoMetadata(document)['contentUrl'] != null) return null;
    if (document.querySelector('.manga-picture img') == null) return null;
    return _readerSource.getDetails(itemId);
  }

  @override
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final base = _resolve(taxonomyId);
    final uri = page == 1
        ? base
        : base.replace(path: base.path.replaceFirst('.html', '-$page.html'));
    final document = await _getDocument(uri);
    return AnimeCatalogPage(
      items: _catalogItems(document, ''),
      nextCursor:
          document.querySelector('.page a.a1[href*="${page + 1}"]') != null
              ? '${page + 1}'
              : null,
    );
  }

  List<AnimeTaxonomyLink> _taxonomyLinks(
    Document document, {
    required bool cosplay,
  }) {
    final links = <String, AnimeTaxonomyLink>{};
    for (final anchor
        in document.querySelectorAll('.summary a, .manga-tags a')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final name = anchor.text.trim();
      if (href.isEmpty || name.isEmpty) continue;
      final kind = switch (href) {
        final value when value.startsWith('/artist/') =>
          cosplay ? AnimeTaxonomyKind.model : AnimeTaxonomyKind.artist,
        final value when value.startsWith('/circle/') =>
          cosplay ? AnimeTaxonomyKind.topic : AnimeTaxonomyKind.tag,
        final value when value.startsWith('/characters/') =>
          AnimeTaxonomyKind.character,
        final value when value.startsWith('/anime/') =>
          AnimeTaxonomyKind.parody,
        final value when value.startsWith('/tags/') => AnimeTaxonomyKind.tag,
        _ => null,
      };
      if (kind != null) {
        links['${kind.name}:$href'] =
            AnimeTaxonomyLink(kind: kind, id: href, name: name);
      }
    }
    return links.values.toList(growable: false);
  }

  Future<List<AnimeVideoStream>> _signedHlsVariants(
    Uri masterUri,
    Uri pageUri,
  ) async {
    try {
      final response = await _client.get(masterUri, headers: {
        'Referer': pageUri.toString(),
        'Origin': '${pageUri.scheme}://${pageUri.host}',
        'User-Agent': _userAgent,
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final lines = const LineSplitter()
          .convert(response.body)
          .map((line) => line.trim())
          .toList(growable: false);
      final streams = <AnimeVideoStream>[];
      for (var index = 0; index < lines.length - 1; index++) {
        final info = lines[index];
        if (!info.startsWith('#EXT-X-STREAM-INF:')) continue;
        final path = lines[index + 1];
        if (path.isEmpty || path.startsWith('#')) continue;
        final resolution = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(info);
        final bandwidth = RegExp(r'BANDWIDTH=(\d+)').firstMatch(info);
        final resolved = masterUri.resolve(path);
        final signed = resolved.replace(queryParameters: {
          ...resolved.queryParameters,
          ...masterUri.queryParameters,
          'from': masterUri.path,
        });
        streams.add(AnimeVideoStream(
          uri: signed,
          protocol: VideoProtocol.hls,
          quality: resolution == null ? 'Auto' : '${resolution.group(2)}p',
          language: 'und',
          bitrate: int.tryParse(bandwidth?.group(1) ?? ''),
          width: int.tryParse(resolution?.group(1) ?? ''),
          height: int.tryParse(resolution?.group(2) ?? ''),
          mimeType: 'application/vnd.apple.mpegurl',
          headers: {
            'Referer': pageUri.toString(),
            'Origin': '${pageUri.scheme}://${pageUri.host}',
            'User-Agent': _userAgent,
          },
        ));
      }
      return streams;
    } catch (_) {
      return const [];
    }
  }

  Future<Document> _getDocument(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Porn-Comic: HTTP ${response.statusCode}');
    }
    return html_parser.parse(response.body);
  }

  Uri _resolve(String value) => _baseUri.resolve(value);

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['src'] ?? image?.attributes['data-src'],
      );
}
