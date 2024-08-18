import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/Scrappers_screen.dart';
import 'package:star_scrapper_app/pages/pages.dart';
import 'package:star_scrapper_app/pages/settings_screen.dart';
import 'package:stylish_bottom_bar/stylish_bottom_bar.dart';

void main(List<String> args) {
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(providers: 
    [
      ChangeNotifierProvider(create: (context) => ThemeProvider()),
      ChangeNotifierProvider(create: (context) => AppState()),
      ChangeNotifierProvider(create: (_) => TabsState(_)),
      ChangeNotifierProvider(create: (context) => FontProvider()),
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

  final List<Map<String, dynamic>> libraryBooks = [];

  late final List<Widget> _pages;
  late Stream<Map<String, dynamic>> Function(String, String) getchapter;
  late final Stream<Map<String, dynamic>> Function(String, String) retrieveLastChapter;  
  late final Stream<Map<String, dynamic>> Function(String, String) retrieveNextChapter;

  @override
  void initState() {
    super.initState();
     final fontProvider = Provider.of<FontProvider>(context, listen: false);
    getchapter = fontProvider.selectedFontApi.getChapter ?? _dummyGetChapter;
    retrieveLastChapter = fontProvider.selectedFontApi.retrieveLastChapter ?? _dummyGetChapter;
    retrieveNextChapter = fontProvider.selectedFontApi.retrieveNextChapter ?? _dummyGetChapter;
    _pages = [
      HomePageScreen(
        libraryBooks: libraryBooks,
        getchapter: getchapter,
        retrieveLastChapter: retrieveLastChapter,
        retrieveNextChapter: retrieveNextChapter
      ),
      ScrappersScreen(
        getChapter: getchapter,
        retrieveLastChapter: retrieveLastChapter,
        retrieveNextChapter: retrieveNextChapter
      ),
      const SettingsScreen(),
    ];
  }

  

  Future<Map<String, dynamic>> _dummyGetChapter(String chapterId) async {  
    // Implement a dummy function or throw an error if no font is selected  
    throw Exception('No font selected');
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
        title: LayoutBuilder(
          builder: (context, constraints) {
            if (MediaQuery.of(context).size.width >= 600) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('lib/assets/starscrapper.png', width: 150, height: 150, fit: BoxFit.fitHeight, alignment: Alignment.center),
                  Text(widget.title, style: const TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 25.0, fontWeight: FontWeight.bold, shadows: [
                    Shadow(color: Colors.blue, offset: Offset(1.0, 1.0), blurRadius: 3.0),
                    Shadow(color: Colors.red, offset: Offset(1.0, 1.0), blurRadius: 3.0),
                  ])),
                  Opacity(opacity: 0.0, child: Image.asset('lib/assets/starscrapper.png', width: 150, height: 150)),
                ],
              );
            } else {
              return Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('lib/assets/starscrapper.png', width: 150, height: 150, fit: BoxFit.fitHeight, alignment: Alignment.center),
                ]
              );
            }
          },
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

      body: Center(
        child: _pages[Provider.of<AppState>(context).currentIndex],
      ), 

      bottomNavigationBar: StylishBottomBar(
        items: [
          BottomBarItem(icon: Icon(Icons.home, color: Colors.teal), title: Text('Library'), selectedColor: Colors.teal),
          BottomBarItem(icon: Icon(Icons.format_list_bulleted), title: Text('Scrappers')),
          BottomBarItem(icon: Icon(Icons.settings), title: Text('settings')),
        ],
        currentIndex: Provider.of<AppState>(context).currentIndex,
        onTap: (index) {
          Provider.of<AppState>(context, listen: false).setIndex(index);
        },
        option: AnimatedBarOptions(
          opacity: 1.0,
          inkColor: Colors.black,
          iconSize: 30,
          barAnimation: BarAnimation.fade,
          iconStyle: IconStyle.animated,
          padding: EdgeInsets.all(10),
          inkEffect: true,
        ),
        hasNotch: true,
        notchStyle: NotchStyle.circle,
        backgroundColor: theme.selectedTheme.bottomNavigationBarTheme.backgroundColor,
        borderRadius: BorderRadius.circular(20),
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
