import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/library/library_storage.dart';

typedef BookDetailsLoader = Future<BookData> Function(
  BookData book,
  String bookId,
);
typedef UpdatedBookHandler = void Function(BookData updatedBook);

/// Checks library books for chapter changes and persists tracker state.
class LibraryUpdateTracker {
  static const _lastCheckedKey = 'trackerLastCheckedAtMs';
  static const _latestTokensKey = 'lastKnownLatestChapterTokenByBook';

  final void Function() onChanged;
  final DateTime Function() clock;

  int _lastCheckedAtMs = 0;
  Map<String, String> _latestTokenByBook = {};

  LibraryUpdateTracker({
    required this.onChanged,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  DateTime? get lastCheckedAt => _lastCheckedAtMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_lastCheckedAtMs);

  Map<String, String> get latestTokenByBook =>
      Map.unmodifiable(_latestTokenByBook);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _lastCheckedAtMs = prefs.getInt(_lastCheckedKey) ?? 0;
    final raw = prefs.getString(_latestTokensKey) ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _latestTokenByBook = decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      } else {
        _latestTokenByBook = {};
      }
    } catch (_) {
      _latestTokenByBook = {};
    }
    onChanged();
  }

  Future<List<BookData>> checkBooks({
    required Iterable<BookData> books,
    required BookDetailsLoader loadDetails,
    required UpdatedBookHandler onBookRefreshed,
  }) async {
    final booksById = <String, BookData>{};
    for (final book in books) {
      final bookId = book['id']?.toString() ?? '';
      if (bookId.isNotEmpty) booksById[bookId] = book;
    }

    final updatedBooks = <BookData>[];
    for (final entry in booksById.entries) {
      final bookId = entry.key;
      final book = entry.value;
      final currentToken =
          _latestTokenByBook[bookId] ?? extractLatestChapterToken(book);

      try {
        final updatedBook = await loadDetails(book, bookId);
        final latestToken = extractLatestChapterToken(updatedBook);
        onBookRefreshed(updatedBook);

        if (latestToken.isNotEmpty) {
          _latestTokenByBook[bookId] = latestToken;
        }
        if (currentToken.isNotEmpty &&
            latestToken.isNotEmpty &&
            currentToken != latestToken) {
          updatedBooks.add(updatedBook);
        }
      } catch (_) {
        // One unavailable source must not prevent the remaining checks.
      }
    }

    _lastCheckedAtMs = clock().millisecondsSinceEpoch;
    await _save();
    onChanged();
    return updatedBooks;
  }

  String extractLatestChapterToken(BookData bookDetails) {
    final chapters = bookDetails['chapters'];
    if (chapters is! List || chapters.isEmpty) return '';

    var bestEpoch = 0;
    var bestId = '';
    for (final raw in chapters) {
      if (raw is! Map) continue;
      final chapter = Map<String, dynamic>.from(raw);
      final id = (chapter['id'] ?? '').toString();
      final candidates = <String?>[
        chapter['updatedAt']?.toString(),
        chapter['publishedAt']?.toString(),
        chapter['createdAt']?.toString(),
      ];
      var epoch = 0;
      for (final candidate in candidates) {
        if (candidate == null || candidate.isEmpty) continue;
        final date = DateTime.tryParse(candidate);
        if (date != null && date.millisecondsSinceEpoch > epoch) {
          epoch = date.millisecondsSinceEpoch;
        }
      }
      if (epoch > bestEpoch) {
        bestEpoch = epoch;
        bestId = id;
      }
    }

    if (bestId.isEmpty) {
      final first = chapters.first;
      if (first is Map && first['id'] != null) {
        bestId = first['id'].toString();
      }
    }
    return '$bestId@$bestEpoch';
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckedKey, _lastCheckedAtMs);
    await prefs.setString(_latestTokensKey, jsonEncode(_latestTokenByBook));
  }
}
