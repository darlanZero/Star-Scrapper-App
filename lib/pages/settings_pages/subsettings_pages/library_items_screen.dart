import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class LibraryItemsSettingsScreen extends StatefulWidget {
  const LibraryItemsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<LibraryItemsSettingsScreen> createState() => _LibraryItemsSettingsScreenState();
}

class _LibraryItemsSettingsScreenState extends State<LibraryItemsSettingsScreen> {

  final List<String> updateIntervals = ['2 hours', '5 hours', '12 hours', '24 hours'];
  String selectedUpdateInterval = '2 hours';
  Map<String, bool> tabsSelection = {};
  bool trackerEnabled = true;
  bool runningNow = false;

  @override
  void initState() {
    super.initState();
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final tabsState = Provider.of<TabsState>(context, listen: false);
    tabsState.libraryTabs.forEach((tab) {
      tabsSelection[tab] = fontProvider.tabsToUpdate.contains(tab);
    });
    trackerEnabled = fontProvider.trackerEnabled;
    final hours = fontProvider.updateInterval.inHours;
    if (hours == 2) selectedUpdateInterval = '2 hours';
    if (hours == 5) selectedUpdateInterval = '5 hours';
    if (hours == 12) selectedUpdateInterval = '12 hours';
    if (hours == 24) selectedUpdateInterval = '24 hours';
  }

  void _saveSettings() {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);

    Duration interval;

    switch (selectedUpdateInterval) {
      case '2 hours':
        interval = const Duration(hours: 2);
        break;
      case '5 hours':
        interval = const Duration(hours: 5);
        break;
      case '12 hours':
        interval = const Duration(hours: 12);
        break;
      case '24 horas':
      default:
        interval = const Duration(hours: 24);
        break;
    }
    fontProvider.setUpdateInterval(interval);

    Set<String> selectedTabs = tabsSelection.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();

    fontProvider.setTabsToUpdate(selectedTabs);

  }

  Future<void> _runNow() async {
    setState(() => runningNow = true);
    try {
      await Provider.of<FontProvider>(context, listen: false).runTrackerNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracker executado com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao executar tracker: $e')),
      );
    } finally {
      if (mounted) setState(() => runningNow = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          "Library Items Settings",
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

      body: Consumer<FontProvider>(
        builder: (context, fp, _) => ListView(
        children: [
          SwitchListTile(
            title: Text(
              'Enable Chapter Tracker',
              style: TextStyle(
                color: theme.selectedTheme.textTheme.titleMedium?.color,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            value: trackerEnabled,
            onChanged: (value) {
              setState(() => trackerEnabled = value);
              fp.setTrackerEnabled(value);
            },
          ),
          ListTile(
            title: Text(
              'Update Interval',
              style: TextStyle(
                color: theme.selectedTheme.textTheme.titleMedium?.color,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                fontWeight: FontWeight.bold,
              )
            ),
            subtitle: DropdownButton<String>(
              value: selectedUpdateInterval,
              items: updateIntervals.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? value) {
                setState(() {
                  selectedUpdateInterval = value!;
                  
                });
              },
            ),
          ),
          ListTile(
            title: Text(
              'Tabs to Update',
              style: TextStyle(
                color: theme.selectedTheme.textTheme.titleMedium?.color,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                fontWeight: FontWeight.bold,
              )
            ),
            subtitle: Column(
              children: tabsSelection.keys.map((tab) {
                return CheckboxListTile(
                  title: Text(tab),
                  value: tabsSelection[tab],
                  onChanged: (bool? value) {
                    setState(() {
                      tabsSelection[tab] = value!;
                    });
                  },
                );
              }).toList(),
            ),
          ),
          ListTile(
            title: Text(
              'Last Check',
              style: TextStyle(
                color: theme.selectedTheme.textTheme.titleMedium?.color,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              fp.trackerLastCheckedAt?.toString() ?? 'Never',
            ),
          ),
          ElevatedButton(
            onPressed: _saveSettings,
            child: Text(
              'Save Settings',
              style: TextStyle(
                color: theme.selectedTheme.textTheme.titleMedium?.color,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                fontWeight: FontWeight.bold,
              )
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: runningNow ? null : _runNow,
            icon: runningNow
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('Check Now'),
          ),
        ],
      )),
    );
  }
}
