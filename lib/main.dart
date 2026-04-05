import 'dart:ui';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/scrappers_screen.dart';
import 'package:star_scrapper_app/pages/pages.dart';
import 'package:star_scrapper_app/pages/settings_screen.dart';
import 'package:stylish_bottom_bar/stylish_bottom_bar.dart';

void main(List<String> args) {

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(
    MultiProvider(providers: 
    [
      ChangeNotifierProvider(create: (context) => ThemeProvider()),
      ChangeNotifierProvider(create: (context) => AppState()),
      ChangeNotifierProvider(create: (_) => TabsState()),
      ChangeNotifierProxyProvider<TabsState, FontProvider>(
        create: (context) => FontProvider(Provider.of<TabsState>(context, listen: false)),
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
      title: 'Stars - A better lecture',
      theme: theme.selectedTheme,
      home: const MainScreen(title: 'Stars - A better lecture'),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.title});
  final String title;
  
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePageScreen(),
      const ScrappersScreen(),
      const SettingsScreen(),
    ];
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        titleSpacing: 0.0,
        elevation: 0,
        title: Center(
          child: Image.asset(
            'lib/assets/starscrapper.png',
            width: 42,
            height: 42,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 25.0, fontWeight: FontWeight.bold),
        bottom: Provider.of<TabsState>(context).appBarBottom,
      ),

      body: IndexedStack(
        index: Provider.of<AppState>(context).currentIndex,
        children: _pages,
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                color: theme.selectedTheme.bottomNavigationBarTheme.backgroundColor?.withOpacity(0.75),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: StylishBottomBar(
                items: [
                  BottomBarItem(icon: Icon(Icons.home, color: Colors.teal), title: Text('Library'), selectedColor: Colors.teal),
                  BottomBarItem(icon: Icon(Icons.format_list_bulleted), title: Text('Scrappers')),
                  BottomBarItem(icon: Icon(Icons.settings), title: Text('settings')),
                ],
                currentIndex: Provider.of<AppState>(context).currentIndex,
                onTap: (index) {
                  Provider.of<AppState>(context, listen: false).setIndex(index);
                  Provider.of<TabsState>(context, listen: false).setActivePageIndex(index);
                },
                option: AnimatedBarOptions(
                  opacity: 1.0,
                  inkColor: Colors.black,
                  iconSize: 28,
                  barAnimation: BarAnimation.fade,
                  iconStyle: IconStyle.animated,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  inkEffect: true,
                ),
                hasNotch: false,
                backgroundColor: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ),
    
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SearchScreen()),
          );
        },
        tooltip: 'Search for mangas',
        child: const Icon(Icons.search),
      ),
    );
  }
}
