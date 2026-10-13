import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/playback/playback_preferences.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/scrappers_screen.dart';
import 'package:star_scrapper_app/pages/pages.dart';
import 'package:star_scrapper_app/pages/settings_screen.dart';
import 'package:star_scrapper_app/pages/tracker_homepage.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';

void main(List<String> args) {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(
    MultiProvider(providers: [
      ChangeNotifierProvider(create: (context) => ThemeProvider()),
      ChangeNotifierProvider(create: (context) => AppState()),
      ChangeNotifierProvider(
        create: (_) {
          final preferences = PlaybackPreferences();
          preferences.initialize();
          return preferences;
        },
      ),
      ChangeNotifierProvider(create: (_) => TabsState()),
      ChangeNotifierProvider(create: (_) => AnimeTabsState()),
      ChangeNotifierProxyProvider<AnimeTabsState, AnimeLibraryController>(
        create: (context) {
          final controller = AnimeLibraryController();
          controller.setSources(SourceCatalog.createAnimeSources());
          final tabs = context.read<AnimeTabsState>();
          controller.configureTabs(tabs, ready: tabs.tabsLoaded);
          controller.initialize();
          return controller;
        },
        update: (_, tabs, controller) {
          controller!.configureTabs(tabs, ready: tabs.tabsLoaded);
          return controller;
        },
      ),
      ChangeNotifierProvider(
        create: (_) {
          final controller = TrackerController();
          controller.initialize();
          return controller;
        },
      ),
      ChangeNotifierProxyProvider<TabsState, FontProvider>(
        create: (context) =>
            FontProvider(Provider.of<TabsState>(context, listen: false)),
        update: (context, tabsState, fontProvider) {
          fontProvider!.setTabsState(tabsState);
          return fontProvider;
        },
      ),
    ], child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'StarsLibrary',
      theme: theme.selectedTheme,
      home: const MainScreen(title: 'StarsLibrary'),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.title});
  final String title;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePageScreen(),
      const TrackerHomepage(),
      const ScrappersScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final tabsState = context.watch<TabsState>();
    final currentIndex = appState.currentIndex;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 58,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'lib/assets/starscrapper.png',
              width: 34,
              height: 34,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            Text(
              'StarsLibrary',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        bottom: tabsState.appBarBottom,
      ),
      body: IndexedStack(
        index: currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(22),
            ),
            child: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) {
                context.read<AppState>().setIndex(index);
                context.read<TabsState>().setActivePageIndex(index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.local_library_outlined),
                  selectedIcon: Icon(Icons.local_library_rounded),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: 'Sources',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: currentIndex == 0
          ? FloatingActionButton.small(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
              tooltip: 'Search for mangas',
              child: const Icon(Icons.search_rounded),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
