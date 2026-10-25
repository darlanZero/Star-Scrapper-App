import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Brazilian Portuguese anime catalog backed by animeq.cloud.
///
/// AnimeQ is a mixed catalog. Its adult titles live behind an explicit catalog
/// filter, so the provider itself is not marked as adult-only.
class AnimeQSource
    implements AnimeSource, FilterableAnimeSource, BrowserPlaybackAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://animeq.cloud/');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, String> _episodeAnimeIds = {};
  final Map<String, Document> _episodeDocuments = {};
  final Map<String, Document> _movieDocuments = {};

  AnimeQSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'animeq';

  @override
  String get name => 'AnimeQ';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.7',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.featured,
        AnimeCatalogFilter.catalog,
        AnimeCatalogFilter.subtitled,
        AnimeCatalogFilter.dubbed,
        AnimeCatalogFilter.manhwa,
        AnimeCatalogFilter.donghua,
        AnimeCatalogFilter.movies,
        AnimeCatalogFilter.subtitledMovies,
        AnimeCatalogFilter.dubbedMovies,
        AnimeCatalogFilter.adult,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    if (filter == AnimeCatalogFilter.featured) {
      return _featuredCatalog();
    }
    final path = switch (filter) {
      AnimeCatalogFilter.recent => 'episodio',
      AnimeCatalogFilter.subtitled => 'tipo/legendado',
      AnimeCatalogFilter.dubbed => 'tipo/dublado',
      AnimeCatalogFilter.manhwa => 'genre/Manhwa',
      AnimeCatalogFilter.donghua => 'genre/Donghua',
      AnimeCatalogFilter.movies => 'filme',
      AnimeCatalogFilter.subtitledMovies => 'genre/Filme-Legendado',
      AnimeCatalogFilter.dubbedMovies => 'genre/Filme-Dublado',
      AnimeCatalogFilter.adult => 'genre/hentai',
      _ => 'anime',
    };
    final uri = _pagedUri(path, cursor);
    return filter == AnimeCatalogFilter.recent
        ? _latestCatalog(uri, cursor)
        : _catalog(uri, cursor);
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return Future.value(AnimeCatalogPage(items: const []));
    }
    return _catalog(
      _pagedUri('anime', cursor, {'catalog_search': normalized}),
      cursor,
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final document = await _getDocument(_baseUri.resolve('anime'));
    return AnimeSearchOptions(
      genres: _selectOptions(document, 'catalog_genre'),
      years: _selectOptions(document, 'catalog_year'),
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.name,
        AnimeSearchSort.nameDescending,
        AnimeSearchSort.score,
        AnimeSearchSort.mostViewed,
      ],
    );
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final order = switch (request.sort) {
      AnimeSearchSort.name => 'title_asc',
      AnimeSearchSort.nameDescending => 'title_desc',
      AnimeSearchSort.score => 'rating',
      AnimeSearchSort.mostViewed => 'views',
      _ => null,
    };
    return _catalog(
      _pagedUri('anime', cursor, {
        if (request.query.trim().isNotEmpty)
          'catalog_search': request.query.trim(),
        if (request.genres.isNotEmpty) 'catalog_genre': request.genres.first,
        if (request.year != null) 'catalog_year': request.year!,
        if (order != null) 'catalog_order': order,
      }),
      cursor,
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final resolvedId = await _resolveAnimeId(animeId);
    final movie = _isMovieId(resolvedId);
    final contentId = _contentId(resolvedId);
    final document = movie
        ? await _movieDocument(contentId)
        : await _getDocument(_animeUri(contentId));
    final header = document.querySelector('.sheader');
    final title = header?.querySelector('h1')?.text.trim() ?? contentId;
    final cover = _imageUri(header?.querySelector('.poster img'));
    final banner = _backgroundImageUri(header?.attributes['style']);
    final overview =
        header?.querySelector('.animeq-single-overview')?.text.trim() ??
            document.querySelector('#info .wp-content p')?.text.trim() ??
            document.querySelector('.wp-content p')?.text.trim() ??
            '';
    final genres = header
            ?.querySelectorAll('.sgeneros a[href*="/genre/"]')
            .map((anchor) => anchor.text.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false) ??
        const <String>[];
    final alternatives = <String>{};
    final overline =
        header?.querySelector('.animeq-single-overline')?.text.trim();
    if (overline != null && overline.isNotEmpty && overline != title) {
      alternatives.add(overline);
    }
    for (final field in document.querySelectorAll('.custom_fields')) {
      final label = field.querySelector('.variante')?.text.trim().toLowerCase();
      final value = field.querySelector('.valor')?.text.trim();
      if (label?.contains('título original') == true &&
          value != null &&
          value.isNotEmpty &&
          value != title) {
        alternatives.add(value);
      }
    }
    final meta = header
            ?.querySelectorAll('.animeq-single-meta-pills span')
            .map((element) => element.text.trim())
            .where((value) => value.isNotEmpty)
            .join(' · ') ??
        '';
    final classicMeta = header
            ?.querySelectorAll('.extra span')
            .map((element) => element.text.trim())
            .where((value) => value.isNotEmpty)
            .join(' · ') ??
        '';
    final score =
        header?.querySelector('.animeq-score-box strong')?.text.trim();

    return AnimeDetails(
      item: AnimeCatalogItem(
        id: resolvedId,
        title: title,
        coverUri: cover,
        subtitle: [
          if (meta.isNotEmpty) meta,
          if (classicMeta.isNotEmpty) classicMeta,
          if (score != null && score.isNotEmpty) '★ $score',
        ].join(' · '),
      ),
      description: overview,
      alternativeTitles: alternatives,
      genres: genres,
      status: _status(header?.text),
      bannerUri: banner,
      externalIds: {'animeq': resolvedId},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final resolvedId = await _resolveAnimeId(animeId);
    if (_isMovieId(resolvedId)) {
      final contentId = _contentId(resolvedId);
      final document = await _movieDocument(contentId);
      return [
        AnimeEpisode(
          id: resolvedId,
          animeId: resolvedId,
          title: 'Filme',
          number: 1,
          thumbnailUri:
              _imageUri(document.querySelector('.sheader .poster img')),
        ),
      ];
    }
    final document = await _getDocument(_animeUri(resolvedId));
    return document
        .querySelectorAll('.episode-card')
        .map((card) {
          final anchor = card.querySelector('.episode-title a[href]') ??
              card.querySelector('a[href*="/episodio/"]');
          final uri = _resolveUri(anchor?.attributes['href']);
          final id = _segmentAfter(uri, 'episodio');
          final number = double.tryParse(
              card.attributes['data-episode-number'] ??
                  RegExp(r'(?:Episódio|Ep(?:isode)?)\s*([\d.]+)',
                          caseSensitive: false)
                      .firstMatch(anchor?.text ?? '')
                      ?.group(1) ??
                  '');
          if (id.isEmpty) return null;
          _episodeAnimeIds['episode:$id'] = resolvedId;
          return AnimeEpisode(
            id: id,
            animeId: resolvedId,
            title: anchor?.text.trim().isNotEmpty == true
                ? anchor!.text.trim()
                : 'Episódio ${_displayNumber(number)}',
            number: number,
            season: int.tryParse(
              _ancestorWithClass(card, 'se-c')
                      ?.querySelector('.se-t')
                      ?.text
                      .trim() ??
                  '',
            ),
            thumbnailUri: _imageUri(card.querySelector('img')),
          );
        })
        .whereType<AnimeEpisode>()
        .toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    if (_isMovieId(animeId) || _isMovieId(episodeId)) {
      return _moviePlayback(_contentId(
        _isMovieId(episodeId) ? episodeId : animeId,
      ));
    }
    final episodeUri = _episodeUri(episodeId);
    final document = await _episodeDocument(episodeId);
    final labels = <String, String>{};
    for (final button in document.querySelectorAll('[data-animeq-switch]')) {
      final index = button.attributes['data-animeq-switch'];
      final label = button.attributes['data-source-name'] ?? button.text.trim();
      if (index != null && label.isNotEmpty) labels[index] = label;
    }
    final streams = <AnimeVideoStream>[];
    final seen = <String>{};
    for (final source in document.querySelectorAll('.animeq-player__source')) {
      final quality = labels[source.attributes['data-animeq-source']] ?? 'Auto';
      for (final media in source.querySelectorAll('video source[src]')) {
        final uri = _resolveUri(media.attributes['src']);
        if (uri == null || !_isMediaUri(uri) || !seen.add(uri.toString())) {
          continue;
        }
        streams.add(AnimeVideoStream(
          uri: uri,
          protocol: _protocol(uri),
          quality: quality,
          language: 'pt-BR',
          mimeType: media.attributes['type'],
          headers: {
            'Referer': episodeUri.toString(),
            'User-Agent': _userAgent,
          },
        ));
      }
    }
    if (streams.isNotEmpty) return AnimePlayback(streams: streams);

    final choices = document
        .querySelectorAll('.animeq-player__source iframe[src]')
        .map((frame) {
          final uri = _resolveUri(frame.attributes['src']);
          if (uri == null) return null;
          final source = _ancestorWithClass(frame, 'animeq-player__source');
          final quality = labels[source?.attributes['data-animeq-source']] ??
              frame.attributes['title'] ??
              'Auto';
          return AnimePlaybackChoice(
            entryUri: uri,
            provider: uri.host.contains('blogger') ? 'Blogger' : uri.host,
            quality: quality,
          );
        })
        .whereType<AnimePlaybackChoice>()
        .toList(growable: false);
    if (choices.isNotEmpty) throw AnimePlaybackResolutionRequired(choices);
    throw StateError('AnimeQ não expôs um vídeo para este episódio.');
  }

  @override
  Future<AnimePlayback> playbackFromResolvedUri(
    Uri uri, {
    String quality = 'Auto',
    String provider = 'Browser',
  }) async {
    if (!_isMediaUri(uri)) {
      throw StateError('O player da AnimeQ não expôs uma URL de mídia válida.');
    }
    return AnimePlayback(streams: [
      AnimeVideoStream(
        uri: uri,
        protocol: _protocol(uri),
        quality: quality,
        language: 'pt-BR',
        mimeType: _mediaMimeType(uri),
        headers: {
          if (provider.toLowerCase().contains('blogger') ||
              uri.host.toLowerCase().contains('googlevideo.com'))
            'Referer': 'https://www.blogger.com/',
          'User-Agent': _userAgent,
        },
      ),
    ]);
  }

  Future<AnimeCatalogPage> _featuredCatalog() async {
    final document = await _getDocument(_baseUri.resolve('anime'));
    return AnimeCatalogPage(
      items: document
          .querySelectorAll('.items.featured article.item')
          .map(_catalogItem)
          .whereType<AnimeCatalogItem>(),
    );
  }

  Future<AnimeCatalogPage> _catalog(Uri uri, String? cursor) async {
    final document = await _getDocument(uri);
    return AnimeCatalogPage(
      items: document
          .querySelectorAll(
            '#archive-content article.item, .items.full article.item',
          )
          .map(_catalogItem)
          .whereType<AnimeCatalogItem>(),
      nextCursor: _nextCursor(document, cursor),
    );
  }

  Future<AnimeCatalogPage> _latestCatalog(Uri uri, String? cursor) async {
    final document = await _getDocument(uri);
    return AnimeCatalogPage(
      items: document
          .querySelectorAll('#archive-content article.item')
          .map((card) {
        final anchor = card.querySelector('a[href*="/episodio/"]');
        final episodeUri = _resolveUri(anchor?.attributes['href']);
        final episodeId = _segmentAfter(episodeUri, 'episodio');
        final title = card.querySelector('.serie')?.text.trim() ?? '';
        if (episodeId.isEmpty || title.isEmpty) return null;
        final episodeTitle = card.querySelector('.data h3')?.text.trim() ?? '';
        final quality = card.querySelector('.quality')?.text.trim() ?? '';
        final date = card.querySelector('.post-date-badge')?.text.trim() ?? '';
        return AnimeCatalogItem(
          id: 'episode:$episodeId',
          title: title,
          coverUri: _imageUri(card.querySelector('.poster img')),
          subtitle: [episodeTitle, quality, date]
              .where((value) => value.isNotEmpty)
              .join(' · '),
        );
      }).whereType<AnimeCatalogItem>(),
      nextCursor: _nextCursor(document, cursor),
    );
  }

  AnimeCatalogItem? _catalogItem(Element card) {
    final anchor = card.querySelector('.data h3 a[href*="/anime/"]') ??
        card.querySelector('.data h3 a[href*="/filme/"]') ??
        card.querySelector('a[href*="/anime/"], a[href*="/filme/"]');
    final uri = _resolveUri(anchor?.attributes['href']);
    final movieId = _segmentAfter(uri, 'filme');
    final animeId = _segmentAfter(uri, 'anime');
    final id = movieId.isNotEmpty ? 'movie:$movieId' : animeId;
    final title = anchor?.text.trim() ?? '';
    if (id.isEmpty || title.isEmpty) return null;
    final rating = card.querySelector('.rating')?.text.trim() ?? '';
    final date = card.querySelector('.post-date-badge')?.text.trim() ??
        card.querySelector('.data > span')?.text.trim() ??
        '';
    return AnimeCatalogItem(
      id: id,
      title: title,
      coverUri: _imageUri(card.querySelector('.poster img')),
      subtitle: [
        if (date.isNotEmpty) date,
        if (rating.isNotEmpty) '★ $rating',
      ].join(' · '),
    );
  }

  Future<String> _resolveAnimeId(String animeId) async {
    if (!animeId.startsWith('episode:')) return animeId;
    final cached = _episodeAnimeIds[animeId];
    if (cached != null) return cached;
    final episodeId = animeId.substring('episode:'.length);
    final document = await _episodeDocument(episodeId);
    final animeUri = _resolveUri(
      document.querySelector('a[href*="/anime/"]')?.attributes['href'],
    );
    final resolved = _segmentAfter(animeUri, 'anime');
    if (resolved.isEmpty) {
      throw StateError('AnimeQ não identificou a obra deste episódio.');
    }
    _episodeAnimeIds[animeId] = resolved;
    return resolved;
  }

  Future<Document> _episodeDocument(String episodeId) async {
    final cached = _episodeDocuments[episodeId];
    if (cached != null) return cached;
    final document = await _getDocument(_episodeUri(episodeId));
    _episodeDocuments[episodeId] = document;
    return document;
  }

  Future<Document> _movieDocument(String movieId) async {
    final cached = _movieDocuments[movieId];
    if (cached != null) return cached;
    final document = await _getDocument(_movieUri(movieId));
    _movieDocuments[movieId] = document;
    return document;
  }

  Future<AnimePlayback> _moviePlayback(String movieId) async {
    final pageUri = _movieUri(movieId);
    final document = await _movieDocument(movieId);
    final streams = <AnimeVideoStream>[];
    final choices = <AnimePlaybackChoice>[];
    final seen = <String>{};

    for (final option in document.querySelectorAll('.dooplay_player_option')) {
      final post = option.attributes['data-post'];
      final number = option.attributes['data-nume'];
      final type = option.attributes['data-type'] ?? 'movie';
      if (post == null || number == null) continue;
      final quality = option.querySelector('.title')?.text.trim() ?? 'Auto';
      final response = await _postText(
        _baseUri.resolve('wp-admin/admin-ajax.php'),
        body: {
          'action': 'doo_player_ajax',
          'post': post,
          'nume': number,
          'type': type,
        },
        referer: pageUri,
      );
      final payload = jsonDecode(response);
      if (payload is! Map) continue;
      final embed = _resolveUri(payload['embed_url']?.toString());
      if (embed == null) continue;
      final source = Uri.tryParse(embed.queryParameters['source'] ?? '');
      final media = source != null && _isMediaUri(source)
          ? source
          : _isMediaUri(embed)
              ? embed
              : null;
      if (media != null && seen.add(media.toString())) {
        streams.add(AnimeVideoStream(
          uri: media,
          protocol: _protocol(media),
          quality: quality,
          language: 'pt-BR',
          mimeType:
              media.path.toLowerCase().endsWith('.mp4') ? 'video/mp4' : null,
          headers: {
            'Referer': pageUri.toString(),
            'User-Agent': _userAgent,
          },
        ));
      } else if (media == null && seen.add(embed.toString())) {
        choices.add(AnimePlaybackChoice(
          entryUri: embed,
          provider: embed.host,
          quality: quality,
        ));
      }
    }

    if (streams.isNotEmpty) return AnimePlayback(streams: streams);
    if (choices.isNotEmpty) throw AnimePlaybackResolutionRequired(choices);
    throw StateError('AnimeQ não expôs um player para este filme.');
  }

  Future<Document> _getDocument(Uri uri) async =>
      html_parser.parse(await _getText(uri));

  Future<String> _getText(Uri uri) async {
    final response = await _retryResponse(
      uri,
      () => _client.get(uri, headers: {
        ...requestHeaders,
        'Connection': 'close',
        'Referer': _baseUri.toString(),
      }),
    );
    return _responseText(response, uri);
  }

  Future<String> _postText(
    Uri uri, {
    required Map<String, String> body,
    required Uri referer,
  }) async {
    final response = await _retryResponse(
      uri,
      () => _client.post(uri,
          headers: {
            ...requestHeaders,
            'Connection': 'close',
            'Referer': referer.toString(),
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: body),
    );
    return _responseText(response, uri);
  }

  Future<http.Response> _retryResponse(
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await request().timeout(const Duration(seconds: 60));
        if (response.statusCode < 500 || attempt == 2) return response;
        lastError = http.ClientException(
          'AnimeQ retornou HTTP ${response.statusCode}.',
          uri,
        );
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
    if (lastError is Exception) throw lastError;
    throw http.ClientException('AnimeQ não concluiu a resposta.', uri);
  }

  String _responseText(http.Response response, Uri uri) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'AnimeQ retornou HTTP ${response.statusCode}.',
        uri,
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Uri _pagedUri(
    String path,
    String? cursor, [
    Map<String, String> parameters = const {},
  ]) {
    final normalized = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final page = int.tryParse(cursor ?? '');
    final pagedPath =
        page != null && page > 1 ? '$normalized/page/$page/' : '$normalized/';
    return _baseUri.resolve(pagedPath).replace(
          queryParameters: parameters.isEmpty ? null : parameters,
        );
  }

  String? _nextCursor(Document document, String? cursor) {
    final current = int.tryParse(cursor ?? '') ?? 1;
    final pages = document
        .querySelectorAll('a[href*="/page/"]')
        .map((anchor) {
          final href = anchor.attributes['href'] ?? '';
          return int.tryParse(
              RegExp(r'/page/(\d+)').firstMatch(href)?.group(1) ?? '');
        })
        .whereType<int>()
        .where((page) => page > current)
        .toList()
      ..sort();
    return pages.isEmpty ? null : pages.first.toString();
  }

  List<AnimeFilterOption> _selectOptions(Document document, String name) =>
      document
          .querySelectorAll('select[name="$name"] option[value]')
          .map((option) => AnimeFilterOption(
                value: option.attributes['value']?.trim() ?? '',
                label: option.text.trim(),
              ))
          .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
          .toList(growable: false);

  Uri _animeUri(String id) => _baseUri.resolve('anime/$id/');

  Uri _movieUri(String id) => _baseUri.resolve('filme/$id/');

  Uri _episodeUri(String id) => _baseUri.resolve('episodio/$id/');

  Uri? _resolveUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _resolveUri(
        image?.attributes['data-src'] ?? image?.attributes['src'],
      );

  Uri? _backgroundImageUri(String? style) {
    final value = RegExp(r'''url\(['"]?([^'")]+)''', caseSensitive: false)
        .firstMatch(style ?? '')
        ?.group(1);
    return _resolveUri(value);
  }

  static String _segmentAfter(Uri? uri, String segment) {
    if (uri == null) return '';
    final parts = uri.pathSegments.where((value) => value.isNotEmpty).toList();
    final index = parts.indexOf(segment);
    return index >= 0 && index + 1 < parts.length ? parts[index + 1] : '';
  }

  static bool _isMovieId(String id) => id.startsWith('movie:');

  static String _contentId(String id) =>
      _isMovieId(id) ? id.substring('movie:'.length) : id;

  static Element? _ancestorWithClass(Element element, String className) {
    Element? current = element.parent;
    while (current != null) {
      if (current.classes.contains(className)) return current;
      current = current.parent;
    }
    return null;
  }

  static AnimeStatus _status(String? value) {
    final normalized = value?.toLowerCase() ?? '';
    if (normalized.contains('completo') || normalized.contains('finalizado')) {
      return AnimeStatus.completed;
    }
    if (normalized.contains('lançamento') ||
        normalized.contains('lancamento') ||
        normalized.contains('em andamento')) {
      return AnimeStatus.ongoing;
    }
    return AnimeStatus.unknown;
  }

  static bool _isMediaUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final mime = uri.queryParameters['mime']?.toLowerCase() ?? '';
    return (host.endsWith('googlevideo.com') &&
            uri.path.contains('/videoplayback')) ||
        mime.startsWith('video/') ||
        RegExp(
          r'\.(m3u8|mpd|mp4|mkv|webm)(\?|$)',
          caseSensitive: false,
        ).hasMatch(uri.toString());
  }

  static String? _mediaMimeType(Uri uri) {
    final mime = uri.queryParameters['mime'];
    if (mime != null && mime.startsWith('video/')) return mime;
    if (uri.path.toLowerCase().endsWith('.mp4') ||
        uri.host.toLowerCase().endsWith('googlevideo.com')) {
      return 'video/mp4';
    }
    return null;
  }

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
