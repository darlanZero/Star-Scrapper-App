import 'package:dynamic_tabbar/dynamic_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/pages/Scrappers_screen.dart';
import 'package:star_scrapper_app/pages/pages.dart';
import 'package:star_scrapper_app/pages/settings_screen.dart';
import 'package:stylish_bottom_bar/stylish_bottom_bar.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp()
    )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stars - A better lecture',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple.shade800),
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
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

class _MainScreenState extends State<MainScreen> {

  final List<Map<String, dynamic>> libraryBooks = [
    {
      'title': 'Naruto',
      'cover': 'https://m.media-amazon.com/images/I/91xUwI2UEVL._AC_SY741_.jpg',
      'language': 'English',
      'author': 'Masashi Kishimoto',
      'tags': ['Action', 'Fantasy'],
    },
    {
      'title': 'Solo Leveling',
      'cover': 'https://m.media-amazon.com/images/I/61FsD3uf6gL._SY445_SX342_.jpg',
      'language': 'English',
      'author': 'Hiroshi Horikoshi',
      'tags': ['Action', 'Fantasy'],
    }
    
  ];

  late final List <Widget> _pages;

  _MainScreenState() {
    _pages = [
    HomePageScreen(libraryBooks: libraryBooks),
    const ScrappersScreen(),
    const SettingsScreen(),
  ];
  }
  
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Color.fromARGB(29, 60, 16, 180),
        title: Text(widget.title, style: const TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontWeight: FontWeight.bold, shadows: <Shadow>[
          Shadow(color: Colors.black, blurRadius: 10.0),
        ])),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 25.0, fontWeight: FontWeight.bold),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: Consumer<AppState>(
            builder: (context, appState, child) {
              return appState.tabController != null ? DynamicTabBarWidget(
               dynamicTabs: <TabData>(
                [
                  TabData()
                ]
               ),
                tabs: appState.currentTabs,
                isScrollable: true,
                indicatorWeight: 5,
                indicatorPadding: const EdgeInsets.all(5),
                indicatorColor: Colors.white,
                labelColor: Colors.deepOrange,
                unselectedLabelColor: Colors.grey,
                onTabControllerUpdated: appState.tabController,
                onTap: (index) {
                  appState.setIndex(index);
                },
              ): 
              SizedBox(
                height: 0,
                width: 0,
              );
            },
          ),
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) => appState.tabController != null ? TabBarView(
          children: [_pages[appState.currentIndex]],
        ): const Center(
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Card.outlined(
                  color: Colors.deepPurple,
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        Text('Loading...', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ), 
          ),
      ),
        bottomNavigationBar: StylishBottomBar(
          currentIndex: appState.currentIndex,
          items: [
            BottomBarItem(icon: Icon(Icons.home, color: Colors.teal), title: Text('Home'), selectedColor: Colors.teal),
            BottomBarItem(icon: Icon(Icons.format_list_bulleted), title: Text('Scrappers')),
            BottomBarItem(icon: Icon(Icons.settings), title: Text('settings')),
          ],
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
          backgroundColor: Color.fromARGB(50, 60, 16, 180),
          borderRadius: BorderRadius.circular(20),
          onTap: (index) {
            appState.setIndex(index);
          },
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
