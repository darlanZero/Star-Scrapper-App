import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/domain/library/book_record.dart';
import 'package:star_scrapper_app/domain/library/chapter_record.dart';

typedef BookData = BookJson;
typedef ReadChaptersByBook = Map<String, List<Map<String, String>>>;
typedef LastReadChapterByBook = Map<String, Map<String, String>>;

/// Persists library data without owning UI or library business state.
class LibraryStorage {
  Future<List<BookData>> loadFavoriteBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedBooks = prefs.getStringList('favoritedBooks') ?? const [];
    final books = <BookData>[];

    for (final encodedBook in encodedBooks) {
      try {
        final decoded = jsonDecode(encodedBook);
        if (decoded is! Map) continue;
        final record = BookRecord.fromJson(Map<String, dynamic>.from(decoded));
        books.add(record.toLegacyTabMigratedJson());
      } catch (_) {
        // Ignore a corrupt entry while preserving the remaining library.
      }
    }
    return books;
  }

  Future<void> saveFavoriteBooks(List<BookData> books) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'favoritedBooks',
      books.map(jsonEncode).toList(),
    );
  }

  Future<List<BookData>> loadReadBooks() async {
    final records = await loadReadBookRecords();
    return records.map((book) => book.toJson()).toList();
  }

  Future<List<BookRecord>> loadReadBookRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedBooks = prefs.getStringList('readBooks') ?? const [];
    final books = <BookRecord>[];
    for (final encodedBook in encodedBooks) {
      try {
        final decoded = jsonDecode(encodedBook);
        if (decoded is Map) {
          books.add(BookRecord.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore a corrupt entry while preserving the remaining history.
      }
    }
    return books;
  }

  Future<void> saveReadBooks(List<BookData> books) async {
    await saveReadBookRecords(books.map(BookRecord.fromJson).toList());
  }

  Future<void> saveReadBookRecords(List<BookRecord> books) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'readBooks',
      books.map((book) => jsonEncode(book.toJson())).toList(),
    );
  }

  Future<ReadChaptersByBook> loadSelectedChapterIds() async {
    final records = await loadSelectedChapterRecords();
    return records.map(
      (bookId, chapters) => MapEntry(
        bookId,
        chapters.map((chapter) => chapter.toJson()).toList(),
      ),
    );
  }

  Future<Map<String, List<ChapterRecord>>> loadSelectedChapterRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selectedChapterIds') ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        if (value is! List) {
          return MapEntry(key.toString(), <ChapterRecord>[]);
        }
        final chapters =
            value.whereType<Map>().map(ChapterRecord.fromJson).toList();
        return MapEntry(key.toString(), chapters);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSelectedChapterIds(ReadChaptersByBook chapters) async {
    await saveSelectedChapterRecords(
      chapters.map(
        (bookId, values) => MapEntry(
          bookId,
          values.map(ChapterRecord.fromJson).toList(),
        ),
      ),
    );
  }

  Future<void> saveSelectedChapterRecords(
    Map<String, List<ChapterRecord>> chapters,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'selectedChapterIds',
      jsonEncode(
        chapters.map(
          (bookId, values) => MapEntry(
            bookId,
            values.map((chapter) => chapter.toJson()).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> clearSelectedChapterIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedChapterIds');
  }

  Future<LastReadChapterByBook> loadLastReadChapterIds() async {
    final records = await loadLastReadChapterRecords();
    return records.map(
      (bookId, chapter) => MapEntry(bookId, chapter.toJson()),
    );
  }

  Future<Map<String, ChapterRecord>> loadLastReadChapterRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('lastReadedChapterId') ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        if (value is! Map) {
          return MapEntry(
            key.toString(),
            const ChapterRecord(id: '', title: ''),
          );
        }
        return MapEntry(
          key.toString(),
          ChapterRecord.fromJson(value),
        );
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> saveLastReadChapterIds(
    LastReadChapterByBook chapters,
  ) async {
    await saveLastReadChapterRecords(
      chapters.map(
        (bookId, value) => MapEntry(
          bookId,
          ChapterRecord.fromJson(value),
        ),
      ),
    );
  }

  Future<void> saveLastReadChapterRecords(
    Map<String, ChapterRecord> chapters,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lastReadedChapterId',
      jsonEncode(
        chapters.map(
          (bookId, chapter) => MapEntry(bookId, chapter.toJson()),
        ),
      ),
    );
  }

  Future<void> clearLastReadChapterIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastReadedChapterId');
  }
}
