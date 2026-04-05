import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;  
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class ChapterBookScreen extends StatefulWidget {
  final String bookTitle;
  final String chapterId;
  final String? chapterTitle;
  final String? chapterNumber;
  final String mangaID;
  final String chapterWebViewUrl;
  final Scrapper? scrapper;

  const ChapterBookScreen({
    super.key,
    required this.bookTitle,
    required this.chapterId,
    this.chapterTitle,
    required this.mangaID,
    this.chapterNumber,
    this.chapterWebViewUrl = '',
    this.scrapper,
  });

  @override
  State<ChapterBookScreen> createState() => _ChapterBookScreenState();
}

class _ChapterBookScreenState extends State<ChapterBookScreen> {
  bool _showControls = false;
  int _currentPage = 0;
  bool _isPaginatedView = false;
  List<String> _chapterImages = [];
  final List<GlobalKey> _imageItemKeys = [];
  StreamSubscription<Map<String, dynamic>>? _chapterImagesSubscription;
  bool _showWebView = false;
  int? _pendingRestorePage;
  bool _recalcScheduled = false;

  late PageController? _pageController;
  late ScrollController _scrollController;
  // ignore: unused_field
  late FontProvider _fontProvider;
  late Scrapper _activeScrapper;
  late String _chapterWebViewUrl;

