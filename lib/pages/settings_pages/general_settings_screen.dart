import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/config/themes.dart';
import 'package:star_scrapper_app/components/UI/theme_preview_widgets.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/library_settings_screen.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: 
        [
          SizedBox(height: 20),
          Text(
            'General Settings',
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18, 
              fontWeight: FontWeight.bold,
              color: theme.selectedTheme.textTheme.titleLarge?.color,
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
                        color: theme.selectedTheme.textTheme.displayMedium?.color,
                        size: MediaQuery.of(context).size.width >= 600 ? 30 : 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Library',
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12, 
                          fontWeight: FontWeight.bold,
                          color: theme.selectedTheme.textTheme.displayMedium?.color,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              ]
            )
          ),

          SizedBox(height: 20),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Themes',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width >= 600 ? 22 : 14, 
                    fontWeight: FontWeight.bold,
                    color: theme.selectedTheme.textTheme.titleSmall?.color,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                SizedBox(height: 20),

                
                  ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      ThemePreviewWidgets(
                        themeData: Appthemes.purpleForest,
                        themeName: 'Purple Forest',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.purpleForest);
                        },
                      ),

                      ThemePreviewWidgets(
                        themeData: Appthemes.deepOcean,
                        themeName: 'Deep Ocean',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.deepOcean);
                        },
                      ),

                      ThemePreviewWidgets(
                        themeData: Appthemes.redRiver,
                        themeName: 'Red River',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.redRiver);
                        },
                      ),

                      ThemePreviewWidgets(
                        themeData: Appthemes.grayCity,
                        themeName: 'Gray City',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.grayCity);
                        },
                      ),

                      ThemePreviewWidgets(
                        themeData: Appthemes.heavensDay,
                        themeName: 'Royal Purple',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.heavensDay);
                        },
                      ),

                      ThemePreviewWidgets(
                        themeData: Appthemes.sunsLight,
                        themeName: 'Sun\'s Light',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.sunsLight);
                        },
                      ),

                      ThemePreviewWidgets(
                        themeData: Appthemes.frozenLake,
                        themeName: 'Frozen Lake',
                        onTap: () {
                          theme.setSelectedTheme(Appthemes.frozenLake);
                        },
                      ),
                    ],
                  ),
              ],
            )
          )
      
        ],
      ) 
    );
  }
}