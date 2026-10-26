import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/application/notifications/app_notification_service.dart';

void main() {
  test('does not deliver an update notification for an empty list', () async {
    var deliveries = 0;
    final notifications = AppNotificationService(
      deliver: ({
        required id,
        required title,
        required body,
        required payload,
        required channel,
      }) async {
        deliveries++;
      },
    );

    expect(await notifications.notifyMangaUpdates([]), isFalse);
    expect(await notifications.notifyAnimeUpdates([]), isFalse);
    expect(deliveries, 0);
  });

  test('formats manga releases with a structured payload', () async {
    int? deliveredId;
    String? deliveredTitle;
    String? deliveredBody;
    String? deliveredPayload;
    AppNotificationChannel? deliveredChannel;
    final notifications = AppNotificationService(
      deliver: ({
        required id,
        required title,
        required body,
        required payload,
        required channel,
      }) async {
        deliveredId = id;
        deliveredTitle = title;
        deliveredBody = body;
        deliveredPayload = payload;
        deliveredChannel = channel;
      },
    );
    final books = [
      <String, dynamic>{'id': '1', 'title': 'First'},
      <String, dynamic>{'id': '2', 'title': 'Second'},
    ];

    expect(await notifications.notifyMangaUpdates(books), isTrue);

    expect(deliveredId, 1000);
    expect(deliveredTitle, '2 manga updates');
    expect(deliveredBody, 'First, Second.');
    expect(deliveredChannel, AppNotificationChannel.libraryUpdates);
    expect(jsonDecode(deliveredPayload!)['items'], books);
  });

  test('uses dedicated tracker and backup channels', () async {
    final channels = <AppNotificationChannel>[];
    final titles = <String>[];
    final notifications = AppNotificationService(
      deliver: ({
        required id,
        required title,
        required body,
        required payload,
        required channel,
      }) async {
        channels.add(channel);
        titles.add(title);
      },
    );

    await notifications.notifyTrackerCompleted(
      mediaType: 'Anime',
      checkedCount: 8,
      updateCount: 2,
    );
    await notifications.notifyBackupCreated('stars_1.starsbackup');
    await notifications.notifyBackupRestored('stars_1.starsbackup');

    expect(channels, [
      AppNotificationChannel.tracker,
      AppNotificationChannel.backups,
      AppNotificationChannel.backups,
    ]);
    expect(titles, [
      'Anime tracking completed',
      'Backup created',
      'Backup restored',
    ]);
  });
}
