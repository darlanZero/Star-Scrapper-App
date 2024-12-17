import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class LibraryItemsSettingsScreen extends StatefulWidget {
  const LibraryItemsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<LibraryItemsSettingsScreen> createState() => _LibraryItemsSettingsScreenState();
}

class _LibraryItemsSettingsScreenState extends State<LibraryItemsSettingsScreen> {

  final List<String> updateIntervals = ['2 hours', '5 hours', '12 hours', '24 hours'];
  String selectedUpdateInterval = '2 hours';
  Map<String, bool> tabsSelection = {};

  @override
  void initState() {
    super.initState();
    final tabsState = Provider.of<TabsState>(context, listen: false);
    tabsState.libraryTabs.forEach((tab) {
      tabsSelection[tab] = true;
    });
  }

  void _saveSettings() {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);

    Duration interval;

    switch (selectedUpdateInterval) {
      case '2 hours':
        interval = const Duration(hours: 2);
        break;
      case '5 hours':
        interval = const Duration(hours: 5);
        break;
      case '12 hours':
        interval = const Duration(hours: 12);
        break;
      case '24 horas':
      default:
        interval = const Duration(hours: 24);
        break;
    }
    fontProvider.setUpdateInterval(interval);

    Set<String> selectedTabs = tabsSelection.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();

    fontProvider.setTabsToUpdate(selectedTabs);

  }


  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          "Library Items Settings",
          style: TextStyle(
            color: theme.selectedTheme.textTheme.titleLarge?.color,
            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
            fontWeight: FontWeight.bold,
          )
        ),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.teal[900]
            ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        iconTheme: IconThemeData(color: theme.selectedTheme.textTheme.titleMedium?.color),
      ),
    );
  }
}