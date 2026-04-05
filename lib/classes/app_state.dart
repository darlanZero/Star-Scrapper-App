import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/config/themes.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';  

class AppState extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  void setIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }
} 

class TabsState extends ChangeNotifier  {
  TabsState() {
    _tabsLoaded = _loadLibraryStructure();
  }

  // library tabs (hierarchical model)
  List<String> _libraryTabs = ['Reading'];
  Map<String, List<String>> _subTabsByPrimary = {
    'Reading': [],
  };
  List<String> get libraryTabs => _libraryTabs;

  List<String> getSubTabsForPrimary(String primaryTab) {
    final subTabs = _subTabsByPrimary[primaryTab] ?? const <String>[];
    return List<String>.from(subTabs);
  }

  late Future<void> _tabsLoaded;
  Future<void> get tabsLoaded => _tabsLoaded;

  String _defaultTab = 'Reading';
  String get defaultTab => _defaultTab;

  String getDefaultSubTabForPrimary(String primaryTab) {
    final subTabs = getSubTabsForPrimary(primaryTab);
    if (subTabs.contains('Unread')) return 'Unread';
    if (subTabs.isNotEmpty) return subTabs.first;
    return '';
  }

  void setDefaultTab(String tabName) {
    if (_libraryTabs.contains(tabName)) {
      _defaultTab = tabName;
    } else {
      _defaultTab =_libraryTabs.isNotEmpty ? _libraryTabs.first : 'Reading';
    }
    notifyListeners();
  }

  void addLibraryTab(String tabName) {
    if (tabName.trim().isEmpty || _libraryTabs.contains(tabName)) return;
    _libraryTabs.add(tabName);
    _subTabsByPrimary[tabName] = [];
    _saveLibraryStructure();
    notifyListeners();
  }

  void removeLibraryTab(int index, FontProvider fontProvider) {
    if (_libraryTabs.length <= 1) return;
    final removedTab = _libraryTabs.removeAt(index);
    final fallback = _libraryTabs.isNotEmpty ? _libraryTabs.first : 'Reading';
    _subTabsByPrimary.remove(removedTab);
    fontProvider.remapBooksFromRemovedTab(removedTab, fallback);
    _defaultTab = _libraryTabs.contains(_defaultTab) ? _defaultTab : fallback;
    _saveLibraryStructure();
    notifyListeners();
  }

  void renameLibraryTab(int index, String newName, FontProvider fontProvider) {
    if (newName.trim().isEmpty || _libraryTabs.contains(newName)) return;
    final oldName = _libraryTabs[index];
    _libraryTabs[index] = newName;

    final currentSubTabs = _subTabsByPrimary[oldName] ?? ['Unread', 'Read'];
    _subTabsByPrimary.remove(oldName);
    _subTabsByPrimary[newName] = currentSubTabs;

    fontProvider.renamePrimaryTabBooks(oldName, newName);
    if (_defaultTab == oldName) _defaultTab = newName;
    _saveLibraryStructure();
    notifyListeners();
  }

