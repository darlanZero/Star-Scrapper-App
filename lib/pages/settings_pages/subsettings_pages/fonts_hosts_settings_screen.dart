import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/source_badge.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';

class FontsHostsSettingsScreen extends StatefulWidget {
  const FontsHostsSettingsScreen({super.key});

  @override
  State<FontsHostsSettingsScreen> createState() =>
      _FontsHostsSettingsScreenState();
}

class _FontsHostsSettingsScreenState extends State<FontsHostsSettingsScreen> {
  bool _running = false;

  static const List<int> _intervalMinutes = [15, 30, 60, 180, 360, 720, 1440];

  String _labelFromMinutes(AppLocalizations l10n, int minutes) {
    if (minutes < 60) return l10n.minutesShort(minutes);
    final h = minutes ~/ 60;
    return l10n.hoursShort(h);
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      await Provider.of<FontProvider>(context, listen: false)
          .checkAllFontsHostsNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.hostsCheckedSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.hostsCheckFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _running = false);
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
        title: Text(l10n.sourceHostMonitorTitle),
        centerTitle: true,
        elevation: 0,
      ),
      body: Consumer<FontProvider>(
        builder: (context, fontProvider, _) {
          final currentMinutes = fontProvider.fontHostCheckInterval.inMinutes;
          final intervalValue =
              _intervalMinutes.contains(currentMinutes) ? currentMinutes : 360;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                value: fontProvider.fontHostAutoCheckEnabled,
                onChanged: fontProvider.setFontHostAutoCheckEnabled,
                title: Text(l10n.automaticHostChecks),
                subtitle: Text(l10n.automaticHostChecksDesc),
              ),
              ListTile(
                title: Text(l10n.autoCheckInterval),
                subtitle: DropdownButton<int>(
                  value: intervalValue,
                  items: _intervalMinutes
                      .map(
                        (m) => DropdownMenuItem<int>(
                          value: m,
                          child: Text(_labelFromMinutes(l10n, m)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    fontProvider
                        .setFontHostCheckInterval(Duration(minutes: value));
                  },
                ),
              ),
              ListTile(
                title: Text(l10n.lastCheck),
                subtitle: Text(
                  fontProvider.fontHostLastCheckedAt?.toString() ?? l10n.never,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _running ? null : _runNow,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_rounded),
                label: Text(l10n.checkNow),
              ),
              const SizedBox(height: 16),
              for (final type in SourceContentType.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    type == SourceContentType.manga
                        ? l10n.mangaSources
                        : l10n.animeSources,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                ...fontProvider.sourceHealthEntries
                    .where((entry) => entry.contentType == type)
                    .map((entry) {
                  final status = fontProvider.getSourceHostStatus(entry.id);
                  Color statusColor;
                  String statusText;
                  switch (status) {
                    case FontHostStatus.online:
                      statusColor = Colors.green;
                      statusText = l10n.hostStatusOnline;
                      break;
                    case FontHostStatus.outdated:
                      statusColor = Colors.redAccent;
                      statusText = l10n.hostStatusOutdated;
                      break;
                    case FontHostStatus.checking:
                      statusColor = Colors.orangeAccent;
                      statusText = l10n.hostStatusChecking;
                      break;
                    case FontHostStatus.unknown:
                      statusColor = Colors.grey;
                      statusText = l10n.hostStatusUnknown;
                      break;
                  }
                  return ListTile(
                    leading: SourceBadge(
                      name: entry.name,
                      imageUri: entry.imageUri,
                      showLabel: false,
                    ),
                    title: Text(entry.name),
                    subtitle: Text(statusText),
                    trailing: Icon(Icons.circle, size: 10, color: statusColor),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
