import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key});

  @override
  State<HomePageScreen> createState() => _HomePageState();
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

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final appBarBase = theme.selectedTheme.appBarTheme.backgroundColor ??
        theme.selectedTheme.primaryColor;
    final scaffoldBase = theme.selectedTheme.scaffoldBackgroundColor;
    final accent = theme.selectedTheme.textTheme.titleMedium?.color ?? const Color(0xFF82EA64);

    Color blend(Color a, Color b, double t) {
      return Color.lerp(a, b, t) ?? a;
    }

    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Consumer<TabsState>(
            builder: (context, tabsState, child) {
              return FutureBuilder<void>(
                future: tabsState.tabsLoaded,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 52,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  } else {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: blend(appBarBase, scaffoldBase, 0.35).withOpacity(0.45),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.10)),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              tabs: tabsState.libraryTabs
                                  .map((tabName) => Tab(text: tabName))
                                  .toList(),
                              isScrollable: true,
                              dividerColor: Colors.transparent,
                              splashBorderRadius: BorderRadius.circular(10),
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(
                                  colors: [
                                    blend(accent, appBarBase, 0.45),
                                    blend(accent, scaffoldBase, 0.25),
                                  ],
                                ),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white70,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: MediaQuery.of(context).size.width >= 600 ? 14 : 12,
                              ),
                              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                        ),
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
            return const Center(child: CircularProgressIndicator());
          } else {
            return TabBarView(
              controller: _tabController,
              children: _tabsState.libraryTabs.map((tabName) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: Column(
                    children: [
                      Expanded(
                        child: _buildBooksGrid(tabName),
                      ),
                    ],
                  ),
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
        final booksInTab = fontProvider.getBooksInTab(tabName);
        return Center(
          child: booksInTab.isEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white.withOpacity(0.06),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.library_books_outlined, size: 46, color: Colors.white60),
                        SizedBox(height: 8),
                        Text(
                          'Your library is empty, try adding some books!',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(4),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.of(context).size.width >= 1100
                      ? 6
                      : MediaQuery.of(context).size.width >= 700
                          ? 4
                          : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.7,
                ),
                itemCount: booksInTab.length,
                itemBuilder: (context, index) {
                  final book = booksInTab[index];
                  final scrapper = fontProvider.findScrapperForBook(book) ?? fontProvider.selectedFontApi;
                  final coverUrl = scrapper.getCoverImageUrl(book);
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BookDetailsScreen(
                            bookDetails: book,
                            scrapper: scrapper,
                          ),
                        ),
                      );
                    },
                    child: GridTile(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: coverUrl,
                              httpHeaders: scrapper.imageHeaders,
                              fit: BoxFit.cover,
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
                                  colors: [
                                    Colors.transparent,
                                    Color.fromARGB(35, 0, 0, 0),
                                    Color.fromARGB(185, 0, 0, 0),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 10,
                              child: Text(
                                (book['title'] ?? '').toString(),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 24,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                                ),
                              ),
                            ),
                          ],
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
