import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/pages/book_details_screen.dart';

class HomePageScreen extends StatefulWidget {
  final List<Map<String, dynamic>> libraryBooks;
  final Function getchapter;
  const HomePageScreen({
    super.key, 
    required this.libraryBooks,
    required this.getchapter
  });

  @override
  State<HomePageScreen> createState() =>  _HomePageState(libraryBooks: []);

}

class _HomePageState extends State<HomePageScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabsState = Provider.of<TabsState>(context, listen: false);
      tabsState.setAppBarBottom(
        PreferredSize(
          preferredSize: Size.fromHeight(48.0), 
          child: TabBar(
            controller: _tabController,
            tabs: const [
            Tab(text: 'Action'),
            Tab(text: 'Fantasy'),
            Tab(text: 'Romance'),
            Tab(text: 'Mystery'),
            Tab(text: 'Thriller'),
            Tab(text: 'Adventure'),
            Tab(text: 'Comedy'),
            Tab(text: 'Sci-Fi'),
          ],
            isScrollable: true,
            splashBorderRadius: BorderRadius.circular(10),
            automaticIndicatorColorAdjustment: true,
            tabAlignment: TabAlignment.center,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            labelStyle: TextStyle(
              color: Colors.lightGreen,
              fontWeight: FontWeight.bold,
              fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12,
            ),
          )
        )
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  _HomePageState({required this.libraryBooks}) : super();
  final List<Map<String, dynamic>> libraryBooks;

  @override
    Widget build(BuildContext context) {
      return TabBarView(
        controller: _tabController,  
        children: [ 
          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Your Library',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Action',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Fantasy',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Romance',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Mystery',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Thriller',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Adventure',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),

          Column(
            children:[
              const SizedBox(height: 16),  
              const Text(  
                'Comedy',  
                style: TextStyle(  
                  color: Colors.blueGrey,  
                  fontWeight: FontWeight.bold,  
                  fontSize: 24,  
                ),  
              ),  
              const SizedBox(height: 16),  
              Expanded(  
                child: _buildBooksGrid(),  
              ),  
              const SizedBox(height: 16),  
            ] ,
          ),
      ],  
    );  
  }  

  Widget _buildBooksGrid() {  
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
                        getChapter: widget.getchapter,  
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