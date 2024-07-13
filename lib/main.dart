import 'package:flutter/material.dart';
import 'package:star_scrapper_app/classes/tabs_state.dart';
import 'package:star_scrapper_app/components/Shared/bottom_page_bar.dart';
import 'package:star_scrapper_app/pages/Scrappers_screen.dart';
import 'package:star_scrapper_app/pages/pages.dart';
import 'package:star_scrapper_app/pages/search_screen.dart';
import 'package:star_scrapper_app/pages/settings_screen.dart';
import 'package:stylish_bottom_bar/stylish_bottom_bar.dart';

void main() {
  runApp(const MyApp());
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
      home: const MyHomePage(title: 'StarsScrapper'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

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

  int _selectedIndex = 0;
  int _selectedTab = 0;

  late final List <Widget> _pages;

  _MyHomePageState() {
    _pages = [
    HomePageScreen(libraryBooks: libraryBooks),
    const ScrappersScreen(),
    const SettingsScreen(),
  ];
  }

  void _onPageChanged(int index) {
    List<Widget> newTabs = [];

    switch (index) {
      case 0:
        newTabs = const [
          Tab(text: 'All'),
          Tab(text: 'Fiction'),
          Tab(text: 'Non-fiction'),
          Tab(text: 'Fantasy'),
          Tab(text: 'Sci-fi'),
        ];
        break;
      case 1:
        newTabs = const [
          Tab(text: 'Scrappers'),
          Tab(text: 'Fonts'),
          Tab(text: 'Migrations'),
        ];
        break;
      case 2:
        newTabs = const [
          Tab(text: 'UI'),
          Tab(text: 'Library'),
          Tab(text: 'Language'),
        ];
        break;
    }

    tabsState.setTabs(newTabs);
    setState(() {
      _selectedIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final int safeIndex = _selectedIndex < _pages.length ? _selectedIndex : 0;
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
          child: BottomPageBar(
            selectedIndex: _selectedTab,
            onTabChanged: _onPageChanged,
            
          ),
        ),
      ),
      body: Center(
          child: _pages.elementAt(safeIndex),
        ),
        bottomNavigationBar: StylishBottomBar(
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
          currentIndex: _selectedIndex,
          borderRadius: BorderRadius.circular(20),
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
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
