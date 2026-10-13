import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:star_scrapper_app/data/library/library_storage.dart';

typedef NotificationDelivery = Future<void> Function({
  required int id,
  required String title,
  required String body,
  required String payload,
});

/// Formats and delivers notifications for books with new chapters.
class LibraryUpdateNotifier {
  final NotificationDelivery _deliver;

  LibraryUpdateNotifier({NotificationDelivery? deliver})
      : _deliver = deliver ?? _deliverWithPlatformPlugin;

  Future<bool> notifyUpdatedBooks(List<BookData> updatedBooks) async {
    if (updatedBooks.isEmpty) return false;
    final bookTitles = updatedBooks
        .map((book) => (book['title'] ?? 'Unknown book').toString())
        .join(', ');

    await _deliver(
      id: 0,
      title: 'Books Updated',
      body: 'The following books have been updated: $bookTitles',
      payload: jsonEncode(updatedBooks),
    );
    return true;
  }

  static Future<void> _deliverWithPlatformPlugin({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'books_updates_channel',
      'Books Updates',
      importance: Importance.max,
      priority: Priority.high,
      channelDescription: 'Channel for books updates',
      showWhen: false,
    );
    const details = NotificationDetails(android: androidDetails);
    await FlutterLocalNotificationsPlugin().show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
