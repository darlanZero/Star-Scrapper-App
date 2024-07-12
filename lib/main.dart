import 'package:flutter/material.dart';
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

  late final List <Widget> _pages;

  _MyHomePageState() {
    _pages = [
    HomePageScreen(libraryBooks: libraryBooks),
    const ScrappersScreen(),
    const SettingsScreen(),
  ];
  }
  
  @override
  Widget build(BuildContext context) {
    final int safeIndex = _selectedIndex < _pages.length ? _selectedIndex : 0;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: Text(widget.title, style: const TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontWeight: FontWeight.bold, shadows: <Shadow>[
          Shadow(color: Colors.black, blurRadius: 10.0),
        ])),
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
            opacity: 0.2,
            inkColor: Colors.black,
            iconSize: 30,
            barAnimation: BarAnimation.fade,
            iconStyle: IconStyle.animated,
            padding: EdgeInsets.all(10),
          ),
          hasNotch: true,
          notchStyle: NotchStyle.square,
          backgroundColor: Theme.of(context).colorScheme.primary,
          currentIndex: _selectedIndex,
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
