import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/config/themes.dart';

/// Owns the active application theme and its persisted selection.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _loadTheme();
  }

  ThemeData _selectedTheme = Appthemes.purpleForest;

  ThemeData get selectedTheme => _selectedTheme;

  void setSelectedTheme(ThemeData theme) {
    _selectedTheme = theme;
    _saveTheme();
    notifyListeners();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('selectedTheme') ?? 'purpleForest';
    _selectedTheme = Appthemes.getThemeByName(themeName);
    notifyListeners();
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = Appthemes.getThemeName(_selectedTheme);
    await prefs.setString('selectedTheme', themeName);
  }
}
