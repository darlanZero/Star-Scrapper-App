import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';  
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
  late Future<List<dynamic>> _bookFuture;  

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

  Future<List<dynamic>> _fetchBooks() async {  
    final api = widget.selectedFont.api;  
    var allBooksData = await api.getAll(currentView);
    return allBooksData;
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
    return FutureBuilder<List<dynamic>>(  
      future: _bookFuture,  
      builder: (context, snapshot) {  
        if (snapshot.connectionState == ConnectionState.waiting) {  
          return const Center(child: CircularProgressIndicator());  
        } else if (snapshot.hasError) {  
          return Center(child: Text('Error: ${snapshot.error}'));  
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {  
          return const Center(child: Text('No data available'));  
        } else {  
          List<dynamic> books = snapshot.data!;  

          return GridView.builder(  
            padding: const EdgeInsets.all(8.0),  
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(  
              crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,  
              mainAxisSpacing: 8.0,  
              crossAxisSpacing: 8.0,  
            ),  
            itemCount: books.length,  
            itemBuilder: (context, index) {  
              return _buildBookTile(books[index]);  
            },  
          );  
        }  
      },  
    );  
  }  

  Widget _buildBookTile(dynamic bookDetails) {  
    String title = widget.selectedFont.api.getTitle(bookDetails);  
    String imageUrl = widget.selectedFont.api.getCoverImageUrl(bookDetails);  
    String mangaId = widget.selectedFont.api.getBookId(bookDetails);  
 
    if (kDebugMode) {
      print('image URL: $imageUrl');
    }
    return InkWell(  
      onTap: () {  
        _navigateToBookDetails(mangaId); 
      },  
      child: GridTile(  
        footer: ClipRRect(  
          borderRadius: BorderRadius.only(  
            bottomLeft: Radius.circular(8.0),  
            bottomRight: Radius.circular(8.0),  
          ),  
          child: Container(  
            color: Colors.black.withOpacity(0.5),  
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),  
            child: Text(  
              title,  
              style: const TextStyle(  
                color: Colors.white,  
                fontWeight: FontWeight.bold,  
                fontSize: 14,  
              ),  
              maxLines: 2,  
              overflow: TextOverflow.ellipsis,  
            ),  
          ),  
        ),  
        child: ClipRRect(  
          borderRadius: BorderRadius.circular(10),  
          child: Image.network(  
            imageUrl,  
            fit: BoxFit.cover,  
            errorBuilder: (context, error, stackTrace) {  
              return Image.network('https://via.placeholder.com/150', fit: BoxFit.cover);  
            },  
          ),  
        ),  
      ),  
    );  
  } 

  void _navigateToBookDetails(String bookId) async {    
    try {  
      final bookDetails = await widget.selectedFont.api.getBookDetails(bookId);  
      if (kDebugMode) {
        print(bookDetails);
      }  
      Navigator.push(  
        context,  
        MaterialPageRoute(  
          builder: (context) => BookDetailsScreen(  
            bookDetails: bookDetails,  
          ),  
        ),  
      );  
    } catch (e) {  
      ScaffoldMessenger.of(context).showSnackBar(  
        SnackBar(content: Text('Failed to load book details: $e')),  
      );  
    }  
  }  

  void _showFilterPopup() {  
    showDialog(  
      context: context,  
      builder: (BuildContext context) {  
        return AlertDialog(  
          title: const Text('Filter'),

          content: SingleChildScrollView(

            child: Column(  
              children: const [  
                Text('Filter by:'),  
                Divider(),  
                Text('Genre'),  
                Divider(),  
                Text('Author'),  
                Divider(),  
                Text('Year'),  
                Divider(),  
                Text('Rating'),  
                Divider(),  
              ],  
            ),  
          ),  
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