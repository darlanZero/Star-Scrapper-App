import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/library_organizer.dart';
import 'package:star_scrapper_app/application/library/tabs_state.dart';

Future<LibraryOrganizer> createOrganizer() async {
  SharedPreferences.setMockInitialValues({
    'libraryTabs': ['Reading', 'Completed'],
    'librarySubTabsByPrimary': jsonEncode({
      'Reading': ['Unread', 'Read'],
      'Completed': ['Archived'],
    }),
  });
  final tabsState = TabsState();
  await tabsState.tabsLoaded;
  return LibraryOrganizer(tabsState: tabsState);
}

void main() {
  test('adds a book with the default subtab and avoids duplicates', () async {
    final organizer = await createOrganizer();
    final book = <String, dynamic>{'id': '1', 'title': 'Book'};

    organizer.addBookToTab('Reading', book);
    organizer.addBookToTab('Reading', book);

    expect(organizer.books, hasLength(1));
    expect(organizer.books.single['tabs'], ['Reading']);
    expect(organizer.books.single['subTabsByPrimary'], {
      'Reading': ['Unread'],
    });
  });

  test('replaces book details while preserving its organization', () async {
    final organizer = await createOrganizer();
    organizer.replaceAll([
      {
        'id': '1',
        'title': 'Old title',
        'tab': 'Reading',
        'subTabs': ['Read'],
      },
    ]);

    final replaced = organizer.replaceBookPreservingOrganization({
      'id': '1',
      'title': 'New title',
    });

    expect(replaced, isTrue);
    expect(organizer.books.single['title'], 'New title');
    expect(organizer.books.single['tabs'], ['Reading']);
    expect(organizer.books.single['subTabsByPrimary'], {
      'Reading': ['Read'],
    });
    expect(organizer.books.single.containsKey('tab'), isFalse);
    expect(organizer.books.single.containsKey('subTabs'), isFalse);
  });

  test('renames and remaps tabs without losing a book', () async {
    final organizer = await createOrganizer();
    organizer.replaceAll([
      {
        'id': '1',
        'tabs': ['Reading'],
        'subTabsByPrimary': {
          'Reading': ['Unread'],
        },
      },
    ]);

    organizer.renamePrimaryTabBooks('Reading', 'Queue');
    organizer.remapBooksFromRemovedTab('Queue', 'Completed');
    organizer.remapBooksFromRemovedSubTab(
      'Completed',
      'Unread',
      'Archived',
    );

    expect(organizer.books, hasLength(1));
    expect(organizer.books.single['tabs'], ['Completed']);
    expect(organizer.books.single['subTabsByPrimary'], {
      'Completed': ['Archived'],
    });
  });

  test('does not expose mutable internal book maps', () async {
    final organizer = await createOrganizer();
    final sourceBook = <String, dynamic>{
      'id': '1',
      'title': 'Original',
      'chapters': [
        {'id': 'chapter-1'},
      ],
    };
    organizer.replaceAll([sourceBook]);

    sourceBook['title'] = 'Changed outside';
    final exportedBooks = organizer.books;
    exportedBooks.single['title'] = 'Changed export';
    (exportedBooks.single['chapters'] as List).clear();

    expect(organizer.books.single['title'], 'Original');
    expect(organizer.books.single['chapters'], hasLength(1));
  });
}
