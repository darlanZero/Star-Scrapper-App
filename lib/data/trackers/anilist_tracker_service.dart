import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/trackers/tracker.dart';

class AniListTrackerService implements TrackerService {
  static final Uri _endpoint = Uri.parse('https://graphql.anilist.co');

  final http.Client _client;
  final String? accessToken;
  final String? userId;

  AniListTrackerService({this.accessToken, this.userId, http.Client? client})
      : _client = client ?? http.Client();

  @override
  TrackerKind get kind => TrackerKind.aniList;

  @override
  String get displayName => 'AniList';

  @override
  bool get isConfigured => true;

  @override
  Future<TrackerHomeData> loadHome({
    required TrackedMediaType type,
    required bool includeAdult,
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toUtc();
    final currentSeason = _seasonFor(reference);
    final nextSeason = _nextSeason(currentSeason, reference.year);
    final mediaType = _mediaType(type);
    final includeSeason = type == TrackedMediaType.anime;
    final scheduleStart = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
    );
    final scheduleEnd = scheduleStart.add(const Duration(days: 14));

    final data = await _post(
      _homeQuery(
        includeSeason: includeSeason,
        restrictAdult: !includeAdult,
      ),
      {
        'type': mediaType,
        'season': currentSeason.name.toUpperCase(),
        'seasonYear': reference.year,
        'nextSeason': nextSeason.season.name.toUpperCase(),
        'nextSeasonYear': nextSeason.year,
        'scheduleStart': scheduleStart.millisecondsSinceEpoch ~/ 1000,
        'scheduleEnd': scheduleEnd.millisecondsSinceEpoch ~/ 1000,
      },
    );

    final sections = <TrackerSection>[
      _section(data, 'popular', 'Popular'),
      _section(data, 'trending', 'Trending now'),
      _section(data, 'recent', 'Most recent'),
      _section(data, 'highestRated', 'Highest rated'),
      if (includeSeason) _section(data, 'thisSeason', 'Popular this season'),
      if (includeSeason) _section(data, 'upcomingSeason', 'Upcoming season'),
      _section(data, 'action', 'Action'),
      _section(data, 'romance', 'Romance'),
      _section(data, 'fantasy', 'Fantasy'),
      _section(data, 'comedy', 'Comedy'),
    ].where((section) => section.items.isNotEmpty).toList();

    return TrackerHomeData(
      schedule: includeSeason
          ? _parseSchedule(data['schedule'])
              .where((entry) => includeAdult || !entry.media.isAdult)
              .toList()
          : const [],
      sections: sections,
    );
  }

