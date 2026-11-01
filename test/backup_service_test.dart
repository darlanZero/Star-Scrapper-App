import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/services/backup_service.dart';

class _FakeSecureStore implements BackupSecureStore {
  Map<String, String> values;

  _FakeSecureStore([Map<String, String>? values])
      : values = Map<String, String>.from(values ?? const {});

  @override
  Future<Map<String, String>> readLoginEntries() async =>
      Map<String, String>.from(values);

  @override
  Future<void> replaceLoginEntries(Map<String, String> entries) async {
    values = Map<String, String>.from(entries);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory backupDirectory;
  late _FakeSecureStore secureStore;
  late BackupService service;

  setUp(() async {
    backupDirectory = await Directory.systemTemp.createTemp('stars_backup_');
    secureStore = _FakeSecureStore();
    service = BackupService(
      secureStore: secureStore,
      backupDirectoryProvider: () async => backupDirectory,
      pbkdf2Iterations: 1000,
    );
  });

  tearDown(() async {
    if (await backupDirectory.exists()) {
      await backupDirectory.delete(recursive: true);
    }
  });

  test('encrypted backup restores all library state and stored logins',
      () async {
    final original = <String, Object>{
      'favoritedBooks': ['favorite-manga'],
      'readBooks': ['read-manga'],
      'selectedChapterIds': '{"manga-1":[{"id":"3"}]}',
      'lastReadedChapterId': '{"manga-1":{"id":"3"}}',
      'anime_library_favorites_v1': ['favorite-anime'],
      'anime_episode_progress_v1': ['watched-episode'],
      'libraryTabs': ['Reading', 'Completed'],
      'librarySubTabsByPrimary': '{"Reading":["Unread","Read"]}',
      'animeLibraryTabs': ['Watching', 'Completed'],
      'animeLibrarySubTabsByPrimary': '{"Watching":["Queue"]}',
      'activeSourceIds': ['mangadex', 'comick'],
      'activeAnimeSourceIds': ['anitube', 'animeq'],
    };
    SharedPreferences.setMockInitialValues(original);
    secureStore.values = {
      'scrapper_session_mediocrescan': '{"access_token":"source-secret"}',
      'tracker_aniList_access_token': 'tracker-secret',
    };

    final filePath = await service.createBackup(password: 'backup-pass-123');
    final encodedFile = await File(filePath).readAsString();

    expect(await service.backupRequiresPassword(filePath), isTrue);
    expect(encodedFile, isNot(contains('favorite-manga')));
    expect(encodedFile, isNot(contains('source-secret')));
    expect(encodedFile, isNot(contains('tracker-secret')));

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('temporary', 'must disappear');
    secureStore.values = {'scrapper_session_old': 'must disappear'};

    await service.restoreBackup(filePath, password: 'backup-pass-123');

    for (final entry in original.entries) {
      expect(prefs.get(entry.key), entry.value, reason: entry.key);
    }
    expect(prefs.containsKey('temporary'), isFalse);
    expect(secureStore.values, {
      'scrapper_session_mediocrescan': '{"access_token":"source-secret"}',
      'tracker_aniList_access_token': 'tracker-secret',
    });
  });

  test('wrong password does not mutate current preferences or logins',
      () async {
    SharedPreferences.setMockInitialValues({
      'libraryTabs': ['Reading']
    });
    secureStore.values = {'scrapper_session_yomu': 'saved-session'};
    final filePath = await service.createBackup(password: 'correct-pass');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('libraryTabs', ['Current']);
    secureStore.values = {'scrapper_session_yomu': 'current-session'};

    await expectLater(
      service.restoreBackup(filePath, password: 'incorrect-pass'),
      throwsA(isA<BackupPasswordException>()),
    );

    expect(prefs.getStringList('libraryTabs'), ['Current']);
    expect(
      secureStore.values,
      {'scrapper_session_yomu': 'current-session'},
    );
  });

  test('legacy schema remains restorable without replacing secure logins',
      () async {
    SharedPreferences.setMockInitialValues({
      'libraryTabs': ['Current']
    });
    secureStore.values = {'scrapper_session_yomu': 'current-session'};
    final file = File('${backupDirectory.path}/legacy.starsbackup');
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'entries': [
          {
            'key': 'libraryTabs',
            'type': 'stringList',
            'value': ['Legacy restored'],
          },
        ],
      }),
    );

    expect(await service.backupRequiresPassword(file.path), isFalse);
    await service.restoreBackup(file.path);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('libraryTabs'), ['Legacy restored']);
    expect(
      secureStore.values,
      {'scrapper_session_yomu': 'current-session'},
    );
  });
}
