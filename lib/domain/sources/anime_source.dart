/// Sort options that an anime catalog source can expose.
enum AnimeCatalogFilter {
  popular,
  recent,
  updated,
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
  final AnimeStatus status;
  final Uri? bannerUri;

  AnimeDetails({
    required this.item,
    this.description = '',
    Iterable<String> alternativeTitles = const [],
    Iterable<String> genres = const [],
    this.status = AnimeStatus.unknown,
    this.bannerUri,
  })  : alternativeTitles = List.unmodifiable(alternativeTitles),
        genres = List.unmodifiable(genres);
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
