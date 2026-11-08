import 'dart:typed_data';

import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Sort options that an anime catalog source can expose.
enum AnimeCatalogFilter {
  featured,
  catalog,
  subtitled,
  dubbed,
  manhwa,
  donghua,
  movies,
  subtitledMovies,
  dubbedMovies,
  adult,
  popular,
  popularToday,
  popularWeek,
  popularMonth,
  recent,
  episodeMostViewed,
  seriesNewest,
  seriesPopular,
  seriesMostViewed,
  updated,
  added,
  airing,
  upcoming,
  completed,
  scheduleSunday,
  scheduleMonday,
  scheduleTuesday,
  scheduleWednesday,
  scheduleThursday,
  scheduleFriday,
  scheduleSaturday,
  scheduleUnknown,
}

enum AnimeSearchSort {
  defaultOrder,
  popularity,
  averageScore,
  trending,
  favorites,
  dateAdded,
  latestUpdated,
  latestAdded,
  score,
  name,
  nameDescending,
  releaseDate,
  mostViewed,
  episodeCount,
}

class AnimeFilterOption {
  final String value;
  final String label;

  const AnimeFilterOption({required this.value, required this.label});
}

class AnimeSearchOptions {
  final List<AnimeFilterOption> genres;
  final List<AnimeFilterOption> tags;
  final List<AnimeFilterOption> seasons;
  final List<AnimeFilterOption> years;
  final List<AnimeFilterOption> types;
  final List<AnimeFilterOption> formats;
  final List<AnimeFilterOption> statuses;
  final List<AnimeFilterOption> languages;
  final List<AnimeFilterOption> ratings;
  final List<AnimeFilterOption> studios;
  final List<AnimeFilterOption> sources;
  final List<AnimeFilterOption> origins;
  final List<AnimeFilterOption> scores;
  final List<AnimeFilterOption> episodeRanges;
  final List<AnimeFilterOption> audioOptions;
  final List<AnimeSearchSort> sorts;
  final Map<AnimeSearchSort, String> sortLabels;
  final Map<String, String> labels;

  AnimeSearchOptions({
    Iterable<AnimeFilterOption> genres = const [],
    Iterable<AnimeFilterOption> tags = const [],
    Iterable<AnimeFilterOption> seasons = const [],
    Iterable<AnimeFilterOption> years = const [],
    Iterable<AnimeFilterOption> types = const [],
    Iterable<AnimeFilterOption> formats = const [],
    Iterable<AnimeFilterOption> statuses = const [],
    Iterable<AnimeFilterOption> languages = const [],
    Iterable<AnimeFilterOption> ratings = const [],
    Iterable<AnimeFilterOption> studios = const [],
    Iterable<AnimeFilterOption> sources = const [],
    Iterable<AnimeFilterOption> origins = const [],
    Iterable<AnimeFilterOption> scores = const [],
    Iterable<AnimeFilterOption> episodeRanges = const [],
    Iterable<AnimeFilterOption> audioOptions = const [],
    Iterable<AnimeSearchSort> sorts = AnimeSearchSort.values,
    Map<AnimeSearchSort, String> sortLabels = const {},
    Map<String, String> labels = const {},
  })  : genres = List.unmodifiable(genres),
        tags = List.unmodifiable(tags),
        seasons = List.unmodifiable(seasons),
        years = List.unmodifiable(years),
        types = List.unmodifiable(types),
        formats = List.unmodifiable(formats),
        statuses = List.unmodifiable(statuses),
        languages = List.unmodifiable(languages),
        ratings = List.unmodifiable(ratings),
        studios = List.unmodifiable(studios),
        sources = List.unmodifiable(sources),
        origins = List.unmodifiable(origins),
        scores = List.unmodifiable(scores),
        episodeRanges = List.unmodifiable(episodeRanges),
        audioOptions = List.unmodifiable(audioOptions),
        sorts = List.unmodifiable(sorts),
        sortLabels = Map.unmodifiable(sortLabels),
        labels = Map.unmodifiable(labels);

  String labelFor(String field, String fallback) => labels[field] ?? fallback;

  String sortLabelFor(AnimeSearchSort sort, String fallback) =>
      sortLabels[sort] ?? fallback;
}

class AnimeSearchRequest {
  final String query;
  final Set<String> genres;
  final Set<String> tags;
  final String? season;
  final String? year;
  final String? type;
  final Set<String> formats;
  final String? status;
  final String? language;
  final String? rating;
  final String? studio;
  final Set<String> sources;
  final String? origin;
  final String? score;
  final String? episodeRange;
  final String? audio;
  final AnimeSearchSort sort;

