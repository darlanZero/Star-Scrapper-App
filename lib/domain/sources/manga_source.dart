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
