import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Adult video catalog backed by hentaihaven.io.
///
/// The site exposes two independent catalogs: individual episode releases and
/// complete series. NHPlayer performs its final media authorization in a real
/// browser, so playback deliberately hands that last step to the app WebView.
class HentaiHavenSource
    implements AnimeSource, FilterableAnimeSource, BrowserPlaybackAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://hentaihaven.io/');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, String> _episodeSeriesIds = {};
  final Map<String, Document> _seriesDocuments = {};
  Uri? _pendingSubtitleUri;

  HentaiHavenSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'hentai_haven';

  @override
  String get name => 'Hentai Haven';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.episodeMostViewed,
        AnimeCatalogFilter.seriesNewest,
        AnimeCatalogFilter.seriesPopular,
        AnimeCatalogFilter.seriesMostViewed,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    final (path, sort, seriesMode) = switch (filter) {
      AnimeCatalogFilter.popular => ('', 'popular', false),
      AnimeCatalogFilter.episodeMostViewed => ('', 'viewed', false),
      AnimeCatalogFilter.seriesNewest => ('series/', null, true),
      AnimeCatalogFilter.seriesPopular => ('series/', 'popular', true),
      AnimeCatalogFilter.seriesMostViewed => ('series/', 'viewed', true),
      _ => ('', null, false),
    };
    return _catalog(
      _uri(path, cursor: cursor, parameters: {
        if (sort != null) 'sort': sort,
      }),
      seriesMode: seriesMode,
    );
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return Future.value(AnimeCatalogPage(items: const []));
    }
    return _catalog(
      _uri('series/', cursor: cursor, parameters: {'q': normalized}),
      seriesMode: true,
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final genresDocument = await _getDocument(_baseUri.resolve('genres/'));
    final genres = genresDocument
        .querySelectorAll('a[href*="/genre/"]')
        .map((anchor) {
          final uri = _resolveUri(anchor.attributes['href']);
          final value = _segmentAfter(uri, 'genre');
          final label = anchor.querySelector('h2, h3, strong')?.text.trim() ??
              anchor.text.replaceAll(RegExp(r'[\d,]+\s+episodes?'), '').trim();
          return value.isEmpty || label.isEmpty
              ? null
              : AnimeFilterOption(value: value, label: label);
        })
        .whereType<AnimeFilterOption>()
        .toSetBy((option) => option.value)
        .toList(growable: false);

    final catalogDocument = await _getDocument(_baseUri.resolve('series/'));
    final years = catalogDocument
        .querySelectorAll('a[href*="year="]')
        .map((anchor) => anchor.text.trim())
        .where((year) => RegExp(r'^\d{4}$').hasMatch(year))
        .toSet()
        .map((year) => AnimeFilterOption(value: year, label: year))
        .toList(growable: false);

    return AnimeSearchOptions(
      genres: genres,
      years: years,
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.mostViewed,
        AnimeSearchSort.name,
        AnimeSearchSort.releaseDate,
      ],
    );
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    // Hentai Haven exposes genre filters only in the episode catalog. The
    // equivalent query in `/series/` is accepted by the site but always
    // returns an empty grid.
    final filtersEpisodes = request.genres.isNotEmpty;
    final sort = switch (request.sort) {
      AnimeSearchSort.mostViewed => 'viewed',
      AnimeSearchSort.name => 'name',
      AnimeSearchSort.releaseDate || AnimeSearchSort.latestAdded => null,
      _ => null,
    };
    return _catalog(
      _uri(filtersEpisodes ? '' : 'series/', cursor: cursor, parameters: {
        if (request.query.trim().isNotEmpty) 'q': request.query.trim(),
        if (request.genres.isNotEmpty) 'genre': request.genres.first,
        if (request.year != null) 'year': request.year!,
        if (sort != null) 'sort': sort,
      }),
      seriesMode: !filtersEpisodes,
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final seriesId = await _resolveSeriesId(animeId);
    final document = await _seriesDocument(seriesId);
    final title = document.querySelector('.detail-heading h1')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        seriesId;
    final cover = _imageUri(document.querySelector('.series-poster'));
    var description =
        document.querySelector('.detail-description .prose')?.text.trim() ?? '';
    var genres = _genres(document);
    final episodes = _episodesFromDocument(seriesId, document);

    if ((description.isEmpty || description.startsWith('No description')) &&
        episodes.isNotEmpty) {
      final episodeDocument =
          await _getDocument(_episodeUri(episodes.first.id));
      final episodeDescription = episodeDocument
              .querySelector('.watch-main .detail-description .prose')
              ?.text
              .trim() ??
          '';
      if (episodeDescription.isNotEmpty) description = episodeDescription;
      if (genres.isEmpty) genres = _genres(episodeDocument);
    }

    final meta = document
        .querySelectorAll('.detail-heading .detail-meta span')
        .map((span) => span.text.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: seriesId,
        title: title,
        coverUri: cover,
        subtitle: [
          if (episodes.isNotEmpty) '${episodes.length} episodes',
          if (meta.isNotEmpty) meta,
        ].join(' · '),
      ),
      description: description,
      genres: genres,
      status: AnimeStatus.unknown,
      externalIds: {'hentaihaven': seriesId},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final seriesId = await _resolveSeriesId(animeId);
    return _episodesFromDocument(seriesId, await _seriesDocument(seriesId));
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final episodeDocument = await _getDocument(_episodeUri(episodeId));
    final embedUri = _resolveUri(
      episodeDocument
          .querySelector('.player-stage iframe[src]')
          ?.attributes['src'],
    );
    if (embedUri == null) {
      throw StateError(
          'Hentai Haven did not expose a player for this episode.');
    }

    if (_isMediaUri(embedUri)) {
      return _playback(embedUri);
    }

    final playerDocument =
        await _getDocument(embedUri, referer: _episodeUri(episodeId));
    final playerPath = playerDocument
        .querySelector('.servers [data-id], [data-id*="player.php"]')
        ?.attributes['data-id'];
    final playerUri =
        playerPath == null ? embedUri : embedUri.resolve(playerPath);
    _pendingSubtitleUri = _decodeBase64Uri(playerUri.queryParameters['s']);
    throw AnimePlaybackResolutionRequired([
      AnimePlaybackChoice(
        // Open the public embed first. Loading player.php directly skips the
        // same-origin navigation that establishes NHPlayer's authorization
        // context and fails with "Please refresh" on Android WebView.
        entryUri: embedUri,
        provider: 'NHPlayer',
        quality: 'Auto',
      ),
    ]);
  }

  @override
  Future<AnimePlayback> playbackFromResolvedUri(
    Uri uri, {
    String quality = 'Auto',
    String provider = 'Browser',
  }) async {
    if (!_isMediaUri(uri)) {
      throw StateError('NHPlayer did not expose a supported media URL.');
    }
    return _playback(uri, quality: quality);
  }

  AnimePlayback _playback(Uri uri, {String quality = 'Auto'}) => AnimePlayback(
        streams: [
          AnimeVideoStream(
            uri: uri,
            protocol: _protocol(uri),
            quality: quality,
            language: 'ja',
            mimeType:
                uri.path.toLowerCase().endsWith('.mp4') ? 'video/mp4' : null,
            headers: const {'Referer': 'https://nhplayer.com/'},
          ),
        ],
        subtitles: [
          if (_pendingSubtitleUri case final subtitle?)
            AnimeSubtitleTrack(
              uri: subtitle,
              label: 'English',
              language: 'en',
              format: subtitle.pathSegments.lastOrNull?.split('.').last,
              isDefault: true,
              headers: const {'Referer': 'https://nhplayer.com/'},
            ),
        ],
      );

  Future<AnimeCatalogPage> _catalog(
    Uri uri, {
    required bool seriesMode,
  }) async {
    final document = await _getDocument(uri);
    final seen = <String>{};
    final items = document
        // Next.js streams parts of the grid through template fragments. The
        // HTML parser keeps those cards outside their visual `.post-grid`, so
        // select cards globally and deduplicate their stable destination IDs.
        .querySelectorAll('.post-card')
        .map((card) => _catalogItem(card, seriesMode: seriesMode))
        .whereType<AnimeCatalogItem>()
        .where((item) => seen.add(item.id))
        .toList(growable: false);
    final next = document.querySelector(
      'a[aria-label="Next page"], .pagination a.next, a.next',
    );
    final nextUri = _resolveUri(next?.attributes['href']);
    return AnimeCatalogPage(
      items: items,
      nextCursor: nextUri?.queryParameters['page'],
    );
  }

  AnimeCatalogItem? _catalogItem(Element card, {required bool seriesMode}) {
    final anchor = card.querySelector('.card-copy h3 a[href]') ??
        card.querySelector('a[href]');
    final uri = _resolveUri(anchor?.attributes['href']);
    if (uri == null) return null;
    final rawTitle = (anchor?.text.trim().isNotEmpty == true
            ? anchor!.text.trim()
            : anchor?.attributes['aria-label']?.trim()) ??
        '';
    if (rawTitle.isEmpty) return null;
    final image = _imageUri(card.querySelector('.card-art img'));
    final meta = card.querySelector('.card-meta')?.text.trim() ?? '';

    if (seriesMode || uri.pathSegments.contains('series')) {
      final seriesId = _segmentAfter(uri, 'series');
      if (seriesId.isEmpty) return null;
      return AnimeCatalogItem(
        id: seriesId,
        title: rawTitle,
        coverUri: image,
        subtitle: meta.isEmpty ? null : meta,
      );
    }

    final episodeId = _lastSegment(uri);
    if (episodeId.isEmpty) return null;
    final match = RegExp(r'\s+Episode\s+([\d.]+)\s*$', caseSensitive: false)
        .firstMatch(rawTitle);
    final episode = card.querySelector('.episode-label')?.text.trim() ??
        (match == null ? '' : 'Episode ${match.group(1)}');
    return AnimeCatalogItem(
      id: 'episode:$episodeId',
      title:
          match == null ? rawTitle : rawTitle.substring(0, match.start).trim(),
      coverUri: image,
      subtitle: [episode, meta].where((value) => value.isNotEmpty).join(' · '),
    );
  }

  Future<String> _resolveSeriesId(String animeId) async {
    if (!animeId.startsWith('episode:')) return animeId;
    final cached = _episodeSeriesIds[animeId];
    if (cached != null) return cached;
    final episodeId = animeId.substring('episode:'.length);
    final document = await _getDocument(_episodeUri(episodeId));
    final seriesUri = _resolveUri(
      document
          .querySelector('.watch-series a[href*="/series/"], a.phone-bar-back')
          ?.attributes['href'],
    );
    final seriesId = _segmentAfter(seriesUri, 'series');
    if (seriesId.isEmpty) {
      throw StateError('Hentai Haven did not identify this episode series.');
    }
    _episodeSeriesIds[animeId] = seriesId;
    return seriesId;
  }

  Future<Document> _seriesDocument(String seriesId) async {
    final cached = _seriesDocuments[seriesId];
    if (cached != null) return cached;
    final document = await _getDocument(_seriesUri(seriesId));
    _seriesDocuments[seriesId] = document;
    return document;
  }

  List<AnimeEpisode> _episodesFromDocument(
    String seriesId,
    Document document,
  ) {
    final seen = <String>{};
    return document
        .querySelectorAll('.post-card')
        .map((card) {
          final anchor = card.querySelector('.card-copy h3 a[href]') ??
              card.querySelector('a[href]');
          final uri = _resolveUri(anchor?.attributes['href']);
          final episodeId = _lastSegment(uri);
          final rawTitle = (anchor?.text.trim().isNotEmpty == true
                  ? anchor!.text.trim()
                  : anchor?.attributes['aria-label']?.trim()) ??
              '';
          final label = card.querySelector('.episode-label')?.text ?? rawTitle;
          final number = double.tryParse(
            RegExp(r'(?:EP|Episode)\s+([\d.]+)', caseSensitive: false)
                    .firstMatch(label)
                    ?.group(1) ??
                '',
          );
          return episodeId.isEmpty
              ? null
              : AnimeEpisode(
                  id: episodeId,
                  animeId: seriesId,
                  title: 'Episode ${_displayNumber(number)}',
                  number: number,
                  thumbnailUri: _imageUri(card.querySelector('img')),
                );
        })
        .whereType<AnimeEpisode>()
        .where((episode) => seen.add(episode.id))
        .toList(growable: false);
  }

  List<String> _genres(Document document) => document
      .querySelectorAll('.genre-tags a[href*="/genre/"]')
      .map((anchor) => anchor.text.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Future<Document> _getDocument(Uri uri, {Uri? referer}) async =>
      html_parser.parse(await _getText(uri, referer: referer));

  Future<String> _getText(Uri uri, {Uri? referer}) async {
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      'Referer': (referer ?? _baseUri).toString(),
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Hentai Haven returned HTTP ${response.statusCode}.',
        uri,
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Uri _uri(
    String path, {
    String? cursor,
    Map<String, String> parameters = const {},
  }) =>
      _baseUri.resolve(path).replace(queryParameters: {
        ...parameters,
        if (cursor != null) 'page': cursor,
      });

  Uri _seriesUri(String id) => _baseUri.resolve('series/$id/');

  Uri _episodeUri(String id) => _baseUri.resolve('$id/');

  Uri? _resolveUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _resolveUri(
        image?.attributes['data-src'] ?? image?.attributes['src'],
      );

  static String _segmentAfter(Uri? uri, String segment) {
    if (uri == null) return '';
    final segments =
        uri.pathSegments.where((value) => value.isNotEmpty).toList();
    final index = segments.indexOf(segment);
    return index >= 0 && index + 1 < segments.length ? segments[index + 1] : '';
  }

  static String _lastSegment(Uri? uri) => uri == null
      ? ''
      : uri.pathSegments.where((value) => value.isNotEmpty).lastOrNull ?? '';

  static Uri? _decodeBase64Uri(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return Uri.tryParse(utf8.decode(base64.decode(base64.normalize(value))));
    } catch (_) {
      return null;
    }
  }

  static bool _isMediaUri(Uri uri) => RegExp(
        r'\.(m3u8|mpd|mp4|mkv|webm)(\?|$)',
        caseSensitive: false,
      ).hasMatch(uri.toString());

  static VideoProtocol _protocol(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('.m3u8')) return VideoProtocol.hls;
    if (value.contains('.mpd')) return VideoProtocol.dash;
    return VideoProtocol.progressive;
  }

  static String _displayNumber(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
}

extension<T> on Iterable<T> {
  Iterable<T> toSetBy(Object Function(T value) keyOf) sync* {
    final keys = <Object>{};
    for (final value in this) {
      if (keys.add(keyOf(value))) yield value;
    }
  }
}
