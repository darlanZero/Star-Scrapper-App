import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';

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
    _tabController = TabController(length: 3, vsync: this);
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
            Tab(text: 'Migrate'),
          ],)
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
          Center(child: Text('Fonts')),
          Center(child: Text('Downloads')),
          Center(child: Text('Migrate')),
        ],
      );
  }
}