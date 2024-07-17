import 'package:dynamic_tabbar/dynamic_tabbar.dart';
import 'package:flutter/material.dart';  

class AppState extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  void setIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }
} 

class TabsState extends ChangeNotifier {  
  List<TabData> _currentTabs = [];  
  int _currentIndex = 0;  
  TabController? _tabController;  

  List<TabData> get currentTabs => _currentTabs;  
  int get currentIndex => _currentIndex;  
  TabController? get tabController => _tabController;  

   set tabController(TabController? newController) {
    _tabController = newController;
    // Você pode adicionar qualquer lógica adicional necessária aqui,
    // como notificar ouvintes sobre a mudança.
  }

  void initTabController(TickerProvider vsync) {  
    _tabController?.dispose();  
    if (_currentTabs.isNotEmpty) {  
      _tabController = TabController(length: _currentTabs.length, vsync: vsync);  
      _tabController!.addListener(_handleTabSelection);  
    }  
  }  

  void setTabs(List<TabData> tabs, TickerProvider vsync) {  
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