  AnimeSearchRequest({
    this.query = '',
    Set<String> genres = const {},
    Set<String> tags = const {},
    this.season,
    this.year,
    this.type,
    Set<String> formats = const {},
    this.status,
    this.language,
    this.rating,
    this.studio,
    Set<String> sources = const {},
    this.origin,
    this.score,
    this.episodeRange,
    this.audio,
    this.sort = AnimeSearchSort.defaultOrder,
  })  : genres = Set.unmodifiable(genres),
        tags = Set.unmodifiable(tags),
        formats = Set.unmodifiable(formats),
        sources = Set.unmodifiable(sources);

  bool get hasFilters =>
      genres.isNotEmpty ||
      tags.isNotEmpty ||
      season != null ||
      year != null ||
      type != null ||
      formats.isNotEmpty ||
      status != null ||
      language != null ||
      rating != null ||
      studio != null ||
      sources.isNotEmpty ||
      origin != null ||
      score != null ||
      episodeRange != null ||
      audio != null ||
      sort != AnimeSearchSort.defaultOrder;

  AnimeSearchRequest copyWith({String? query}) => AnimeSearchRequest(
        query: query ?? this.query,
        genres: genres,
        tags: tags,
        season: season,
        year: year,
        type: type,
        formats: formats,
        status: status,
        language: language,
        rating: rating,
        studio: studio,
        sources: sources,
        origin: origin,
        score: score,
        episodeRange: episodeRange,
        audio: audio,
        sort: sort,
      );
}

/// Publication state reported by an anime source.
enum AnimeStatus {
  unknown,
  upcoming,
  ongoing,
  completed,
  hiatus,
  cancelled,
}

/// Transport used by a playable video stream.
enum VideoProtocol {
  hls,
  dash,
  progressive,
  file,
}

enum AnimeSkipType { intro, recap, outro, preview, custom }

/// A time range that the player may offer to skip.
class AnimeSkipSegment {
  final Duration start;
  final Duration end;
  final AnimeSkipType type;
  final String? label;

  AnimeSkipSegment({
    required this.start,
    required this.end,
    this.type = AnimeSkipType.intro,
    this.label,
  }) {
    if (end <= start) {
      throw ArgumentError.value(
        end,
        'end',
        'Skip segment end must be after its start.',
      );
    }
  }

  bool contains(Duration position) => position >= start && position < end;

  String get displayLabel =>
      label ??
      switch (type) {
        AnimeSkipType.intro => 'Skip intro',
        AnimeSkipType.recap => 'Skip recap',
        AnimeSkipType.outro => 'Skip outro',
        AnimeSkipType.preview => 'Skip preview',
        AnimeSkipType.custom => 'Skip segment',
      };
}

/// A lightweight anime entry returned by browse and search operations.
class AnimeCatalogItem {
  final String id;
  final String title;
  final Uri? coverUri;
  final String? subtitle;

  const AnimeCatalogItem({
    required this.id,
    required this.title,
    this.coverUri,
    this.subtitle,
  });
}

enum AnimeTaxonomyKind { tag, artist, character, parody, model, topic }

class AnimeTaxonomyLink {
  final AnimeTaxonomyKind kind;
  final String id;
  final String name;

  const AnimeTaxonomyLink({
    required this.kind,
    required this.id,
    required this.name,
  });
}

/// One page of catalog results.
///
/// [nextCursor] is intentionally opaque. Sources can use a page number, token,
/// URL, or any other pagination value without leaking that detail to the UI.
class AnimeCatalogPage {
  final List<AnimeCatalogItem> items;
  final String? nextCursor;

