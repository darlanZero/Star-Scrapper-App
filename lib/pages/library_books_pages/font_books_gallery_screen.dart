import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';  
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';  
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';  

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
  late ScrollController _scrollController;
  bool _isLoadingMore = false; 
  List<dynamic> allBooksData = [];  


  @override  
  void initState() {  
    super.initState();  
    _scrollController = ScrollController();  
    _scrollController.addListener(_onScroll);  
    currentView = widget.initialView;  
    _loadBooks();  
  }  

  void _loadBooks() {  
    setState(() {  
      _bookFuture = _fetchBooks();  
    });  
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent && !_isLoadingMore) {
      _loadMoreBooks();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }  

  Future<List<dynamic>> _fetchBooks() async {  
    final api = widget.selectedFont.api;  
    var booksData = await api.getAll(currentView);
    setState(() {
      allBooksData = booksData;
    });

    return booksData;
  }

  Future<void> _loadMoreBooks() async {
    setState(() {
      _isLoadingMore = true;
    });

    final api = widget.selectedFont.api;
    var moreBooksData = await api.loadMore(currentView);

    setState(() {
      _isLoadingMore = false;
      allBooksData = List.from(allBooksData)..addAll(moreBooksData);
    });
  }
  @override  
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    
    return Scaffold(  
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,  
      appBar: AppBar(  
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,  
        title: Text(widget.selectedFont.name, style: TextStyle(color: theme.selectedTheme.textTheme.titleMedium?.color, fontWeight: FontWeight.bold, shadows: <Shadow>[  
          Shadow(color: Colors.black, blurRadius: 10.0),  
        ])),  
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),  
        centerTitle: true,  
        
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
                _buildButton('Popular', Icons.trending_up_outlined, theme),  
                _buildButton('Recent', Icons.new_releases_outlined, theme),  
                OutlinedButton(  
                  onPressed: () {  
                    _showFilterPopup();  
                  },  
                  style: OutlinedButton.styleFrom(  
                    shape: RoundedRectangleBorder(  
                      borderRadius: BorderRadius.circular(10.0),  
                    ),  
                    
                  ),  
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center,  
                    mainAxisAlignment: MainAxisAlignment.center,  
                    mainAxisSize: MainAxisSize.min,children: [  
                    Icon(Icons.filter_list, color: theme.selectedTheme.textTheme.displayMedium?.color,),  
                    Text('filter', style: TextStyle(color: theme.selectedTheme.textTheme.displayMedium?.color),)  
                    ],  
                  ),  
                ),  
              ],  
            )  
          )  
        ),  
      ),  
      body: _dynamicBooksGrid(theme),  
    );  
  }  

  Widget _buildButton(String text, IconData icon, ThemeProvider theme) {  
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
        Icon(icon, color: theme.selectedTheme.textTheme.displayMedium?.color,),  
        Text(text, style: TextStyle(color: theme.selectedTheme.textTheme.displayMedium?.color,),)  
      ],),  
    );  
  }  

   Widget _dynamicBooksGrid(ThemeProvider theme) {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);  
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
            

           return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification scrollInfo) {
              if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent && !_isLoadingMore) {
                _loadMoreBooks();
              }
              return false;
            },
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final isFavorited = fontProvider.isFavorited(books[index]);
                return _buildBookTile(books[index], theme, isFavorited);
              },
            ),
          );  
        }  
      },  
    );  
  }  

  Widget _buildBookTile(dynamic bookDetails, ThemeProvider theme, bool isFavorited) {
    String title = widget.selectedFont.api.getTitle(bookDetails);
    String imageUrl = widget.selectedFont.api.getCoverImageUrl(bookDetails);
    String mangaId = widget.selectedFont.api.getBookId(bookDetails);
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    bool isBookFavorited = fontProvider.isFavorited(bookDetails);

    if (kDebugMode) {
      print('image URL: $imageUrl');
    }
    return InkWell(
      onTap: () {
        _navigateToBookDetails(mangaId);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.0),
          border: isBookFavorited ? Border.all(color: theme.selectedTheme.primaryColor.withAlpha(150), width: 2.0) : null,
        ),
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
            child:Stack(
              children: [
                Image.network(

                  imageUrl,
                  color: isBookFavorited ? Colors.black.withOpacity(0.5) : null,
                  colorBlendMode: isBookFavorited ? BlendMode.srcOver : BlendMode.dstATop,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.network('https://via.placeholder.com/150', fit: BoxFit.cover);
                  },
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width,
                ),
                if (isBookFavorited) 
                  Positioned(
                    top: 10,
                    right: 10,
                    child: const Icon(Icons.favorite, color: Colors.red, size: 24,),
                  )
                
              ],
            ) 
          ),
        ),
      ), 
    );
  } 

  void _navigateToBookDetails(String bookId) async {    

    final loadingSnackBar = SnackBar(
      content: Row(
        children: const [
          Text('Loading book details...'),
          SizedBox(width: 10),
          CircularProgressIndicator(),
        ]
      ),
      duration: const Duration(minutes: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
    );

    ScaffoldMessenger.of(context).showSnackBar(loadingSnackBar);

    try {  
      final bookDetails = await widget.selectedFont.api.getBookDetails(bookId);  
      if (kDebugMode) {
        print(bookDetails);
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.push(  
        context,  
        MaterialPageRoute(  
          builder: (context) => BookDetailsScreen(  
            bookDetails: bookDetails,  
            getChapter: widget.selectedFont.api.getChapter,
          ),  
        ),  
      ).then((_) {
        setState(() {
          
        });
      });  
    } catch (e) {  
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(  
        SnackBar(content: Text('Failed to load book details: $e'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
          
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