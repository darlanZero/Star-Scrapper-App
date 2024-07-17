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

  setAppBarBottom(PreferredSizeWidget? newBottom) {  
    _appBarBottom = newBottom;  
    notifyListeners();  
  }

 
}