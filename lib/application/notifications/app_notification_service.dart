import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum AppNotificationChannel { libraryUpdates, tracker, backups }

typedef AppNotificationDelivery = Future<void> Function({
  required int id,
  required String title,
  required String body,
  required String payload,
  required AppNotificationChannel channel,
});

/// Central notification gateway for library tracking and backup operations.
class AppNotificationService {
  static final AppNotificationService instance = AppNotificationService._();

  final AppNotificationDelivery _deliver;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  AppNotificationService({
    AppNotificationDelivery? deliver,
    FlutterLocalNotificationsPlugin? plugin,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _deliver = deliver ?? _deliverWithPlatformPlugin;

  AppNotificationService._()
      : _plugin = FlutterLocalNotificationsPlugin(),
        _deliver = _deliverWithPlatformPlugin;

  Future<void> initialize({bool requestPermission = true}) async {
    if (_initialized) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _initialized = true;

      if (requestPermission &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (error) {
      debugPrint('Could not initialize notifications: $error');
    }
  }

  Future<bool> notifyMangaUpdates(
    Iterable<Map<String, dynamic>> books,
  ) async {
    final items = books.toList(growable: false);
    if (items.isEmpty) return false;
    final titles = items
        .map((book) => (book['title'] ?? 'Unknown title').toString())
        .toList(growable: false);
    await _send(
      id: 1000,
      title: items.length == 1
          ? 'New chapter available'
          : '${items.length} manga updates',
      body: _titlesBody(titles, singularSuffix: 'has a new chapter'),
      payload: jsonEncode({'type': 'manga_updates', 'items': items}),
      channel: AppNotificationChannel.libraryUpdates,
    );
    return true;
  }

  Future<bool> notifyAnimeUpdates(Iterable<String> titles) async {
    final items = titles.where((title) => title.trim().isNotEmpty).toList();
    if (items.isEmpty) return false;
    await _send(
      id: 1001,
      title: items.length == 1
          ? 'New episode available'
          : '${items.length} anime updates',
      body: _titlesBody(items, singularSuffix: 'has a new episode'),
      payload: jsonEncode({'type': 'anime_updates', 'titles': items}),
      channel: AppNotificationChannel.libraryUpdates,
    );
    return true;
  }

  Future<void> notifyTrackerCompleted({
    required String mediaType,
    required int checkedCount,
    required int updateCount,
  }) =>
      _send(
        id: mediaType.toLowerCase() == 'anime' ? 1101 : 1100,
        title: '$mediaType tracking completed',
        body: updateCount == 0
            ? '$checkedCount titles checked. Everything is up to date.'
            : '$checkedCount titles checked. $updateCount update(s) found.',
        payload: jsonEncode({
          'type': 'tracker_completed',
          'mediaType': mediaType.toLowerCase(),
          'checkedCount': checkedCount,
          'updateCount': updateCount,
        }),
        channel: AppNotificationChannel.tracker,
      );

  Future<void> notifyBackupCreated(String fileName) => _send(
        id: 1200,
        title: 'Backup created',
        body: '$fileName was saved successfully.',
        payload: jsonEncode({'type': 'backup_created', 'file': fileName}),
        channel: AppNotificationChannel.backups,
      );

  Future<void> notifyBackupRestored(String fileName) => _send(
        id: 1201,
        title: 'Backup restored',
        body: '$fileName was loaded successfully.',
        payload: jsonEncode({'type': 'backup_restored', 'file': fileName}),
        channel: AppNotificationChannel.backups,
      );

  static String _titlesBody(
    List<String> titles, {
    required String singularSuffix,
  }) {
    if (titles.length == 1) return '${titles.single} $singularSuffix.';
    const visibleLimit = 3;
    final visible = titles.take(visibleLimit).join(', ');
    final remaining = titles.length - visibleLimit;
    return remaining > 0 ? '$visible and $remaining more.' : '$visible.';
  }

  Future<void> _send({
    required int id,
    required String title,
    required String body,
    required String payload,
    required AppNotificationChannel channel,
  }) async {
    try {
      await _deliver(
        id: id,
        title: title,
        body: body,
        payload: payload,
        channel: channel,
      );
    } catch (error) {
      debugPrint('Could not deliver notification: $error');
    }
  }

  static Future<void> _deliverWithPlatformPlugin({
    required int id,
    required String title,
    required String body,
    required String payload,
    required AppNotificationChannel channel,
  }) async {
    final android = switch (channel) {
      AppNotificationChannel.libraryUpdates => const AndroidNotificationDetails(
          'library_updates',
          'New releases',
          channelDescription: 'New chapters and episodes from tracked titles',
          importance: Importance.high,
          priority: Priority.high,
          groupKey: 'starslibrary_updates',
        ),
      AppNotificationChannel.tracker => const AndroidNotificationDetails(
          'library_tracker',
          'Library tracking',
          channelDescription: 'Results from manual library tracking checks',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          groupKey: 'starslibrary_tracker',
        ),
      AppNotificationChannel.backups => const AndroidNotificationDetails(
          'library_backups',
          'Backups',
          channelDescription: 'Backup creation and restore confirmations',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          groupKey: 'starslibrary_backups',
        ),
    };
    await FlutterLocalNotificationsPlugin().show(
      id,
      title,
      body,
      NotificationDetails(android: android),
      payload: payload,
    );
  }
}
