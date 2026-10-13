import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/chapter_update_scheduler.dart';

void main() {
  test('loads persisted tracker preferences', () async {
    SharedPreferences.setMockInitialValues({
      'updateIntervalHours': 12,
      'tabsToUpdate': ['Reading', 'Favorites'],
      'trackerEnabled': false,
    });
    final scheduler = ChapterUpdateScheduler(
      onRun: () async {},
      onChanged: () {},
    );

    await scheduler.initialize();

    expect(scheduler.interval, const Duration(hours: 12));
    expect(scheduler.tabs, {'Reading', 'Favorites'});
    expect(scheduler.enabled, isFalse);
    scheduler.dispose();
  });

  test('persists tracker preference changes', () async {
    SharedPreferences.setMockInitialValues({'trackerEnabled': false});
    final scheduler = ChapterUpdateScheduler(
      onRun: () async {},
      onChanged: () {},
    );
    await scheduler.initialize();

    await scheduler.setInterval(const Duration(hours: 5));
    await scheduler.setTabs({'Reading'});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('updateIntervalHours'), 5);
    expect(prefs.getStringList('tabsToUpdate'), ['Reading']);
    scheduler.dispose();
  });
}
