import 'package:flutter/material.dart';

class TabsState extends ChangeNotifier {
  List<Widget> _tabs = [];

  List<Widget> get tabs => _tabs;

  void setTabs(List<Widget> newTabs) {
    _tabs = newTabs;
    notifyListeners();
  }
}

final tabsState = TabsState();