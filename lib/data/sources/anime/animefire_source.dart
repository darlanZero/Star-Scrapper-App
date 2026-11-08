import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Brazilian Portuguese anime catalog backed by AnimeFire's JSON API.
///
/// AnimeFire returns short-lived HLS manifests from the episode endpoint. They
/// are deliberately resolved only when playback starts.
class AnimeFireSource implements AnimeSource, FilterableAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://animefire.one/');
  static final Uri _defaultApiUri = Uri.parse('https://api.animefire.one/');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Uri _apiUri;
  final Map<String, String> _episodeAnimeIds = {};

  AnimeFireSource({
    http.Client? client,
    Uri? baseUri,
    Uri? apiUri,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _apiUri = apiUri ?? _defaultApiUri;

  @override
  String get id => 'animefire';

  @override
  String get name => 'AnimeFire';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.7',
        'Origin': _baseUri.origin,
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
      };

  Map<String, String> get _mediaHeaders => {
        'Accept': '*/*',
        'Origin': _baseUri.origin,
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.dubbed,
        AnimeCatalogFilter.added,
        AnimeCatalogFilter.catalog,
        AnimeCatalogFilter.movies,
        AnimeCatalogFilter.airing,
        AnimeCatalogFilter.upcoming,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) =>
      switch (filter) {
        AnimeCatalogFilter.recent => _homeCarousel('new-episodes'),
        AnimeCatalogFilter.popular => _homeCarousel('most-liked'),
        AnimeCatalogFilter.dubbed => _homeCarousel('new-animes-dubbed'),
        AnimeCatalogFilter.added => _homeCarousel('new-animes'),
        AnimeCatalogFilter.movies => _catalog('animes/filmes', cursor: cursor),
        AnimeCatalogFilter.airing => _launchCatalog(upcoming: false),
        AnimeCatalogFilter.upcoming => _launchCatalog(upcoming: true),
        _ => _catalog('animes', cursor: cursor),
      };

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return _catalog('animes', cursor: cursor);
    }
    return _catalog(
      'animes/pesquisar',
      cursor: cursor,
      parameters: {'q': normalized},
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final response = _map(await _getJson('animes'));
    final meta = _map(response['meta']);
    return AnimeSearchOptions(
      genres: _strings(meta['genres'])
          .map((genre) => AnimeFilterOption(value: genre, label: genre)),
      formats: const [
        AnimeFilterOption(value: 'anime', label: 'Animes'),
        AnimeFilterOption(value: 'movie', label: 'Filmes'),
      ],
      audioOptions: const [
        AnimeFilterOption(value: 'legendado', label: 'Legendado'),
        AnimeFilterOption(value: 'dublado', label: 'Dublado'),
      ],
      sorts: const [AnimeSearchSort.defaultOrder],
      labels: const {
        'formats': 'Catálogo',
        'audioOptions': 'Áudio',
      },
    );
  }

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final isMovie = request.formats.contains('movie');
    final query = request.query.trim();
    final path = query.isNotEmpty
        ? 'animes/pesquisar'
        : isMovie
            ? 'animes/filmes'
            : 'animes';
    return _catalog(
      path,
      cursor: cursor,
      parameters: {
        if (query.isNotEmpty) 'q': query,
        if (request.genres.isNotEmpty) 'genre': request.genres.first,
        if (request.audio != null) 'audio': request.audio!,
        if (isMovie && query.isNotEmpty) 'format': 'movie',
      },
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final resolvedId = await _resolveAnimeId(animeId);
    final response = _map(await _getJson(
      'anime/${Uri.encodeComponent(resolvedId)}',
    ));
    final data = _map(response['data']);
    final hero = _map(data['hero']);
    final title = _title(hero);
    final score = _number(hero['score']);
    final ageRating = _string(hero['age_rating']);
    final format = _formatLabel(data['format']);

    return AnimeDetails(
      item: AnimeCatalogItem(
        id: resolvedId,
        title: title,
        coverUri: _absoluteUri(hero['poster_src']),
        subtitle: [
          format,
          _string(hero['audio']),
          if (score != null) '${_displayNumber(score)} ★',
          if (ageRating.isNotEmpty) '$ageRating anos',
        ].where((value) => value.isNotEmpty).join(' · '),
      ),
      description: _string(hero['synopsis']),
      alternativeTitles: _map(hero['titles'])
          .values
          .map(_string)
          .where((value) => value.isNotEmpty && value != title),
      genres: _strings(hero['genres']),
      status: _status(hero['status']),
      bannerUri: _absoluteUri(hero['backdrop_src']),
      externalIds: {'animefire': resolvedId},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final resolvedId = await _resolveAnimeId(animeId);
    final response = _map(await _getJson(
      'anime/${Uri.encodeComponent(resolvedId)}',
    ));
    final data = _map(response['data']);
    return _maps(data['episodes'])
        .map((episode) {
          final episodeId = _string(episode['id']);
          _episodeAnimeIds[episodeId] = resolvedId;
          final number = _number(episode['number']);
          final title = _string(episode['title']);
          return AnimeEpisode(
            id: episodeId,
            animeId: resolvedId,
            title: title.isNotEmpty
                ? title
                : 'Episódio ${_displayNumber(number ?? 0)}',
            number: number,
            season: _integer(episode['season']),
            releasedAt: DateTime.tryParse(_string(episode['created_at'])),
            thumbnailUri: _absoluteUri(episode['still_src']),
          );
        })
        .where((episode) => episode.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final response = _map(await _getJson(
      'episode/${Uri.encodeComponent(_episodeId(episodeId))}',
    ));
    final data = _map(response['data']);
    final streams = <AnimeVideoStream>[];
    final skipSegments = <AnimeSkipSegment>[];
    final seenSkips = <String>{};
    var declaredStream = false;

    for (final stream in _maps(data['streams'])) {
      final uri = _absoluteUri(stream['url']);
      if (uri == null || stream['is_offline'] == true) continue;
      declaredStream = true;
      if (!await _isLiveManifest(uri)) continue;
      final audio = _string(stream['audio']);
      final qualities = _strings(stream['qualities']);
      streams.add(AnimeVideoStream(
        uri: uri,
        protocol: VideoProtocol.hls,
        quality: [
          _audioLabel(audio),
          if (qualities.isNotEmpty) qualities.join('/'),
        ].where((value) => value.isNotEmpty).join(' · '),
        language: _audioLanguage(audio),
        mimeType: 'application/vnd.apple.mpegurl',
        headers: _mediaHeaders,
      ));
      for (final chapter in _maps(stream['chapters'])) {
        final type = _skipType(chapter['type']);
        if (type == null) continue;
        final start = _number(chapter['start']);
        final end = _number(chapter['end']);
        if (start == null || end == null || end <= start) continue;
        final key = '${type.name}:$start:$end';
        if (!seenSkips.add(key)) continue;
        skipSegments.add(AnimeSkipSegment(
          start: Duration(milliseconds: (start * 1000).round()),
          end: Duration(milliseconds: (end * 1000).round()),
          type: type,
        ));
      }
    }
    if (streams.isEmpty) {
      if (declaredStream) {
        throw StateError(
          'O servidor de vídeo do AnimeFire está offline para este episódio. '
          'Durante a manutenção do site, somente episódios novos estão '
          'disponíveis.',
        );
      }
      throw StateError('AnimeFire não retornou um stream disponível.');
    }
    return AnimePlayback(streams: streams, skipSegments: skipSegments);
  }

  Future<bool> _isLiveManifest(Uri uri) async {
    try {
      final response = await _client.get(uri, headers: _mediaHeaders);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      return utf8
          .decode(response.bodyBytes, allowMalformed: true)
          .trimLeft()
          .startsWith('#EXTM3U');
    } catch (_) {
      return false;
    }
  }

  Future<AnimeCatalogPage> _homeCarousel(String key) async {
    final response = _map(await _getJson('home'));
    final data = _map(response['data']);
    final carousel = _maps(data['carousels']).where(
      (item) => _string(item['key']) == key,
    );
    if (carousel.isEmpty) return AnimeCatalogPage(items: const []);
    final isEpisode = key == 'new-episodes';
    return AnimeCatalogPage(
      items: _maps(carousel.first['items'])
          .map((item) => _catalogItem(item, episode: isEpisode))
          .whereType<AnimeCatalogItem>(),
    );
  }

  Future<AnimeCatalogPage> _catalog(
    String path, {
    String? cursor,
    Map<String, String> parameters = const {},
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final response = _map(await _getJson(path, {
      ...parameters,
      'page': '$page',
    }));
    final meta = _map(response['meta']);
    final currentPage = _integer(meta['current_page']) ?? page;
    final lastPage = _integer(meta['last_page']) ?? currentPage;
    return AnimeCatalogPage(
      items: _maps(response['data'])
          .map(_catalogItem)
          .whereType<AnimeCatalogItem>(),
      nextCursor: currentPage < lastPage ? '${currentPage + 1}' : null,
    );
  }

  Future<AnimeCatalogPage> _launchCatalog({required bool upcoming}) async {
    final response = _map(await _getJson('animes/lancamentos'));
    final data = _map(response['data']);
    final entries = upcoming
        ? _maps(_map(data['upcoming'])['items'])
        : _maps(data['animes']);
    entries.sort((left, right) {
      final leftDate = _launchDate(left, upcoming: upcoming);
      final rightDate = _launchDate(right, upcoming: upcoming);
      if (!upcoming && leftDate != null && rightDate != null) {
        final weekday = leftDate.weekday.compareTo(rightDate.weekday);
        if (weekday != 0) return weekday;
      }
      if (leftDate == null) return 1;
      if (rightDate == null) return -1;
      return leftDate.compareTo(rightDate);
    });
    return AnimeCatalogPage(
      items: entries
          .map((item) => _catalogItem(item, launch: true, upcoming: upcoming))
          .whereType<AnimeCatalogItem>(),
    );
  }

  AnimeCatalogItem? _catalogItem(
    Map<String, dynamic> data, {
    bool episode = false,
    bool launch = false,
    bool upcoming = false,
  }) {
    final rawId = _string(data['id']);
    final title = _title(data);
    if (rawId.isEmpty || title.isEmpty) return null;
    final id = episode ? 'episode:$rawId' : rawId;
    final number = _number(data['number']);
    final season = _integer(data['season']);
    final launchDate = launch ? _launchDate(data, upcoming: upcoming) : null;
    final nextAir = _map(data['next_air']);
    final audio = _string(data['audio']);
    return AnimeCatalogItem(
      id: id,
      title: title,
      coverUri: _absoluteUri(data['poster_src']),
      subtitle: [
        if (episode && season != null) 'T$season',
        if (episode && number != null) 'EP.${_displayNumber(number)}',
        if (launchDate != null && !upcoming) _weekday(launchDate.weekday),
        if (!upcoming) _string(nextAir['time']),
        if (launchDate != null && upcoming) _dateLabel(launchDate),
        if (data['is_new_season'] == true) 'Nova temporada',
        audio,
        if (!episode && !launch) _statusLabel(data['status']),
      ].where((value) => value.isNotEmpty).join(' · '),
    );
  }

  Future<String> _resolveAnimeId(String value) async {
    if (!value.startsWith('episode:')) return value;
    final episodeId = _episodeId(value);
    final cached = _episodeAnimeIds[episodeId];
    if (cached != null) return cached;
    final response = _map(await _getJson(
      'episode/${Uri.encodeComponent(episodeId)}',
    ));
    final animeId = _string(_map(_map(response['data'])['anime'])['id']);
    if (animeId.isEmpty) {
      throw StateError('AnimeFire não informou o anime deste episódio.');
    }
    _episodeAnimeIds[episodeId] = animeId;
    return animeId;
  }

  Future<Object?> _getJson(
    String path, [
    Map<String, String> parameters = const {},
  ]) async {
    final uri = _apiUri.resolve(path).replace(queryParameters: {
      ...parameters,
      'v': '3',
    });
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'AnimeFire retornou HTTP ${response.statusCode}.',
        uri,
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static DateTime? _launchDate(
    Map<String, dynamic> data, {
    required bool upcoming,
  }) {
    final value = upcoming
        ? _string(data['premieres_at'])
        : _string(_map(data['next_air'])['date']);
    return DateTime.tryParse(value);
  }

  static String _title(Map<String, dynamic> data) {
    final titles = _map(data['titles']);
    for (final key in const ['BR', 'US', 'JP']) {
      final title = _string(titles[key]);
      if (title.isNotEmpty) return title;
    }
    return '';
  }

  static String _episodeId(String value) =>
      value.startsWith('episode:') ? value.substring(8) : value;

  static AnimeStatus _status(Object? value) => switch (_string(value)) {
        'airing' => AnimeStatus.ongoing,
        'completed' => AnimeStatus.completed,
        'upcoming' => AnimeStatus.upcoming,
        'hiatus' => AnimeStatus.hiatus,
        'cancelled' => AnimeStatus.cancelled,
        _ => AnimeStatus.unknown,
      };

  static String _statusLabel(Object? value) => switch (_string(value)) {
        'airing' => 'Em lançamento',
        'completed' => 'Completo',
        'upcoming' => 'Em breve',
        _ => '',
      };

  static String _formatLabel(Object? value) => switch (_string(value)) {
        'tv' => 'Série',
        'movie' => 'Filme',
        final value when value.isNotEmpty => value.toUpperCase(),
        _ => '',
      };

  static String _audioLabel(String value) => switch (value.toLowerCase()) {
        'dublado' => 'Dublado',
        'legendado' => 'Legendado',
        _ => value,
      };

  static String _audioLanguage(String value) =>
      value.toLowerCase().contains('dublado') ? 'pt-BR' : 'ja';

  static AnimeSkipType? _skipType(Object? value) {
    final normalized = _string(value).toLowerCase();
    if (normalized.contains('intro') || normalized.contains('opening')) {
      return AnimeSkipType.intro;
    }
    if (normalized.contains('credit') ||
        normalized.contains('outro') ||
        normalized.contains('ending')) {
      return AnimeSkipType.outro;
    }
    if (normalized.contains('recap')) return AnimeSkipType.recap;
    if (normalized.contains('preview')) return AnimeSkipType.preview;
    return null;
  }

  static String _weekday(int weekday) => const {
        DateTime.monday: 'Segunda-feira',
        DateTime.tuesday: 'Terça-feira',
        DateTime.wednesday: 'Quarta-feira',
        DateTime.thursday: 'Quinta-feira',
        DateTime.friday: 'Sexta-feira',
        DateTime.saturday: 'Sábado',
        DateTime.sunday: 'Domingo',
      }[weekday]!;

  static String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _displayNumber(num value) =>
      value == value.truncateToDouble() ? '${value.toInt()}' : value.toString();

  static Uri? _absoluteUri(Object? value) {
    final uri = Uri.tryParse(_string(value));
    return uri != null && uri.hasScheme ? uri : null;
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  static List<String> _strings(Object? value) => value is List
      ? value.map(_string).where((item) => item.isNotEmpty).toList()
      : const <String>[];

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(_string(value));

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse(_string(value));
}