  void reorderLibraryTabs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String tabToMove = _libraryTabs.removeAt(oldIndex);
    _libraryTabs.insert(newIndex, tabToMove);
    _saveLibraryStructure();
    notifyListeners();
  }

  void addSubTabToPrimary(String primaryTab, String subTabName) {
    if (!_libraryTabs.contains(primaryTab) || subTabName.trim().isEmpty) return;
    final current = _subTabsByPrimary[primaryTab] ?? ['Unread'];
    if (current.contains(subTabName)) return;
    current.add(subTabName);
    _subTabsByPrimary[primaryTab] = current;
    _saveLibraryStructure();
    notifyListeners();
  }

  void removeSubTabFromPrimary(
    String primaryTab,
    int index,
    FontProvider fontProvider,
  ) {
    if (!_libraryTabs.contains(primaryTab)) return;
    final current = _subTabsByPrimary[primaryTab] ?? <String>[];
    if (current.isEmpty || index < 0 || index >= current.length) return;

    final removed = current.removeAt(index);
    _subTabsByPrimary[primaryTab] = current;

    final fallbackSubTab = current.isNotEmpty ? current.first : '';
    fontProvider.remapBooksFromRemovedSubTab(
      primaryTab,
      removed,
      fallbackSubTab,
    );

    _saveLibraryStructure();
    notifyListeners();
  }

  void renameSubTabInPrimary(
    String primaryTab,
    int index,
    String newName,
    FontProvider fontProvider,
  ) {
    if (!_libraryTabs.contains(primaryTab) || newName.trim().isEmpty) return;
    final current = _subTabsByPrimary[primaryTab] ?? <String>[];
    if (current.contains(newName) || index < 0 || index >= current.length) return;

    final oldName = current[index];
    current[index] = newName;
    _subTabsByPrimary[primaryTab] = current;
    fontProvider.renameSubTabBooks(primaryTab, oldName, newName);

    _saveLibraryStructure();
    notifyListeners();
  }

  void reorderSubTabsInPrimary(String primaryTab, int oldIndex, int newIndex) {
    if (!_libraryTabs.contains(primaryTab)) return;
    final current = _subTabsByPrimary[primaryTab] ?? <String>[];
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 ||
        oldIndex >= current.length ||
        newIndex < 0 ||
        newIndex > current.length) {
      return;
    }
    final tabToMove = current.removeAt(oldIndex);
    current.insert(newIndex, tabToMove);
    _subTabsByPrimary[primaryTab] = current;
    _saveLibraryStructure();
    notifyListeners();
  }

  void nestPrimaryTabAsSubTab({
    required String tabToNest,
    required String targetPrimary,
    required FontProvider fontProvider,
  }) {
    if (tabToNest == targetPrimary) return;
    if (!_libraryTabs.contains(tabToNest) || !_libraryTabs.contains(targetPrimary)) return;
    if (_libraryTabs.length <= 1) return;

    addSubTabToPrimary(targetPrimary, tabToNest);
    fontProvider.nestPrimaryAsSubTab(tabToNest, targetPrimary);

    final index = _libraryTabs.indexOf(tabToNest);
    if (index != -1) {
      _libraryTabs.removeAt(index);
      _subTabsByPrimary.remove(tabToNest);
      if (_defaultTab == tabToNest) {
        _defaultTab = _libraryTabs.isNotEmpty ? _libraryTabs.first : targetPrimary;
      }
    }

    _saveLibraryStructure();
    notifyListeners();
  }

  Future<void> _loadLibraryStructure() async {
    final prefs = await SharedPreferences.getInstance();
    final libraryTabs = prefs.getStringList('libraryTabs') ?? ['Reading'];
    final subTabsByPrimaryRaw = prefs.getString('librarySubTabsByPrimary');

    Map<String, dynamic> decodedMap = {};
    if (subTabsByPrimaryRaw != null && subTabsByPrimaryRaw.isNotEmpty) {
      decodedMap = jsonDecode(subTabsByPrimaryRaw) as Map<String, dynamic>;
    } else {
      // fallback legado (modelo antigo)
      final legacySubTabs = prefs.getStringList('librarySubTabs') ?? ['Unread', 'Read'];
      for (final tab in libraryTabs) {
        decodedMap[tab] = List<String>.from(legacySubTabs);
      }
    }

    _libraryTabs = libraryTabs.isEmpty ? ['Reading'] : libraryTabs;

    _subTabsByPrimary = {};
    for (final tab in _libraryTabs) {
      final raw = decodedMap[tab];
      if (raw is List) {
        final values = raw.map((e) => e.toString()).toList();
        _subTabsByPrimary[tab] = values;
      } else {
        _subTabsByPrimary[tab] = [];
      }
    }

    _defaultTab = _libraryTabs.contains('Reading') ? 'Reading' : _libraryTabs.first;

    notifyListeners();
  }

  void _saveLibraryStructure() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('libraryTabs', _libraryTabs);
    prefs.setString('librarySubTabsByPrimary', jsonEncode(_subTabsByPrimary));
  }

  //general tabs — armazena um bottom por índice de página
  final Map<int, PreferredSizeWidget?> _pageBottoms = {};
  int _activePageIndex = 0;

  PreferredSizeWidget? get appBarBottom => _pageBottoms[_activePageIndex];

  void setAppBarBottom(int pageIndex, PreferredSizeWidget? newBottom) {
    _pageBottoms[pageIndex] = newBottom;
    notifyListeners();
  }

  void setActivePageIndex(int index) {
    _activePageIndex = index;
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
