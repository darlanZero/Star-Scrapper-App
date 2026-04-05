import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

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
      final provider = Provider.of<FontProvider>(context, listen: false);
      provider.loadSelectedChapterId();
      provider.loadLastReadedChapterId();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FontProvider>(
      builder: (context, fontProvider, _) {
        final readedBooks = fontProvider.readBooks.reversed.toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return GridView.builder(
                padding: const EdgeInsets.all(8.0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8.0,
                  crossAxisSpacing: 8.0,
                ),
                itemCount: readedBooks.length,
                itemBuilder: (context, index) {
                  final book = readedBooks[index];
                  final scrapper = fontProvider.findScrapperForBook(book) ?? fontProvider.selectedFontApi;
                  final bookId = book['id'] as String?;
                  final lastChapter = bookId != null
                      ? fontProvider.lastReadedChapterId[bookId]
                      : null;
                  final chapterTitle = lastChapter?['title'] ?? 'N/A';
                  final coverUrl = scrapper.getCoverImageUrl(book);
                  final imageHeaders = scrapper.imageHeaders;

                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => BookDetailsScreen(bookDetails: book, scrapper: scrapper),
                    )),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: coverUrl,
                          httpHeaders: imageHeaders,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorWidget: (context, _, __) => Container(
                            color: Colors.grey.shade900,
                            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                          ),
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
                            child: Text(
                              'Cap. $chapterTitle',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            } else {
              return ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: readedBooks.length,
                itemBuilder: (context, index) {
                  final book = readedBooks[index];
                  final scrapper = fontProvider.findScrapperForBook(book) ?? fontProvider.selectedFontApi;
                  final bookId = book['id'] as String?;
                  final lastChapter = bookId != null
                      ? fontProvider.lastReadedChapterId[bookId]
                      : null;
                  final chapterTitle = lastChapter?['title'] ?? 'N/A';
                  final selectedChapters = bookId != null
                      ? (fontProvider.selectedChapterIds[bookId] ?? [])
                      : <Map<String, String>>[];
                  final coverUrl = scrapper.getCoverImageUrl(book);
                  final imageHeaders = scrapper.imageHeaders;

                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => BookDetailsScreen(bookDetails: book, scrapper: scrapper),
                    )),
                    child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: coverUrl,
                          httpHeaders: imageHeaders,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 200,
                          color: Colors.black.withOpacity(0.5),
                          colorBlendMode: BlendMode.darken,
                          errorWidget: (context, _, __) => Container(
                            color: Colors.grey.shade900,
                            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            httpHeaders: imageHeaders,
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                            errorWidget: (context, _, __) => Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.broken_image_outlined, size: 16, color: Colors.grey),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 70,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scrapper.getTitle(book),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Cap. $chapterTitle',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Wrap(
                            spacing: 8.0,
                            children: selectedChapters.map((chapter) {
                              final title = chapter['title'] ?? 'N/A';
                              return Chip(label: Text('Chap. $title'));
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),  // fecha Card
                  );  // fecha InkWell
                },
              );
            }
          },
        );
      },
    );
  }
}
