import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';

enum _TrackedLibrary { manga, anime }

class LibraryItemsSettingsScreen extends StatefulWidget {
  const LibraryItemsSettingsScreen({super.key});

  @override
  State<LibraryItemsSettingsScreen> createState() =>
      _LibraryItemsSettingsScreenState();
}

class _LibraryItemsSettingsScreenState
    extends State<LibraryItemsSettingsScreen> {
  final List<String> updateIntervals = [
    '2 hours',
    '5 hours',
    '12 hours',
    '24 hours'
  ];
  String selectedUpdateInterval = '2 hours';
  Map<String, bool> tabsSelection = {};
  bool trackerEnabled = true;
  bool runningNow = false;
  _TrackedLibrary _library = _TrackedLibrary.manga;

  @override
  void initState() {
    super.initState();
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final tabsState = Provider.of<TabsState>(context, listen: false);
    for (final tab in tabsState.libraryTabs) {
      tabsSelection[tab] = fontProvider.tabsToUpdate.contains(tab);
    }
    trackerEnabled = fontProvider.trackerEnabled;
    final hours = fontProvider.updateInterval.inHours;
    if (hours == 2) selectedUpdateInterval = '2 hours';
    if (hours == 5) selectedUpdateInterval = '5 hours';
    if (hours == 12) selectedUpdateInterval = '12 hours';
    if (hours == 24) selectedUpdateInterval = '24 hours';
  }

  void _saveSettings() {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final animeProvider = context.read<AnimeLibraryController>();

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
    if (_library == _TrackedLibrary.manga) {
      fontProvider.setUpdateInterval(interval);
    } else {
      animeProvider.setUpdateInterval(interval);
    }

    Set<String> selectedTabs = tabsSelection.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();

    if (_library == _TrackedLibrary.manga) {
      fontProvider.setTabsToUpdate(selectedTabs);
    } else {
      animeProvider.setTabsToUpdate(selectedTabs);
    }
  }

  void _selectLibrary(_TrackedLibrary value) {
    final fp = context.read<FontProvider>();
    final anime = context.read<AnimeLibraryController>();
    final tabs = value == _TrackedLibrary.manga
        ? context.read<TabsState>().libraryTabs
        : context.read<AnimeTabsState>().libraryTabs;
    final selected =
        value == _TrackedLibrary.manga ? fp.tabsToUpdate : anime.tabsToUpdate;
    final interval = value == _TrackedLibrary.manga
        ? fp.updateInterval
        : anime.updateInterval;
    setState(() {
      _library = value;
      tabsSelection = {for (final tab in tabs) tab: selected.contains(tab)};
      trackerEnabled = value == _TrackedLibrary.manga
          ? fp.trackerEnabled
          : anime.trackerEnabled;
      selectedUpdateInterval = '${interval.inHours} hours';
    });
  }

  Future<void> _runNow() async {
    setState(() => runningNow = true);
    try {
      final changes = _library == _TrackedLibrary.manga
          ? await context.read<FontProvider>().runTrackerNow()
          : await context
              .read<AnimeLibraryController>()
              .runTrackerNow(notifyCompletion: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_library == _TrackedLibrary.manga ? 'Manga' : 'Anime'} '
            'tracker completed: $changes update(s).',
          ),
        ),
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
        title: Text("Library Items Settings",
            style: TextStyle(
              color: theme.selectedTheme.textTheme.titleLarge?.color,
              fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
              fontWeight: FontWeight.bold,
            )),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.teal[900]),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        iconTheme: IconThemeData(
            color: theme.selectedTheme.textTheme.titleMedium?.color),
      ),
      body: Consumer2<FontProvider, AnimeLibraryController>(
          builder: (context, fp, anime, _) {
        final activeEnabled = _library == _TrackedLibrary.manga
            ? fp.trackerEnabled
            : anime.trackerEnabled;
        final lastCheck = _library == _TrackedLibrary.manga
            ? fp.trackerLastCheckedAt
            : anime.trackerLastCheckedAt;
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<_TrackedLibrary>(
                segments: const [
                  ButtonSegment(
                    value: _TrackedLibrary.manga,
                    label: Text('Manga'),
                  ),
                  ButtonSegment(
                    value: _TrackedLibrary.anime,
                    label: Text('Anime'),
                  ),
                ],
                selected: {_library},
                onSelectionChanged: (value) => _selectLibrary(value.first),
              ),
            ),
            SwitchListTile(
              title: Text(
                _library == _TrackedLibrary.manga
                    ? 'Enable Chapter Tracker'
                    : 'Enable Episode Tracker',
                style: TextStyle(
                  color: theme.selectedTheme.textTheme.titleMedium?.color,
                  fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              value: activeEnabled,
              onChanged: (value) {
                setState(() => trackerEnabled = value);
                if (_library == _TrackedLibrary.manga) {
                  fp.setTrackerEnabled(value);
                } else {
                  anime.setTrackerEnabled(value);
                }
              },
            ),
            ListTile(
              title: Text('Update Interval',
                  style: TextStyle(
                    color: theme.selectedTheme.textTheme.titleMedium?.color,
                    fontSize:
                        MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                    fontWeight: FontWeight.bold,
                  )),
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
              title: Text('Tabs to Update',
                  style: TextStyle(
                    color: theme.selectedTheme.textTheme.titleMedium?.color,
                    fontSize:
                        MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                    fontWeight: FontWeight.bold,
                  )),
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
                lastCheck?.toString() ?? 'Never',
              ),
            ),
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text('Save Settings',
                  style: TextStyle(
                    color: theme.selectedTheme.textTheme.titleMedium?.color,
                    fontSize:
                        MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                    fontWeight: FontWeight.bold,
                  )),
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
        );
      }),
    );
  }
}
