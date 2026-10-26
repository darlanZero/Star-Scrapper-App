import 'package:star_scrapper_app/data/library/library_storage.dart';
import 'package:star_scrapper_app/domain/library/book_record.dart';
import 'package:star_scrapper_app/domain/library/chapter_record.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

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
    final previous = _readBooks[index].toJson();
    final merged = Map<String, dynamic>.from(updatedBook);
    for (final key in const ['sourceId', 'readChapterCount']) {
      if (!merged.containsKey(key) && previous.containsKey(key)) {
        merged[key] = previous[key];
      }
    }
    _readBooks[index] = BookRecord.fromJson(merged);
    _expandSequentialRemoteProgress(merged);
    await storage.saveReadBookRecords(_readBooks);
    await storage.saveSelectedChapterRecords(_selectedChapters);
    await rebuildLastReadChapters(notify: false);
    onChanged();
  }

  /// Merges source-side Continue Reading entries without deleting newer local
  /// data. Returns the number of remote titles considered.
  Future<int> mergeRemoteHistory(
    String sourceId,
    Iterable<MangaReadingHistoryEntry> entries,
  ) async {
    var mergedCount = 0;
    for (final entry in entries) {
      final remoteBook = entry.details.toJson()
        ..['sourceId'] = sourceId
        ..['readChapterCount'] = entry.readChapterCount;
      final bookId = remoteBook['id']?.toString() ?? '';
      if (bookId.isEmpty) continue;

      final index = _readBooks.indexWhere((book) => book.id == bookId);
      if (index == -1) {
        _readBooks.add(BookRecord.fromJson(remoteBook));
      } else {
        final local = _readBooks[index].toJson();
        final localSource = local['sourceId']?.toString();
        if (localSource != null &&
            localSource.isNotEmpty &&
            localSource != sourceId) {
          continue;
        }
        final combined = <String, dynamic>{...remoteBook, ...local};
        combined['sourceId'] = sourceId;
        combined['readChapterCount'] = _maxInt(
          _asInt(local['readChapterCount']),
          entry.readChapterCount,
        );
        _readBooks[index] = BookRecord.fromJson(combined);
      }

      final remoteChapter = ChapterRecord(
        id: entry.lastReadChapter.id,
        title: entry.lastReadChapter.number.isNotEmpty
            ? entry.lastReadChapter.number
            : (entry.lastReadChapter.title.isNotEmpty
                ? entry.lastReadChapter.title
                : entry.lastReadChapter.id),
      );
      final chapters = _selectedChapters.putIfAbsent(bookId, () => []);
      if (!chapters.any((chapter) => chapter.id == remoteChapter.id)) {
        chapters.add(remoteChapter);
      }
      final localLast = _lastReadChapters[bookId];
      if (localLast == null ||
          _chapterOrder(remoteChapter) >= _chapterOrder(localLast)) {
        _lastReadChapters[bookId] = remoteChapter;
      }
      mergedCount++;
    }

    if (mergedCount == 0) return 0;
    await Future.wait([
      storage.saveReadBookRecords(_readBooks),
      storage.saveSelectedChapterRecords(_selectedChapters),
      storage.saveLastReadChapterRecords(_lastReadChapters),
    ]);
    onChanged();
    return mergedCount;
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
    final bookIndex = _readBooks.indexWhere((book) => book.id == bookId);
    if (bookIndex != -1) {
      final book = _readBooks[bookIndex].toJson();
      book['readChapterCount'] = _maxInt(
        _asInt(book['readChapterCount']),
        chapters.length,
      );
      _readBooks[bookIndex] = BookRecord.fromJson(book);
      await storage.saveReadBookRecords(_readBooks);
    }
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

  void _expandSequentialRemoteProgress(BookData book) {
    final bookId = book['id']?.toString() ?? '';
    final last = _lastReadChapters[bookId];
    final rawChapters = book['chapters'];
    if (bookId.isEmpty || last == null || rawChapters is! List) return;

    final lastOrder = _chapterOrder(last);
    if (!lastOrder.isFinite) return;
    final selected = _selectedChapters.putIfAbsent(bookId, () => []);
    for (final raw in rawChapters) {
      if (raw is! Map) continue;
      final chapter = ChapterRecord.fromJson(raw);
      if (chapter.id.isEmpty) continue;
      final number = (raw['chapter'] ?? chapter.title).toString();
      final candidate = ChapterRecord(id: chapter.id, title: number);
      if (_chapterOrder(candidate) <= lastOrder &&
          !selected.any((stored) => stored.id == candidate.id)) {
        selected.add(candidate);
      }
    }
    selected.sort(
        (left, right) => _chapterOrder(left).compareTo(_chapterOrder(right)));
  }

  static int _asInt(Object? value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;

  static int _maxInt(int left, int right) => left > right ? left : right;

  static double _chapterOrder(ChapterRecord chapter) {
    final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(chapter.title);
    if (match == null) return double.negativeInfinity;
    return double.tryParse(match.group(0)!.replaceAll(',', '.')) ??
        double.negativeInfinity;
  }
}