  AnimeCatalogPage({
    required Iterable<AnimeCatalogItem> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// Complete metadata for an anime title.
class AnimeDetails {
  final AnimeCatalogItem item;
  final String description;
  final List<String> alternativeTitles;
  final List<String> genres;
  final List<AnimeTaxonomyLink> taxonomyLinks;
  final AnimeStatus status;
  final Uri? bannerUri;
  final Map<String, String> externalIds;
  final List<String> studios;
  final List<String> producers;

  AnimeDetails({
    required this.item,
    this.description = '',
    Iterable<String> alternativeTitles = const [],
    Iterable<String> genres = const [],
    Iterable<AnimeTaxonomyLink> taxonomyLinks = const [],
    this.status = AnimeStatus.unknown,
    this.bannerUri,
    Map<String, String> externalIds = const {},
    Iterable<String> studios = const [],
    Iterable<String> producers = const [],
  })  : alternativeTitles = List.unmodifiable(alternativeTitles),
        genres = List.unmodifiable(genres),
        taxonomyLinks = List.unmodifiable(taxonomyLinks),
        externalIds = Map.unmodifiable(externalIds),
        studios = List.unmodifiable(studios),
        producers = List.unmodifiable(producers);
}

/// An episode that can be resolved into one or more video streams.
class AnimeEpisode {
  final String id;
  final String animeId;
  final String title;
  final double? number;
  final int? season;
  final DateTime? releasedAt;
  final Uri? thumbnailUri;

  const AnimeEpisode({
    required this.id,
    required this.animeId,
    required this.title,
    this.number,
    this.season,
    this.releasedAt,
    this.thumbnailUri,
  });
}

/// A subtitle or closed-caption track associated with a playback manifest.
class AnimeSubtitleTrack {
  final Uri uri;
  final String label;
  final String language;
  final String? format;
  final bool isDefault;
  final Map<String, String> headers;

  AnimeSubtitleTrack({
    required this.uri,
    required this.label,
    required this.language,
    this.format,
    this.isDefault = false,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);
}

/// One playable variant of an episode.
class AnimeVideoStream {
  final Uri uri;
  final VideoProtocol protocol;
  final String quality;
  final String language;
  final String? codec;
  final String? mimeType;
  final int? bitrate;
  final int? width;
  final int? height;
  final Map<String, String> headers;

  AnimeVideoStream({
    required this.uri,
    required this.protocol,
    required this.quality,
    this.language = 'und',
    this.codec,
    this.mimeType,
    this.bitrate,
    this.width,
    this.height,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);
}

/// Everything the player needs to start an episode.
class AnimePlayback {
  final List<AnimeVideoStream> streams;
  final List<AnimeSubtitleTrack> subtitles;
  final List<AnimeSkipSegment> skipSegments;

  AnimePlayback({
    required Iterable<AnimeVideoStream> streams,
    Iterable<AnimeSubtitleTrack> subtitles = const [],
    Iterable<AnimeSkipSegment> skipSegments = const [],
  })  : streams = List.unmodifiable(streams),
        subtitles = List.unmodifiable(subtitles),
        skipSegments = List.unmodifiable(skipSegments) {
    if (this.streams.isEmpty) {
      throw ArgumentError.value(
        this.streams,
        'streams',
        'Playback must contain at least one video stream.',
      );
    }
  }
}

/// Contract implemented by anime/video sources.
///
/// It is deliberately independent from the legacy manga [Scrapper] contract:
/// anime sources return typed models and resolve an episode into a playback
/// manifest instead of returning chapter image streams.
abstract interface class AnimeSource {
  /// Stable identifier used by persistence. It must not depend on display name.
  String get id;

  String get name;

  Uri get baseUri;

  /// Headers applied to catalog and metadata requests when needed by a source.
  Map<String, String> get requestHeaders;

  List<AnimeCatalogFilter> get catalogFilters;

  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.popular,
    String? cursor,
  });

  Future<AnimeCatalogPage> search(
    String query, {
    String? cursor,
  });

  Future<AnimeDetails> getDetails(String animeId);

  Future<List<AnimeEpisode>> getEpisodes(String animeId);

  /// Resolves short-lived or protected URLs as late as possible, immediately
  /// before playback.
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  });
}

/// Optional, source-scoped translation for providers whose catalog metadata is
/// not available in the user's language. Implementations must keep raw values
/// for requests and only translate presentation text.
abstract interface class StaticMetadataTranslationAnimeSource {
  String get staticTranslationLabel;

  Future<bool> isStaticTranslationEnabled();

  Future<void> setStaticTranslationEnabled(bool enabled);
}

/// Optional capability for hybrid catalogs where some entries are image/GIF
/// galleries and must be opened by the native reader instead of the player.
abstract interface class ReaderBackedAnimeSource {
  MangaSource get readerSource;

  /// Returns reader details for image media, or null when [itemId] is video.
  Future<MangaDetails?> getReaderDetails(String itemId);
}

/// Optional capability for canonical metadata links shown on anime details.
abstract interface class TaxonomyBrowsableAnimeSource {
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  });
}

/// Presentation metadata shared by the source-management screens.
///
/// Keeping this mapping next to the typed source contract prevents individual
/// screens from disagreeing about a source's language.
extension AnimeSourcePresentation on AnimeSource {
  bool get isRRated =>
      id == 'hentai_haven' ||
      id == 'porn_comic_video' ||
      id == 'hanime1' ||
      id == 'jable';

  Uri get iconUri => baseUri.resolve('/favicon.ico');

  /// Compact label used to group providers in source-management screens.
  String get languageGroupLabel => switch (id) {
        'goyabu' ||
        'smart_animes' ||
        'animeq' ||
        'animy_anime' ||
        'animefire' ||
        'animes_online' =>
          'PT-BR',
        'anikage' => 'English',
        'hanime1' => 'Chinese',
        'jable' => 'Japanese',
        _ => 'All Languages',
      };

  String get languageLabel => switch (id) {
        'goyabu' ||
        'smart_animes' ||
        'animeq' ||
        'animy_anime' ||
        'animefire' ||
        'animes_online' =>
          'Português (Brasil)',
        'hanime1' => 'Chinese (Traditional)',
        'jable' => 'Japanese',
        'anikage' => 'English (US)',
        _ => 'All languages',
      };

