import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class LibraryTabsSettingsScreen extends StatefulWidget {
  const LibraryTabsSettingsScreen({super.key});

  @override
  State<LibraryTabsSettingsScreen> createState() => _LibraryTabsSettingsScreenState();
}

class _LibraryTabsSettingsScreenState extends State<LibraryTabsSettingsScreen> {
  final TextEditingController _tabController = TextEditingController();
  final Map<String, TextEditingController> _subTabControllers = {};

  TextEditingController _controllerForPrimary(String primary) {
    return _subTabControllers.putIfAbsent(primary, TextEditingController.new);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in _subTabControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          "Library Tabs Settings",
          style: TextStyle(
            color: theme.selectedTheme.textTheme.titleLarge?.color,
            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
            fontWeight: FontWeight.bold,
          )
        ),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.teal[900]
            ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        iconTheme: IconThemeData(color: theme.selectedTheme.textTheme.titleMedium?.color),
      ),

      body: Consumer<TabsState>(
        builder: (context, tabsState, child) {
          final fontProvider = Provider.of<FontProvider>(context, listen: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tabController,
                      decoration: InputDecoration(
                        hintText: 'Add primary tab',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.green),
                    onPressed: () {
                      final text = _tabController.text.trim();
                      if (text.isEmpty) return;
                      tabsState.addLibraryTab(text);
                      _tabController.clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Tip: long-press and drag a primary tab onto another to nest it as subtab.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: tabsState.reorderLibraryTabs,
                children: [
                  for (int i = 0; i < tabsState.libraryTabs.length; i++)
                    _buildPrimaryNode(
                      key: ValueKey('primary-${tabsState.libraryTabs[i]}'),
                      primaryTab: tabsState.libraryTabs[i],
                      tabsState: tabsState,
                      fontProvider: fontProvider,
                    ),
                ],
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildPrimaryNode({
    required Key key,
    required String primaryTab,
    required TabsState tabsState,
    required FontProvider fontProvider,
  }) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final subTabs = tabsState.getSubTabsForPrimary(primaryTab);
    final subTabController = _controllerForPrimary(primaryTab);

    return DragTarget<String>(
      key: key,
      onWillAccept: (data) => data != null && data != primaryTab,
      onAccept: (data) {
        tabsState.nestPrimaryTabAsSubTab(
          tabToNest: data,
          targetPrimary: primaryTab,
          fontProvider: fontProvider,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return Card(
      color: Colors.white.withOpacity(0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LongPressDraggable<String>(
              data: primaryTab,
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.selectedTheme.cardTheme.color?.withOpacity(0.9) ??
                        const Color(0xFF2A1C46),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(primaryTab),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: highlighted
                      ? Colors.green.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    primaryTab,
                    style: TextStyle(
                      color: theme.selectedTheme.textTheme.titleMedium?.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  leading: const Icon(Icons.drag_indicator),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final newName = await _showRenameDialog(context, primaryTab);
                          if (newName != null && newName.trim().isNotEmpty) {
                            final index = tabsState.libraryTabs.indexOf(primaryTab);
                            if (index != -1) {
                              tabsState.renameLibraryTab(
                                index,
                                newName.trim(),
                                fontProvider,
                              );
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          final index = tabsState.libraryTabs.indexOf(primaryTab);
                          if (index != -1) {
                            tabsState.removeLibraryTab(index, fontProvider);
                          }
                        },
                      ),
                      ReorderableDragStartListener(
                        index: tabsState.libraryTabs.indexOf(primaryTab),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.menu),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (subTabs.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...subTabs.asMap().entries.map((entry) {
                final idx = entry.key;
                final subTab = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(subTab),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final newName = await _showRenameDialog(context, subTab);
                            if (newName != null && newName.trim().isNotEmpty) {
                              tabsState.renameSubTabInPrimary(
                                primaryTab,
                                idx,
                                newName.trim(),
                                fontProvider,
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            tabsState.removeSubTabFromPrimary(primaryTab, idx, fontProvider);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: subTabController,
                    decoration: InputDecoration(
                      hintText: 'Add subtab to "$primaryTab"',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.green),
                  onPressed: () {
                    final text = subTabController.text.trim();
                    if (text.isEmpty) return;
                    tabsState.addSubTabToPrimary(primaryTab, text);
                    subTabController.clear();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

Future<String?> _showRenameDialog(BuildContext context, String currentTabName) {
  final TextEditingController _controller = TextEditingController();
  _controller.text = currentTabName;

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Rename Tab'),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: 'Enter new tab name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
