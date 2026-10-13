import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/library_organization_contracts.dart';

/// Owns the editable hierarchy of library tabs and page app-bar state.
class TabsState extends ChangeNotifier implements LibraryTabConfiguration {
  TabsState() {
    _tabsLoaded = _loadLibraryStructure();
  }

  List<String> _libraryTabs = ['Reading'];
  Map<String, List<String>> _subTabsByPrimary = {
    'Reading': [],
  };

  @override
  List<String> get libraryTabs => _libraryTabs;

  @override
  List<String> getSubTabsForPrimary(String primaryTab) {
    final subTabs = _subTabsByPrimary[primaryTab] ?? const <String>[];
    return List<String>.from(subTabs);
  }

  late Future<void> _tabsLoaded;
  Future<void> get tabsLoaded => _tabsLoaded;

  String _defaultTab = 'Reading';
  String get defaultTab => _defaultTab;

  @override
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
      _defaultTab = _libraryTabs.isNotEmpty ? _libraryTabs.first : 'Reading';
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

  void removeLibraryTab(int index, LibraryOrganizationUpdater organizer) {
    if (_libraryTabs.length <= 1) return;
    final removedTab = _libraryTabs.removeAt(index);
    final fallback = _libraryTabs.isNotEmpty ? _libraryTabs.first : 'Reading';
    _subTabsByPrimary.remove(removedTab);
    organizer.remapBooksFromRemovedTab(removedTab, fallback);
    _defaultTab = _libraryTabs.contains(_defaultTab) ? _defaultTab : fallback;
    _saveLibraryStructure();
    notifyListeners();
  }

  void renameLibraryTab(
    int index,
    String newName,
    LibraryOrganizationUpdater organizer,
  ) {
    if (newName.trim().isEmpty || _libraryTabs.contains(newName)) return;
    final oldName = _libraryTabs[index];
    _libraryTabs[index] = newName;

    final currentSubTabs = _subTabsByPrimary[oldName] ?? ['Unread', 'Read'];
    _subTabsByPrimary.remove(oldName);
    _subTabsByPrimary[newName] = currentSubTabs;

    organizer.renamePrimaryTabBooks(oldName, newName);
    if (_defaultTab == oldName) _defaultTab = newName;
    _saveLibraryStructure();
    notifyListeners();
  }

  void reorderLibraryTabs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final tabToMove = _libraryTabs.removeAt(oldIndex);
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
    LibraryOrganizationUpdater organizer,
  ) {
    if (!_libraryTabs.contains(primaryTab)) return;
    final current = _subTabsByPrimary[primaryTab] ?? <String>[];
    if (current.isEmpty || index < 0 || index >= current.length) return;

    final removed = current.removeAt(index);
    _subTabsByPrimary[primaryTab] = current;
    organizer.remapBooksFromRemovedSubTab(
      primaryTab,
      removed,
      current.isNotEmpty ? current.first : '',
    );
    _saveLibraryStructure();
    notifyListeners();
  }

  void renameSubTabInPrimary(
    String primaryTab,
    int index,
    String newName,
    LibraryOrganizationUpdater organizer,
  ) {
    if (!_libraryTabs.contains(primaryTab) || newName.trim().isEmpty) return;
    final current = _subTabsByPrimary[primaryTab] ?? <String>[];
    if (current.contains(newName) || index < 0 || index >= current.length) {
      return;
    }

    final oldName = current[index];
    current[index] = newName;
    _subTabsByPrimary[primaryTab] = current;
    organizer.renameSubTabBooks(primaryTab, oldName, newName);
    _saveLibraryStructure();
    notifyListeners();
  }

  void reorderSubTabsInPrimary(String primaryTab, int oldIndex, int newIndex) {
    if (!_libraryTabs.contains(primaryTab)) return;
    final current = _subTabsByPrimary[primaryTab] ?? <String>[];
    if (oldIndex < newIndex) newIndex -= 1;
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
    required LibraryOrganizationUpdater organizer,
  }) {
    if (tabToNest == targetPrimary ||
        !_libraryTabs.contains(tabToNest) ||
        !_libraryTabs.contains(targetPrimary) ||
        _libraryTabs.length <= 1) {
      return;
    }

    addSubTabToPrimary(targetPrimary, tabToNest);
    organizer.nestPrimaryAsSubTab(tabToNest, targetPrimary);

    final index = _libraryTabs.indexOf(tabToNest);
    if (index != -1) {
      _libraryTabs.removeAt(index);
      _subTabsByPrimary.remove(tabToNest);
      if (_defaultTab == tabToNest) {
        _defaultTab =
            _libraryTabs.isNotEmpty ? _libraryTabs.first : targetPrimary;
      }
    }

    _saveLibraryStructure();
    notifyListeners();
  }

  Future<void> _loadLibraryStructure() async {
    final prefs = await SharedPreferences.getInstance();
    final libraryTabs = prefs.getStringList('libraryTabs') ?? ['Reading'];
    final rawSubTabs = prefs.getString('librarySubTabsByPrimary');

    Map<String, dynamic> decodedMap = {};
    if (rawSubTabs != null && rawSubTabs.isNotEmpty) {
      decodedMap = jsonDecode(rawSubTabs) as Map<String, dynamic>;
    } else {
      final legacySubTabs =
          prefs.getStringList('librarySubTabs') ?? ['Unread', 'Read'];
      for (final tab in libraryTabs) {
        decodedMap[tab] = List<String>.from(legacySubTabs);
      }
    }

    _libraryTabs = libraryTabs.isEmpty ? ['Reading'] : libraryTabs;
    _subTabsByPrimary = {
      for (final tab in _libraryTabs)
        tab: decodedMap[tab] is List
            ? (decodedMap[tab] as List).map((item) => item.toString()).toList()
            : <String>[],
    };
    _defaultTab =
        _libraryTabs.contains('Reading') ? 'Reading' : _libraryTabs.first;
    notifyListeners();
  }

  Future<void> reloadLibraryStructure() async {
    _tabsLoaded = _loadLibraryStructure();
    await _tabsLoaded;
  }

  Future<void> _saveLibraryStructure() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('libraryTabs', _libraryTabs);
    await prefs.setString(
      'librarySubTabsByPrimary',
      jsonEncode(_subTabsByPrimary),
    );
  }

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
