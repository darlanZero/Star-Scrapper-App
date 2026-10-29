import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/animy/animy_session.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Animy.net anime provider. Uses the same account/token as AnimyMangaSource.
class AnimyAnimeSource implements AnimeSource, FilterableAnimeSource {
  static const _site = 'https://animy.net';
  static const _pageSize = 24;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36';

  final http.Client _client;
  final AnimySession _session;
  final Uri _baseUri;
  final Map<String, Map<String, dynamic>> _detailsCache = {};

  AnimyAnimeSource({http.Client? client, AnimySession? session, Uri? baseUri})
      : _client = client ?? http.Client(),
        _session = session ?? AnimySession(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'animy_anime';
  @override
  String get name => 'Animy';
  @override
  Uri get baseUri => _baseUri;
  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'application/json',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'User-Agent': _userAgent,
        'Referer': _baseUri.resolve('/animes/inicio/').toString(),
        if (_session.token case final token?) 'Authorization': 'Bearer $token',
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.popularWeek,
        AnimeCatalogFilter.popularMonth,
        AnimeCatalogFilter.catalog,
        AnimeCatalogFilter.updated,
        AnimeCatalogFilter.added,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    if (filter == AnimeCatalogFilter.recent) return _recentEpisodes();
    if (filter == AnimeCatalogFilter.popular ||
        filter == AnimeCatalogFilter.popularWeek ||
        filter == AnimeCatalogFilter.popularMonth) {
      final period = switch (filter) {
        AnimeCatalogFilter.popularWeek => 'week',
        AnimeCatalogFilter.popularMonth => 'month',
        _ => 'day',
      };
      return _top(period);
    }
    final sort = switch (filter) {
      AnimeCatalogFilter.updated => 'favorites',
      AnimeCatalogFilter.added => 'newest',
      _ => 'popular',
    };
    return _catalog(page: _page(cursor), sort: sort);
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => _catalog(
        page: _page(cursor),
        sort: 'popular',
        search: query.trim(),
      );

  Future<AnimeCatalogPage> _recentEpisodes() async {
    final payload = await _getJson('/animes/recent-episodes?limit=100');
    final items = _list(payload).map((raw) {
      final item = _map(raw);
      final id = item['seriesId']?.toString() ?? '';
      final season = _int(item['season']);
      final episode = _number(item['number']);
      return AnimeCatalogItem(
        id: id,
        title: item['seriesTitle']?.toString() ?? '',
        coverUri: Uri.tryParse(item['seriesCover']?.toString() ?? ''),
        subtitle: [
          if (season != null) 'Temporada $season',
          if (episode != null) 'Episódio ${_displayNumber(episode)}',
        ].join(' · '),
      );
    }).toList(growable: false);
    return AnimeCatalogPage(items: items);
  }

  Future<AnimeCatalogPage> _top(String period) async {
    final payload = _map(await _getJson('/animes/top?period=$period&limit=20'));
    return AnimeCatalogPage(
      items: _list(payload['items']).map((raw) => _catalogItem(_map(raw))),
    );
  }

  Future<AnimeCatalogPage> _catalog({
    required int page,
    required String sort,
    String search = '',
    Iterable<String> genres = const [],
    String? kind,
    String? audio,
    String? season,
    String? status,
    String? year,
  }) async {
    final params = <String, dynamic>{
      'limit': '$_pageSize',
      'offset': '${(page - 1) * _pageSize}',
      'sort': sort,
      if (search.isNotEmpty) 'search': search,
      if (genres.isNotEmpty) 'genre': genres,
      if (kind != null && kind.isNotEmpty) 'kind': kind,
      if (audio != null && audio.isNotEmpty) 'audio': audio,
      if (season != null && season.isNotEmpty) 'season': season,
      if (status != null && status.isNotEmpty) 'status': status,
      if (year != null && year.isNotEmpty) 'year': year,
    };
    final payload = _map(await _getJson('/animes?${_query(params)}'));
    final items =
        _list(payload['items']).map((raw) => _catalogItem(_map(raw))).toList();
    final total = _int(payload['total']) ?? items.length;
    return AnimeCatalogPage(
      items: items,
      nextCursor: page * _pageSize < total ? '${page + 1}' : null,
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final facets = _map(await _getJson('/animes/meta/facets'));
    return AnimeSearchOptions(
      genres: _options(facets['genres']),
      seasons: _options(facets['seasons']),
      years: _options(facets['years']),
      types: _options(facets['kinds']),
      statuses: _options(facets['statuses']),
      languages: _options(facets['audios']),
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.mostViewed,
        AnimeSearchSort.score,
        AnimeSearchSort.latestAdded,
      ],
    );
  }

  @override
  Future<AnimeCatalogPage> filter(AnimeSearchRequest request,
      {String? cursor}) {
    final sort = switch (request.sort) {
      AnimeSearchSort.score => 'score',
      AnimeSearchSort.latestAdded || AnimeSearchSort.releaseDate => 'newest',
      AnimeSearchSort.name => 'title',
      AnimeSearchSort.mostViewed => 'popular',
      _ => 'popular',
    };
    return _catalog(
      page: _page(cursor),
      sort: sort,
      search: request.query.trim(),
      genres: request.genres,
      kind: request.type,
      audio: request.language,
      season: request.season,
      status: request.status,
      year: request.year,
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final data = _map(await _getJson('/animes/$animeId'));
    _detailsCache[animeId] = data;
    final alternatives = <String>{
      if (data['nativeTitle']?.toString().isNotEmpty == true)
        data['nativeTitle'].toString(),
      ..._list(data['altTitles'])
          .map((raw) => _map(raw)['title']?.toString() ?? '')
          .where((title) => title.isNotEmpty),
    };
    final links = _map(data['links']).map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return AnimeDetails(
      item: _catalogItem(data),
      description: data['desc']?.toString() ?? '',
      alternativeTitles: alternatives,
      genres: _strings(data['g']),
      status: _status(data['status']),
      bannerUri: Uri.tryParse(data['banner']?.toString() ?? ''),
      externalIds: {'animy': animeId, ...links},
      studios: [
        if (data['studio']?.toString().isNotEmpty == true)
          data['studio'].toString()
      ],
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final data =
        _detailsCache[animeId] ?? _map(await _getJson('/animes/$animeId'));
    _detailsCache[animeId] = data;
    return _list(data['episodes']).map((raw) {
      final episode = _map(raw);
      final season = _int(episode['season']) ?? 1;
      final number = _number(episode['number']);
      return AnimeEpisode(
        id: '$season|${_displayNumber(number ?? 0)}',
        animeId: animeId,
        title: episode['title']?.toString().isNotEmpty == true
            ? episode['title'].toString()
            : episode['numberLabel']?.toString() ??
                'Episódio ${_displayNumber(number ?? 0)}',
        number: number,
        season: season,
        releasedAt: DateTime.tryParse(episode['date']?.toString() ?? ''),
        thumbnailUri: Uri.tryParse(episode['thumb']?.toString() ?? ''),
      );
    }).toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback(
      {required String animeId, required String episodeId}) async {
    final parts = episodeId.split('|');
    final season = parts.first;
    final number = parts.length > 1 ? parts[1] : '1';
    final data =
        _map(await _getJson('/animes/$animeId/episodes/$season/$number'));
    final streams = _list(data['streams'])
        .map((raw) {
          final stream = _map(raw);
          final uri = Uri.tryParse(stream['url']?.toString() ?? '');
          if (uri == null || !uri.hasScheme) return null;
          final kind = stream['kind']?.toString().toLowerCase();
          return AnimeVideoStream(
            uri: uri,
            protocol: kind == 'hls' || uri.path.endsWith('.m3u8')
                ? VideoProtocol.hls
                : VideoProtocol.progressive,
            quality: stream['quality']?.toString() ?? 'Auto',
            language: stream['audio']?.toString() ?? 'pt-BR',
            mimeType: kind == 'hls' ? 'application/x-mpegURL' : 'video/mp4',
            headers: {
              'User-Agent': _userAgent,
              'Referer': _baseUri.resolve('/animes/inicio/').toString(),
            },
          );
        })
        .whereType<AnimeVideoStream>()
        .toList();
    if (streams.isEmpty) {
      throw StateError(
          'A Animy não retornou uma mídia válida para este episódio.');
    }
    final skips = <AnimeSkipSegment>[];
    for (final raw in _list(data['streams'])) {
      final skip = _map(_map(raw)['skip']);
      if (skip['enabled'] != true) continue;
      final start = _number(skip['start']);
      final end = _number(skip['end']);
      if (start != null && end != null && end > start) {
        skips.add(AnimeSkipSegment(
          start: Duration(milliseconds: (start * 1000).round()),
          end: Duration(milliseconds: (end * 1000).round()),
        ));
      }
    }
    return AnimePlayback(streams: streams, skipSegments: skips);
  }

  Future<dynamic> _getJson(String path) async {
    await _session.restore();
    final response = await _client.get(_uri(path), headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Animy: HTTP ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Uri _uri(String path) =>
      _baseUri.resolve('/api/v1${path.startsWith('/') ? path : '/$path'}');

  AnimeCatalogItem _catalogItem(Map<String, dynamic> item) {
    final episodes = _int(item['eps'] ?? item['episodeTotal']);
    final audio = _strings(item['audios']);
    if (audio.isEmpty && item['audio'] != null) {
      audio.add(item['audio'].toString());
    }
    final score = _number(item['score']);
    final kind = item['kind']?.toString().toUpperCase();
    return AnimeCatalogItem(
      id: item['id']?.toString() ?? '',
      title: item['t']?.toString() ?? item['title']?.toString() ?? '',
      coverUri: Uri.tryParse(item['cover']?.toString() ?? ''),
      subtitle: [
        if (episodes != null) '$episodes eps',
        if (audio.isNotEmpty) audio.map(_titleCase).join('/'),
        if (kind != null && kind.isNotEmpty) kind,
        if (score != null && score > 0) '★ ${_displayNumber(score)}',
      ].join(' · '),
    );
  }

  static AnimeStatus _status(dynamic value) =>
      switch (value?.toString().toLowerCase()) {
        'airing' || 'ongoing' => AnimeStatus.ongoing,
        'completed' => AnimeStatus.completed,
        'hiatus' => AnimeStatus.hiatus,
        'cancelled' => AnimeStatus.cancelled,
        'upcoming' => AnimeStatus.upcoming,
        _ => AnimeStatus.unknown,
      };
  static int _page(String? cursor) => int.tryParse(cursor ?? '') ?? 1;
  static int? _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static String _displayNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  static String _titleCase(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  static List<dynamic> _list(dynamic value) => value is List ? value : const [];
  static List<String> _strings(dynamic value) =>
      _list(value).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  static List<AnimeFilterOption> _options(dynamic value) => _strings(value)
      .map((entry) => AnimeFilterOption(value: entry, label: _titleCase(entry)))
      .toList();
  static String _query(Map<String, dynamic> params) {
    final query = <String>[];
    for (final entry in params.entries) {
      final values = entry.value is Iterable && entry.value is! String
          ? entry.value as Iterable
          : [entry.value];
      for (final value in values) {
        if (value == null || value.toString().isEmpty) continue;
        query.add(
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value.toString())}');
      }
    }
    return query.join('&');
  }
}
