import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Brazilian Portuguese anime catalog backed by AnimesOnline.io.
///
/// Catalog metadata is server-rendered. Episodes decode AniDrive's protected
/// JWPlayer configuration natively and retain the browser resolver as a
/// compatibility fallback.
class AnimesOnlineSource
    implements AnimeSource, FilterableAnimeSource, BrowserPlaybackAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://animesonline.io/');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, Document> _animeDocuments = {};
  final Map<String, Document> _episodeDocuments = {};
  Uri? _pendingPlayerUri;

  AnimesOnlineSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'animes_online';

  @override
  String get name => 'Animes Online';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.6',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.catalog,
        AnimeCatalogFilter.airing,
        AnimeCatalogFilter.scheduleSunday,
        AnimeCatalogFilter.scheduleMonday,
        AnimeCatalogFilter.scheduleTuesday,
        AnimeCatalogFilter.scheduleWednesday,
        AnimeCatalogFilter.scheduleThursday,
        AnimeCatalogFilter.scheduleFriday,
        AnimeCatalogFilter.scheduleSaturday,
        AnimeCatalogFilter.scheduleUnknown,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.catalog,
    String? cursor,
  }) {
    final scheduleDay = switch (filter) {
      AnimeCatalogFilter.scheduleSunday => 'sunday',
      AnimeCatalogFilter.scheduleMonday => 'monday',
      AnimeCatalogFilter.scheduleTuesday => 'tuesday',
      AnimeCatalogFilter.scheduleWednesday => 'wednesday',
      AnimeCatalogFilter.scheduleThursday => 'thursday',
      AnimeCatalogFilter.scheduleFriday => 'friday',
      AnimeCatalogFilter.scheduleSaturday => 'saturday',
      AnimeCatalogFilter.scheduleUnknown => 'unknown',
      _ => null,
    };
    if (filter == AnimeCatalogFilter.airing || scheduleDay != null) {
      return _schedule(day: scheduleDay);
    }

    final parameters = switch (filter) {
      AnimeCatalogFilter.dubbed => <String, List<String>>{
          'sub': ['dub']
        },
      AnimeCatalogFilter.subtitled => <String, List<String>>{
          'sub': ['sub']
        },
      AnimeCatalogFilter.completed => <String, List<String>>{
          'status': ['completed'],
        },
      AnimeCatalogFilter.upcoming => <String, List<String>>{
          'status': ['upcoming'],
        },
      AnimeCatalogFilter.popular => <String, List<String>>{
          'order': ['popular'],
        },
      AnimeCatalogFilter.recent ||
      AnimeCatalogFilter.updated ||
      AnimeCatalogFilter.added =>
        <String, List<String>>{
          'order': ['latest']
        },
      _ => <String, List<String>>{},
    };
    return _catalog(parameters, cursor: cursor);
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => filter(
        AnimeSearchRequest(query: query),
        cursor: cursor,
      );

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final document = await _getDocument(_baseUri.resolve('anime/'));
    return AnimeSearchOptions(
      genres: _checkboxOptions(document, 'genre[]'),
      seasons: _checkboxOptions(document, 'season[]'),
      studios: _checkboxOptions(document, 'studio[]'),
      languages: _selectOptions(document, 'sub'),
      statuses: _selectOptions(document, 'status'),
      types: _selectOptions(document, 'type'),
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.nameDescending,
        AnimeSearchSort.releaseDate,
        AnimeSearchSort.latestUpdated,
        AnimeSearchSort.latestAdded,
        AnimeSearchSort.popularity,
        AnimeSearchSort.score,
      ],
      sortLabels: const {
        AnimeSearchSort.defaultOrder: 'A–Z',
        AnimeSearchSort.nameDescending: 'Z-A',
        AnimeSearchSort.releaseDate: 'Último episódio publicado',
        AnimeSearchSort.latestUpdated: 'Última atualização',
        AnimeSearchSort.latestAdded: 'Mais recentes',
        AnimeSearchSort.popularity: 'Popular',
        AnimeSearchSort.score: 'Avaliação',
      },
      labels: const {
        'genres': 'Gêneros',
        'genresAny': 'Todos os gêneros',
        'languages': 'Idioma',
        'seasons': 'Temporada',
        'studios': 'Estúdio',
        'statuses': 'Status',
        'types': 'Tipo',
        'sorts': 'Ordenar por',
      },
    );
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final parameters = <String, List<String>>{
      if (request.query.trim().isNotEmpty) 'keyword': [request.query.trim()],
      if (request.genres.isNotEmpty) 'genre[]': request.genres.toList(),
      if (request.language != null) 'sub': [request.language!],
      if (request.season != null) 'season[]': [request.season!],
      if (request.studio != null) 'studio[]': [request.studio!],
      if (request.status != null) 'status': [request.status!],
      if (request.type != null) 'type': [request.type!],
      if (_sortValue(request.sort) case final sort?) 'order': [sort],
    };
    return _catalog(parameters, cursor: cursor);
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final document = await _animeDocument(animeId);
    final title =
        document.querySelector('.entry-title')?.text.trim() ?? animeId;
    final cover = _imageUri(document.querySelector('.clean-anime-poster img'));
    final format =
        document.querySelector('.clean-anime-format')?.text.trim() ?? '';
    final score =
        document.querySelector('.clean-anime-rating strong')?.text.trim() ?? '';
    final statusLabel =
        document.querySelector('.clean-anime-status-label')?.text.trim() ?? '';
    final alternativeText = document
            .querySelector('.clean-anime-alternative')
            ?.text
            .replaceFirst(RegExp(r'^Títulos alternativos\s*'), '')
            .trim() ??
        '';
    final alternatives = alternativeText
        .split(RegExp(r'\s*[,;|]\s*'))
        .where((value) => value.isNotEmpty && value != title)
        .toList(growable: false);
    final genres = document
        .querySelectorAll('.clean-anime-genres a')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final studios = document
        .querySelectorAll('a[href*="/studio/"]')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final producers = document
        .querySelectorAll('a[href*="/producer/"]')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    return AnimeDetails(
      item: AnimeCatalogItem(
        id: animeId,
        title: title,
        coverUri: cover,
        subtitle: [
          format,
          statusLabel,
          if (score.isNotEmpty) '★ $score',
        ].where((value) => value.isNotEmpty).join(' · '),
      ),
      description: document
              .querySelector('#clean-anime-synopsis-content')
              ?.text
              .trim() ??
          '',
      alternativeTitles: alternatives,
      genres: genres,
      status: _status(statusLabel),
      bannerUri: cover,
      externalIds: {'animes_online': animeId},
      studios: studios,
      producers: producers,
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final document = await _animeDocument(animeId);
    final episodes = document
        .querySelectorAll('.eplister li[data-episode-id]')
        .map((row) {
          final id = row.attributes['data-episode-id']?.trim() ?? '';
          final numberText = row.querySelector('.epl-num')?.text.trim() ??
              row.querySelector('a')?.attributes['data-episode-label'] ??
              '';
          if (id.isEmpty) return null;
          final number = double.tryParse(
            RegExp(r'[\d.]+').firstMatch(numberText)?.group(0) ?? '',
          );
          final title = row.querySelector('.epl-title')?.text.trim() ?? '';
          return AnimeEpisode(
            id: id,
            animeId: animeId,
            title: title.isEmpty ? 'Episódio ${_displayNumber(number)}' : title,
            number: number,
          );
        })
        .whereType<AnimeEpisode>()
        .toList(growable: true)
      ..sort((left, right) => (left.number ?? double.infinity)
          .compareTo(right.number ?? double.infinity));
    if (episodes.isNotEmpty) return episodes;

    final watchUri = _resolveUri(
      document.querySelector('#clean-watch-primary')?.attributes['href'],
    );
    final episodeId = _numericPageId(watchUri);
    if (episodeId == null) return const [];
    return [
      AnimeEpisode(
        id: episodeId,
        animeId: animeId,
        title: 'Filme',
        number: 1,
        thumbnailUri: _imageUri(
          document.querySelector('.clean-anime-poster img'),
        ),
      ),
    ];
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final episodeUri = _baseUri.resolve('${_episodeId(episodeId)}/');
    final document = await _episodeDocument(episodeId);
    final directStreams = <AnimeVideoStream>[];
    final seen = <String>{};
    for (final element in document.querySelectorAll(
      '.player-embed video[src], .player-embed video source[src], '
      '.player-embed source[src]',
    )) {
      final uri = _resolveUri(element.attributes['src']);
      if (uri == null || !_isMediaUri(uri) || !seen.add(uri.toString())) {
        continue;
      }
      directStreams.add(_videoStream(uri, referer: episodeUri));
    }
    if (directStreams.isNotEmpty) {
      return AnimePlayback(streams: directStreams);
    }

    final choices = <AnimePlaybackChoice>[];
    for (final frame in document.querySelectorAll('.player-embed iframe')) {
      final uri = _resolveUri(
        frame.attributes['data-src'] ?? frame.attributes['src'],
      );
      if (uri == null ||
          uri.scheme == 'data' ||
          !seen.add(uri.toString()) ||
          !{'http', 'https'}.contains(uri.scheme)) {
        continue;
      }
      _pendingPlayerUri = uri;
      if (_isAniDriveUri(uri)) {
        try {
          final streams = await _resolveAniDrive(
            uri,
            episodeReferer: episodeUri,
          );
          if (streams.isNotEmpty) return AnimePlayback(streams: streams);
        } catch (_) {
          // AniDrive occasionally changes its protected player payload. Keep
          // the browser resolver as a fallback instead of failing playback.
        }
      }
      choices.add(AnimePlaybackChoice(
        entryUri: uri,
        provider: _providerName(uri),
        quality: 'Auto',
        headers: {
          'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
          'Origin': _baseUri.origin,
          'Referer': episodeUri.toString(),
        },
      ));
    }
    if (choices.isNotEmpty) {
      throw AnimePlaybackResolutionRequired(choices);
    }
    throw StateError('Animes Online não expôs um player para este episódio.');
  }

  Future<List<AnimeVideoStream>> _resolveAniDrive(
    Uri playerUri, {
    required Uri episodeReferer,
  }) async {
    final response = await _client.get(playerUri, headers: {
      ...requestHeaders,
      'Referer': episodeReferer.toString(),
      'Sec-Fetch-Dest': 'iframe',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'cross-site',
      'Upgrade-Insecure-Requests': '1',
    }).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'AniDrive retornou HTTP ${response.statusCode}.',
        playerUri,
      );
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final decodedScripts = _decodeAniDriveScripts(html);
    final seen = <String>{};
    final streams = <AnimeVideoStream>[];
    for (final script in [html, ...decodedScripts]) {
      final config = _aniDrivePlayerConfig(script);
      final sources = config?['sources'];
      if (sources is! List) continue;
      for (final source in sources.whereType<Map>()) {
        final uri = Uri.tryParse(source['file']?.toString() ?? '');
        if (uri == null || !_isMediaUri(uri) || !seen.add(uri.toString())) {
          continue;
        }
        streams.add(
          _videoStream(
            uri,
            referer: playerUri,
            quality: source['label']?.toString().trim(),
          ),
        );
      }
    }
    return streams;
  }

  static List<String> _decodeAniDriveScripts(String html) {
    final decoded = <String>[];
    final pending = <String>[html];
    final inspected = <String>{};
    final invocation = RegExp(
      r'\}\s*_[A-Za-z0-9]+\((\[.*?\]),(\[[\d,\s]+\]),"([^"]+)"\)',
      dotAll: true,
    );

    while (pending.isNotEmpty && inspected.length < 12) {
      final source = pending.removeLast();
      if (!inspected.add(source)) continue;
      for (final match in invocation.allMatches(source)) {
        try {
          final chunks = (jsonDecode(match.group(1)!) as List).cast<String>();
          final indices = (jsonDecode(match.group(2)!) as List).cast<int>();
          final cipher = base64Decode(
            indices.map((index) => chunks[index]).join(),
          );
          final key = base64Decode(match.group(3)!);
          if (key.isEmpty) continue;
          final plain = List<int>.generate(
            cipher.length,
            (index) => cipher[index] ^ key[index % key.length],
            growable: false,
          );
          final script = utf8.decode(plain, allowMalformed: true);
          decoded.add(script);
          pending.add(script);
        } catch (_) {
          // Ignore unrelated or malformed obfuscator calls.
        }
      }
    }
    return decoded;
  }

  static Map<String, dynamic>? _aniDrivePlayerConfig(String script) {
    final match = RegExp(
      r'window\.AniDrivePlayerConfig\s*=\s*(\{.*?\})\s*;',
      dotAll: true,
    ).firstMatch(script);
    if (match == null) return null;
    try {
      final value = jsonDecode(match.group(1)!);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AnimePlayback> playbackFromResolvedUri(
    Uri uri, {
    String quality = 'Auto',
    String provider = 'Browser',
  }) async {
    if (!_isMediaUri(uri)) {
      throw StateError(
        'O player do Animes Online não expôs uma URL de mídia válida.',
      );
    }
    final referer = _pendingPlayerUri ?? _baseUri;
    return AnimePlayback(streams: [
      AnimeVideoStream(
        uri: uri,
        protocol: _protocol(uri),
        quality: quality,
        language: 'pt-BR',
        mimeType: _mimeType(uri),
        headers: {
          'Accept': '*/*',
          'Origin': referer.origin,
          'Referer': referer.toString(),
          'User-Agent': _userAgent,
        },
      ),
    ]);
  }

  Future<AnimeCatalogPage> _catalog(
    Map<String, List<String>> parameters, {
    String? cursor,
  }) async {
    final query = <String, dynamic>{
      for (final entry in parameters.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
      if (int.tryParse(cursor ?? '') case final page? when page > 1)
        'page': page.toString(),
    };
    final uri = _baseUri.resolve('anime/').replace(
          queryParameters: query.isEmpty ? null : query,
        );
    final document = await _getDocument(uri);
    return AnimeCatalogPage(
      items: document
          .querySelectorAll('#catalog-results .catalog-card, .catalog-card')
          .map(_catalogItem)
          .whereType<AnimeCatalogItem>(),
      nextCursor: _nextCursor(document),
    );
  }

  Future<AnimeCatalogPage> _schedule({String? day}) async {
    final document = await _getDocument(_baseUri.resolve('lancamentos/'));
    final selector =
        day == null ? '.schedulepage .bs' : '.schedulepage.sch_$day .bs';
    return AnimeCatalogPage(
      items: document
          .querySelectorAll(selector)
          .map(_scheduleItem)
          .whereType<AnimeCatalogItem>(),
    );
  }

  AnimeCatalogItem? _catalogItem(Element card) {
    final anchor = card.querySelector('a[href*="/anime/"]');
    final uri = _resolveUri(anchor?.attributes['href']);
    final id = _segmentAfter(uri, 'anime');
    final title = card.querySelector('h2')?.text.trim() ??
        anchor?.attributes['title']?.trim() ??
        '';
    if (id.isEmpty || title.isEmpty) return null;
    final metadata =
        card.querySelector('.catalog-card-meta')?.text.trim() ?? '';
    final labels = card
        .querySelectorAll('.catalog-card-labels span')
        .map((element) => element.text.trim())
        .where((value) => value.isNotEmpty);
    return AnimeCatalogItem(
      id: id,
      title: title,
      coverUri: _imageUri(card.querySelector('.catalog-poster img')),
      subtitle:
          [metadata, ...labels].where((value) => value.isNotEmpty).join(' · '),
    );
  }

  AnimeCatalogItem? _scheduleItem(Element card) {
    final anchor = card.querySelector('a[href*="/anime/"]');
    final uri = _resolveUri(anchor?.attributes['href']);
    final id = _segmentAfter(uri, 'anime');
    final title = anchor?.attributes['title']?.trim() ??
        card.querySelector('.tt')?.text.trim() ??
        '';
    if (id.isEmpty || title.isEmpty) return null;
    final time = card.querySelector('.epx')?.text.trim() ?? '';
    final episode = card.querySelector('.sb')?.text.trim() ?? '';
    return AnimeCatalogItem(
      id: id,
      title: title,
      coverUri: _imageUri(card.querySelector('img')),
      subtitle: [
        if (episode.isNotEmpty) 'EP $episode',
        time,
      ].where((value) => value.isNotEmpty).join(' · '),
    );
  }

  Future<Document> _animeDocument(String animeId) async {
    final cached = _animeDocuments[animeId];
    if (cached != null) return cached;
    final document = await _getDocument(_baseUri.resolve('anime/$animeId/'));
    _animeDocuments[animeId] = document;
    return document;
  }

  Future<Document> _episodeDocument(String episodeId) async {
    final id = _episodeId(episodeId);
    final cached = _episodeDocuments[id];
    if (cached != null) return cached;
    final document = await _getDocument(_baseUri.resolve('$id/'));
    _episodeDocuments[id] = document;
    return document;
  }

  Future<Document> _getDocument(Uri uri) async =>
      html_parser.parse(await _getText(uri));

  Future<String> _getText(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client.get(uri, headers: {
          ...requestHeaders,
          'Referer': _baseUri.toString(),
        }).timeout(const Duration(seconds: 45));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return utf8.decode(response.bodyBytes, allowMalformed: true);
        }
        lastError = http.ClientException(
          'Animes Online retornou HTTP ${response.statusCode}.',
          uri,
        );
        if (response.statusCode < 500) break;
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
    if (lastError is Exception) throw lastError;
    throw http.ClientException('Animes Online não concluiu a resposta.', uri);
  }

  List<AnimeFilterOption> _checkboxOptions(Document document, String name) =>
      document
          .querySelectorAll('input[name="$name"][value]')
          .map((input) {
            final value = input.attributes['value']?.trim() ?? '';
            final label = input.parent?.text.trim() ?? '';
            return AnimeFilterOption(value: value, label: label);
          })
          .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
          .toList(growable: false);

  List<AnimeFilterOption> _selectOptions(Document document, String name) =>
      document
          .querySelectorAll('select[name="$name"] option[value]')
          .map((option) => AnimeFilterOption(
                value: option.attributes['value']?.trim() ?? '',
                label: option.text.trim(),
              ))
          .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
          .toList(growable: false);

  String? _nextCursor(Document document) {
    final href = document
        .querySelector('.catalog-page-directions a[rel="next"]')
        ?.attributes['href'];
    final uri = _resolveUri(href);
    if (uri == null) return null;
    final queryPage = int.tryParse(uri.queryParameters['page'] ?? '');
    if (queryPage != null) return queryPage.toString();
    return RegExp(r'/page/(\d+)').firstMatch(uri.path)?.group(1);
  }

  AnimeVideoStream _videoStream(
    Uri uri, {
    required Uri referer,
    String? quality,
  }) =>
      AnimeVideoStream(
        uri: uri,
        protocol: _protocol(uri),
        quality: quality == null || quality.isEmpty ? 'Auto' : quality,
        language: 'pt-BR',
        mimeType: _mimeType(uri),
        headers: {
          'Accept': '*/*',
          'Origin': referer.origin,
          'Referer': referer.toString(),
          'User-Agent': _userAgent,
        },
      );

  Uri? _resolveUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().startsWith('//')
        ? '${_baseUri.scheme}:${value.trim()}'
        : value.trim();
    return _baseUri.resolve(normalized);
  }

  Uri? _imageUri(Element? image) => _resolveUri(
        image?.attributes['data-src'] ?? image?.attributes['src'],
      );

  static String _segmentAfter(Uri? uri, String segment) {
    if (uri == null) return '';
    final parts = uri.pathSegments.where((value) => value.isNotEmpty).toList();
    final index = parts.indexOf(segment);
    return index >= 0 && index + 1 < parts.length ? parts[index + 1] : '';
  }

  static String? _numericPageId(Uri? uri) {
    if (uri == null) return null;
    final parts = uri.pathSegments.where((value) => value.isNotEmpty).toList();
    if (parts.length != 1 || int.tryParse(parts.single) == null) return null;
    return parts.single;
  }

  static String _episodeId(String value) =>
      value.replaceAll(RegExp(r'^episode:'), '').replaceAll('/', '').trim();

  static String? _sortValue(AnimeSearchSort sort) => switch (sort) {
        AnimeSearchSort.defaultOrder || AnimeSearchSort.name => null,
        AnimeSearchSort.nameDescending => 'titlereverse',
        AnimeSearchSort.releaseDate => 'episode',
        AnimeSearchSort.latestUpdated => 'update',
        AnimeSearchSort.latestAdded || AnimeSearchSort.dateAdded => 'latest',
        AnimeSearchSort.popularity => 'popular',
        AnimeSearchSort.score || AnimeSearchSort.averageScore => 'rating',
        _ => null,
      };

  static AnimeStatus _status(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('completo')) return AnimeStatus.completed;
    if (normalized.contains('breve')) return AnimeStatus.upcoming;
    if (normalized.contains('hiato')) return AnimeStatus.hiatus;
    if (normalized.contains('lançamento') ||
        normalized.contains('lancamento') ||
        normalized.contains('andamento')) {
      return AnimeStatus.ongoing;
    }
    return AnimeStatus.unknown;
  }

  static bool _isMediaUri(Uri uri) {
    final value = uri.toString().toLowerCase();
    return uri.host.toLowerCase().endsWith('googlevideo.com') ||
        RegExp(r'\.(m3u8|mpd|mp4|mkv|webm)(\?|$)').hasMatch(value) ||
        (uri.queryParameters['mime']?.startsWith('video/') ?? false);
  }

  static VideoProtocol _protocol(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('.m3u8')) return VideoProtocol.hls;
    if (value.contains('.mpd')) return VideoProtocol.dash;
    return VideoProtocol.progressive;
  }

  static String? _mimeType(Uri uri) {
    final mime = uri.queryParameters['mime'];
    if (mime != null && mime.startsWith('video/')) return mime;
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (path.endsWith('.mpd')) return 'application/dash+xml';
    if (path.endsWith('.mp4') || uri.host.endsWith('googlevideo.com')) {
      return 'video/mp4';
    }
    return null;
  }

  static String _providerName(Uri uri) =>
      uri.host.toLowerCase().contains('anidrive') ? 'AniDrive' : uri.host;

  static bool _isAniDriveUri(Uri uri) =>
      uri.host.toLowerCase().contains('anidrive');

  static String _displayNumber(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
}
