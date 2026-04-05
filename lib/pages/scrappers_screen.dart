import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/active_scrappers.dart';
import 'package:star_scrapper_app/components/Shared/library_books_history.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';

class ScrappersScreen extends StatefulWidget {
  const ScrappersScreen({super.key});

  @override
  State<ScrappersScreen> createState() => _ScrappersScreenState();
}

class _ScrappersScreenState extends State<ScrappersScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabsState = Provider.of<TabsState>(context, listen: false);
      final theme = Provider.of<ThemeProvider>(context, listen: false);
      final appBarBase =
          theme.selectedTheme.appBarTheme.backgroundColor ?? theme.selectedTheme.primaryColor;
      final scaffoldBase = theme.selectedTheme.scaffoldBackgroundColor;
      final accent =
          theme.selectedTheme.textTheme.titleMedium?.color ?? const Color(0xFF82EA64);

      Color blend(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;
      tabsState.setAppBarBottom(1,
        PreferredSize(
          preferredSize: const Size.fromHeight(46.0),
          child: Padding(
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
                    tabs: const [
                      Tab(text: 'Fonts'),
                      Tab(text: 'Downloads'),
                      Tab(text: 'History'),
                      Tab(text: 'Migrate'),
                    ],
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
          ),
        )
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
       return TabBarView(
        controller: _tabController,
        children: [
          const Center(child: ScrapperActiveFonts()),
          Center(child: ScrapperDownloaderFonts()),
          Center(child: LibraryBooksHistory()),
          Center(child: Text('Migrate')),
        ],
      );
  }
}
