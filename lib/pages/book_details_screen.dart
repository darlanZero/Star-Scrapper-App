import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BookDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bookDetails;
  final Function getChapter;
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

  void _toogleChapterOrder() {
    setState(() {
      _isChapterReversed = !_isChapterReversed;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 600;
    

    return Scaffold(
      backgroundColor: Colors.black,
      body: _ReactiveDetailsBook(isDesktop),
      floatingActionButton: FloatingActionButton(
        onPressed: _toogleChapterOrder,
        child: const Icon(Icons.swap_vert),
      ),
    );
  }

  Widget _ReactiveDetailsBook(bool isDesktop) {
    
    List<dynamic> chapters = List.from(widget.bookDetails['chapters'] ?? []);

    if (_isChapterReversed) {
      chapters = chapters.reversed.toList();
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
                          widget.bookDetails['author'] ?? 'No author available',
                          style: const TextStyle(
                            fontSize: 8.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey
                          ),
                        ),
                        Text(
                          widget.bookDetails['artist'] ?? 'No artist available',
                          style: const TextStyle(
                            fontSize: 8.0,
                            color: Colors.grey
                          ),
                        )
                      ]
                    ),
                  )
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                if (index == 0) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (isDesktop) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      widget.bookDetails['title'] ?? 'No title available',
                                      style: const TextStyle(
                                        fontSize: 24.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey
                                      ),
                                    ),
                                    
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: SizedBox(),
                            )
                          ],
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.bookDetails['title'] ?? 'No title available',
                                style: const TextStyle(
                                  fontSize: 24.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.bookDetails['description'] ?? 'No description available',
                                style: const TextStyle(
                                  fontSize: 16.0,
                                  color: Colors.grey
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  );
                } 
                final chapter = chapters[index - 1];
                return ListTile(
                  title: 
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Chapter ${chapter['chapter']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      Text(
                        'Volume: ' + _FormatVolume(chapter['volume']),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                        ),
                      ),

                      Text(
                        '${chapter['translatedLanguage']}',
                        style: const TextStyle(
                          color: Colors.white,
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
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14.0,
                        ),
                      ),
                      Text(
                        chapter['uploader'] ?? 'No uploader',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14.0,
                        ),
                      ),

                      Text(
                        _formatDate(chapter['publishedAt']),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14.0,
                        ),
                      )
                    ],
                  ),
                  onTap: () {
                    widget.getChapter(chapter['id']);
                  }
                );
              },
              childCount: chapters.length + 1,
            )
          )
        ],
      );
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
}