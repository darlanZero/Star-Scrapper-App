import 'package:flutter/material.dart';
import 'package:star_scrapper_app/pages/settings_pages/library_settings_screen.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: 20),
        Text(
          'General Settings',
          style: TextStyle(
            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18, 
            fontWeight: FontWeight.bold,
            color: Colors.white,
            overflow: TextOverflow.ellipsis,

          ),
        ),
        SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LibrarySettingsScreen()),
                  );
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.library_books,
                      color: Colors.white,
                      size: MediaQuery.of(context).size.width >= 600 ? 30 : 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Library',
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12, 
                        fontWeight: FontWeight.normal,
                        color: Colors.white,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            ]
          )
        ),
      ],
    );
  }
}
