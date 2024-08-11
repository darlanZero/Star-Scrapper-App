import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
          backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
          title: Text('Search', style: TextStyle(color: theme.selectedTheme.textTheme.titleLarge?.color, fontWeight: FontWeight.bold, shadows: <Shadow>[
            Shadow(color: Colors.black, blurRadius: 10.0),
          ])),
          iconTheme: IconThemeData(color: theme.selectedTheme.textTheme.titleMedium?.color),
          centerTitle: true,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
          )
        ),
      body: Column(
        children: [
          Padding (
            padding: EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12.0)),
                ),
                labelText: 'Search for items',
                prefixIcon: Icon(Icons.search),
              ),
              style: TextStyle(color: theme.selectedTheme.textTheme.displayMedium?.color),
              controller: _searchController,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (conxtext, index) {
                return ListTile(
                  title: Text('Item $index', style: TextStyle(color: theme.selectedTheme.textTheme.displaySmall?.color)),
                );
              }
            )
          )
        ]
      )
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}