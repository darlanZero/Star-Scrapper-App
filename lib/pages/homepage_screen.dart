import 'package:flutter/material.dart';
import 'package:star_scrapper_app/pages/book_details_screen.dart';

class HomePageScreen extends StatelessWidget {
  final List<Map<String, dynamic>> libraryBooks;

  const HomePageScreen({Key? key, required this.libraryBooks}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: libraryBooks.isEmpty
          ? Card(
              color: Colors.deepPurple.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.library_books, size: 50, color: Colors.grey),
                    Text('Your library is empty, try adding some books!', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
              ),
              itemCount: libraryBooks.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookDetailsScreen(
                          bookDetails: libraryBooks[index],
                        ),
                      ),
                    );
                  },
                  child: GridTile(
                    footer: ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(8.0),
                        bottomRight: Radius.circular(8.0),
                      ),
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Text(
                          libraryBooks[index]['title']!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                offset: Offset(1, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        libraryBooks[index]['cover']!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}