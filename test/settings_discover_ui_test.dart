import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/settings_nav_item.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/pages/settings_pages/account_settings_screen.dart';
import 'package:star_scrapper_app/pages/settings_pages/general_settings_screen.dart';
import 'package:star_scrapper_app/pages/tracker_homepage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('settings option explains itself on long press', (tester) async {
    final theme = ThemeProvider();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.selectedTheme,
        home: Scaffold(
          body: SettingsNavItem(
            icon: Icons.sync_alt_rounded,
            label: 'Trackers',
            description: 'Configure tracker services.',
            theme: theme,
            onTap: () {},
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Trackers'));
    await tester.pumpAndSettle();

    expect(find.text('Configure tracker services.'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('settings sections omit redundant captions and center headings',
      (tester) async {
    final theme = ThemeProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
          theme: theme.selectedTheme,
          home: const Scaffold(body: GeneralSettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(
        find.text('Customize your library and content sources.'), findsNothing);
    expect(find.text('Choose a palette. Layout and contrast stay consistent.'),
        findsNothing);
    expect(
        tester.widget<Text>(find.text('General')).textAlign, TextAlign.center);
    expect(tester.widget<Text>(find.text('Appearance')).textAlign,
        TextAlign.center);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
          theme: theme.selectedTheme,
          home: const Scaffold(body: AccountSettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Manage your account information, security settings, and preferences.',
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('Account Settings')).textAlign,
      TextAlign.center,
    );
  });

  testWidgets('Discover shows and remembers its first-use tutorial',
      (tester) async {
    final tracker = _FakeTrackerController();
    final navigation = AppState();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TrackerController>.value(value: tracker),
          ChangeNotifierProvider<AppState>.value(value: navigation),
        ],
        child: const MaterialApp(home: Scaffold(body: TrackerHomepage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Discover at a glance'), findsNothing);
    navigation.setIndex(1);
    await tester.pumpAndSettle();

    expect(find.text('Discover at a glance'), findsOneWidget);
    expect(find.text('Search the tracker catalog'), findsOneWidget);
    expect(find.text('Open or find a source'), findsOneWidget);

    await tester.tap(find.text('Start exploring'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('discover_tracker_tutorial_seen_v1'),
      isTrue,
    );
    expect(
      find.text(
          'Powered by your enabled trackers and matched with your sources.'),
      findsNothing,
    );
  });
}

class _FakeTrackerController extends TrackerController {
  @override
  bool get initialized => true;

  @override
  bool get hasEnabledTracker => false;

  @override
  Future<TrackerHomeData> loadHome(TrackedMediaType type) async =>
      TrackerHomeData(sections: const []);

  @override
  Future<TrackerTaxonomy> loadTaxonomy() async => TrackerTaxonomy.empty;
}
