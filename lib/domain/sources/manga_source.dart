/// Typed domain contract for manga/comic sources.
///
/// It mirrors [AnimeSource] (see `anime_source.dart`): sources return typed,
/// immutable models and resolve a chapter into a stream of reader pages instead
/// of passing flexible `Map<String, dynamic>` payloads around.
///
/// Persistence note: the library is stored on disk as `Map<String, dynamic>`
/// (see [BookRecord]). To avoid breaking existing libraries, [MangaDetails] and
/// [MangaChapter] serialize to and from the exact legacy keys the storage and UI
/// already use (`coverImageUrl`, `translatedLanguage`, `chapter`, ...).
library;

/// Catalog sort/listing options a manga source can expose.
enum MangaCatalogFilter {
  popular,
  recent,
  trending,
  added,
  updated,
  alphabetical,
}

/// Publication state reported by a manga source.
enum MangaStatus {
  unknown,
  ongoing,
  completed,
  hiatus,
  cancelled,
}

/// Returns the current page plus the next pages the reader should warm in its
/// image cache. The window is clamped at chapter boundaries.
List<int> mangaReaderPreloadIndexes({
  required int currentPage,
  required int pageCount,
  int windowSize = 4,
  bool reverse = false,
}) {
  if (pageCount <= 0 || windowSize <= 0) return const [];
  final anchor = currentPage.clamp(0, pageCount - 1);
  final direction = reverse ? -1 : 1;
  return List<int>.generate(windowSize, (offset) => anchor + offset * direction)
      .where((index) => index >= 0 && index < pageCount)
      .toList(growable: false);
}

/// Produces the compact metadata line shared by manga catalog cards.
/// Missing values are omitted instead of being rendered as placeholders.
String mangaCatalogSubtitle({
  String? latestChapter,
  int? totalChapters,
  String? format,
  MangaStatus? status,
  double? rating,
  int? year,
}) {
  final parts = <String>[];
  final chapter = normalizeMangaChapterNumber(latestChapter);
  if (totalChapters != null && totalChapters > 0) {
    parts.add(
      chapter != null && chapter != '$totalChapters'
          ? '$chapter/$totalChapters Ch'
          : '$totalChapters Ch',
    );
  } else if (chapter != null) {
    parts.add('$chapter Ch');
  }
  if (format != null && format.trim().isNotEmpty) parts.add(format.trim());
  final statusLabel = mangaStatusLabel(status ?? MangaStatus.unknown);
  if (statusLabel != null) parts.add(statusLabel);
  if (rating != null && rating > 0) {
    final normalized = rating > 10 ? rating / 10 : rating;
    parts.add(normalized
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), ''));
  }
  if (parts.length < 3 && year != null && year > 0) parts.add('$year');
  return parts.join(' • ');
}

String? normalizeMangaChapterNumber(Object? value) {
  var text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  text = text.replaceFirst(
    RegExp(r'^(?:cap[ií]tulo|cap\.?|chapter|ch\.?)\s*', caseSensitive: false),
    '',
  );
  return text.trim().isEmpty ? null : text.trim();
}

String? mangaStatusLabel(MangaStatus status) => switch (status) {
      MangaStatus.ongoing => 'Ongoing',
      MangaStatus.completed => 'Completed',
      MangaStatus.hiatus => 'Hiatus',
      MangaStatus.cancelled => 'Cancelled',
      MangaStatus.unknown => null,
    };

/// A lightweight manga entry returned by browse and search operations.
class MangaCatalogItem {
  final String id;
  final String title;
  final Uri? coverUri;

  /// Short secondary line (latest chapter, type, etc.).
  final String? subtitle;

  const MangaCatalogItem({
    required this.id,
    required this.title,
    this.coverUri,
    this.subtitle,
  });

