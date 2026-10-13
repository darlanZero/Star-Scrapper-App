import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/reading_progress_controller.dart';
import 'package:star_scrapper_app/data/library/library_storage.dart';

void main() {
  test('loads reading history and chapter progress together', () async {
    SharedPreferences.setMockInitialValues({
      'readBooks': [
        jsonEncode({'id': 'book-1', 'title': 'Book'})
      ],
      'selectedChapterIds': jsonEncode({
        'book-1': [
          {'id': 'chapter-1', 'title': 'Chapter 1'},
        ],
      }),
      'lastReadedChapterId': jsonEncode({
        'book-1': {'id': 'chapter-1', 'title': 'Chapter 1'},
      }),
    });
    var changes = 0;
    final controller = ReadingProgressController(
      storage: LibraryStorage(),
      onChanged: () => changes++,
    );

    await controller.initialize();

    expect(controller.readBooks.single['id'], 'book-1');
    expect(controller.selectedChapterIds['book-1'], hasLength(1));
    expect(controller.lastReadChapterIds['book-1']?['id'], 'chapter-1');
    expect(changes, 1);
  });

  test('adds each chapter once and updates the last-read chapter', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LibraryStorage();
    final controller = ReadingProgressController(
      storage: storage,
      onChanged: () {},
    );
    await controller.initialize();

    expect(
      await controller.addReadChapter('book-1', 'chapter-1', 'Chapter 1'),
      isTrue,
    );
    expect(
      await controller.addReadChapter('book-1', 'chapter-1', 'Chapter 1'),
      isFalse,
    );
    expect(
      await controller.addReadChapter('book-1', 'chapter-2', 'Chapter 2'),
      isTrue,
    );

    expect(controller.selectedChapterIds['book-1'], hasLength(2));
    expect(controller.lastReadChapterIds['book-1'], {
      'id': 'chapter-2',
      'title': 'Chapter 2',
    });
    expect((await storage.loadSelectedChapterIds())['book-1'], hasLength(2));
  });

  test('deduplicates history and replaces stored book details', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LibraryStorage();
    final controller = ReadingProgressController(
      storage: storage,
      onChanged: () {},
    );
    await controller.initialize();

    expect(
      await controller.addBookToHistory({'id': 'book-1', 'title': 'Old'}),
      isTrue,
    );
    expect(
      await controller.addBookToHistory({'id': 'book-1', 'title': 'Duplicate'}),
      isFalse,
    );
    await controller.replaceBookDetails({'id': 'book-1', 'title': 'New'});

    expect(controller.readBooks, hasLength(1));
    expect(controller.readBooks.single['title'], 'New');
    expect((await storage.loadReadBooks()).single['title'], 'New');
  });

  test('clears selected and last-read chapters consistently', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LibraryStorage();
    final controller = ReadingProgressController(
      storage: storage,
      onChanged: () {},
    );
    await controller.initialize();
    await controller.addReadChapter('book-1', 'chapter-1', 'Chapter 1');

    await controller.clearSelectedChapters();

    expect(controller.selectedChapterIds, isEmpty);
    expect(controller.lastReadChapterIds, isEmpty);
    expect(await storage.loadSelectedChapterIds(), isEmpty);
    expect(await storage.loadLastReadChapterIds(), isEmpty);
  });

  test('does not expose mutable internal chapter collections', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ReadingProgressController(
      storage: LibraryStorage(),
      onChanged: () {},
    );
    await controller.initialize();
    await controller.addReadChapter('book-1', 'chapter-1', 'Chapter 1');

    final exported = controller.selectedChapterIds;
    exported['book-1']!.clear();

    expect(controller.selectedChapterIds['book-1'], hasLength(1));
    expect(controller.lastReadChapterIds['book-1'], {
      'id': 'chapter-1',
      'title': 'Chapter 1',
    });
  });

  test('does not expose mutable reading-history books', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ReadingProgressController(
      storage: LibraryStorage(),
      onChanged: () {},
    );
    await controller.initialize();
    final sourceBook = <String, dynamic>{
      'id': 'book-1',
      'title': 'Original',
      'chapters': [
        {'id': 'chapter-1'},
      ],
    };
    await controller.addBookToHistory(sourceBook);

    sourceBook['title'] = 'Changed outside';
    final exported = controller.readBooks;
    (exported.single['chapters'] as List).clear();

    expect(controller.readBooks.single['title'], 'Original');
    expect(controller.readBooks.single['chapters'], hasLength(1));
  });
}
