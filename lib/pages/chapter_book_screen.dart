import 'dart:io';  
import 'package:flutter/material.dart';  
import 'package:flutter/services.dart';  
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';  
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';  

class ChapterBookScreen extends StatefulWidget {  
  final String bookTitle;  
  final String chapterId;  
  final String chapterTitle;  

  final Function(String) getNextChapter;  
  final Function(String) getPreviousChapter;  
  final List<String> chapterImages;  
  const ChapterBookScreen({super.key, required this.bookTitle, required this.chapterId, required this.chapterTitle, required this.getNextChapter, required this.getPreviousChapter, required this.chapterImages});  

  @override  
  State<ChapterBookScreen> createState() => _ChapterBookScreenState();  
}  

class _ChapterBookScreenState extends State<ChapterBookScreen> {  
  bool _showControls = false;  
  int _currentPage = 0;  
  bool _isPaginatedView = false;  
  late PageController? _pageController;
  late FontProvider _fontProvider;  

  @override  
  void initState() {  
    super.initState();  
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);  
    _fontProvider = Provider.of<FontProvider>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadReadingProgress();
        _pageController = PageController(initialPage: _currentPage, viewportFraction: _isPaginatedView ? 0.75 : 1.0);
        _pageController!.addListener(() {
          setState(() {
            _currentPage = _pageController!.page?.round() ?? 0;
          });
        });
        setState(() {});
      } 
    );
     
  }  

  @override  
  void dispose() {  
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);  
    _pageController?.dispose();  
    _saveReadingProgress();  
    super.dispose();  
  }  

  Future<void> _loadReadingProgress() async {  
     final prefs = await SharedPreferences.getInstance();
     final savedPage = prefs.getInt('${widget.bookTitle}_${widget.chapterId}_page');
     if (savedPage != null) {
       setState(() {
         _currentPage = savedPage;
       });
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (_pageController!.hasClients) {
           _pageController!.jumpToPage(savedPage);
         }
       });
     }
  }  

  Future<void> _saveReadingProgress() async {  
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${widget.bookTitle}_${widget.chapterId}_page', _currentPage);  
  }  

  void _toggleControls() {  
    setState(() {  
      _showControls = !_showControls;  
    });  
  }  

  void _toggleView() {  
    setState(() {  
      _isPaginatedView = !_isPaginatedView;  
    });  
  }  

  void _showImageOptions(String imagePath) {  
    showDialog(  
      context: context,  
      builder: (BuildContext context) {  
        return AlertDialog(  
          title: const Text('Image Options'),  
          content: Column(  
            mainAxisSize: MainAxisSize.min,  
            children: [  
              ListTile(  
                leading: Icon(Icons.save_alt),  
                title: const Text('Save Image'),  
                onTap: () {  
                  _downloadImage(imagePath);  
                  Navigator.of(context).pop();  
                },  
              ),  
              ListTile(  
                leading: Icon(Icons.share),  
                title: const Text('Share Image'),  
                onTap: () {  
                  _shareImage(imagePath);  
                  Navigator.of(context).pop();  
                },  
              ),  
            ],  
          ),  
        );  
      }  
    );  
  }  

  Future<void> _downloadImage(String imagePath) async {  
    // TODO: Implement image download logic  
  }  

  Future<void> _shareImage(String imagePath) async {  
    // TODO: Implement image sharing logic  
  }  

  void _onPageChanged(int index) {  
    setState(() {  
      _currentPage = index;  
    });  
    _saveReadingProgress();  
  }  

  @override  
  Widget build(BuildContext context) {  
    return Scaffold(  
      backgroundColor: Colors.grey[900],  
      body: GestureDetector(  
        onTap: _toggleControls,  
        onLongPress: () => _showImageOptions(widget.chapterImages[_currentPage]),  
        child: Container(  
          decoration: BoxDecoration(  
            gradient: LinearGradient(  
              begin: Alignment.topCenter,  
              end: Alignment.bottomCenter,  
              colors: [  
                Colors.black,  
                Colors.grey[900]!,  
              ],  
            )  
          ),  
          child: _isPaginatedView ?   
          PageView.builder(  
            controller: _pageController ?? PageController(),  
            onPageChanged: _onPageChanged,  
            itemCount: widget.chapterImages.length,  
            itemBuilder: (context, index) {  
              return Image(  
                image: FileImage(File(widget.chapterImages[index])),  
                fit: BoxFit.contain,  
                errorBuilder: (context, error, stackTrace) {  
                  print('Error loading image: $error');  
                  return Center(child: Text('Error loading image', style: TextStyle(color: Colors.white)));  
                },  
              );  
            },  
          ): ListView.builder(  
            itemCount: widget.chapterImages.length,  
            itemBuilder: (context, index) {  
              return Image(  
                image: FileImage(File(widget.chapterImages[index])),  
                fit: BoxFit.contain,  
                errorBuilder: (context, error, stackTrace) {  
                  print('Error loading image: $error');  
                  return Center(child: Text('Error loading image', style: TextStyle(color: Colors.white)));  
                },  
              );  
            },  
          )  
        ),  
      ),  
      appBar: _showControls ? AppBar(  
        title: Text(
          '${widget.bookTitle} - Chapter ${widget.chapterTitle}',
          style: TextStyle(color: Colors.white),
        ),  
        backgroundColor: Color.fromARGB(29, 60, 16, 180),  
        leading: IconButton(  
          icon: Icon(Icons.arrow_back_ios_new_rounded),  
          onPressed: () => Navigator.of(context).pop(), 
          style: IconButton.styleFrom(
            backgroundColor: Colors.deepPurple.withOpacity(0.5),
            highlightColor: Colors.white,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ) 
        ),  
        actions: [  
          IconButton(  
            icon: Icon(Icons.open_in_new_rounded),  
            onPressed: () => {},  
            style: IconButton.styleFrom(
              backgroundColor: Colors.deepPurple.withOpacity(0.5),
              highlightColor: Colors.white,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          )  
        ],  
      ): null,  

      bottomNavigationBar: _showControls ? BottomAppBar(  
        color: Color.fromARGB(29, 60, 16, 180),  
        child: Row(  
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,  
          children: [  
            IconButton(  
              icon: Icon(Icons.auto_mode_rounded),  
              onPressed: () => widget.getPreviousChapter(widget.chapterId),  
            ),  
            Text(  
              '${_currentPage + 1}/${widget.chapterImages.length}',  
              style: TextStyle(  
                color: Colors.white,  
                fontWeight: FontWeight.bold,  
              ),  
            ),  
            IconButton(  
              icon: Icon(_isPaginatedView ? Icons.view_agenda_rounded : Icons.view_carousel_rounded),  
              onPressed: () => _toggleView(),  
            ),  
            IconButton(  
              icon: Icon(Icons.arrow_forward_ios_rounded),  
              onPressed: () {
                String nextChapterId = widget.getNextChapter(widget.chapterId);

                if (nextChapterId.isNotEmpty) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChapterBookScreen(
                        bookTitle: widget.bookTitle,
                        chapterId: nextChapterId,
                        chapterTitle: widget.chapterTitle,
                        chapterImages: widget.chapterImages,
                        getPreviousChapter: widget.getPreviousChapter,
                        getNextChapter: widget.getNextChapter,
                      )
                    )
                  );
                }
              },  
            ),  
          ],  
        ),  
      ): null,  
    );  
  }  
}