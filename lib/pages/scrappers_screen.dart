import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/active_scrappers.dart';
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
      tabsState.setAppBarBottom(
        PreferredSize(
          preferredSize: Size.fromHeight(48.0), 
          child: TabBar(
            controller: _tabController,
            
            tabs: const [
            Tab(text: 'Fonts'),
            Tab(text: 'Downloads'),
            Tab(text: 'History'),
            Tab(text: 'Migrate'),
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

  @override
  Widget build(BuildContext context) {
       return TabBarView(
        controller: _tabController,
        children: const [
          Center(child: ScrapperActiveFonts()),
          Center(child: ScrapperDownloaderFonts()),
          Center(child: Text('History')),
          Center(child: Text('Migrate')),
        ],
      );
  }
}