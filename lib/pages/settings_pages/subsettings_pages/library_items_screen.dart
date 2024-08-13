import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';

class LibraryItemsSettingsScreen extends StatefulWidget {
  const LibraryItemsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<LibraryItemsSettingsScreen> createState() => _LibraryItemsSettingsScreenState();
}

class _LibraryItemsSettingsScreenState extends State<LibraryItemsSettingsScreen> {

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          "Library Tabs Settings",
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