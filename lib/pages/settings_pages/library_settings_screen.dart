import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/library_tabs_settings_screen.dart';

class LibrarySettingsScreen extends StatefulWidget {
  const LibrarySettingsScreen({super.key});

  @override
  State<LibrarySettingsScreen> createState() => _LibrarySettingsScreenState();
}

class _LibrarySettingsScreenState extends State<LibrarySettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          'Library Settings',
          style: TextStyle(
            color: Color.fromARGB(255, 224, 224, 224),
            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
            fontWeight: FontWeight.bold,
          )
        ),
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),
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
      ),

      body: Container(
        color: theme.selectedTheme.scaffoldBackgroundColor,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LibraryTabsSettingsScreen()),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.format_list_bulleted_rounded,
                          color: Colors.white,
                          size: MediaQuery.of(context).size.width >= 600 ? 30 : 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Library Tabs Settings',
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12, 
                            fontWeight: FontWeight.normal,
                            color: Colors.white,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]
                    )
                  )
                ],
              ),
            )
          ]
          ),
        ),
      );
  }
} 
