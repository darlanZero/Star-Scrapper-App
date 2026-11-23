import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

class CartoonPornVideoSource
    implements
        AnimeSource,
        FilterableAnimeSource,
        TaxonomyBrowsableAnimeSource {
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  final http.Client _client;
  final Uri _baseUri;

  CartoonPornVideoSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse('https://cartoonporn.to/');

  @override
  String get id => 'cartoon_porn_video';
  @override
  String get name => 'Cartoon Porn Videos';
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
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularToday,
        AnimeCatalogFilter.popularWeek,
        AnimeCatalogFilter.popularMonth,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    final window = switch (filter) {
      AnimeCatalogFilter.popularToday => 'day',
      AnimeCatalogFilter.popularWeek => 'week',
      AnimeCatalogFilter.popularMonth => 'month',
      _ => null,
    };
    return _catalog(
      path: '/cartoon-porn-videos/',
      cursor: cursor,
      query: {
        if (filter != AnimeCatalogFilter.recent) 'sort': 'views',
        if (window != null) 'window': window,
      },
    );
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return _catalog(
      path: '/cartoon-porn-videos/',
      cursor: cursor,
      query: {'q': value},
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async => AnimeSearchOptions(
        types: const [
          AnimeFilterOption(value: 'motion', label: 'Videos & GIFs'),
          AnimeFilterOption(value: 'videos', label: 'Videos'),
          AnimeFilterOption(value: 'gifs', label: 'GIFs'),
          AnimeFilterOption(value: 'pics', label: 'Pics'),
          AnimeFilterOption(value: 'all', label: 'All'),
        ],
        formats: const [
          AnimeFilterOption(value: 'xs', label: 'Under 15s'),
          AnimeFilterOption(value: 's', label: '15s – 1 min'),
          AnimeFilterOption(value: 'm', label: '1 – 3 min'),
          AnimeFilterOption(value: 'l', label: '3 min+'),
          AnimeFilterOption(value: 'xl', label: '10 min+'),
        ],
        years: const [
          AnimeFilterOption(value: 'day', label: 'Today'),
          AnimeFilterOption(value: 'week', label: 'This week'),
          AnimeFilterOption(value: 'month', label: 'This month'),
          AnimeFilterOption(value: 'year', label: 'This year'),
        ],
        sorts: const [
          AnimeSearchSort.dateAdded,
          AnimeSearchSort.mostViewed,
          AnimeSearchSort.episodeCount,
          AnimeSearchSort.defaultOrder,
        ],
        sortLabels: const {
          AnimeSearchSort.dateAdded: 'Newest',
          AnimeSearchSort.mostViewed: 'Most viewed',
          AnimeSearchSort.episodeCount: 'Longest',
          AnimeSearchSort.defaultOrder: 'Random',
        },
        labels: const {
          'type': 'Show',
          'format': 'Length',
          'year': 'Uploaded',
        },
      );

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final type = request.type ?? 'motion';
    final path = type == 'motion'
        ? '/cartoon-porn-videos/'
        : '/cartoon-porn-videos/$type/';
    final sort = switch (request.sort) {
      AnimeSearchSort.mostViewed => 'views',
      AnimeSearchSort.episodeCount => 'long',
      AnimeSearchSort.defaultOrder => 'random',
      _ => 'new',
    };
    return _catalog(path: path, cursor: cursor, query: {
      if (sort != 'new') 'sort': sort,
      if (request.year != null) 'window': request.year!,
      if (request.formats.isNotEmpty) 'dur': request.formats.first,
      if (request.query.trim().isNotEmpty) 'q': request.query.trim(),
      if (request.tags.isNotEmpty) 'tags': request.tags.join(','),
    });
  }

  Future<AnimeCatalogPage> _catalog({
    required String path,
    required String? cursor,
    required Map<String, String> query,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final normalized = path.endsWith('/') ? path : '$path/';
    final route = page == 1 ? normalized : '${normalized}page/$page/';
    final document = await _document(
      _baseUri.resolve(route).replace(queryParameters: query),
    );
    final items = document.querySelectorAll('.cptv-card').map((root) {
      final anchor = root.querySelector('.cptv-card__link');
      final href = anchor?.attributes['href'] ?? '';
      final title = root.querySelector('.cptv-card__title')?.text.trim() ??
          anchor?.attributes['title']?.trim() ??
          '';
      if (href.isEmpty || title.isEmpty) return null;
      final duration = root.querySelector('.cptv-card__dur')?.text.trim();
      final views = root.querySelector('.cptv-card__views')?.text.trim();
      return AnimeCatalogItem(
        id: _baseUri.resolve(href).path,
        title: title,
        coverUri: _image(root.querySelector('.cptv-card__img')),
        subtitle: [duration, views]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .join(' • '),
      );
    }).whereType<AnimeCatalogItem>();
    return AnimeCatalogPage(
      items: items,
      nextCursor:
          document.querySelector('a[href*="/page/${page + 1}/"]') == null
              ? null
              : '${page + 1}',
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final uri = _baseUri.resolve(animeId);
    final document = await _document(uri);
    final title =
        document.querySelector('h1, .cptv-single__title')?.text.trim() ??
            document.querySelector('title')?.text.trim() ??
            '';
    final poster = _image(document.querySelector('video')) ??
        _uri(document.querySelector('.cptv-player')?.attributes['data-poster']);
    final taxonomy = <String, AnimeTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      'a[href*="cartoon-porn-series"], a[href*="cartoon-porn-tags"], '
      'a[href*="/tag/"], a[href*="/series/"]',
    )) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final kind = href.contains('series')
          ? AnimeTaxonomyKind.parody
          : AnimeTaxonomyKind.tag;
      taxonomy['${kind.name}:$href'] =
          AnimeTaxonomyLink(kind: kind, id: href, name: label);
    }
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: uri.path,
        title: title,
        coverUri: poster,
        subtitle:
            document.querySelector('.cptv-player')?.attributes['data-duration'],
      ),
      description: document
              .querySelector('.cptv-single__desc, .entry-content')
              ?.text
              .trim() ??
          '',
      genres: taxonomy.values.map((item) => item.name),
      taxonomyLinks: taxonomy.values,
      status: AnimeStatus.completed,
      externalIds: {'cartoon_porn': uri.path},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final details = await getDetails(animeId);
    return [
      AnimeEpisode(
        id: animeId,
        animeId: animeId,
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
    final uri = _baseUri.resolve(episodeId);
    final document = await _document(uri);
    final source = document.querySelector('video source[src]');
    final media = _uri(source?.attributes['src']);
    if (media == null) {
      throw StateError('Cartoon Porn did not expose a playable video URL.');
    }
    final hls = media.path.toLowerCase().endsWith('.m3u8');
    return AnimePlayback(streams: [
      AnimeVideoStream(
        uri: media,
        protocol: hls ? VideoProtocol.hls : VideoProtocol.progressive,
        quality: 'Auto',
        language: 'en',
        mimeType: source?.attributes['type'] ??
            (hls ? 'application/vnd.apple.mpegurl' : 'video/mp4'),
        headers: {
          'Referer': uri.toString(),
          'User-Agent': _ua,
        },
      ),
    ]);
  }

  @override
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) =>
      _catalog(path: taxonomyId, cursor: cursor, query: const {});

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cartoon Porn returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri? _image(Element? image) {
    final poster = image?.attributes['poster']?.trim() ?? '';
    if (poster.isNotEmpty) return _baseUri.resolve(poster);
    for (final key in const ['data-src', 'src']) {
      final value = image?.attributes[key]?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('data:')) {
        return _baseUri.resolve(value);
      }
    }
    return null;
  }

  Uri? _uri(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : _baseUri.resolve(normalized);
  }
}
