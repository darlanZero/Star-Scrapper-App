import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/pages/settings_pages/about_application_screen.dart';
import 'package:star_scrapper_app/pages/settings_pages/general_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

 @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
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
            Tab(text: 'General'),
            Tab(text: 'Account'),
            Tab(text: 'About'),
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
          Center(child: GeneralSettingsScreen()),
          Center(child: Text('Account')),
          Center(child: AboutApplicationScreen()),
        ]
      );
  }
}