  @override
  void initState() {
    super.initState();
    _chapterWebViewUrl = widget.chapterWebViewUrl;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _fontProvider = Provider.of<FontProvider>(context, listen: false);
    _activeScrapper = widget.scrapper ?? _fontProvider.selectedFontApi;
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadReadingProgress();
      await _loadChapterImages();
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
    _chapterImagesSubscription = _activeScrapper.getChapter(widget.chapterId, widget.mangaID).listen(
      (imageData) {
        if (imageData['type'] == 'image') {
          setState(() {
            _chapterImages.add(imageData['imagePath']);
            _imageItemKeys.add(GlobalKey());
          });
          _tryRestoreScrollPosition();
        } else if (imageData['type'] == 'info') {
          _chapterWebViewUrl = imageData['chapterWebviewUrl'];
        }
      },
      onDone: () {
        // Se o scrapper não forneceu imagens (ex.: conteúdo protegido por DRM),
        // abre automaticamente a WebView com a URL do capítulo.
        if (_chapterImages.isEmpty && _chapterWebViewUrl.isNotEmpty) {
          setState(() {
            _showWebView = true;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _saveReadingProgress();
    _scrollController.dispose();
    _pageController?.dispose();
    _chapterImagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getInt('reading_progress_${widget.chapterId}') ?? 0;
    _pendingRestorePage = savedPage;
    setState(() {
      _currentPage = savedPage;
    });
  }

  Future<void> _saveReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('reading_progress_${widget.chapterId}', _currentPage);
  }

  void _onScroll() {
    _scheduleScrollProgressRecalc();

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

  void _scheduleScrollProgressRecalc() {
    if (_isPaginatedView || _recalcScheduled) return;
    _recalcScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcScheduled = false;
      _recalculateCurrentPageFromViewport();
    });
  }

  void _recalculateCurrentPageFromViewport() {
    if (!mounted || _chapterImages.isEmpty || _isPaginatedView) return;

    final viewportHeight = MediaQuery.of(context).size.height;
    final probeY = viewportHeight * 0.35;
    int bestIndex = _currentPage.clamp(0, _chapterImages.length - 1).toInt();
    double bestDistance = double.infinity;

    for (var i = 0; i < _imageItemKeys.length; i++) {
      final ctx = _imageItemKeys[i].currentContext;
      if (ctx == null) continue;
      final render = ctx.findRenderObject();
      if (render is! RenderBox) continue;

      final top = render.localToGlobal(Offset.zero).dy;
      final center = top + (render.size.height / 2);
      final distance = (center - probeY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex != _currentPage) {
      setState(() {
        _currentPage = bestIndex;
      });
    }
  }

  void _tryRestoreScrollPosition() {
    if (_isPaginatedView || _pendingRestorePage == null) return;
    final target = _pendingRestorePage!;
    if (target < 0 || target >= _imageItemKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingRestorePage == null) return;
      final targetContext = _imageItemKeys[target].currentContext;
      if (targetContext == null) return;

      Scrollable.ensureVisible(
        targetContext,
        duration: Duration.zero,
        alignment: 0,
      );
      _pendingRestorePage = null;
    });
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

  Widget _buildWebView(BuildContext context) {
    final String url = _chapterWebViewUrl.isNotEmpty ? _chapterWebViewUrl : 'https://www.google.com';

    Widget webViewContent;

    if (kIsWeb) {
      return Center(child: Text('Web view not supported on this platform.'),);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final controller = flutter_webview.WebViewController();
      controller.setJavaScriptMode(flutter_webview.JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0x00000000));
      controller.setNavigationDelegate(
        flutter_webview.NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onWebResourceError: (flutter_webview.WebResourceError error) {},
          onNavigationRequest: (flutter_webview.NavigationRequest request) {
            return flutter_webview.NavigationDecision.navigate;
          },
        )
      );

      controller.loadRequest(Uri.parse(url));

      webViewContent = flutter_webview.WebViewWidget(
        controller: controller,
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      webViewContent = FutureBuilder<webview_windows.WebviewController>(
        future: _initializeWebviewController(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final controller = snapshot.data!;
            controller.loadUrl(url);
            return webview_windows.Webview(controller);
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            return const CircularProgressIndicator();
          }
        }
      );
    } else {
      webViewContent = const Text('Unsupported platform');
    }

    final displayTitle = widget.chapterTitle ?? widget.chapterNumber ?? 'Chapter';
    return Scaffold(
      
      appBar: AppBar(
        title: Text(displayTitle),
        backgroundColor: Color.fromARGB(178, 60, 16, 180),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _showWebView = false;
            });
          },
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
            onPressed: () {
              launchUrl(Uri.parse(url));
            },
          ),
        ],
      ),
      body: webViewContent,
    );
  }

  Future<webview_windows.WebviewController> _initializeWebviewController() async {
    final controller = webview_windows.WebviewController();
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.chapterTitle ?? widget.chapterNumber ?? 'Chapter';

    return Scaffold(
      appBar:_showControls ? AppBar(
        title: Text(
          '${widget.bookTitle} - $displayTitle',
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
            onPressed: () => {
              setState(() {
                _showWebView = !_showWebView;
              })
            },  
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
      body: _showWebView ? _buildWebView(context) : GestureDetector(
        
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        onLongPress: () {
          if (_chapterImages.isEmpty) return;
          final safeIndex = _currentPage.clamp(0, _chapterImages.length - 1).toInt();
          _showImageOptions(_chapterImages[safeIndex]);
        },
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
              return Container(
                key: _imageItemKeys[index],
                child: Image.file(
                  File(_chapterImages[index]),
                  fit: BoxFit.contain,
                ),
              );
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
                    onPressed: () async {
                      final previousChapterStream = _activeScrapper.retrieveLastChapter(widget.chapterId, widget.mangaID);
                      bool hasPreviousChapter = false;

                     await for (var previousChapterData in previousChapterStream) {
                        if (previousChapterData['type'] == 'image') {
                          hasPreviousChapter = true;
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ChapterBookScreen(
                            bookTitle: widget.bookTitle,
                            chapterId: previousChapterData['chapterID'],
                            mangaID: widget.mangaID,
                            chapterTitle: previousChapterData['title'],
                            chapterNumber: previousChapterData['chapter'],
                            chapterWebViewUrl: previousChapterData['chapterWebviewUrl'],
                            scrapper: _activeScrapper,
                          )));
                          break;
                        } else if (previousChapterData['type'] == 'error') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(previousChapterData['message']),
                            ),
                          );
                          break;
                        }
                      }
                    }
                      
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
                      final nextChapterStream = _activeScrapper.retrieveNextChapter(widget.chapterId, widget.mangaID);
                      bool hasNextChapter = false;

                     await for (var nextChapterData in nextChapterStream) {
                        if (nextChapterData['type'] == 'image') {
                          hasNextChapter = true;
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ChapterBookScreen(
                            bookTitle: widget.bookTitle,
                            chapterId: nextChapterData['chapterID'],
                            mangaID: widget.mangaID,
                            chapterTitle: nextChapterData['title'],
                            chapterNumber: nextChapterData['chapter'],
                            chapterWebViewUrl: nextChapterData['chapterWebviewUrl'],
                            scrapper: _activeScrapper,
                          )));
                          break;
                        } else if (nextChapterData['type'] == 'error') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(nextChapterData['message']),
                            ),
                          );
                          break;
                        }
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
