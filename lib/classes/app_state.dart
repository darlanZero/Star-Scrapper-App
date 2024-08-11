import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/config/themes.dart';  

class AppState extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  void setIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }
} 

class TabsState extends ChangeNotifier  {  
  PreferredSizeWidget? _appBarBottom;    
  PreferredSizeWidget? get appBarBottom => _appBarBottom;

  TabsState() {
    _tabsLoaded = _loadLibraryTabs();
  }

  //library tabs
  List<String> _libraryTabs = ['Reading'];
  List<String> get libraryTabs => _libraryTabs;

  late Future<void> _tabsLoaded;
  Future<void> get tabsLoaded => _tabsLoaded;

  void addLibraryTab(String tabName) {
    _libraryTabs.add(tabName);
    _saveLibraryTabs();
    notifyListeners();
  }

  void removeLibraryTab(int index) {
    _libraryTabs.removeAt(index);
    _saveLibraryTabs();
    notifyListeners();
  }

  void renameLibraryTab(int index, String newName) {
    _libraryTabs[index] = newName;
    _saveLibraryTabs();
    notifyListeners();
  }

  void reorderLibraryTabs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String tabToMove = _libraryTabs.removeAt(oldIndex);
    _libraryTabs.insert(newIndex, tabToMove);
    _saveLibraryTabs();
    notifyListeners();
  }

  Future<void> _loadLibraryTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final libraryTabs = prefs.getStringList('libraryTabs') ?? ['Reading'];
    _libraryTabs = libraryTabs;
    notifyListeners();
  }

  void _saveLibraryTabs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('libraryTabs', _libraryTabs);
  }

  //general tabs
  setAppBarBottom(PreferredSizeWidget? newBottom) {  
    _appBarBottom = newBottom;  
    notifyListeners();  
  }
 
}

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

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('selectedTheme') ?? 'purpleForest';
    _selectedTheme = Appthemes.getThemeByName(themeName);
    notifyListeners();
  }

  void _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = Appthemes.getThemeName(_selectedTheme);
    prefs.setString('selectedTheme', themeName);
  }
}