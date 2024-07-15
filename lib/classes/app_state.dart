import 'package:flutter/material.dart';  

class AppState extends ChangeNotifier {  
  List<Widget> _currentTabs = [];  
  int _currentIndex = 0;  
  TabController? _tabController;  

  List<Widget> get currentTabs => _currentTabs;  
  int get currentIndex => _currentIndex;  
  TabController? get tabController => _tabController;  

  void initTabController(TickerProvider vsync) {  
    _tabController?.dispose();  
    if (_currentTabs.isNotEmpty) {  
      _tabController = TabController(length: _currentTabs.length, vsync: vsync);  
      _tabController!.addListener(_handleTabSelection);  
    }  
  }  

  void setTabs(List<Widget> tabs, TickerProvider vsync) {  
    _currentTabs = tabs;  
    initTabController(vsync);  
    notifyListeners();  
  }  

  void setIndex(int index) {  
    _currentIndex = index;  
    _tabController?.animateTo(index);  
    notifyListeners();  
  }  

  void _handleTabSelection() {  
    if (_tabController!.indexIsChanging) {  
      setIndex(_tabController!.index);  
    }  
  }  

  @override  
  void dispose() {  
    _tabController?.removeListener(_handleTabSelection);  
    _tabController?.dispose();  
    super.dispose();  
  }  
}