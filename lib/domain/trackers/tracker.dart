enum TrackerKind { aniList, myAnimeList }

enum TrackedMediaType { anime, manga }

enum AnimeSeason { winter, spring, summer, fall }

enum TrackerSort {
  popularity,
  trending,
  mostRecent,
  highestRated,
}

class TrackerTag {
  final String name;
  final String category;
  final bool isAdult;

  const TrackerTag({
    required this.name,
    this.category = 'Other',
    this.isAdult = false,
  });
}

class TrackerTaxonomy {
  final List<String> genres;
  final List<TrackerTag> tags;

  TrackerTaxonomy({
    Iterable<String> genres = const [],
    Iterable<TrackerTag> tags = const [],
  })  : genres = List.unmodifiable(genres),
        tags = List.unmodifiable(tags);

  static final empty = TrackerTaxonomy();
}

class TrackerAccount {
  final String id;
  final String username;
  final Uri? avatarUri;

  const TrackerAccount({
    required this.id,
    required this.username,
    this.avatarUri,
  });
}

class TrackerTitle {
  final String preferred;
  final String? english;
  final String? romaji;
  final String? native;
  final List<String> synonyms;

  TrackerTitle({
    required this.preferred,
    this.english,
    this.romaji,
    this.native,
    Iterable<String> synonyms = const [],
  }) : synonyms = List.unmodifiable(synonyms);

  List<String> get searchTerms {
    final values = <String>[
      preferred,
      if (english != null) english!,
      if (romaji != null) romaji!,
      if (native != null) native!,
      ...synonyms,
    ];
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value.toLowerCase()))
        .toList(growable: false);
  }

  String display({bool preferEnglish = false}) {
    if (preferEnglish) {
      return english ?? romaji ?? native ?? preferred;
    }
    return romaji ?? english ?? native ?? preferred;
  }
}

class TrackerMedia {
  final String id;
  final int? malId;
  final TrackerKind tracker;
  final TrackedMediaType type;
  final TrackerTitle title;
  final Uri? coverUri;
  final Uri? bannerUri;
  final Uri? siteUri;
  final String description;
  final List<String> genres;
  final List<String> tags;
  final bool isAdult;
  final int? score;
  final int? popularity;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? nextReleaseAt;
  final int? nextReleaseNumber;
  final String? listStatus;
  final int? progress;
  final int? progressTotal;
  final DateTime? listUpdatedAt;

  TrackerMedia({
    required this.id,
    required this.tracker,
    required this.type,
    required this.title,
    this.malId,
    this.coverUri,
    this.bannerUri,
    this.siteUri,
    this.description = '',
    Iterable<String> genres = const [],
    Iterable<String> tags = const [],
    this.isAdult = false,
    this.score,
    this.popularity,
    this.startDate,
    this.endDate,
    this.nextReleaseAt,
    this.nextReleaseNumber,
    this.listStatus,
    this.progress,
    this.progressTotal,
    this.listUpdatedAt,
  })  : genres = List.unmodifiable(genres),
        tags = List.unmodifiable(tags);
}

class TrackerSection {
  final String id;
  final String title;
  final List<TrackerMedia> items;

  TrackerSection({
    required this.id,
    required this.title,
    required Iterable<TrackerMedia> items,
  }) : items = List.unmodifiable(items);
}

class TrackerScheduleEntry {
  final TrackerMedia media;
  final DateTime releaseAt;
  final int? releaseNumber;

  const TrackerScheduleEntry({
    required this.media,
    required this.releaseAt,
    this.releaseNumber,
  });
}

class TrackerHomeData {
  final List<TrackerScheduleEntry> schedule;
  final List<TrackerSection> librarySections;
  final List<TrackerSection> sections;

  TrackerHomeData({
    Iterable<TrackerScheduleEntry> schedule = const [],
    Iterable<TrackerSection> librarySections = const [],
    required Iterable<TrackerSection> sections,
  })  : schedule = List.unmodifiable(schedule),
        librarySections = List.unmodifiable(librarySections),
        sections = List.unmodifiable(sections);
}

class TrackerSearchPage {
  final List<TrackerMedia> items;
  final int page;
  final bool hasNextPage;

  TrackerSearchPage({
    required Iterable<TrackerMedia> items,
    required this.page,
    required this.hasNextPage,
  }) : items = List.unmodifiable(items);
}

class TrackerSearchRequest {
  final String query;
  final TrackedMediaType type;
  final List<String> tags;
  final List<String> genres;
  final TrackerSort sort;
  final bool includeAdult;
  final int page;

  TrackerSearchRequest({
    this.query = '',
    required this.type,
    Iterable<String> tags = const [],
    Iterable<String> genres = const [],
    this.sort = TrackerSort.popularity,
    this.includeAdult = false,
    this.page = 1,
  })  : tags = List.unmodifiable(tags),
        genres = List.unmodifiable(genres);
}

class TrackerCredit {
  final String name;
  final String role;
  final Uri? imageUri;
  final Uri? siteUri;

  const TrackerCredit({
    required this.name,
    required this.role,
    this.imageUri,
    this.siteUri,
  });
}

class TrackerReview {
  final String summary;
  final String body;
  final int? rating;
  final int? score;
  final String? username;
  final Uri? avatarUri;
  final Uri? siteUri;

  const TrackerReview({
    required this.summary,
    required this.body,
    this.rating,
    this.score,
    this.username,
    this.avatarUri,
    this.siteUri,
  });
}

class TrackerMediaDetails {
  final TrackerMedia media;
  final String? format;
  final String? status;
  final String? source;
  final int? episodes;
  final int? chapters;
  final int? volumes;
  final int? durationMinutes;
  final List<TrackerCredit> creators;
  final List<TrackerCredit> voiceActors;
  final List<String> studios;
  final List<TrackerReview> reviews;

  TrackerMediaDetails({
    required this.media,
    this.format,
    this.status,
    this.source,
    this.episodes,
    this.chapters,
    this.volumes,
    this.durationMinutes,
    Iterable<TrackerCredit> creators = const [],
    Iterable<TrackerCredit> voiceActors = const [],
    Iterable<String> studios = const [],
    Iterable<TrackerReview> reviews = const [],
  })  : creators = List.unmodifiable(creators),
        voiceActors = List.unmodifiable(voiceActors),
        studios = List.unmodifiable(studios),
        reviews = List.unmodifiable(reviews);
}

abstract interface class TrackerService {
  TrackerKind get kind;

  String get displayName;

  bool get isConfigured;

  Future<TrackerHomeData> loadHome({
    required TrackedMediaType type,
    required bool includeAdult,
    DateTime? now,
  });

  Future<TrackerSearchPage> search(TrackerSearchRequest request);

  Future<TrackerSearchPage> loadSeason({
    required int year,
    required AnimeSeason season,
    required TrackerSort sort,
    required bool includeAdult,
    required int page,
  });

  Future<TrackerMediaDetails> loadDetails(TrackerMedia media);

  Future<List<TrackerSection>> loadLibrary({
    required TrackedMediaType type,
  });

  Future<TrackerTaxonomy> loadTaxonomy({required bool includeAdult});
}
