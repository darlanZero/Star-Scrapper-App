import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class LibraryBooksHistory extends StatefulWidget {
  const LibraryBooksHistory({super.key});

  @override
  State<LibraryBooksHistory> createState() => _LibraryBooksHistoryState();
}

class _LibraryBooksHistoryState extends State<LibraryBooksHistory> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FontProvider>(context, listen: false).readBooks;
      Provider.of<FontProvider>(context, listen: false).loadSelectedChapterId();
      Provider.of<FontProvider>(context, listen: false).loadLastReadedChapterId();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final readedBooks = fontProvider.readBooks.reversed.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return GridView.builder(
            padding: const EdgeInsets.all(8.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
            ),
            itemCount: readedBooks.length,
            itemBuilder: (context, index) {
              final book = readedBooks[index];
              final bookId = book['id'];

              return Stack(
                children: [
                  Image.network(
                    fontProvider.selectedFontApi.getCoverImageUrl(book),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FutureBuilder<Map<String, String>?>(
                        future: fontProvider.loadLastReadedChapterId().then((map) => map[bookId]),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          } else if (snapshot.hasError) {
                            return Text('Erro: ${snapshot.error}');
                          } else {
                            final lastReadedChapter = snapshot.data ?? 'N/A';
                            return Text(
                              'Chap. $lastReadedChapter',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  )
                ],
              );
            },
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: readedBooks.length,
            itemBuilder: (context, index) {
              final book = readedBooks[index];
              final bookId = book['id'];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: Stack(
                  children: [
                    Image.network(
                      fontProvider.selectedFontApi.getCoverImageUrl(book),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 200,
                      color: Colors.black.withOpacity(0.5),
                      colorBlendMode: BlendMode.darken,
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Image.network(
                        fontProvider.selectedFontApi.getCoverImageUrl(book),
                        fit: BoxFit.cover,
                        width: 50,
                        height: 50,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 70,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fontProvider.selectedFontApi.getTitle(book),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          FutureBuilder<Map<String, String>?>(
                            future: fontProvider.loadLastReadedChapterId().then((map) => map[bookId]),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const CircularProgressIndicator();
                              } else if (snapshot.hasError) {
                                return Text('Erro: ${snapshot.error}');
                              } else {
                                final lastReadedChapter = snapshot.data;
                                if (lastReadedChapter != null) {
                                  final chapterTitle = lastReadedChapter['title'] ?? 'N/A';
                                  return Text(
                                    'Cap. $chapterTitle',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  );
                                } else {
                                  return Text(
                                    'Cap. N/A',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    FutureBuilder<List<Map<String, String>>>(
                      future: fontProvider.loadSelectedChapterId().then((map) => map[bookId] ?? []),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const CircularProgressIndicator();
                        } else if (snapshot.hasError) {
                          return Text('Erro: ${snapshot.error}');
                        } else {
                          final selectedChapters = snapshot.data ?? [];
                          return Positioned(
                            bottom: 10,
                            left: 10,
                            right: 10,
                            child: Wrap(
                              spacing: 8.0,
                              children: selectedChapters.map((chapter) {
                                final chapterTitle = chapter['title'] ?? 'N/A';
                                return Chip(
                                  label: Text('Chap. $chapterTitle'),
                                );
                              }).toList(),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        }
      },
    );
  }
}
