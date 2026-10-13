import 'package:star_scrapper_app/domain/sources/anime_source.dart';

class AnimeLibraryRecord {
  final String sourceId;
  final String animeId;
  final String title;
  final String? coverUrl;
  final String? bannerUrl;
  final String? subtitle;
  final int addedAtMillis;
  final List<String> tabs;
  final Map<String, List<String>> subTabsByPrimary;
  final List<String> studios;
  final List<String> producers;

  const AnimeLibraryRecord({
    required this.sourceId,
    required this.animeId,
    required this.title,
    this.coverUrl,
    this.bannerUrl,
    this.subtitle,
    required this.addedAtMillis,
    this.tabs = const [],
    this.subTabsByPrimary = const {},
    this.studios = const [],
    this.producers = const [],
  });

  String get key => '$sourceId::$animeId';

  factory AnimeLibraryRecord.fromDetails({
    required String sourceId,
    required AnimeDetails details,
    String primaryTab = 'Watching',
    String? subTab = 'Watching',
    DateTime? addedAt,
  }) {
    return AnimeLibraryRecord(
      sourceId: sourceId,
      animeId: details.item.id,
      title: details.item.title,
      coverUrl: details.item.coverUri?.toString(),
      bannerUrl: details.bannerUri?.toString(),
      subtitle: details.item.subtitle,
      addedAtMillis: (addedAt ?? DateTime.now()).millisecondsSinceEpoch,
      tabs: [primaryTab],
      subTabsByPrimary: {
        if (subTab != null && subTab.isNotEmpty) primaryTab: [subTab],
      },
      studios: details.studios,
      producers: details.producers,
    );
  }

  factory AnimeLibraryRecord.fromJson(Map<dynamic, dynamic> json) {
    return AnimeLibraryRecord(
      sourceId: (json['sourceId'] ?? '').toString(),
      animeId: (json['animeId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      coverUrl: json['coverUrl']?.toString(),
      bannerUrl: json['bannerUrl']?.toString(),
      subtitle: json['subtitle']?.toString(),
      addedAtMillis: (json['addedAtMillis'] as num?)?.toInt() ?? 0,
      tabs: (json['tabs'] as List? ?? const ['Watching'])
          .map((item) => item.toString())
          .toList(),
      subTabsByPrimary: (json['subTabsByPrimary'] as Map? ??
              const {
                'Watching': ['Watching'],
              })
          .map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List? ?? const []).map((item) => item.toString()).toList(),
        ),
      ),
      studios: (json['studios'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      producers: (json['producers'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'animeId': animeId,
        'title': title,
        'coverUrl': coverUrl,
        'bannerUrl': bannerUrl,
        'subtitle': subtitle,
        'addedAtMillis': addedAtMillis,
        'tabs': tabs,
        'subTabsByPrimary': subTabsByPrimary,
        'studios': studios,
        'producers': producers,
      };

  AnimeLibraryRecord copyWith({
    String? title,
    List<String>? tabs,
    Map<String, List<String>>? subTabsByPrimary,
  }) =>
      AnimeLibraryRecord(
        sourceId: sourceId,
        animeId: animeId,
        title: title ?? this.title,
        coverUrl: coverUrl,
        bannerUrl: bannerUrl,
        subtitle: subtitle,
        addedAtMillis: addedAtMillis,
        tabs: tabs ?? this.tabs,
        subTabsByPrimary: subTabsByPrimary ?? this.subTabsByPrimary,
        studios: studios,
        producers: producers,
      );

  AnimeCatalogItem toCatalogItem() => AnimeCatalogItem(
        id: animeId,
        title: title,
        coverUri: coverUrl == null ? null : Uri.tryParse(coverUrl!),
        subtitle: subtitle,
      );
}

class AnimeEpisodeProgress {
  final String sourceId;
  final String animeId;
  final String episodeId;
  final String episodeTitle;
  final double? episodeNumber;
  final int positionMillis;
  final int durationMillis;
  final int lastPlayedAtMillis;
  final bool viewed;
  final bool completed;
  final String? animeTitle;
  final String? animeCoverUrl;

  const AnimeEpisodeProgress({
    required this.sourceId,
    required this.animeId,
    required this.episodeId,
    required this.episodeTitle,
    this.episodeNumber,
    this.positionMillis = 0,
    this.durationMillis = 0,
    required this.lastPlayedAtMillis,
    this.viewed = true,
    this.completed = false,
    this.animeTitle,
    this.animeCoverUrl,
  });

  String get key => '$sourceId::$animeId::$episodeId';
  Duration get position => Duration(milliseconds: positionMillis);
  Duration get duration => Duration(milliseconds: durationMillis);
  bool get canResume => !completed && positionMillis > 0;

  AnimeEpisodeProgress copyWith({
    int? positionMillis,
    int? durationMillis,
    int? lastPlayedAtMillis,
    bool? viewed,
    bool? completed,
    String? animeTitle,
    String? animeCoverUrl,
  }) {
    return AnimeEpisodeProgress(
      sourceId: sourceId,
      animeId: animeId,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      episodeNumber: episodeNumber,
      positionMillis: positionMillis ?? this.positionMillis,
      durationMillis: durationMillis ?? this.durationMillis,
      lastPlayedAtMillis: lastPlayedAtMillis ?? this.lastPlayedAtMillis,
      viewed: viewed ?? this.viewed,
      completed: completed ?? this.completed,
      animeTitle: animeTitle ?? this.animeTitle,
      animeCoverUrl: animeCoverUrl ?? this.animeCoverUrl,
    );
  }

  factory AnimeEpisodeProgress.fromJson(Map<dynamic, dynamic> json) {
    return AnimeEpisodeProgress(
      sourceId: (json['sourceId'] ?? '').toString(),
      animeId: (json['animeId'] ?? '').toString(),
      episodeId: (json['episodeId'] ?? '').toString(),
      episodeTitle: (json['episodeTitle'] ?? '').toString(),
      episodeNumber: (json['episodeNumber'] as num?)?.toDouble(),
      positionMillis: (json['positionMillis'] as num?)?.toInt() ?? 0,
      durationMillis: (json['durationMillis'] as num?)?.toInt() ?? 0,
      lastPlayedAtMillis: (json['lastPlayedAtMillis'] as num?)?.toInt() ?? 0,
      viewed: json['viewed'] != false,
      completed: json['completed'] == true,
      animeTitle: json['animeTitle']?.toString(),
      animeCoverUrl: json['animeCoverUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'animeId': animeId,
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
        'episodeNumber': episodeNumber,
        'positionMillis': positionMillis,
        'durationMillis': durationMillis,
        'lastPlayedAtMillis': lastPlayedAtMillis,
        'viewed': viewed,
        'completed': completed,
        'animeTitle': animeTitle,
        'animeCoverUrl': animeCoverUrl,
      };
}
