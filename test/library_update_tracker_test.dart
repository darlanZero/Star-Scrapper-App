import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/library_update_tracker.dart';

Map<String, dynamic> bookWithChapter(
  String bookId,
  String chapterId,
  String updatedAt,
) {
  return {
    'id': bookId,
    'chapters': [
      {'id': chapterId, 'updatedAt': updatedAt},
    ],
  };
}

void main() {
  test('loads persisted state and tolerates corrupt token data', () async {
    SharedPreferences.setMockInitialValues({
      'trackerLastCheckedAtMs': 1000,
      'lastKnownLatestChapterTokenByBook': 'invalid-json',
    });
    final tracker = LibraryUpdateTracker(onChanged: () {});

    await tracker.initialize();

    expect(tracker.lastCheckedAt?.millisecondsSinceEpoch, 1000);
    expect(tracker.latestTokenByBook, isEmpty);
  });

  test('detects chapter changes, deduplicates books and persists state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final checkedAt = DateTime.utc(2026, 10, 11, 12);
    final tracker = LibraryUpdateTracker(
      onChanged: () {},
      clock: () => checkedAt,
    );
    await tracker.initialize();
    final oldBook = bookWithChapter(
      'book-1',
      'chapter-1',
      '2026-10-10T12:00:00Z',
    );
    final newBook = bookWithChapter(
      'book-1',
      'chapter-2',
      '2026-10-11T12:00:00Z',
    );
    var loads = 0;
    final refreshed = <Map<String, dynamic>>[];

    final updates = await tracker.checkBooks(
      books: [oldBook, oldBook],
      loadDetails: (book, bookId) async {
        loads++;
        return newBook;
      },
      onBookRefreshed: refreshed.add,
    );

    expect(loads, 1);
    expect(refreshed, [newBook]);
    expect(updates, [newBook]);
    expect(
      tracker.lastCheckedAt?.millisecondsSinceEpoch,
      checkedAt.millisecondsSinceEpoch,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('trackerLastCheckedAtMs'),
        checkedAt.millisecondsSinceEpoch);
    final tokens = jsonDecode(
      prefs.getString('lastKnownLatestChapterTokenByBook')!,
    ) as Map<String, dynamic>;
    expect(tokens['book-1'], contains('chapter-2'));
  });

  test('continues checking when one source fails', () async {
    SharedPreferences.setMockInitialValues({});
    final tracker = LibraryUpdateTracker(onChanged: () {});
    await tracker.initialize();
    final first = bookWithChapter('first', '1', '2026-10-10T12:00:00Z');
    final second = bookWithChapter('second', '1', '2026-10-10T12:00:00Z');
    final refreshed = <String>[];

    final updates = await tracker.checkBooks(
      books: [first, second],
      loadDetails: (book, bookId) async {
        if (bookId == 'first') throw StateError('source unavailable');
        return bookWithChapter('second', '2', '2026-10-11T12:00:00Z');
      },
      onBookRefreshed: (book) => refreshed.add(book['id'].toString()),
    );

    expect(refreshed, ['second']);
    expect(updates.single['id'], 'second');
  });
}
