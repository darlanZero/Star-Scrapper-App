import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/trackers/anilist_tracker_service.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';

class MalTrackerService implements TrackerService {
  static final Uri _baseUri = Uri.parse('https://api.myanimelist.net/v2');
  static const _fields =
      'id,title,main_picture,alternative_titles,start_date,end_date,'
      'synopsis,mean,rank,popularity,genres,nsfw,status,num_episodes,'
      'num_chapters,num_volumes,media_type,start_season';

  final http.Client _client;
  final String clientId;
  final String? accessToken;

  MalTrackerService({
    required this.clientId,
    this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  TrackerKind get kind => TrackerKind.myAnimeList;

  @override
  String get displayName => 'MyAnimeList';

  @override
  bool get isConfigured => clientId.trim().isNotEmpty;

  @override
  Future<TrackerHomeData> loadHome({
    required TrackedMediaType type,
    required bool includeAdult,
    DateTime? now,
  }) async {
    _requireConfiguration();
    final reference = now ?? DateTime.now();
    final popular = await _ranking(type, 'bypopularity');
    final highest = await _ranking(type, 'all');
    final sections = <TrackerSection>[
      TrackerSection(
        id: 'mal_popular',
        title: 'Popular on MyAnimeList',
        items: _adultFilter(popular, includeAdult),
      ),
      TrackerSection(
        id: 'mal_highest',
        title: 'Highest rated on MyAnimeList',
        items: _adultFilter(highest, includeAdult),
      ),
    ];

    if (type == TrackedMediaType.anime) {
      final current = _seasonFor(reference);
      final next = _nextSeason(current.season, current.year);
      final seasonal = await Future.wait([
        _season(current.year, current.season),
        _season(next.year, next.season),
      ]);
      sections.addAll([
        TrackerSection(
          id: 'mal_this_season',
          title: 'This season on MyAnimeList',
          items: _adultFilter(seasonal[0], includeAdult),
        ),
        TrackerSection(
          id: 'mal_upcoming_season',
          title: 'Upcoming on MyAnimeList',
          items: _adultFilter(seasonal[1], includeAdult),
        ),
      ]);
    }

    return TrackerHomeData(
      sections: sections.where((section) => section.items.isNotEmpty),
    );
  }

  @override
  Future<TrackerSearchPage> search(TrackerSearchRequest request) async {
    _requireConfiguration();
    final query = request.query.trim();
    List<TrackerMedia> results;
    bool hasNextPage;
    if (query.isEmpty) {
      final ranking = switch (request.sort) {
        TrackerSort.highestRated => 'all',
        _ => 'bypopularity',
      };
      results = await _ranking(request.type, ranking,
          offset: (request.page - 1) * 30);
      hasNextPage = results.length == 30;
    } else {
      final path = request.type == TrackedMediaType.anime ? 'anime' : 'manga';
      final json = await _get(
        '/$path',
        {
          'q': query,
          'limit': '30',
          'offset': '${(request.page - 1) * 30}',
          'fields': _fields,
        },
      );
      results = _parseList(json, request.type);
      final paging = json['paging'];
      hasNextPage = paging is Map &&
          (paging['next']?.toString().trim().isNotEmpty ?? false);
    }

    final requestedTags = {
      ...request.tags,
      ...request.genres,
    }.map((tag) => tag.toLowerCase()).toSet();
    final filtered = results.where((media) {
      if (!request.includeAdult && media.isAdult) return false;
      if (requestedTags.isEmpty) return true;
      final mediaTags = {...media.genres, ...media.tags}
          .map((tag) => tag.toLowerCase())
          .toSet();
      return requestedTags.every(mediaTags.contains);
    }).toList();
    return TrackerSearchPage(
      items: filtered,
      page: request.page,
      hasNextPage: hasNextPage,
    );
  }

  @override
  Future<TrackerSearchPage> loadSeason({
    required int year,
    required AnimeSeason season,
    required TrackerSort sort,
    required bool includeAdult,
    required int page,
  }) async {
    _requireConfiguration();
    final json = await _get(
      '/anime/season/$year/${season.name}',
      {
        'limit': '30',
        'offset': '${(page - 1) * 30}',
        'sort': sort == TrackerSort.highestRated
            ? 'anime_score'
            : 'anime_num_list_users',
        'fields': _fields,
      },
    );
    final items = _adultFilter(
      _parseList(json, TrackedMediaType.anime),
      includeAdult,
    );
    final paging = json['paging'];
    return TrackerSearchPage(
      items: items,
      page: page,
      hasNextPage: paging is Map &&
          (paging['next']?.toString().trim().isNotEmpty ?? false),
    );
  }

  @override
  Future<TrackerMediaDetails> loadDetails(TrackerMedia media) async {
    _requireConfiguration();
    final path = media.type == TrackedMediaType.anime ? 'anime' : 'manga';
    final fields = media.type == TrackedMediaType.anime
        ? '$_fields,source,average_episode_duration,studios'
        : '$_fields,authors';
    final json = await _get('/$path/${media.malId ?? media.id}', {
      'fields': fields,
    });
    final creators = <TrackerCredit>[];
    for (final author in (json['authors'] as List? ?? const [])) {
      if (author is! Map || author['node'] is! Map) continue;
      final node = author['node'] as Map;
      final first = node['first_name']?.toString().trim() ?? '';
      final last = node['last_name']?.toString().trim() ?? '';
      final name = [first, last].where((part) => part.isNotEmpty).join(' ');
      if (name.isEmpty) continue;
      creators.add(
        TrackerCredit(
          name: name,
          role: author['role']?.toString() ?? 'Author',
        ),
      );
    }
    final studios = (json['studios'] as List? ?? const [])
        .whereType<Map>()
        .map((studio) => studio['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    return TrackerMediaDetails(
      media: _parseMedia(json, media.type),
      format: _humanize(json['media_type']),
      status: _humanize(json['status']),
      source: _humanize(json['source']),
      episodes: (json['num_episodes'] as num?)?.toInt(),
      chapters: (json['num_chapters'] as num?)?.toInt(),
      volumes: (json['num_volumes'] as num?)?.toInt(),
      durationMinutes: json['average_episode_duration'] is num
          ? ((json['average_episode_duration'] as num).toInt() ~/ 60)
          : null,
      creators: creators,
      studios: studios,
    );
  }

  @override
  Future<List<TrackerSection>> loadLibrary({
    required TrackedMediaType type,
  }) async {
    if (accessToken == null || accessToken!.isEmpty) return const [];
    _requireConfiguration();
    final listPath = type == TrackedMediaType.anime ? 'animelist' : 'mangalist';
    final json = await _get(
      '/users/@me/$listPath',
      {'limit': '1000', 'fields': '$_fields,list_status'},
    );
    final data = json['data'];
    if (data is! List) return const [];
    final grouped = <String, List<TrackerMedia>>{};
    for (final rawEntry in data) {
      if (rawEntry is! Map || rawEntry['node'] is! Map) continue;
      final status = rawEntry['list_status'] is Map
          ? rawEntry['list_status'] as Map
          : const {};
      final statusKey = status['status']?.toString() ?? 'other';
      final node = (rawEntry['node'] as Map)
          .map((key, value) => MapEntry(key.toString(), value));
      final progressKey = type == TrackedMediaType.anime
          ? 'num_episodes_watched'
          : 'num_chapters_read';
      final totalKey =
          type == TrackedMediaType.anime ? 'num_episodes' : 'num_chapters';
      grouped.putIfAbsent(statusKey, () => []).add(
            _parseMedia(
              node,
              type,
              listStatus: statusKey,
              progress: (status[progressKey] as num?)?.toInt(),
              progressTotal: (node[totalKey] as num?)?.toInt(),
              listUpdatedAt: _date(status['updated_at']),
            ),
          );
    }
    return grouped.entries.map((entry) {
      entry.value.sort((a, b) => (b.listUpdatedAt ?? DateTime(0))
          .compareTo(a.listUpdatedAt ?? DateTime(0)));
      return TrackerSection(
        id: 'mal_${entry.key}',
        title: _libraryStatusLabel(entry.key, type),
        items: entry.value,
      );
    }).toList();
  }

  @override
  Future<TrackerTaxonomy> loadTaxonomy({required bool includeAdult}) async {
    // MAL does not expose a taxonomy collection endpoint. AniList supplies the
    // shared discovery taxonomy while MAL results are still filtered locally.
    return TrackerTaxonomy.empty;
  }

  Future<TrackerAccount> loadCurrentAccount() async {
    _requireConfiguration();
    if (accessToken == null || accessToken!.isEmpty) {
      throw const TrackerRequestException('MyAnimeList is not connected.');
    }
    final json = await _get('/users/@me', const {});
    return TrackerAccount(
      id: json['id'].toString(),
      username: json['name']?.toString() ?? 'MyAnimeList user',
      avatarUri: Uri.tryParse(json['picture']?.toString() ?? ''),
    );
  }

  Future<List<TrackerMedia>> _ranking(
    TrackedMediaType type,
    String rankingType, {
    int offset = 0,
  }) async {
    final path = type == TrackedMediaType.anime ? 'anime' : 'manga';
    final json = await _get(
      '/$path/ranking',
      {
        'ranking_type': rankingType,
        'limit': '30',
        'offset': '$offset',
        'fields': _fields,
      },
    );
    return _parseList(json, type);
  }

  Future<List<TrackerMedia>> _season(int year, String season) async {
    final json = await _get(
      '/anime/season/$year/$season',
      {'limit': '30', 'sort': 'anime_num_list_users', 'fields': _fields},
    );
    return _parseList(json, TrackedMediaType.anime);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = _baseUri.replace(
      path: '${_baseUri.path}$path',
      queryParameters: query,
    );
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'X-MAL-CLIENT-ID': clientId,
      if (accessToken != null && accessToken!.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerRequestException(
        'MyAnimeList request failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TrackerRequestException(
        'MyAnimeList returned an invalid response.',
      );
    }
    return decoded;
  }

  List<TrackerMedia> _parseList(
    Map<String, dynamic> json,
    TrackedMediaType type,
  ) {
    final data = json['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map((entry) {
      final raw = entry['node'] is Map ? entry['node'] as Map : entry;
      return _parseMedia(
        raw.map((key, value) => MapEntry(key.toString(), value)),
        type,
      );
    }).toList();
  }

  TrackerMedia _parseMedia(
    Map<String, dynamic> json,
    TrackedMediaType type, {
    String? listStatus,
    int? progress,
    int? progressTotal,
    DateTime? listUpdatedAt,
  }) {
    final alternatives = json['alternative_titles'] is Map
        ? json['alternative_titles'] as Map
        : const {};
    final pictures =
        json['main_picture'] is Map ? json['main_picture'] as Map : const {};
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final title = json['title']?.toString() ?? 'Untitled';
    return TrackerMedia(
      id: '$id',
      malId: id == 0 ? null : id,
      tracker: TrackerKind.myAnimeList,
      type: type,
      title: TrackerTitle(
        preferred: title,
        english: _text(alternatives['en']),
        romaji: title,
        native: _text(alternatives['ja']),
        synonyms: alternatives['synonyms'] is List
            ? (alternatives['synonyms'] as List).map((item) => '$item')
            : const [],
      ),
      coverUri: Uri.tryParse(
        (pictures['large'] ?? pictures['medium'] ?? '').toString(),
      ),
      siteUri: Uri.tryParse(
        type == TrackedMediaType.anime
            ? 'https://myanimelist.net/anime/$id'
            : 'https://myanimelist.net/manga/$id',
      ),
      description: json['synopsis']?.toString() ?? '',
      genres: json['genres'] is List
          ? (json['genres'] as List)
              .whereType<Map>()
              .map((genre) => genre['name']?.toString() ?? '')
              .where((genre) => genre.isNotEmpty)
          : const [],
      isAdult: const {'gray', 'black'}.contains(json['nsfw']),
      score: json['mean'] is num
          ? ((json['mean'] as num).toDouble() * 10).round()
          : null,
      popularity: (json['popularity'] as num?)?.toInt(),
      startDate: _date(json['start_date']),
      endDate: _date(json['end_date']),
      listStatus: listStatus,
      progress: progress,
      progressTotal: progressTotal,
      listUpdatedAt: listUpdatedAt,
    );
  }

  List<TrackerMedia> _adultFilter(
    List<TrackerMedia> items,
    bool includeAdult,
  ) {
    return items.where((item) => includeAdult || !item.isAdult).toList();
  }

  ({String season, int year}) _seasonFor(DateTime date) {
    final season = switch (date.month) {
      <= 3 => 'winter',
      <= 6 => 'spring',
      <= 9 => 'summer',
      _ => 'fall',
    };
    return (season: season, year: date.year);
  }

  ({String season, int year}) _nextSeason(String season, int year) {
    return switch (season) {
      'winter' => (season: 'spring', year: year),
      'spring' => (season: 'summer', year: year),
      'summer' => (season: 'fall', year: year),
      _ => (season: 'winter', year: year + 1),
    };
  }

  DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _humanize(dynamic value) {
    final text = _text(value);
    if (text == null) return null;
    return text
        .toLowerCase()
        .split('_')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _libraryStatusLabel(String status, TrackedMediaType type) {
    return switch (status) {
      'watching' => 'Watching',
      'reading' => 'Reading',
      'completed' => 'Completed',
      'on_hold' => 'On hold',
      'dropped' => 'Dropped',
      'plan_to_watch' => 'Plan to watch',
      'plan_to_read' => 'Plan to read',
      _ => type == TrackedMediaType.anime ? 'My anime' : 'My manga',
    };
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw const TrackerRequestException(
        'Add a MyAnimeList Client ID in Settings > Account > Trackers.',
      );
    }
  }
}