  factory MangaCatalogItem.fromJson(Map<dynamic, dynamic> json) {
    return MangaCatalogItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      coverUri: _parseUri(json['coverImageUrl']),
      subtitle: _nullableString(json['latestChapter'] ?? json['subtitle']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverImageUrl': coverUri?.toString() ?? '',
        if (subtitle != null && subtitle!.isNotEmpty) 'latestChapter': subtitle,
        'type': 'manga',
      };
}

/// One page of catalog results.
///
/// [nextCursor] is intentionally opaque. Sources can use a page number, token,
/// URL, or any other pagination value without leaking that detail to the UI.
class MangaCatalogPage {
  final List<MangaCatalogItem> items;
  final String? nextCursor;

  MangaCatalogPage({
    required Iterable<MangaCatalogItem> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// A genre/category exposed by a manga source.
class MangaGenre {
  final String id;
  final String name;
  final bool isAdult;

  const MangaGenre({
    required this.id,
    required this.name,
    this.isAdult = false,
  });
}

/// Taxonomy groups exposed by sources with richer adult-gallery metadata.
enum MangaTaxonomyKind { tag, artist, circle }

/// A selectable tag, artist, or circle and its canonical source identifier.
class MangaTaxonomyOption {
  final String id;
  final String name;
  final int? titleCount;

  const MangaTaxonomyOption({
    required this.id,
    required this.name,
    this.titleCount,
  });
}

/// A single chapter reference belonging to a manga.
class MangaChapter {
  final String id;
  final String title;

  /// Raw chapter number as the source reports it (e.g. '1', '1.5', '32').
  /// Kept as a string to preserve the exact label and stay compatible with the
  /// stored `chapter` key.
  final String number;
  final String? volume;
  final String language;
  final String? pages;
  final String? uploader;
  final String? publishedAt;

  const MangaChapter({
    required this.id,
    this.title = '',
    this.number = '',
    this.volume,
    this.language = 'pt-br',
    this.pages,
    this.uploader,
    this.publishedAt,
  });

  factory MangaChapter.fromJson(Map<dynamic, dynamic> json) {
    return MangaChapter(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      number: (json['chapter'] ?? '').toString(),
      volume: _nullableString(json['volume']),
      language: (json['translatedLanguage'] ?? 'pt-br').toString(),
      pages: _nullableString(json['pages']),
      uploader: _nullableString(json['uploader']),
      publishedAt: _nullableString(json['publishedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'chapter': number,
        if (volume != null) 'volume': volume,
        'translatedLanguage': language,
        if (pages != null) 'pages': pages,
        if (uploader != null) 'uploader': uploader,
        if (publishedAt != null) 'publishedAt': publishedAt,
      };
}

/// Complete metadata for a manga title.
class MangaDetails {
  final MangaCatalogItem item;
  final String description;

  /// Alternative titles as `{languageCode: title}` maps, matching the legacy
  /// `altTitles` shape the UI already renders.
  final List<Map<String, String>> alternativeTitles;
  final List<String> genres;
  final String? author;
  final String? artist;
  final MangaStatus status;

  /// Canonical web URL for the title (opened by the in-app WebView).
  final Uri? externalUri;
  final List<MangaChapter> chapters;

  MangaDetails({
    required this.item,
    this.description = '',
    Iterable<Map<String, String>> alternativeTitles = const [],
    Iterable<String> genres = const [],
    this.author,
    this.artist,
    this.status = MangaStatus.unknown,
    this.externalUri,
    Iterable<MangaChapter> chapters = const [],
  })  : alternativeTitles = List.unmodifiable(alternativeTitles),
        genres = List.unmodifiable(genres),
        chapters = List.unmodifiable(chapters);

  factory MangaDetails.fromJson(Map<dynamic, dynamic> json) {
    return MangaDetails(
      item: MangaCatalogItem.fromJson(Map<dynamic, dynamic>.from(json)),
      description: (json['description'] ?? '').toString(),
      alternativeTitles: _parseAltTitles(json['altTitles']),
      genres: _parseStringList(json['tags']),
      author: _parsePersonName(json['author']),
      artist: _parsePersonName(json['artist']),
      status: mangaStatusFromString(json['status']),
      externalUri: _parseUri(json['mangaUrl']),
      chapters: _parseChapters(json['chapters']),
    );
  }

  /// Serializes to the legacy book map so the storage/organization layer and the
  /// existing UI keep working without a data migration.
  Map<String, dynamic> toJson() => {
        ...item.toJson(),
        'description': description,
        'altTitles': alternativeTitles
            .map((entry) => Map<String, String>.from(entry))
            .toList(),
        'tags': List<String>.from(genres),
        if (author != null) 'author': author,
        if (artist != null) 'artist': artist,
        'status': status.name,
        if (externalUri != null) 'mangaUrl': externalUri.toString(),
        'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
      };
}

/// A single resolved page of a chapter.
///
/// A page is either a locally downloaded image ([filePath]) or a remote image
/// ([uri] + [headers]). This unifies the previously inconsistent chapter reading
/// protocols across sources.
class MangaReaderPage {
  final String? filePath;
  final Uri? uri;
  final Map<String, String> headers;

  MangaReaderPage._({
    this.filePath,
    this.uri,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers) {
    if ((filePath == null || filePath!.isEmpty) && uri == null) {
      throw ArgumentError(
        'A reader page must have either a local file path or a remote URI.',
      );
    }
  }

  /// A page backed by a file already downloaded to disk.
  factory MangaReaderPage.file(String filePath) {
    if (filePath.isEmpty) {
      throw ArgumentError.value(filePath, 'filePath', 'must not be empty');
    }
    return MangaReaderPage._(filePath: filePath);
  }

  /// A page served directly from a remote URL, with optional request headers.
  factory MangaReaderPage.network(
    Uri uri, {
    Map<String, String> headers = const {},
  }) =>
      MangaReaderPage._(uri: uri, headers: headers);

  bool get isLocal => filePath != null && filePath!.isNotEmpty;
}

/// Contract implemented by manga/comic sources.
///
/// It is deliberately independent from the typed [AnimeSource] contract and
/// replaces the legacy `Scrapper` class.
abstract interface class MangaSource {
  /// Stable identifier used by persistence. It must match `^[a-z0-9_]+$` and
  /// must not depend on the display [name].
  String get id;

  String get name;

  Uri get baseUri;

  /// Headers applied to catalog and metadata requests when a source needs them.
  Map<String, String> get requestHeaders;

  /// Headers the UI must apply when loading cover/page images (e.g. MangaDex
  /// requires a `Referer`). Replaces the legacy `Scrapper.imageHeaders`.
  Map<String, String> get coverImageHeaders;

  List<MangaCatalogFilter> get catalogFilters;

  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  });

  Future<MangaCatalogPage> search(String query, {String? cursor});

  Future<MangaDetails> getDetails(String mangaId);

  /// Streams the pages of a chapter. Sources that download images emit local
  /// [MangaReaderPage.file] pages progressively; sources that can only be read
  /// in a browser emit nothing and rely on [WebViewChapterMangaSource].
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  });
}

/// Optional capability for sources whose chapters are only readable in a
/// browser (DRM/WASM images, SPA players). Also used as the fallback when
/// [MangaSource.readChapter] produces no pages.
abstract interface class WebViewChapterMangaSource {
  Uri chapterWebUri({required String mangaId, required String chapterId});
}

/// Optional capability for previous/next chapter navigation.
abstract interface class ChapterNavigationMangaSource {
  Future<String?> nextChapterId(String mangaId, String currentChapterId);

  Future<String?> previousChapterId(String mangaId, String currentChapterId);
}

/// Optional capability for sources that expose a genre catalog.
abstract interface class GenreBrowsableMangaSource {
  Future<List<MangaGenre>> getGenres();

  Future<MangaCatalogPage> browseGenre(
    String genreId, {
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  });
}

/// Optional capability for sources that expose tags and creator taxonomies.
///
/// Large artist/circle indexes may require [query] before returning results;
/// implementations should cache their parsed index so typing does not trigger
/// repeated multi-megabyte downloads.
abstract interface class TaxonomyBrowsableMangaSource {
  List<MangaTaxonomyKind> get taxonomyKinds;

  Future<List<MangaTaxonomyOption>> getTaxonomy(
    MangaTaxonomyKind kind, {
    String query = '',
  });

  Future<MangaCatalogPage> browseTaxonomy(
    MangaTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  });
}

/// Source-aware catalog labels while keeping the shared filter enum stable.
extension MangaSourcePresentation on MangaSource {
  String catalogFilterLabel(MangaCatalogFilter filter) {
    if (id == 'hdoujin') {
      return switch (filter) {
        MangaCatalogFilter.popular => 'Popular',
        MangaCatalogFilter.updated => 'Recent doujin',
        MangaCatalogFilter.added => 'Recent removals',
        MangaCatalogFilter.recent => 'Recent manga',
        MangaCatalogFilter.trending => 'Trending',
        MangaCatalogFilter.alphabetical => 'Alphabetical',
      };
    }
    return switch (filter) {
      MangaCatalogFilter.updated => 'Latest',
      MangaCatalogFilter.added => 'Recently added',
      MangaCatalogFilter.recent => 'Recent',
      MangaCatalogFilter.trending => 'Trending',
      MangaCatalogFilter.alphabetical => 'Alphabetical',
      MangaCatalogFilter.popular => 'Popular',
    };
  }
}

/// Optional capability for sources that authenticate with a username/password
/// form (e.g. Django allauth).
abstract interface class CredentialAuthMangaSource {
  Future<void> authenticateWithCredentials(String username, String password);

  Future<void> logout();

  bool get isAuthenticated;
}

/// Optional capability for sources protected by a browser-managed session
/// (cookies/Bearer captured through a WebView, e.g. Cloudflare Turnstile).
abstract interface class BrowserSessionMangaSource {
  Uri get loginUri;

  Future<void> updateBrowserSession(Map<String, String> cookies);

  Future<void> restoreSession();

  Future<void> logout();

  bool get isAuthenticated;
}

/// Signals that a source needs its browser verification/login to be completed
/// before its endpoints can be consumed.
class MangaSourceSessionRequired implements Exception {
  final String message;

  const MangaSourceSessionRequired(this.message);

  @override
  String toString() => message;
}

// ─── Parsing helpers ─────────────────────────────────────────────────────────

MangaStatus mangaStatusFromString(Object? value) {
  final status = value?.toString().toLowerCase().trim() ?? '';
  if (status.isEmpty) return MangaStatus.unknown;
  if (status == MangaStatus.ongoing.name ||
      status.contains('ongoing') ||
      status.contains('andamento') ||
      status.contains('em lançamento') ||
      status.contains('airing') ||
      status.contains('publishing')) {
    return MangaStatus.ongoing;
  }
  if (status == MangaStatus.completed.name ||
      status.contains('complete') ||
      status.contains('completo') ||
      status.contains('finished') ||
      status.contains('finalizado')) {
    return MangaStatus.completed;
  }
  if (status == MangaStatus.hiatus.name || status.contains('hiatus')) {
    return MangaStatus.hiatus;
  }
  if (status == MangaStatus.cancelled.name ||
      status.contains('cancel') ||
      status.contains('abandon')) {
    return MangaStatus.cancelled;
  }
  return MangaStatus.unknown;
}

Uri? _parseUri(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  return uri != null && uri.hasScheme ? uri : null;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

List<String> _parseStringList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .map((item) => item?.toString() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, String>> _parseAltTitles(Object? value) {
  if (value is! Iterable) return const [];
  final result = <Map<String, String>>[];
  for (final entry in value) {
    if (entry is Map) {
      result.add(entry.map(
        (key, val) => MapEntry(key.toString(), val?.toString() ?? ''),
      ));
    } else if (entry is String && entry.isNotEmpty) {
      result.add({'': entry});
    }
  }
  return result;
}

/// Reads a person field that may be a plain string or a `{name: ...}` map.
String? _parsePersonName(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is Map) return _nullableString(value['name']);
  return _nullableString(value);
}

List<MangaChapter> _parseChapters(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((chapter) => MangaChapter.fromJson(chapter))
      .toList(growable: false);
}
