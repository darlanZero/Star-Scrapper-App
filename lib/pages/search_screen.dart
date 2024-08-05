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
          title: const Text('Search', style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontWeight: FontWeight.bold, shadows: <Shadow>[
            Shadow(color: Colors.black, blurRadius: 10.0),
          ])),
          iconTheme: const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),
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
              style: TextStyle(color: Color.fromARGB(255, 241, 219, 219)),
              controller: _searchController,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (conxtext, index) {
                return ListTile(
                  title: Text('Item $index', style: TextStyle(color: Color.fromARGB(255, 241, 219, 219))),
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