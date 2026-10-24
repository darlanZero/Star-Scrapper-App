import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/config/tracker_build_config.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/tracker_settings_screen.dart';

void main() {
  test('AniList OAuth client is fixed by the StarsLibrary build', () {
    expect(TrackerBuildConfig.aniListClientId, '53713');
    expect(TrackerBuildConfig.hasAniListClient, isTrue);
  });

  testWidgets('tracker settings show the fixed AniList client as read only',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TrackerController(),
        child: const MaterialApp(home: TrackerSettingsScreen()),
      ),
    );

    expect(find.textContaining('Client ID 53713'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'AniList Client ID'), findsNothing);
  });
}
