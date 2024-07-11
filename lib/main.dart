import 'package:flutter/material.dart';
import 'package:star_scrapper_app/pages/pages.dart';
import 'package:star_scrapper_app/pages/search_screen.dart';

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
      home: const MyHomePage(title: 'Library'),
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: Text(widget.title, style: const TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontWeight: FontWeight.bold, shadows: <Shadow>[
          Shadow(color: Colors.black, blurRadius: 10.0),
        ])),
      ),
      body: Center( 
        child: libraryBooks.isEmpty ? Card(
          color: Colors.deepPurple.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            
            child: Column(
              mainAxisSize: MainAxisSize.min,
              
              children: const [
                Icon(Icons.library_books, size: 50, color: Colors.grey),
                Text('Your library is empty, try adding some books!', style: TextStyle(color: Colors.grey)),
                
              ],
            ),
          ),
        ) 
        : 
        GridView.builder(
          padding: const EdgeInsets.all(8.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
            mainAxisSpacing: 8.0,
            crossAxisSpacing: 8.0,
          ),
          itemCount: libraryBooks.length,
          itemBuilder: (context, index) {
            return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookDetailsScreen(
                        bookDetails: libraryBooks[index],
                      ),
                    ),
                  );
                },

                child: GridTile(
                  footer: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8.0),
                      bottomRight: Radius.circular(8.0),
                    ),
                    child:Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Text(
                        libraryBooks[index]['title']!,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(1, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      )
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10), // Aplica o raio de borda aqui
                    child: Image.network(
                      libraryBooks[index]['cover']!,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              );
            
          }
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
