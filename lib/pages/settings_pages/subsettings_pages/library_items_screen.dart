import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';

enum _TrackedLibrary { manga, anime }

class LibraryItemsSettingsScreen extends StatefulWidget {
  const LibraryItemsSettingsScreen({super.key});

  @override
  State<LibraryItemsSettingsScreen> createState() =>
      _LibraryItemsSettingsScreenState();
}

class _LibraryItemsSettingsScreenState
    extends State<LibraryItemsSettingsScreen> {
  static const List<int> _updateIntervalHours = [2, 5, 12, 24];
  int _selectedUpdateIntervalHours = 2;
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
    _selectedUpdateIntervalHours =
        _updateIntervalHours.contains(hours) ? hours : 24;
  }

  void _saveSettings() {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final animeProvider = context.read<AnimeLibraryController>();

    final interval = Duration(hours: _selectedUpdateIntervalHours);
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
      final hours = interval.inHours;
      _selectedUpdateIntervalHours =
          _updateIntervalHours.contains(hours) ? hours : 24;
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
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.trackerCompletedUpdates(
              _library == _TrackedLibrary.manga
                  ? l10n.libraryTabManga
                  : l10n.libraryTabAnime,
              changes,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trackerRunFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => runningNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(l10n.libraryItemsSettingsTitle,
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
                segments: [
                  ButtonSegment(
                    value: _TrackedLibrary.manga,
                    label: Text(l10n.libraryTabManga),
                  ),
                  ButtonSegment(
                    value: _TrackedLibrary.anime,
                    label: Text(l10n.libraryTabAnime),
                  ),
                ],
                selected: {_library},
                onSelectionChanged: (value) => _selectLibrary(value.first),
              ),
            ),
            SwitchListTile(
              title: Text(
                _library == _TrackedLibrary.manga
                    ? l10n.enableChapterTracker
                    : l10n.enableEpisodeTracker,
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
              title: Text(l10n.updateInterval,
                  style: TextStyle(
                    color: theme.selectedTheme.textTheme.titleMedium?.color,
                    fontSize:
                        MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                    fontWeight: FontWeight.bold,
                  )),
              subtitle: DropdownButton<int>(
                value: _selectedUpdateIntervalHours,
                items: _updateIntervalHours.map((int hours) {
                  return DropdownMenuItem<int>(
                    value: hours,
                    child: Text(l10n.hoursCount(hours)),
                  );
                }).toList(),
                onChanged: (int? value) {
                  if (value == null) return;
                  setState(() {
                    _selectedUpdateIntervalHours = value;
                  });
                },
              ),
            ),
            ListTile(
              title: Text(l10n.tabsToUpdate,
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
                l10n.lastCheck,
                style: TextStyle(
                  color: theme.selectedTheme.textTheme.titleMedium?.color,
                  fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                lastCheck?.toString() ?? l10n.never,
              ),
            ),
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text(l10n.saveSettings,
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
              label: Text(l10n.checkNow),
            ),
          ],
        );
      }),
    );
  }
}
