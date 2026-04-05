import 'dart:ui';
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
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
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color.fromARGB(200, 0, 0, 0)],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: Text(
                                    'Cap. $chapterTitle',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromARGB(100, 0, 0, 0),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
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
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color.fromARGB(50, 106, 65, 255),
                                    Color.fromARGB(160, 0, 0, 0),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 14,
                              left: 14,
                              child: CachedNetworkImage(
                                imageUrl: coverUrl,
                                httpHeaders: imageHeaders,
                                fit: BoxFit.cover,
                                width: 56,
                                height: 76,
                                errorWidget: (context, _, __) => Container(
                                  color: Colors.grey.shade900,
                                  child: const Icon(Icons.broken_image_outlined, size: 16, color: Colors.grey),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 14,
                              left: 82,
                              right: 14,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    scrapper.getTitle(book),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.black.withOpacity(0.35),
                                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                                    ),
                                    child: Text(
                                      'Last: Cap. $chapterTitle',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
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
                                runSpacing: 8.0,
                                children: selectedChapters.map((chapter) {
                                  final title = chapter['title'] ?? 'N/A';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Chap. $title',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }
          },
        );
      },
    );
  }
}
