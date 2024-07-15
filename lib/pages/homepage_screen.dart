
import 'package:dynamic_tabbar/dynamic_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/pages/book_details_screen.dart';

class HomePageScreen extends StatefulWidget {
  final List<Map<String, dynamic>> libraryBooks;


  const HomePageScreen({super.key, required this.libraryBooks});

  @override
  State<HomePageScreen> createState() =>  _HomePageState(libraryBooks: []);

}

class _HomePageState extends State<HomePageScreen> with TickerProviderStateMixin {
  List<TabData> tabs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.initTabController(this);
      appState.setTabs([...tabs], this);
    });
  }

  Future<void> tabDataRenderer() async {
    await Future.delayed(const Duration(seconds: 1), () {
      dynamic tabsData = [
        {
          'title': 'All',
          'items': [...widget.libraryBooks],
          'index': 1,
        },
        {
          'title': 'Fiction',
          'items': [...widget.libraryBooks],
          'index': 2,
        },
        {
          'title': 'Non-fiction',
          'items': [...widget.libraryBooks],
          'index': 3,
        },
        {
          'title': 'Fantasy',
          'items': [...widget.libraryBooks],
          'index': 4,
        },
        {
          'title': 'Sci-fi',
          'items': [...widget.libraryBooks],
          'index': 5,
        },
      ];

      for (var element in tabsData) {
        tabs.add(TabData(
          title: Tab(text: element['title'],),
          content: _buildBooksGrid(element['index']),
          index: element['index'],
        ));
      }
      setState(() {});
    });
  }
  
  _HomePageState({required this.libraryBooks}) : super();
  final List<Map<String, dynamic>> libraryBooks;

  @override
    Widget build(BuildContext context) {
      final appState = Provider.of<AppState>(context);

      if (appState.tabController == null) {
        return const Center(
            child: CircularProgressIndicator()
          );
      }
     
       return Column(  
      children: [  
        Expanded(  
          child: TabBarView(  
            children: [  
              _buildBooksGrid(appState.currentIndex),  
              const Center(child: Text('Fiction')),  
              const Center(child: Text('Non-fiction')),  
              const Center(child: Text('Fantasy')),  
              const Center(child: Text('Sci-fi')),  
            ],  
          ),  
        ),  
      ],  
    );  
  }  

  Widget _buildBooksGrid(int tabIndex) {  
    return Center(  
      child: widget.libraryBooks.isEmpty  
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
            itemCount: widget.libraryBooks.length,  
            itemBuilder: (context, index) {  
              return InkWell(  
                onTap: () {  
                  Navigator.push(  
                    context,  
                    MaterialPageRoute(  
                      builder: (context) => BookDetailsScreen(  
                        bookDetails: widget.libraryBooks[index],  
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
                        widget.libraryBooks[index]['title']!,  
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
                      widget.libraryBooks[index]['cover'] ?? 'https://via.placeholder.com/150',  
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