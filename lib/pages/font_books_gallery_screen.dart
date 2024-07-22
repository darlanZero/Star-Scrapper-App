import 'package:flutter/material.dart';
import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';
import 'package:star_scrapper_app/pages/book_details_screen.dart';

class FontBooksGalleryScreen extends StatefulWidget {
  final String initialView;  
  final Fonte selectedFont;  
  const FontBooksGalleryScreen({
      Key? key,
      required this.initialView,
      required this.selectedFont
    }) : super(key: key);

  @override
  State<FontBooksGalleryScreen> createState() => _FontBooksGalleryScreenState();
}

class _FontBooksGalleryScreenState extends State<FontBooksGalleryScreen> {
  late String currentView;
  late Future<dynamic> _bookFuture;

  @override
  void initState() {
    super.initState();
    currentView = widget.initialView;
    _loadBooks();
  }

  void _loadBooks() {
    setState(() {
      _bookFuture = _fetchBooks();
    });
  }

  Future<dynamic> _fetchBooks() async {
    final api = widget.selectedFont.api as MangadexScrapper;
    return api.getAll(currentView);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Color.fromARGB(29, 60, 16, 180),
        title: Text(widget.selectedFont.name, style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontWeight: FontWeight.bold, shadows: <Shadow>[
          Shadow(color: Colors.black, blurRadius: 10.0),
        ])),
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildButton('Popular', Icons.trending_up_outlined),
                _buildButton('Recent', Icons.new_releases_outlined),
                OutlinedButton(
                  onPressed: () {
                    _showFilterPopup();
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,children: [
                    Icon(Icons.filter_list, color: Color.fromARGB(255, 224, 224, 224),),
                    Text('filter', style: TextStyle(color: Color.fromARGB(255, 224, 224, 224)),)
                    ],
                  ),
                ),
              ],
            )
          )
        ),
      ),

      body: _dynamicBooksGrid(),
    );
  }

  Widget _buildButton(String text, IconData icon) {
    bool isSelected = currentView.toLowerCase() == text.toLowerCase();
    return OutlinedButton(
      onPressed: () {
        setState(() {
          currentView = text;
          _loadBooks();
        });
      },
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        backgroundColor: isSelected ? Colors.deepPurple.withOpacity(0.3) : Colors.transparent,
      ),
      child: Row(children: [
        Icon(icon, color: Color.fromARGB(255, 224, 224, 224),),
        Text(text, style: TextStyle(color: Color.fromARGB(255, 224, 224, 224)),)
      ],),
    );
  }

  Widget _dynamicBooksGrid() {
    return FutureBuilder<dynamic>(
      future: _bookFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData) {
          return const Center(child: Text('No data available'));
        } else {
          List<dynamic> books = snapshot.data['data'];

          return GridView.builder(
            padding: const EdgeInsets.all(8.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              const String _baseUrl = 'https://mangadex.org';
              var book = books[index];
              var bookId = book['id'];
              var attributes = book['attributes'];
              var titleLanguageKey = attributes['title'].keys.first;
              var title = attributes['title'][titleLanguageKey];
              var coverId = book['relationships'].firstWhere((relation) => relation['type'] == 'cover_art', orElse: () => null)?['id'];
              var cover = coverId != null ? '$_baseUrl/covers/$bookId/$coverId.png' : 'https://via.placeholder.com/150';

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookDetailsScreen(
                       bookDetails: book,
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
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Text(
                        title ?? 'No title',
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
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      cover,
                      fit: BoxFit.cover
                    )
                  ),
                ),
              );
            },
          );
        }
      },
    );
  }

  void _showFilterPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter'),
          content: const Text('Filter content'),
          scrollable: true,
          titleTextStyle: const TextStyle(color: Color.fromARGB(255, 224, 224, 224)),
          contentTextStyle: const TextStyle(color: Color.fromARGB(255, 224, 224, 224)),
          backgroundColor: Color.fromARGB(255, 26, 17, 51),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10.0)),
          ),
          actionsPadding: const EdgeInsets.all(16.0),

          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Apply'),
            ),
            
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}