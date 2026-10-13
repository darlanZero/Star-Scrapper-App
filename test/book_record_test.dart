import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/domain/library/book_record.dart';

void main() {
  test('reads legacy organization fields without losing source metadata', () {
    final record = BookRecord.fromJson({
      'id': 42,
      'title': 'Legacy book',
      'tab': 'Reading',
      'subTabs': ['Read'],
      'sourceSpecificField': {'value': true},
    });

    final normalized = record.toNormalizedLibraryJson();

    expect(record.id, '42');
    expect(record.title, 'Legacy book');
    expect(record.tabs, ['Reading']);
    expect(record.subTabsByPrimary, {
      'Reading': ['Read'],
    });
    expect(normalized['sourceSpecificField'], {'value': true});
    expect(normalized.containsKey('tab'), isFalse);
    expect(normalized.containsKey('subTabs'), isFalse);
  });

  test('uses read state as a fallback for legacy subtab data', () {
    final readBook = BookRecord.fromJson({'id': '1', 'isRead': true});
    final unreadBook = BookRecord.fromJson({'id': '2'});

    expect(readBook.subTabsByPrimary, {
      'Reading': ['Read'],
    });
    expect(unreadBook.subTabsByPrimary, {
      'Reading': ['Unread'],
    });
  });

  test('applies organization to refreshed scraper data', () {
    final stored = BookRecord.fromJson({
      'id': '1',
      'tabs': ['Reading', 'Completed'],
      'subTabsByPrimary': {
        'Reading': ['Unread'],
        'Completed': ['Archived'],
      },
    });
    final refreshed = <String, dynamic>{
      'id': '1',
      'title': 'Updated',
      'tab': 'Legacy',
    };

    stored.applyOrganizationTo(refreshed);

    expect(refreshed['tabs'], ['Reading', 'Completed']);
    expect(refreshed['subTabsByPrimary'], {
      'Reading': ['Unread'],
      'Completed': ['Archived'],
    });
    expect(refreshed.containsKey('tab'), isFalse);
  });
}
