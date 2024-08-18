import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

class HomePageScreen extends StatefulWidget {
  final List<Map<String, dynamic>> libraryBooks;
  final  Stream<Map<String, dynamic>> Function(String, String) getchapter; 
  final Stream<Map<String, dynamic>> Function(String, String) retrieveLastChapter;  
  final Stream<Map<String, dynamic>> Function(String, String) retrieveNextChapter;
  const HomePageScreen({
    super.key, 
    required this.libraryBooks,
    required this.getchapter,
    required this.retrieveLastChapter,
    required this.retrieveNextChapter,

  });

  @override
  State<HomePageScreen> createState() =>  _HomePageState(libraryBooks: []);
}

class _HomePageState extends State<HomePageScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late TabsState _tabsState;
  late FontProvider _favoritedBooksState;

  @override
  void initState() {
    super.initState();
    final tabsState = Provider.of<TabsState>(context, listen: false);
    _tabController = TabController(length: tabsState.libraryTabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tabsState.addListener(_updateLibraryTabs);
      tabsState.setAppBarBottom(
        PreferredSize(
          preferredSize: Size.fromHeight(10.0), 
          child: Text(
            'Library',
            style: TextStyle(
              color: Colors.lightGreen,
              fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
              fontWeight: FontWeight.bold,
              shadows: <Shadow>[
                Shadow(color: Colors.black, blurRadius: 10.0),
              ],
            ),
          )
        )
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabsState = Provider.of<TabsState>(context, listen: false);
    _favoritedBooksState = Provider.of<FontProvider>(context, listen: false);
    _tabsState.addListener(_updateLibraryTabs);
    _favoritedBooksState.addListener(_updateLibraryTabs);
  }

  void _updateLibraryTabs() {
    if (mounted) {
      setState(() {
        _tabController = TabController(length: _tabsState.libraryTabs.length, vsync: this);
      });
    }
  }

  @override
  void dispose() {
    _tabsState.removeListener(_updateLibraryTabs);
    _tabController.dispose();
    super.dispose();
  }

  _HomePageState({required this.libraryBooks}) : super();
  final List<Map<String, dynamic>> libraryBooks;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(10.0),
          child: Consumer<TabsState>(
            builder: (context, tabsState, child) {
              return FutureBuilder<void>(
                future: tabsState.tabsLoaded,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return CircularProgressIndicator();
                  } else {
                    return TabBar(
                      controller: _tabController,
                      tabs: tabsState.libraryTabs.map((tabName) => Tab(text: tabName)).toList(),
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
                    );
                  }
                },
              );
            },
          ),
        ),
      ),
      body: FutureBuilder<void>(
        future: _tabsState.tabsLoaded,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else {
            return TabBarView(
              controller: _tabController,
              children: _tabsState.libraryTabs.map((tabName) {
                return Column(
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      tabName, 
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.selectedTheme.textTheme.titleSmall?.color
                      )
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _buildBooksGrid(tabName),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              }).toList(),
            );
          }
        },
      ),
    );
  }

  Widget _buildBooksGrid(String tabName) {
    return Consumer<FontProvider>(
      builder: (context, fontProvider, child) {
        final booksInTab = fontProvider.getBooksInTab(tabName, context);
        return Center(
          child: booksInTab.isEmpty
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
                itemCount: booksInTab.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BookDetailsScreen(
                            bookDetails: booksInTab[index],
                            getChapter: widget.getchapter,
                            retrieveLastChapter: widget.retrieveLastChapter,
                            retrieveNextChapter: widget.retrieveNextChapter,
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
                            booksInTab[index]['title']!,
                            style: const TextStyle(
                              color: Colors.white70,
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
                          booksInTab[index]['coverImageUrl'] ?? 'https://via.placeholder.com/150',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
        );
      },
    );
  }
}