  @override
  Future<TrackerSearchPage> search(TrackerSearchRequest request) async {
    final data = await _post(
      _searchQuery(restrictAdult: !request.includeAdult),
      {
        'page': request.page,
        'type': _mediaType(request.type),
        'search': request.query.trim().isEmpty ? null : request.query.trim(),
        'tags': request.tags.isEmpty ? null : request.tags,
        'genres': request.genres.isEmpty ? null : request.genres,
        'sort': [_mediaSort(request.sort)],
      },
    );
    final page = data['Page'];
    final items = _mediaNodes(page).map(_parseMedia).toList();
    final pageInfo = page is Map && page['pageInfo'] is Map
        ? page['pageInfo'] as Map
        : const {};
    return TrackerSearchPage(
      items: items,
      page: request.page,
      hasNextPage: pageInfo['hasNextPage'] == true ||
          (pageInfo.isEmpty && items.length == 30),
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
    final data = await _post(
      _seasonQuery(restrictAdult: !includeAdult),
      {
        'page': page,
        'season': season.name.toUpperCase(),
        'seasonYear': year,
        'sort': [_mediaSort(sort)],
      },
    );
    final result = data['Page'];
    final items = _mediaNodes(result).map(_parseMedia).toList();
    final pageInfo = result is Map && result['pageInfo'] is Map
        ? result['pageInfo'] as Map
        : const {};
    return TrackerSearchPage(
      items: items,
      page: page,
      hasNextPage: pageInfo['hasNextPage'] == true,
    );
  }

  @override
  Future<TrackerMediaDetails> loadDetails(TrackerMedia media) async {
    final aniListId =
        media.tracker == TrackerKind.aniList ? int.tryParse(media.id) : null;
    final data = await _post(
      _detailsQuery,
      {
        if (aniListId != null) 'id': aniListId,
        if (aniListId == null && media.malId != null) 'idMal': media.malId,
        'type': _mediaType(media.type),
      },
    );
    final raw = data['Media'];
    if (raw is! Map) {
      throw const TrackerRequestException('AniList details were not found.');
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final staff = json['staff'] is Map ? json['staff'] as Map : const {};
    final creators = <TrackerCredit>[];
    for (final edge in (staff['edges'] as List? ?? const [])) {
      if (edge is! Map || edge['node'] is! Map) continue;
      final node = edge['node'] as Map;
      final name = node['name'] is Map ? node['name'] as Map : const {};
      final image = node['image'] is Map ? node['image'] as Map : const {};
      final fullName = _stringOrNull(name['full']);
      if (fullName == null) continue;
      creators.add(
        TrackerCredit(
          name: fullName,
          role: _stringOrNull(edge['role']) ?? 'Staff',
          imageUri: _uriOrNull(image['large'] ?? image['medium']),
          siteUri: _uriOrNull(node['siteUrl']),
        ),
      );
    }

    final characters =
        json['characters'] is Map ? json['characters'] as Map : const {};
    final voiceActors = <TrackerCredit>[];
    final seenVoiceActors = <String>{};
    for (final edge in (characters['edges'] as List? ?? const [])) {
      if (edge is! Map) continue;
      final character = edge['node'] is Map ? edge['node'] as Map : const {};
      final characterName = character['name'] is Map
          ? _stringOrNull((character['name'] as Map)['full'])
          : null;
      for (final actor in (edge['voiceActors'] as List? ?? const [])) {
        if (actor is! Map) continue;
        final name = actor['name'] is Map ? actor['name'] as Map : const {};
        final actorName = _stringOrNull(name['full']);
        if (actorName == null || !seenVoiceActors.add(actorName)) continue;
        final image = actor['image'] is Map ? actor['image'] as Map : const {};
        voiceActors.add(
          TrackerCredit(
            name: actorName,
            role: characterName == null
                ? 'Voice actor'
                : 'Voice of $characterName',
            imageUri: _uriOrNull(image['large'] ?? image['medium']),
            siteUri: _uriOrNull(actor['siteUrl']),
          ),
        );
      }
    }

    final studiosJson =
        json['studios'] is Map ? json['studios'] as Map : const {};
    final studios = <String>[];
    for (final edge in (studiosJson['edges'] as List? ?? const [])) {
      if (edge is! Map || edge['node'] is! Map) continue;
      final name = _stringOrNull((edge['node'] as Map)['name']);
      if (name != null) studios.add(name);
    }

    final reviewsJson =
        json['reviews'] is Map ? json['reviews'] as Map : const {};
    final reviews = <TrackerReview>[];
    for (final rawReview in (reviewsJson['nodes'] as List? ?? const [])) {
      if (rawReview is! Map) continue;
      final user =
          rawReview['user'] is Map ? rawReview['user'] as Map : const {};
      final avatar = user['avatar'] is Map ? user['avatar'] as Map : const {};
      reviews.add(
        TrackerReview(
          summary: _plainText(rawReview['summary']?.toString() ?? ''),
          body: _plainText(rawReview['body']?.toString() ?? ''),
          rating: (rawReview['rating'] as num?)?.toInt(),
          score: (rawReview['score'] as num?)?.toInt(),
          username: _stringOrNull(user['name']),
          avatarUri: _uriOrNull(avatar['large'] ?? avatar['medium']),
          siteUri: _uriOrNull(rawReview['siteUrl']),
        ),
      );
    }

    return TrackerMediaDetails(
      media: _parseMedia(json),
      format: _humanize(json['format']),
      status: _humanize(json['status']),
      source: _humanize(json['source']),
      episodes: (json['episodes'] as num?)?.toInt(),
      chapters: (json['chapters'] as num?)?.toInt(),
      volumes: (json['volumes'] as num?)?.toInt(),
      durationMinutes: (json['duration'] as num?)?.toInt(),
      creators: creators,
      voiceActors: voiceActors,
      studios: studios,
      reviews: reviews,
    );
  }

  @override
  Future<List<TrackerSection>> loadLibrary({
    required TrackedMediaType type,
  }) async {
    final id = int.tryParse(userId ?? '');
    if (accessToken == null || accessToken!.isEmpty || id == null) {
      return const [];
    }
    final data = await _post(
      _libraryQuery,
      {'userId': id, 'type': _mediaType(type)},
    );
    final collection = data['MediaListCollection'];
    if (collection is! Map || collection['lists'] is! List) return const [];

    final sections = <TrackerSection>[];
    for (final rawList in collection['lists'] as List) {
      if (rawList is! Map || rawList['entries'] is! List) continue;
      final items = <TrackerMedia>[];
      for (final rawEntry in rawList['entries'] as List) {
        if (rawEntry is! Map || rawEntry['media'] is! Map) continue;
        final mediaJson = (rawEntry['media'] as Map)
            .map((key, value) => MapEntry(key.toString(), value));
        items.add(
          _parseMedia(
            mediaJson,
            listStatus: rawEntry['status']?.toString(),
            progress: (rawEntry['progress'] as num?)?.toInt(),
            progressTotal: type == TrackedMediaType.anime
                ? (mediaJson['episodes'] as num?)?.toInt()
                : (mediaJson['chapters'] as num?)?.toInt(),
            listUpdatedAt: _unixDate(rawEntry['updatedAt']),
          ),
        );
      }
      if (items.isEmpty) continue;
      items.sort((a, b) => (b.listUpdatedAt ?? DateTime(0))
          .compareTo(a.listUpdatedAt ?? DateTime(0)));
      sections.add(
        TrackerSection(
          id: 'anilist_${rawList['status'] ?? rawList['name']}',
          title: rawList['name']?.toString() ?? 'My AniList',
          items: items,
        ),
      );
    }
    return sections;
  }

  @override
  Future<TrackerTaxonomy> loadTaxonomy({required bool includeAdult}) async {
    final data = await _post(_taxonomyQuery, const {});
    const adultOnlyGenres = {'hentai'};
    final genres = _stringList(data['GenreCollection'])
        .where((genre) =>
            includeAdult || !adultOnlyGenres.contains(genre.toLowerCase()))
        .toList()
      ..sort();
    final rawTags = data['MediaTagCollection'];
    final tags = rawTags is List
        ? rawTags.whereType<Map>().map((raw) {
            return TrackerTag(
              name: raw['name']?.toString() ?? '',
              category: raw['category']?.toString() ?? 'Other',
              isAdult: raw['isAdult'] == true,
            );
          }).where((tag) {
            return tag.name.isNotEmpty && (includeAdult || !tag.isAdult);
          }).toList()
        : <TrackerTag>[];
    tags.sort((a, b) {
      final category = a.category.compareTo(b.category);
      return category != 0 ? category : a.name.compareTo(b.name);
    });
    return TrackerTaxonomy(genres: genres, tags: tags);
  }

  Future<TrackerAccount> loadCurrentAccount() async {
    if (accessToken == null || accessToken!.isEmpty) {
      throw const TrackerRequestException('AniList is not connected.');
    }
    final data = await _post(_viewerQuery, const {});
    final viewer = data['Viewer'];
    if (viewer is! Map) {
      throw const TrackerRequestException('AniList account was not returned.');
    }
    final avatar = viewer['avatar'] is Map ? viewer['avatar'] as Map : const {};
    return TrackerAccount(
      id: viewer['id'].toString(),
      username: viewer['name']?.toString() ?? 'AniList user',
      avatarUri: _uriOrNull(avatar['large'] ?? avatar['medium']),
    );
  }

  Future<void> addAnimeToList({
    int? aniListId,
    int? malId,
    required String title,
  }) async {
    if (accessToken == null || accessToken!.isEmpty) {
      throw const TrackerRequestException('AniList is not connected.');
    }
    var mediaId = aniListId;
    if (mediaId == null) {
      const query = '''
        query ResolveAnime(\$idMal: Int, \$search: String) {
          Media(type: ANIME, idMal: \$idMal, search: \$search) { id }
        }
      ''';
      final data = await _post(query, {
        if (malId != null) 'idMal': malId,
        if (malId == null) 'search': title,
      });
      final media = data['Media'];
      if (media is Map) mediaId = (media['id'] as num?)?.toInt();
    }
    if (mediaId == null) {
      throw TrackerRequestException('AniList could not match "$title".');
    }
    const mutation = '''
      mutation AddAnime(\$mediaId: Int!) {
        SaveMediaListEntry(mediaId: \$mediaId, status: CURRENT) { id status }
      }
    ''';
    await _post(mutation, {'mediaId': mediaId});
  }

  Future<void> updateAnimeProgress({
    int? aniListId,
    int? malId,
    required String title,
    required int progress,
  }) async {
    if (accessToken == null || accessToken!.isEmpty) {
      throw const TrackerRequestException('AniList is not connected.');
    }
    final mediaId = await _resolveAnimeId(
      aniListId: aniListId,
      malId: malId,
      title: title,
    );
    const mutation = '''
      mutation UpdateAnimeProgress(\$mediaId: Int!, \$progress: Int!) {
        SaveMediaListEntry(
          mediaId: \$mediaId,
          status: CURRENT,
          progress: \$progress
        ) { id status progress }
      }
    ''';
    await _post(mutation, {'mediaId': mediaId, 'progress': progress});
  }

  Future<int> _resolveAnimeId({
    int? aniListId,
    int? malId,
    required String title,
  }) async {
    if (aniListId != null) return aniListId;
    const query = '''
      query ResolveAnime(\$idMal: Int, \$search: String) {
        Media(type: ANIME, idMal: \$idMal, search: \$search) { id }
      }
    ''';
    final data = await _post(query, {
      if (malId != null) 'idMal': malId,
      if (malId == null) 'search': title,
    });
    final media = data['Media'];
    final resolved = media is Map ? (media['id'] as num?)?.toInt() : null;
    if (resolved == null) {
      throw TrackerRequestException('AniList could not match "$title".');
    }
    return resolved;
  }

  Future<Map<String, dynamic>> _post(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _client.post(
      _endpoint,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (accessToken != null && accessToken!.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'query': query, 'variables': variables}),
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TrackerRequestException(
          'AniList returned an invalid response.');
    }
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? first['message']?.toString() : null;
      throw TrackerRequestException(message ?? 'AniList returned an error.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerRequestException(
        'AniList request failed (${response.statusCode}).',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const TrackerRequestException('AniList response has no data.');
    }
    return data;
  }

  TrackerSection _section(
    Map<String, dynamic> data,
    String id,
    String title,
  ) {
    return TrackerSection(
      id: id,
      title: title,
      items: _mediaNodes(data[id]).map(_parseMedia),
    );
  }

  List<Map<String, dynamic>> _mediaNodes(dynamic page) {
    if (page is! Map) return const [];
    final media = page['media'];
    if (media is! List) return const [];
    return media.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  TrackerMedia _parseMedia(
    Map<String, dynamic> json, {
    String? listStatus,
    int? progress,
    int? progressTotal,
    DateTime? listUpdatedAt,
  }) {
    final titleJson = json['title'] is Map ? json['title'] as Map : const {};
    final english = _stringOrNull(titleJson['english']);
    final romaji = _stringOrNull(titleJson['romaji']);
    final native = _stringOrNull(titleJson['native']);
    final preferred = romaji ?? english ?? native ?? 'Untitled';
    final cover =
        json['coverImage'] is Map ? json['coverImage'] as Map : const {};
    final tags = json['tags'] is List
        ? (json['tags'] as List)
            .whereType<Map>()
            .where((tag) => ((tag['rank'] as num?)?.toInt() ?? 0) >= 20)
            .map((tag) => tag['name']?.toString() ?? '')
            .where((tag) => tag.isNotEmpty)
            .toList()
        : const <String>[];
    final next = json['nextAiringEpisode'] is Map
        ? json['nextAiringEpisode'] as Map
        : const {};

    return TrackerMedia(
      id: json['id'].toString(),
      malId: (json['idMal'] as num?)?.toInt(),
      tracker: TrackerKind.aniList,
      type: json['type'] == 'MANGA'
          ? TrackedMediaType.manga
          : TrackedMediaType.anime,
      title: TrackerTitle(
        preferred: preferred,
        english: english,
        romaji: romaji,
        native: native,
        synonyms: _stringList(json['synonyms']),
      ),
      coverUri: _uriOrNull(cover['extraLarge'] ?? cover['large']),
      bannerUri: _uriOrNull(json['bannerImage']),
      siteUri: _uriOrNull(json['siteUrl']),
      description: _plainText(json['description']?.toString() ?? ''),
      genres: _stringList(json['genres']),
      tags: tags,
      isAdult: json['isAdult'] == true,
      score: (json['averageScore'] as num?)?.toInt(),
      popularity: (json['popularity'] as num?)?.toInt(),
      startDate: _fuzzyDate(json['startDate']),
      endDate: _fuzzyDate(json['endDate']),
      nextReleaseAt: _unixDate(next['airingAt']),
      nextReleaseNumber: (next['episode'] as num?)?.toInt(),
      listStatus: listStatus,
      progress: progress,
      progressTotal: progressTotal,
      listUpdatedAt: listUpdatedAt,
    );
  }

  List<TrackerScheduleEntry> _parseSchedule(dynamic page) {
    if (page is! Map || page['airingSchedules'] is! List) return const [];
    final entries = <TrackerScheduleEntry>[];
    for (final raw in page['airingSchedules'] as List) {
      if (raw is! Map || raw['media'] is! Map) continue;
      final releaseAt = _unixDate(raw['airingAt']);
      if (releaseAt == null) continue;
      entries.add(
        TrackerScheduleEntry(
          media: _parseMedia(
            (raw['media'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
          releaseAt: releaseAt,
          releaseNumber: (raw['episode'] as num?)?.toInt(),
        ),
      );
    }
    return entries;
  }

  String _mediaType(TrackedMediaType type) =>
      type == TrackedMediaType.anime ? 'ANIME' : 'MANGA';

  String _mediaSort(TrackerSort sort) => switch (sort) {
        TrackerSort.popularity => 'POPULARITY_DESC',
        TrackerSort.trending => 'TRENDING_DESC',
        TrackerSort.mostRecent => 'START_DATE_DESC',
        TrackerSort.highestRated => 'SCORE_DESC',
      };

  _Season _seasonFor(DateTime date) => switch (date.month) {
        <= 3 => _Season.winter,
        <= 6 => _Season.spring,
        <= 9 => _Season.summer,
        _ => _Season.fall,
      };

  ({_Season season, int year}) _nextSeason(_Season season, int year) {
    return switch (season) {
      _Season.winter => (season: _Season.spring, year: year),
      _Season.spring => (season: _Season.summer, year: year),
      _Season.summer => (season: _Season.fall, year: year),
      _Season.fall => (season: _Season.winter, year: year + 1),
    };
  }

  String? _stringOrNull(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Uri? _uriOrNull(dynamic value) {
    final text = _stringOrNull(value);
    return text == null ? null : Uri.tryParse(text);
  }

  DateTime? _unixDate(dynamic value) {
    if (value is! num || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    ).toLocal();
  }

  DateTime? _fuzzyDate(dynamic value) {
    if (value is! Map) return null;
    final year = (value['year'] as num?)?.toInt();
    if (year == null || year <= 0) return null;
    final month = (value['month'] as num?)?.toInt() ?? 1;
    final day = (value['day'] as num?)?.toInt() ?? 1;
    return DateTime(year, month.clamp(1, 12), day.clamp(1, 31));
  }

  String _plainText(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .trim();
  }

  String? _humanize(dynamic value) {
    final text = _stringOrNull(value);
    if (text == null) return null;
    return text
        .toLowerCase()
        .split('_')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _homeQuery({
    required bool includeSeason,
    required bool restrictAdult,
  }) {
    final adultFilter = restrictAdult ? ', isAdult: false' : '';
    return '''
    query TrackerHome(
      \$type: MediaType!
      ${includeSeason ? ''',
      \$season: MediaSeason,
      \$seasonYear: Int,
      \$nextSeason: MediaSeason,
      \$nextSeasonYear: Int,
      \$scheduleStart: Int,
      \$scheduleEnd: Int
      ''' : ''}
    ) {
      popular: Page(page: 1, perPage: 12) {
        media(type: \$type, sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
      trending: Page(page: 1, perPage: 12) {
        media(type: \$type, sort: TRENDING_DESC$adultFilter) { ...MediaCard }
      }
      recent: Page(page: 1, perPage: 12) {
        media(type: \$type, sort: START_DATE_DESC$adultFilter) { ...MediaCard }
      }
      highestRated: Page(page: 1, perPage: 12) {
        media(type: \$type, sort: SCORE_DESC$adultFilter) { ...MediaCard }
      }
      ${includeSeason ? '''
      thisSeason: Page(page: 1, perPage: 12) {
        media(type: ANIME, season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
      upcomingSeason: Page(page: 1, perPage: 12) {
        media(type: ANIME, season: \$nextSeason, seasonYear: \$nextSeasonYear, sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
      schedule: Page(page: 1, perPage: 50) {
        airingSchedules(airingAt_greater: \$scheduleStart, airingAt_lesser: \$scheduleEnd, sort: TIME) {
          airingAt
          episode
          media { ...MediaCard }
        }
      }
      ''' : ''}
      action: Page(page: 1, perPage: 12) {
        media(type: \$type, genre: "Action", sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
      romance: Page(page: 1, perPage: 12) {
        media(type: \$type, genre: "Romance", sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
      fantasy: Page(page: 1, perPage: 12) {
        media(type: \$type, genre: "Fantasy", sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
      comedy: Page(page: 1, perPage: 12) {
        media(type: \$type, genre: "Comedy", sort: POPULARITY_DESC$adultFilter) { ...MediaCard }
      }
    }
    $_mediaFragment
  ''';
  }

  String _searchQuery({required bool restrictAdult}) {
    final adultFilter = restrictAdult ? ', isAdult: false' : '';
    return '''
    query TrackerSearch(
      \$page: Int!,
      \$type: MediaType!,
      \$search: String,
      \$tags: [String],
      \$genres: [String],
      \$sort: [MediaSort]
    ) {
      Page(page: \$page, perPage: 30) {
        pageInfo { hasNextPage }
        media(type: \$type, search: \$search, tag_in: \$tags, genre_in: \$genres, sort: \$sort$adultFilter) {
          ...MediaCard
        }
      }
    }
    $_mediaFragment
  ''';
  }

  String _seasonQuery({required bool restrictAdult}) {
    final adultFilter = restrictAdult ? ', isAdult: false' : '';
    return '''
    query TrackerSeason(
      \$page: Int!,
      \$season: MediaSeason!,
      \$seasonYear: Int!,
      \$sort: [MediaSort]
    ) {
      Page(page: \$page, perPage: 30) {
        pageInfo { hasNextPage }
        media(type: ANIME, season: \$season, seasonYear: \$seasonYear, sort: \$sort$adultFilter) {
          ...MediaCard
        }
      }
    }
    $_mediaFragment
  ''';
  }

  String get _detailsQuery => '''
    query TrackerDetails(\$id: Int, \$idMal: Int, \$type: MediaType) {
      Media(id: \$id, idMal: \$idMal, type: \$type) {
        ...MediaCard
        description
        tags { name rank isAdult category }
        format
        status
        source
        duration
        volumes
        staff(page: 1, perPage: 25, sort: [RELEVANCE]) {
          edges {
            role
            node { name { full } image { large medium } siteUrl }
          }
        }
        characters(page: 1, perPage: 20, sort: [ROLE, RELEVANCE]) {
          edges {
            node { name { full } }
            voiceActors(language: JAPANESE, sort: [RELEVANCE]) {
              name { full }
              image { large medium }
              siteUrl
            }
          }
        }
        studios {
          edges { isMain node { name siteUrl } }
        }
        reviews(page: 1, perPage: 5, sort: [RATING_DESC]) {
          nodes {
            summary
            body
            rating
            score
            siteUrl
            user { name avatar { large medium } }
          }
        }
      }
    }
    $_mediaFragment
  ''';

  static const String _taxonomyQuery = '''
    query TrackerTaxonomy {
      GenreCollection
      MediaTagCollection { name category isAdult }
    }
  ''';

  static const String _viewerQuery = '''
    query TrackerViewer {
      Viewer { id name avatar { large medium } }
    }
  ''';

  String get _libraryQuery => '''
    query TrackerLibrary(\$userId: Int!, \$type: MediaType!) {
      MediaListCollection(userId: \$userId, type: \$type) {
        lists {
          name
          status
          entries {
            status
            progress
            updatedAt
            media { ...MediaCard }
          }
        }
      }
    }
    $_mediaFragment
  ''';

  static const String _mediaFragment = '''
    fragment MediaCard on Media {
      id
      idMal
      type
      title { romaji english native }
      synonyms
      startDate { year month day }
      endDate { year month day }
      coverImage { large extraLarge }
      bannerImage
      genres
      averageScore
      popularity
      episodes
      chapters
      isAdult
      siteUrl
      nextAiringEpisode { airingAt episode }
    }
  ''';
}

class TrackerRequestException implements Exception {
  final String message;

  const TrackerRequestException(this.message);

  @override
  String toString() => message;
}

enum _Season { winter, spring, summer, fall }
