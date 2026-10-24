import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

typedef GoyabuBrowserHtmlLoad = Future<String> Function(
  Uri uri,
  String userAgent,
);
typedef GoyabuBrowserImageLoad = Future<Uint8List> Function(
  Uri uri,
  String userAgent,
);

/// Brazilian Portuguese anime catalog backed by goyabu.io.
///
/// Goyabu is protected by Cloudflare. A verified WebView session is persisted
/// and reused by the HTTP client; if Cloudflare still refuses the native HTTP
/// request, catalog HTML is loaded by the browser engine with the same session.
class GoyabuSource
    implements
        AnimeSource,
        FilterableAnimeSource,
        BrowserSessionAnimeSource,
        BrowserImageAnimeSource,
        BrowserPlaybackAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://goyabu.io/');
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
  static const _cookiesKey = 'goyabu_browser_cookies';
  static const _userAgentKey = 'goyabu_browser_user_agent';

  final http.Client _client;
  final Uri _baseUri;
  final GoyabuBrowserHtmlLoad? _browserHtmlLoader;
  final GoyabuBrowserImageLoad? _browserImageLoader;
  Map<String, String> _cookies = const {};
  final Map<String, String> _releaseAnimeIds = {};
  String _userAgent = _defaultUserAgent;
  bool _sessionLoaded = false;

  GoyabuSource({
    http.Client? client,
    Uri? baseUri,
    GoyabuBrowserHtmlLoad? browserHtmlLoader,
    GoyabuBrowserImageLoad? browserImageLoader,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _browserHtmlLoader = browserHtmlLoader,
        _browserImageLoader = browserImageLoader;

  @override
  String get id => 'goyabu';

  @override
  String get name => 'Goyabu';

  @override
  Uri get baseUri => _baseUri;

  @override
  Uri get sessionUri => _baseUri.resolve('lista-de-animes?l=todos');

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,application/json',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.7',
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; '),
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularWeek,
        AnimeCatalogFilter.popularMonth,
      ];

  @override
  Future<Uint8List> loadBrowserImage(Uri uri) async {
    await _loadSession();
    final loader = _browserImageLoader;
    if (loader == null) {
      throw StateError('Browser image loading is unavailable.');
    }
    return loader(uri, _userAgent);
  }

  @override
  Future<void> updateBrowserSession({
    required Map<String, String> cookies,
    required String userAgent,
  }) async {
    _cookies = Map.unmodifiable(cookies);
    _userAgent = userAgent.trim().isEmpty ? _defaultUserAgent : userAgent;
    _sessionLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiesKey, jsonEncode(_cookies));
    await prefs.setString(_userAgentKey, _userAgent);
  }

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) =>
      switch (filter) {
        AnimeCatalogFilter.popular => _popularCatalog('day'),
        AnimeCatalogFilter.popularWeek => _popularCatalog('week'),
        AnimeCatalogFilter.popularMonth => _popularCatalog('month'),
        _ => _latestCatalog(_pagedUri('lancamentos', cursor)),
      };

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return Future.value(AnimeCatalogPage(items: const []));
    }
    return _catalog(_pagedUri('', cursor, {'s': normalized}));
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) async {
    if (request.query.trim().isNotEmpty) {
      return search(request.query, cursor: cursor);
    }
    final genre = request.genres.firstOrNull;
    final page = await _catalog(
      genre == null
          ? _pagedUri('lista-de-animes', cursor, {'l': 'todos'})
          : _pagedUri('generos/$genre', cursor),
    );
    final language = request.language?.toLowerCase();
    if (language == null) return page;
    return AnimeCatalogPage(
      items: page.items.where((item) {
        final subtitle = item.subtitle?.toLowerCase() ?? '';
        return language == 'dublado'
            ? subtitle.contains('dublado')
            : !subtitle.contains('dublado');
      }),
      nextCursor: page.nextCursor,
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final document = await _getDocument(_baseUri.resolve('generos'));
    final genres = <String, AnimeFilterOption>{};
    for (final link in document.querySelectorAll('a[href*="/generos/"]')) {
      final uri = _resolveUri(link.attributes['href']);
      final segments = uri?.pathSegments.where((value) => value.isNotEmpty);
      final value = segments?.lastOrNull ?? '';
      final label = link.text.trim();
      if (value.isNotEmpty && label.isNotEmpty) {
        genres[value] = AnimeFilterOption(value: value, label: label);
      }
    }
    return AnimeSearchOptions(
      genres: genres.values,
      languages: const [
        AnimeFilterOption(value: 'legendado', label: 'Legendado'),
        AnimeFilterOption(value: 'dublado', label: 'Dublado'),
      ],
      sorts: const [AnimeSearchSort.defaultOrder],
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final resolvedAnimeId = await _resolveAnimeId(animeId);
    final document = await _getDocument(_animeUri(resolvedAnimeId));
    final title = document.querySelector('.streamer-info h1, h1')?.text.trim();
    final resolvedTitle = title?.isNotEmpty == true ? title! : animeId;
    final audio =
        document.querySelector('.streamer-poster .audio-box')?.text.trim();
    final year = document.querySelector('#year')?.text.trim();
    final rating = document.querySelector('.rating-total')?.text.trim();
    final subtitle = [
      if (audio?.isNotEmpty == true) audio!,
      if (year?.isNotEmpty == true) year!,
      if (rating?.isNotEmpty == true && rating != '0.0') '★ $rating',
    ].join(' · ');
    final postId = _postId(document);
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: resolvedAnimeId,
        title: resolvedTitle,
        coverUri: _imageUri(
          document.querySelector('.streamer-poster img, .animecapa img'),
        ),
        subtitle: subtitle.isEmpty ? null : subtitle,
      ),
      description: document
              .querySelector('.streamer-sinopse .sinopse-full')
              ?.text
              .trim()
              .takeIfNotEmpty ??
          document
              .querySelector('.streamer-sinopse .sinopse-short')
              ?.text
              .trim() ??
          '',
      genres: document
          .querySelectorAll('.streamer-categories a[href*="/generos/"]')
          .map((link) => link.text.trim())
          .where((value) => value.isNotEmpty),
      status: _status(document.querySelector('.streamer-info .status')?.text),
      bannerUri: _imageUri(document.querySelector('.streamer-bg img')),
      externalIds: {
        if (postId != null) 'goyabu': postId,
      },
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final resolvedAnimeId = await _resolveAnimeId(animeId);
    final details = await _getDocument(_animeUri(resolvedAnimeId));
    final postId = _postId(details);
    if (postId != null) {
      final payload = await _getJson(
        _baseUri.resolve('wp-admin/admin-ajax.php').replace(
          queryParameters: {
            'action': 'get_anime_episodes',
            'anime_id': postId,
          },
        ),
        ajax: true,
        referer: _animeUri(resolvedAnimeId),
      );
      final data = payload['data'];
      if (payload['success'] == true && data is List) {
        return data
            .whereType<Map>()
            .map((row) => _episodeFromJson(resolvedAnimeId, row))
            .where((episode) => episode.id.isNotEmpty)
            .toList(growable: false);
      }
    }
    return _episodesFromDocument(resolvedAnimeId, details);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final document = await _getDocument(_episodeUri(episodeId));
    final choices = <AnimePlaybackChoice>[];
    final seen = <String>{};
    for (final tab in document.querySelectorAll('.player-tab')) {
      final encrypted = tab.attributes['data-blogger-url-encrypted'];
      final decoded = _decodePlayerUri(encrypted);
      if (decoded == null || !seen.add(decoded.toString())) continue;
      choices.add(AnimePlaybackChoice(
        entryUri: decoded,
        provider: 'Blogger',
        quality: _quality(tab.text),
      ));
    }
    final frame = _resolveUri(
      document.querySelector('#player iframe[src]')?.attributes['src'],
    );
    if (frame != null && seen.add(frame.toString())) {
      choices.add(AnimePlaybackChoice(
        entryUri: frame,
        provider: 'Blogger',
        quality: choices.isEmpty ? 'HD' : 'Auto',
      ));
    }
    if (choices.isEmpty) {
      throw StateError('Goyabu não retornou um player para este episódio.');
    }

    final streams = <AnimeVideoStream>[];
    final streamUris = <String>{};
    for (final choice in choices) {
      try {
        for (final stream in await _resolveBloggerStreams(choice)) {
          if (streamUris.add(stream.uri.toString())) streams.add(stream);
        }
      } catch (_) {
        // Keep the browser resolver as a fallback if Blogger changes its page.
      }
    }
    if (streams.isNotEmpty) {
      streams.sort(
        (left, right) => (right.height ?? 0).compareTo(left.height ?? 0),
      );
      return AnimePlayback(streams: streams);
    }
    throw AnimePlaybackResolutionRequired(choices);
  }

  Future<List<AnimeVideoStream>> _resolveBloggerStreams(
    AnimePlaybackChoice choice,
  ) async {
    final response = await _client.get(choice.entryUri, headers: {
      'Referer': _baseUri.toString(),
      'User-Agent': _userAgent,
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Blogger retornou HTTP ${response.statusCode}.',
        choice.entryUri,
      );
    }
    final body = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\/', '/');
    final matches = RegExp(
      r'''https://[^"'\\\s<>]*googlevideo\.com/videoplayback\?[^"'\\\s<>]+''',
    ).allMatches(body);
    final seen = <String>{};
    return matches
        .map((match) => Uri.tryParse(match.group(0) ?? ''))
        .whereType<Uri>()
        .where((uri) => seen.add(uri.toString()))
        .map((uri) {
      final height = _bloggerHeight(uri.queryParameters['itag']);
      return AnimeVideoStream(
        uri: uri,
        protocol: VideoProtocol.progressive,
        quality: height == null ? choice.quality : '${height}p',
        language: 'pt-BR',
        mimeType: 'video/mp4',
        height: height,
        headers: {
          'Referer': 'https://www.blogger.com/',
          'User-Agent': _userAgent,
        },
      );
    }).toList(growable: false);
  }

  @override
  Future<AnimePlayback> playbackFromResolvedUri(
    Uri uri, {
    String quality = 'Auto',
    String provider = 'Browser',
  }) async =>
      AnimePlayback(
        streams: [
          AnimeVideoStream(
            uri: uri,
            protocol: _protocol(uri),
            quality: quality,
            language: 'pt-BR',
            headers: {
              'Referer': 'https://www.blogger.com/',
              'User-Agent': _userAgent,
            },
          ),
        ],
      );

  Future<AnimeCatalogPage> _catalog(Uri uri) async {
    return _catalogFromDocument(uri, await _getDocument(uri));
  }

  Future<AnimeCatalogPage> _popularCatalog(String period) async {
    final uri = _baseUri.resolve('wp-json/cronos/v1/views/ranking-all').replace(
      queryParameters: const {'limit': '10', 'type': 'anime'},
    );
    final payload = await _getJson(uri);
    final rankings = payload['rankings'];
    final rows = rankings is Map ? rankings[period] : null;
    if (rows is! List) {
      throw const FormatException('Goyabu retornou rankings inválidos.');
    }
    final items = rows
        .whereType<Map>()
        .map((row) {
          final title = (row['title'] ?? 'Sem título').toString().trim();
          final rating = (row['rating'] ?? '').toString().trim();
          final views = (row['views_formatted'] ?? '').toString().trim();
          final audio =
              row['audio'] == 'ptBr' || title.toLowerCase().contains('dublado')
                  ? 'Dublado'
                  : 'Legendado';
          final permalink = _resolveUri((row['permalink'] ?? '').toString());
          return AnimeCatalogItem(
            id: _animeId(permalink),
            title: title,
            coverUri: _resolveUri((row['poster'] ?? '').toString()),
            subtitle: [
              audio,
              if (rating.isNotEmpty && rating != '0.0') '★ $rating',
              if (views.isNotEmpty) '$views views',
            ].join(' · '),
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    return AnimeCatalogPage(items: items);
  }

  AnimeCatalogPage _catalogFromDocument(Uri uri, Document document) {
    final items = document
        .querySelectorAll('.boxAN, .cardAN')
        .map((node) {
          final anchor = node.querySelector('a[href*="/anime/"]');
          final href = _resolveUri(anchor?.attributes['href']);
          final image = node.querySelector('img');
          final title =
              node.querySelector('.title')?.text.trim().takeIfNotEmpty ??
                  image?.attributes['title']?.trim().takeIfNotEmpty ??
                  image?.attributes['alt']?.trim().takeIfNotEmpty ??
                  'Sem título';
          final audio = node.querySelector('.audio-box')?.text.trim();
          final rating = node.querySelector('.rating-poster')?.text.trim();
          final subtitle = [
            if (audio?.isNotEmpty == true)
              audio!
            else if (title.toLowerCase().contains('dublado'))
              'Dublado'
            else
              'Legendado',
            if (rating?.isNotEmpty == true && rating != '0.0') '★ $rating',
          ].join(' · ');
          return AnimeCatalogItem(
            id: _animeId(href),
            title: title,
            coverUri: _imageUri(image),
            subtitle: subtitle,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    final current = int.tryParse(uri.queryParameters['paged'] ?? '') ?? 1;
    final next = document
        .querySelector('a[href*="paged=${current + 1}"]')
        ?.attributes['href'];
    return AnimeCatalogPage(
      items: items,
      nextCursor: next == null ? null : '${current + 1}',
    );
  }

  Future<AnimeCatalogPage> _latestCatalog(Uri uri) async {
    final document = await _getDocument(uri);
    final seenTitles = <String>{};
    final items = <AnimeCatalogItem>[];
    for (final node in document.querySelectorAll('.boxEP')) {
      final anchor = node.querySelector('a[href]');
      final episodeId = _episodeId(_resolveUri(anchor?.attributes['href']));
      final title = node.querySelector('.title')?.text.trim() ?? '';
      if (episodeId.isEmpty ||
          title.isEmpty ||
          !seenTitles.add(title.toLowerCase())) {
        continue;
      }
      final alias = 'release:$episodeId';
      final episode = node.querySelector('.ep-type')?.text.trim();
      final age = node.querySelector('.timeAgo')?.text.trim();
      items.add(AnimeCatalogItem(
        id: alias,
        title: title,
        coverUri: _resolveUri(
              node.querySelector('.thumb')?.attributes['data-thumb'],
            ) ??
            _backgroundUri(
              node.querySelector('.coverImg')?.attributes['style'],
            ),
        subtitle: [
          if (episode?.isNotEmpty == true) episode!,
          if (age?.isNotEmpty == true) age!,
        ].join(' · ').takeIfNotEmpty,
      ));
    }
    final current = int.tryParse(uri.queryParameters['paged'] ?? '') ?? 1;
    final next = document
        .querySelector('a[href*="paged=${current + 1}"]')
        ?.attributes['href'];
    return AnimeCatalogPage(
      items: items,
      nextCursor: next == null ? null : '${current + 1}',
    );
  }

  Future<String> _resolveAnimeId(String animeId) async {
    if (!animeId.startsWith('release:')) return animeId;
    final cached = _releaseAnimeIds[animeId];
    if (cached != null) return cached;
    final episodeId = animeId.substring('release:'.length);
    final document = await _getDocument(_episodeUri(episodeId));
    final anchor = document.querySelector(
      '.episodes-controls a[href*="/anime/"]',
    );
    final resolved = _animeId(_resolveUri(anchor?.attributes['href']));
    if (resolved.isEmpty) {
      throw StateError('Goyabu não informou a página deste anime.');
    }
    _releaseAnimeIds[animeId] = resolved;
    return resolved;
  }

  AnimeEpisode _episodeFromJson(String animeId, Map<Object?, Object?> row) {
    final id = (row['id'] ?? '').toString().trim();
    final rawNumber = (row['episodio'] ?? '').toString();
    final number = double.tryParse(
      RegExp(r'[\d.]+').firstMatch(rawNumber)?.group(0) ?? '',
    );
    final episodeName = (row['episode_name'] ?? '').toString().trim();
    return AnimeEpisode(
      id: id,
      animeId: animeId,
      title: episodeName.isNotEmpty
          ? episodeName
          : 'Episódio ${_displayNumber(number)}',
      number: number,
      releasedAt: DateTime.tryParse((row['update'] ?? '').toString()),
      thumbnailUri: _resolveUri((row['imagem'] ?? '').toString()),
    );
  }

  List<AnimeEpisode> _episodesFromDocument(
    String animeId,
    Document document,
  ) =>
      document
          .querySelectorAll('.boxEP a[href]')
          .map((anchor) {
            final uri = _resolveUri(anchor.attributes['href']);
            final text = anchor.querySelector('.ep-type')?.text ?? anchor.text;
            final number = double.tryParse(
              RegExp(r'[\d.]+').firstMatch(text)?.group(0) ?? '',
            );
            return AnimeEpisode(
              id: _episodeId(uri),
              animeId: animeId,
              title: 'Episódio ${_displayNumber(number)}',
              number: number,
              thumbnailUri: _backgroundUri(
                    anchor.querySelector('.coverImg')?.attributes['style'],
                  ) ??
                  _resolveUri(
                    anchor.querySelector('.thumb')?.attributes['data-thumb'],
                  ),
            );
          })
          .where((episode) => episode.id.isNotEmpty)
          .toList(growable: false);

  Future<Document> _getDocument(Uri uri) async =>
      html_parser.parse(await _getText(uri));

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    bool ajax = false,
    Uri? referer,
  }) async {
    final raw = await _getText(uri, ajax: ajax, referer: referer);
    var text = raw.trim();
    if (text.startsWith('<')) {
      text = html_parser.parse(text).body?.text.trim() ?? text;
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Goyabu retornou JSON inválido.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<String> _getText(
    Uri uri, {
    bool ajax = false,
    Uri? referer,
  }) async {
    await _loadSession();
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      if (ajax) 'X-Requested-With': 'XMLHttpRequest',
      if (referer != null) 'Referer': referer.toString(),
    });
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (_isBrowserChallenge(response.statusCode, body)) {
      final loader = _browserHtmlLoader;
      if (loader != null && _cookies.isNotEmpty) {
        try {
          final browserBody = await loader(uri, _userAgent);
          if (!_isBrowserChallenge(200, browserBody)) return browserBody;
        } catch (_) {
          // Fall through to the actionable session error below.
        }
      }
      throw const AnimeSourceSessionRequired(
        'Goyabu requires browser verification to continue.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Goyabu retornou HTTP ${response.statusCode}.',
        uri,
      );
    }
    return body;
  }

  Future<void> _loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    _userAgent = prefs.getString(_userAgentKey) ?? _defaultUserAgent;
    final encoded = prefs.getString(_cookiesKey);
    if (encoded == null) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        _cookies = decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      _cookies = const {};
    }
  }

  Uri _pagedUri(
    String path,
    String? cursor, [
    Map<String, String> parameters = const {},
  ]) =>
      _baseUri.resolve(path).replace(queryParameters: {
        ...parameters,
        if (cursor != null) 'paged': cursor,
      });

  Uri _animeUri(String id) => _baseUri.resolve('anime/$id');

  Uri _episodeUri(String id) => _baseUri.resolve(id);

  Uri? _resolveUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _resolveUri(
        image?.attributes['data-src'] ??
            image?.attributes['data-lazy-src'] ??
            image?.attributes['src'],
      );

  Uri? _backgroundUri(String? style) => _resolveUri(
        RegExp(r'''url\(["']?([^"')]+)''').firstMatch(style ?? '')?.group(1),
      );

  static String _animeId(Uri? uri) {
    if (uri == null) return '';
    final segments =
        uri.pathSegments.where((value) => value.isNotEmpty).toList();
    final index = segments.indexOf('anime');
    return index >= 0 && index + 1 < segments.length ? segments[index + 1] : '';
  }

  static String _episodeId(Uri? uri) => uri == null
      ? ''
      : uri.pathSegments.where((value) => value.isNotEmpty).lastOrNull ?? '';

  static String? _postId(Document document) => document
      .querySelector(
        '.rating-stars[data-post-id], #share-btn[data-post-id], '
        '#comments-section[data-post-id]',
      )
      ?.attributes['data-post-id']
      ?.trim()
      .takeIfNotEmpty;

  static Uri? _decodePlayerUri(String? encrypted) {
    if (encrypted == null || encrypted.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(encrypted)));
      return Uri.tryParse(decoded.split('').reversed.join());
    } catch (_) {
      return null;
    }
  }

  static AnimeStatus _status(String? value) {
    final normalized = value?.toLowerCase() ?? '';
    if (normalized.contains('lançamento') ||
        normalized.contains('lancamento') ||
        normalized.contains('andamento')) {
      return AnimeStatus.ongoing;
    }
    if (normalized.contains('completo') || normalized.contains('finalizado')) {
      return AnimeStatus.completed;
    }
    return AnimeStatus.unknown;
  }

  static String _quality(String value) =>
      value.toUpperCase().contains('FHD') ? 'FHD' : 'HD';

  static int? _bloggerHeight(String? itag) => switch (itag) {
        '37' => 1080,
        '22' => 720,
        '59' => 480,
        '18' => 360,
        _ => null,
      };

  static VideoProtocol _protocol(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('.m3u8')) return VideoProtocol.hls;
    if (value.contains('.mpd')) return VideoProtocol.dash;
    return VideoProtocol.progressive;
  }

  static bool _isBrowserChallenge(int statusCode, String body) {
    final normalized = body.toLowerCase();
    return statusCode == 403 ||
        normalized.contains('just a moment') ||
        normalized.contains('cf-chl-') ||
        normalized.contains('challenge-platform') ||
        normalized.contains('executando verificação de segurança');
  }

  static String _displayNumber(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
}

extension on String {
  String? get takeIfNotEmpty => isEmpty ? null : this;
}
