import 'package:flutter/material.dart';
import 'package:star_scrapper_app/classes/tabs_state.dart';

class SecondTopNav extends StatefulWidget {
  final int selectedIndex;
  final void Function(int) onTabChanged;

  const SecondTopNav({Key? key, required this.selectedIndex, required this.onTabChanged}) : super(key: key);

  @override
  State<SecondTopNav> createState() => _SecondTopNavState();
}

class _SecondTopNavState extends State<SecondTopNav> with SingleTickerProviderStateMixin {
   TabController? _tabController;

  @override
  void initState() {
    super.initState();
    // Inicializa o TabController com o número de abas atual.
    _tabController = TabController(length: tabsState.tabs.length, vsync: this);
    // Adiciona um ouvinte para atualizar o TabController quando o estado das abas mudar.
    tabsState.addListener(_updateTabController);
  }

  void _updateTabController() {
    // Atualiza o comprimento do TabController para corresponder ao número de abas.
    _tabController?.addListener(() {
      widget.onTabChanged(tabsState.tabs.length);
      tabsState.removeListener(_updateTabController);
      tabsState.addListener(_updateTabController);
      tabsState.setTabs(tabsState.tabs);
      
    });
    _tabController?.dispose();
    _tabController = TabController(length: tabsState.tabs.length, vsync: this);
    setState(() {}); // Força a reconstrução do widget para refletir as mudanças.
  }

  @override
  void dispose() {
    _tabController?.dispose();
    tabsState.removeListener(_updateTabController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
        controller: _tabController,
        tabs: tabsState.tabs,
        indicatorColor: Colors.white,
        labelColor: Colors.deepOrange,
        unselectedLabelColor: Colors.grey,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        isScrollable: true,
      );
  }
}