  String get audioLabel => switch (id) {
        'goyabu' ||
        'smart_animes' ||
        'animeq' ||
        'animy_anime' ||
        'animefire' ||
        'animes_online' =>
          'Legendado/Dublado',
        'jable' => 'Japanese',
        _ => 'Sub/Dub',
      };

  String get capabilityLabel => switch (id) {
        'smart_animes' => '$languageLabel · $audioLabel · Google Drive',
        'goyabu' => '$languageLabel · $audioLabel · Blogger',
        'animeq' => '$languageLabel · $audioLabel · MP4',
        'animy_anime' => '$languageLabel · $audioLabel · HLS/MP4',
        'animefire' => '$languageLabel · $audioLabel · HLS',
        'animes_online' => '$languageLabel · $audioLabel · HLS/WebView',
        'anikage' => '$languageLabel · $audioLabel · HLS · AniList metadata',
        'hentai_haven' => 'R-rated · $audioLabel · Native/WebView',
        'porn_comic_video' => 'R-rated · Animation/Cosplay · HLS',
        'hanime1' =>
          'R-rated · Chinese (Traditional) · MP4 · Static English opt-in',
        'jable' => 'R-rated · Japanese · HLS · Static English opt-in',
        _ => '$languageLabel · $audioLabel · HLS · Subtitles',
      };
}

extension AnimeSourceGrouping on Iterable<AnimeSource> {
  /// Groups sources for presentation while keeping the registry order inside
  /// each language group and a predictable order between groups.
  Map<String, List<AnimeSource>> get groupedByLanguage {
    final grouped = <String, List<AnimeSource>>{};
    for (final source in this) {
      grouped.putIfAbsent(source.languageGroupLabel, () => []).add(source);
    }

    const preferredOrder = {
      'All Languages': 0,
      'English': 1,
      'PT-BR': 2,
      'Chinese': 3,
      'Japanese': 4,
    };
    final entries = grouped.entries.toList()
      ..sort((left, right) {
        final leftOrder = preferredOrder[left.key] ?? 100;
        final rightOrder = preferredOrder[right.key] ?? 100;
        final byOrder = leftOrder.compareTo(rightOrder);
        return byOrder != 0 ? byOrder : left.key.compareTo(right.key);
      });
    return Map.unmodifiable({
      for (final entry in entries)
        entry.key: List<AnimeSource>.unmodifiable(entry.value),
    });
  }
}

/// Optional capability for sources that expose structured catalog filters.
abstract interface class FilterableAnimeSource {
  Future<AnimeSearchOptions> getSearchOptions();

  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  });
}

/// Signals that a source needs its normal browser verification to be completed
/// before its HTML endpoints can be consumed by the HTTP client.
class AnimeSourceSessionRequired implements Exception {
  final String message;

  const AnimeSourceSessionRequired(this.message);

  @override
  String toString() => message;
}

/// Optional capability for sources protected by a browser-managed session.
abstract interface class BrowserSessionAnimeSource {
  Uri get sessionUri;

  Future<void> updateBrowserSession({
    required Map<String, String> cookies,
    required String userAgent,
  });
}

/// Optional capability for image hosts that only serve assets to a real
/// browser client (for example, behind TLS-fingerprint protection).
abstract interface class BrowserImageAnimeSource {
  Future<Uint8List> loadBrowserImage(Uri uri);
}

class AnimePlaybackChoice {
  final Uri entryUri;
  final String provider;
  final String quality;
  final Map<String, String> headers;

  AnimePlaybackChoice({
    required this.entryUri,
    required this.provider,
    this.quality = 'Auto',
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);

  String get label => quality == 'Auto' ? provider : '$provider · $quality';
}

/// Signals that playback must follow a browser redirect chain first. Sources
/// can expose more than one host so the user chooses which session to use.
class AnimePlaybackResolutionRequired implements Exception {
  final List<AnimePlaybackChoice> choices;

  AnimePlaybackResolutionRequired(List<AnimePlaybackChoice> choices)
      : assert(choices.isNotEmpty),
        choices = List.unmodifiable(choices);

  Uri get entryUri => choices.first.entryUri;
  String get quality => choices.first.quality;
  String get provider => choices.first.provider;

  AnimePlaybackResolutionRequired selecting(AnimePlaybackChoice choice) =>
      AnimePlaybackResolutionRequired([choice]);

  @override
  String toString() => 'The video host needs browser resolution.';
}

/// Optional capability for providers whose final media URL is produced by a
/// JavaScript redirect/player page.
abstract interface class BrowserPlaybackAnimeSource {
  Future<AnimePlayback> playbackFromResolvedUri(
    Uri uri, {
    String quality = 'Auto',
    String provider = 'Browser',
  });
}
