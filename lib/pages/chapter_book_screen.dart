import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class ChapterBookScreen extends StatefulWidget {
  final String bookTitle;
  final String chapterId;
  final String chapterTitle;

  final Future<Map<String, dynamic>> Function(String) fetchChapterImages; // Function to fetch chapter images

  const ChapterBookScreen({
    super.key,
    required this.bookTitle,
    required this.chapterId,
    required this.chapterTitle,
    required this.fetchChapterImages,
  });

  @override
  State<ChapterBookScreen> createState() => _ChapterBookScreenState();
}

class _ChapterBookScreenState extends State<ChapterBookScreen> {
  bool _showControls = false;
  int _currentPage = 0;
  bool _isPaginatedView = false;
  List<double> _pageHeights = [];
  List<String> _chapterImages = [];

  late PageController? _pageController;
  late ScrollController _scrollController;
  late FontProvider _fontProvider;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _fontProvider = Provider.of<FontProvider>(context, listen: false);
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadReadingProgress();
      await _loadChapterImages();
      await _calculatePageHeights();
      _scrollController.addListener(() {
        _onScroll();
      });
      _pageController = PageController(
          initialPage: _currentPage,
          viewportFraction: _isPaginatedView ? 0.75 : 1.0);
      _pageController!.addListener(() {
        setState(() {
          _currentPage = _pageController!.page?.round() ?? 0;
        });
      });
      setState(() {});
    });
  }

  Future<void> _loadChapterImages() async {
    final chapterData = await widget.fetchChapterImages(widget.chapterId);
    setState(() {
      _chapterImages = List<String>.from(chapterData['imagePaths']);
    });
  }

  Future<void> _calculatePageHeights() async {
    for (String imagePath in _chapterImages) {
      final image = await _getImageSize(imagePath);
      _pageHeights.add(image.height.toDouble());
    }
  }

  Future<Size> _getImageSize(String path) async {
    final Completer<Size> completer = Completer();
    final image = Image.file(File(path));
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        completer.complete(Size(
            info.image.width.toDouble(), info.image.height.toDouble()));
      }),
    );
    return completer.future;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _loadReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getInt('reading_progress_${widget.chapterId}') ?? 0;
    setState(() {
      _currentPage = savedPage;
    });
  }

  Future<void> _saveReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('reading_progress_${widget.chapterId}', _currentPage);
  }

  void _onScroll() {
    double scrollOffset = _scrollController.offset;
    double cumulativeHeight = 0.0;

    for (int i = 0; i < _pageHeights.length; i++) {
      cumulativeHeight += _pageHeights[i];
      if (scrollOffset < cumulativeHeight) {
        setState(() {
          _currentPage = i;
        });
        break;
      }
    }

    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse && _showControls) {
      setState(() {
        _showControls = false;
      });
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward && !_showControls) {
      setState(() {
        _showControls = true;
      });
    }
  }

  void _toggleView() {
    setState(() {
      _isPaginatedView = !_isPaginatedView;
      _pageController = PageController(
          initialPage: _currentPage,
          viewportFraction: _isPaginatedView ? 1.0 : 1.0);
    });
  }

  Future<void> _downloadImage(String imagePath) async {  
    // TODO: Implement image download logic  
  }  

  Future<void> _shareImage(String imagePath) async {  
    // TODO: Implement image sharing logic  
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:_showControls ? AppBar(
        title: Text(
          '${widget.bookTitle} - ${widget.chapterTitle}',
          style: const TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontWeight: FontWeight.bold)
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        backgroundColor: Color.fromARGB(158, 60, 16, 180),
        elevation: 0,
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
      body: GestureDetector(
        
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        onLongPress: () => _showImageOptions(_chapterImages[_currentPage]),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black,
                Colors.grey[900]!,
              ],
            ),
          ),
          child: _isPaginatedView ? PageView.builder(
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },

            scrollBehavior: ScrollBehavior(
              
            ).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            controller: _pageController,
            itemCount: _chapterImages.length,
            itemBuilder: (context, index) {
              return Image.file(File(_chapterImages[index]));
            },
          ) :
          ListView.builder(
            controller: _scrollController,
            itemCount: _chapterImages.length,
            itemBuilder: (context, index) {
              return Image.file(File(_chapterImages[index]));
            },
          ),
        ),
        
      ),
      floatingActionButton: _showControls
          ? FloatingActionButton(
              onPressed: () => _saveReadingProgress(),
              child: Icon(Icons.save),
            )
          : null,
      bottomNavigationBar: _showControls
          ? BottomAppBar(
              color: Color.fromARGB(174, 53, 13, 180),
              shape: const CircularNotchedRectangle(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.auto_mode_rounded),
                    onPressed: () =>
                        widget.fetchChapterImages(widget.chapterId), // Use function to get previous chapter
                  ),
                  Text(
                    '${_currentPage + 1}/${_chapterImages.length}',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isPaginatedView
                        ? Icons.view_agenda_rounded
                        : Icons.view_carousel_rounded),
                    onPressed: () => _toggleView(),
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_forward_ios_rounded),
                    onPressed: () async {
                      final nextChapterData =
                          await widget.fetchChapterImages(widget.chapterId);
                      if (nextChapterData.isNotEmpty) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChapterBookScreen(
                              bookTitle: widget.bookTitle,
                              chapterId: nextChapterData['chapterID'],
                              chapterTitle: widget.chapterTitle,
                              fetchChapterImages: widget.fetchChapterImages,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No more chapters available'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
