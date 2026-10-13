import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/library/library_storage.dart';
import 'package:star_scrapper_app/domain/library/book_record.dart';

void main() {
  test('loads favorites and migrates the legacy single-tab field', () async {
    SharedPreferences.setMockInitialValues({
      'favoritedBooks': [
        jsonEncode({'id': '1', 'title': 'Legacy', 'tab': 'Reading'}),
        'not-json',
      ],
    });
    final storage = LibraryStorage();

    final books = await storage.loadFavoriteBooks();

    expect(books, hasLength(1));
    expect(books.single['tabs'], ['Reading']);
    expect(books.single.containsKey('tab'), isFalse);
  });

  test('round-trips library history and chapter progress', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LibraryStorage();
    final books = [
      <String, dynamic>{
        'id': '1',
        'title': 'Book',
        'tabs': ['Reading'],
      }
    ];
    final selected = {
      '1': [
        {'id': 'chapter-1', 'title': 'Chapter 1'}
      ]
    };
    final lastRead = {
      '1': {'id': 'chapter-1', 'title': 'Chapter 1'}
    };

    await storage.saveFavoriteBooks(books);
    await storage.saveReadBooks(books);
    await storage.saveSelectedChapterIds(selected);
    await storage.saveLastReadChapterIds(lastRead);

    expect(await storage.loadFavoriteBooks(), books);
    expect(await storage.loadReadBooks(), books);
    expect(await storage.loadSelectedChapterIds(), selected);
    expect(await storage.loadLastReadChapterIds(), lastRead);
  });

  test('returns empty progress when stored JSON is corrupt', () async {
    SharedPreferences.setMockInitialValues({
      'selectedChapterIds': 'invalid',
      'lastReadedChapterId': 'invalid',
    });
    final storage = LibraryStorage();

    expect(await storage.loadSelectedChapterIds(), isEmpty);
    expect(await storage.loadLastReadChapterIds(), isEmpty);
  });

  test('round-trips typed reading-history records', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LibraryStorage();
    final records = [
      BookRecord.fromJson({'id': '1', 'title': 'Typed history'}),
    ];

    await storage.saveReadBookRecords(records);
    final loaded = await storage.loadReadBookRecords();

    expect(loaded.single.id, '1');
    expect(loaded.single.title, 'Typed history');
  });
}
