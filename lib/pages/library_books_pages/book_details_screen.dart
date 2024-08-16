import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, kDebugMode;
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/library_books_pages/chapter_book_screen.dart';
import 'package:url_launcher/url_launcher.dart';  
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;  
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class BookDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bookDetails;
  final Stream<Map<String, dynamic>> Function(String) getChapter;
  const BookDetailsScreen({
    Key? key, 
    required this.bookDetails,
    required this.getChapter,
  }): super(key: key);

  @override
  _BookDetailsScreenState createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  bool _isChapterReversed = false;
  String _selectedLanguagePrefix = '';
  bool _showWebView = false;
  // ignore: unused_field
  bool _isLoadingChapter = false;

  void _toogleChapterOrder() {
    setState(() {
      _isChapterReversed = !_isChapterReversed;
    });
  }

  void _filterChaptersByLanguage(String languagePrefix) {
    setState(() {
      _selectedLanguagePrefix = languagePrefix;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    bool isDesktop = MediaQuery.of(context).size.width > 600;
    

    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      body: _showWebView ? _buildWebView(context) : _ReactiveDetailsBook(isDesktop, theme),
      floatingActionButton: FloatingActionButton(
        onPressed: _toogleChapterOrder,
        child: const Icon(Icons.swap_vert),
      ),
    );
  }

  Widget _ReactiveDetailsBook(bool isDesktop, ThemeProvider theme) {
    
    List<dynamic> chapters = List.from(widget.bookDetails['chapters'] ?? []);

    if (_isChapterReversed) {
      chapters = chapters.reversed.toList();
    }

    if (_selectedLanguagePrefix.isNotEmpty) {
      chapters = chapters
        .where((chapter) => 
          chapter['translatedLanguage']
          .toString()
          .startsWith(_selectedLanguagePrefix)
        )
        .toList();
    }

    String imageUrl = widget.bookDetails['coverImageUrl'] ?? 'https://via.placeholder.com/150';

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          iconTheme: const IconThemeData(color: Colors.blueGrey, size: 30.0, shadows: <Shadow>[
            Shadow(color: Colors.black, blurRadius: 10.0),
          ]),
          expandedHeight: isDesktop ? 500.0 : 250.0,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                                                                                                                                                                                                                                                                                                                                                                    
                ClipRRect(
                  child: Image.network(
                    imageUrl,
                    fit: isDesktop ? BoxFit.cover : BoxFit.fill,
                    color: Colors.black.withOpacity(0.5),
                    colorBlendMode:BlendMode.darken,
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.black,
                        Colors.transparent,
                      ]
                    ),
                  ),
                ), 
                Positioned(
                  top: 16.0,
                  left: 16.0,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: isDesktop ? 200 : 100,
                        height: isDesktop ? 300 : 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                ),
                if (isDesktop) Positioned(
                  top: 16.0,
                  right: 16.0,
                  child: SizedBox(
                    width: 300,
                    child: SingleChildScrollView(
                      child: Text(
                        widget.bookDetails['description'] ?? 'No description Available',
                        style: const TextStyle(
                          fontSize: 16.0,
                          color: Colors.white
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16.0,
                  left: 16.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.bookDetails['author']['name'] ?? 'No author available',
                        style: TextStyle(
                          fontSize: isDesktop ? 16.0 : 8.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        widget.bookDetails['artist']['name'] ?? 'No artist available',
                        style:  TextStyle(
                          fontSize: isDesktop ? 16.0 : 8.0,
                          color: Colors.grey
                        ),
                      )
                    ]
                  ),
                )
              ],
            ),
          ),
          actions: [
            Consumer<FontProvider>(
              builder: (context, favoritedBooksState, child) {
                final isFavorited = favoritedBooksState.isFavorited(widget.bookDetails);
                return IconButton(
                  icon: Icon(
                    isFavorited ? Icons.favorite : Icons.favorite_border,
                    color: Colors.red,
                  ),
                  onPressed: () {
                    favoritedBooksState.toggleFavorite(widget.bookDetails, context);
                    setState(() {
                      
                    });
                  }
                );
              },
            ),

            const SizedBox(width: 16.0),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () {
                setState(() {
                  _showWebView = !_showWebView;
                });
              },
            )
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: isDesktop ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  widget.bookDetails['title'] ?? 'No title available',
                  style: TextStyle(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color: theme.selectedTheme.textTheme.titleMedium?.color,
                    shadows: <Shadow>[
                      Shadow(color: Color.fromARGB(255, 87, 25, 25), blurRadius: 2.0),
                      Shadow(color: Color.fromARGB(255, 0, 0, 0), blurRadius: 2.0),
                    ]
                  ),
                ),

                const SizedBox(height: 16.0),
                if (!isDesktop)
                  Text(
                    widget.bookDetails['description'] ?? 'No description Available',
                    style: TextStyle(
                      fontSize: 16.0,
                      color: theme.selectedTheme.textTheme.displayMedium?.color
                    ),
                  ),

                Text(
                  'Chapters',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    color: theme.selectedTheme.textTheme.displayMedium?.color
                  ),
                ), 
                const SizedBox(height: 8.0),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildLanguageFilterButtons(),
                  )
                )

              ],
            ),
          ),
        ),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {

              if (index >= chapters.length) {
                return const SizedBox.shrink();
              }
                
              final chapter = chapters[index];
              return ListTile(
                title: 
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chapter ${chapter['chapter']}',
                      style: TextStyle(
                        color: theme.selectedTheme.textTheme.titleSmall?.color,
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    Text(
                      'Volume: ' + _FormatVolume(chapter['volume']),
                      style: TextStyle(
                        color: theme.selectedTheme.textTheme.titleSmall?.color,
                        fontSize: 16.0,
                      ),
                    ),

                    Text(
                      '${chapter['translatedLanguage']}',
                      style: TextStyle(
                        color: theme.selectedTheme.textTheme.titleSmall?.color,
                        fontSize: 16.0,
                      ),
                    )
                  ],
                ),
                subtitle: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${chapter['pages']} pages',
                      style: TextStyle(
                        color: theme.selectedTheme.textTheme.displayMedium?.color,
                        fontSize: 14.0,
                      ),
                    ),
                    Text(
                      chapter['uploader'] ?? 'No uploader',
                      style: TextStyle(
                        color: theme.selectedTheme.textTheme.displayMedium?.color,
                        fontSize: 14.0,
                      ),
                    ),

                    Text(
                      _formatDate(chapter['publishedAt']),
                      style: TextStyle(
                        color: theme.selectedTheme.textTheme.displayMedium?.color,
                        fontSize: 14.0,
                      ),
                    )
                  ],
                ),
                onTap: () async {
                  setState(() {
                    _isLoadingChapter = true;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: const [
                          Text('Loading chapter...'),
                          SizedBox(width: 10),
                          CircularProgressIndicator(),
                        ]
                      ),
                      duration: const Duration(minutes: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                    )
                  );

                  try {
                    await for (final chapterData in widget.getChapter(chapter['id'])) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ChapterBookScreen(
                        bookTitle: widget.bookDetails['title'],
                        chapterId: chapterData['chapterID'],
                        chapterTitle: chapter['title'],
                        fetchChapterImages: widget.getChapter,
                        chapterWebViewUrl: chapterData['chapterWebviewUrl'],
                      )));
                      break;
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to load chapter: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                      )
                    );

                    if (kDebugMode) {
                      print('Failed to load chapter: $e');
                      print(widget.getChapter(chapter['id']));
                    }
                  } finally {
                    setState(() {
                      _isLoadingChapter = false;
                    });
                  }
                }
              );
            },
            childCount: chapters.length,
          )
        )
      ],
    );
  }

  List<Widget> _buildLanguageFilterButtons() {
    List<String> languagePrefixes = widget.bookDetails['chapters']
      .map<String>((chapter) => chapter['translatedLanguage'].toString())
      .toSet()
      .toList();

    return languagePrefixes.map((prefix) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () {
            _filterChaptersByLanguage(prefix);
          },
          child: Text(prefix),
        ),
      );
    }).toList();
  }

  Widget _buildWebView(BuildContext context) {
    final String url = widget.bookDetails['mangaUrl'] ?? 'https://www.google.com';
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

            return webview_windows.Webview(
              controller
            );
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        }
      );
    } else {
      webViewContent = Center(child: Text('Platform not supported.'),);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookDetails['title']),
        backgroundColor: Color.fromARGB(29, 60, 16, 180),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _showWebView = false;
            });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              launchUrl(Uri.parse(url));
            },
          ),
        ],
      ),
    
      body: webViewContent,
    );
  }
}

Future<webview_windows.WebviewController> _initializeWebviewController() async {
  final controller = webview_windows.WebviewController();
  await controller.initialize();
  return controller;
}

String _formatDate(String? date) {
  if (date == null) {
    return 'No date';
  }

  try {
    final DateTime parsedDate = DateTime.parse(date);
    return DateFormat('dd MMM yyyy').format(parsedDate);
  } catch (e) {
    return 'Invalid date';
  }
}

String _FormatVolume (String? volume) {
  if (volume == null) {
    return 'No volume';
  }

  try {
    final int parsedVolume = int.parse(volume);
    return parsedVolume.toString();
  } catch (e) {
    return 'Invalid volume';
  }
}