import 'package:flutter/material.dart';  

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

  //library tabs
  List<String> _libraryTabs = ['Reading'];
  List<String> get libraryTabs => _libraryTabs;

  void addLibraryTab(String tabName) {
    _libraryTabs.add(tabName);
    notifyListeners();
  }

  void removeLibraryTab(int index) {
    _libraryTabs.removeAt(index);
    notifyListeners();
  }

  void renameLibraryTab(int index, String newName) {
    _libraryTabs[index] = newName;
    notifyListeners();
  }

  void reorderLibraryTabs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String tabToMove = _libraryTabs.removeAt(oldIndex);
    _libraryTabs.insert(newIndex, tabToMove);
    notifyListeners();
  }

  //general tabs
  setAppBarBottom(PreferredSizeWidget? newBottom) {  
    _appBarBottom = newBottom;  
    notifyListeners();  
  }

 
}