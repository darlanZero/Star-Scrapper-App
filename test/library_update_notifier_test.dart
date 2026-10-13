import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/application/notifications/library_update_notifier.dart';

void main() {
  test('does not invoke the platform for an empty update list', () async {
    var deliveries = 0;
    final notifier = LibraryUpdateNotifier(
      deliver: ({
        required id,
        required title,
        required body,
        required payload,
      }) async {
        deliveries++;
      },
    );

    expect(await notifier.notifyUpdatedBooks([]), isFalse);
    expect(deliveries, 0);
  });

  test('formats titles and serializes updated books in the payload', () async {
    int? deliveredId;
    String? deliveredTitle;
    String? deliveredBody;
    String? deliveredPayload;
    final notifier = LibraryUpdateNotifier(
      deliver: ({
        required id,
        required title,
        required body,
        required payload,
      }) async {
        deliveredId = id;
        deliveredTitle = title;
        deliveredBody = body;
        deliveredPayload = payload;
      },
    );
    final books = [
      <String, dynamic>{'id': '1', 'title': 'First'},
      <String, dynamic>{'id': '2', 'title': 'Second'},
    ];

    expect(await notifier.notifyUpdatedBooks(books), isTrue);

    expect(deliveredId, 0);
    expect(deliveredTitle, 'Books Updated');
    expect(deliveredBody, contains('First, Second'));
    expect(jsonDecode(deliveredPayload!), books);
  });
}
