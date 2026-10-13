import 'package:star_scrapper_app/data/library/library_storage.dart';
import 'package:star_scrapper_app/domain/library/book_record.dart';
import 'package:star_scrapper_app/domain/library/chapter_record.dart';

typedef ReadingProgressChanged = void Function();

/// Owns reading history and chapter progress, including persistence.
class ReadingProgressController {
  final LibraryStorage storage;
  final ReadingProgressChanged onChanged;

  List<BookRecord> _readBooks = [];
  Map<String, List<ChapterRecord>> _selectedChapters = {};
  Map<String, ChapterRecord> _lastReadChapters = {};

  List<BookData> get readBooks =>
      _readBooks.map((book) => book.toJson()).toList(growable: false);

  ReadChaptersByBook get selectedChapterIds => _selectedChapters.map(
        (bookId, chapters) => MapEntry(
          bookId,
          chapters.map((chapter) => chapter.toJson()).toList(),
        ),
      );

  LastReadChapterByBook get lastReadChapterIds => _lastReadChapters.map(
        (bookId, chapter) => MapEntry(bookId, chapter.toJson()),
      );

  ReadingProgressController({
    required this.storage,
    required this.onChanged,
  });

  Future<void> initialize() async {
    final loaded = await Future.wait<dynamic>([
      storage.loadReadBookRecords(),
      storage.loadSelectedChapterRecords(),
      storage.loadLastReadChapterRecords(),
    ]);
    _readBooks = loaded[0] as List<BookRecord>;
    _selectedChapters = loaded[1] as Map<String, List<ChapterRecord>>;
    _lastReadChapters = loaded[2] as Map<String, ChapterRecord>;
    onChanged();
  }

  Future<void> replaceBookDetails(BookData updatedBook) async {
    final bookId = updatedBook['id']?.toString() ?? '';
    if (bookId.isEmpty) return;
    final index = _readBooks.indexWhere((book) => book.id == bookId);
    if (index == -1) return;
    _readBooks[index] = BookRecord.fromJson(updatedBook);
    await storage.saveReadBookRecords(_readBooks);
    onChanged();
  }

  Future<bool> addBookToHistory(BookData book) async {
    final bookId = book['id']?.toString() ?? '';
    if (bookId.isEmpty || _readBooks.any((stored) => stored.id == bookId)) {
      return false;
    }
    _readBooks.add(BookRecord.fromJson(book));
    onChanged();
    await storage.saveReadBookRecords(_readBooks);
    return true;
  }

  Future<ReadChaptersByBook> reloadSelectedChapters() async {
    _selectedChapters = await storage.loadSelectedChapterRecords();
    onChanged();
    return selectedChapterIds;
  }

  Future<void> saveSelectedChapters(
    String bookId,
    List<Map<String, String>> chapters,
  ) async {
    _selectedChapters[bookId] = chapters.map(ChapterRecord.fromJson).toList();
    await storage.saveSelectedChapterRecords(_selectedChapters);
    onChanged();
  }

  Future<void> saveSelectedChaptersSilently() =>
      storage.saveSelectedChapterRecords(_selectedChapters);

  Future<bool> addReadChapter(
    String bookId,
    String chapterId,
    String chapterTitle,
  ) async {
    final chapters = _selectedChapters.putIfAbsent(bookId, () => []);
    if (chapters.any((chapter) => chapter.id == chapterId)) return false;

    chapters.add(ChapterRecord(id: chapterId, title: chapterTitle));
    await storage.saveSelectedChapterRecords(_selectedChapters);
    await rebuildLastReadChapters(notify: false);
    onChanged();
    return true;
  }

  Future<void> clearSelectedChapters() async {
    _selectedChapters = {};
    _lastReadChapters = {};
    await storage.clearSelectedChapterIds();
    await storage.clearLastReadChapterIds();
    onChanged();
  }

  Future<void> rebuildLastReadChapters({bool notify = true}) async {
    _lastReadChapters = {
      for (final entry in _selectedChapters.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.last,
    };
    await storage.saveLastReadChapterRecords(_lastReadChapters);
    if (notify) onChanged();
  }

  Future<LastReadChapterByBook> reloadLastReadChapters() async {
    _lastReadChapters = await storage.loadLastReadChapterRecords();
    onChanged();
    return lastReadChapterIds;
  }

  Future<void> clearLastReadChapters() async {
    _lastReadChapters = {};
    await storage.clearLastReadChapterIds();
    onChanged();
  }
}
