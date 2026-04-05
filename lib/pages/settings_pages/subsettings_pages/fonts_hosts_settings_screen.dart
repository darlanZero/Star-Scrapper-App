import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class FontsHostsSettingsScreen extends StatefulWidget {
  const FontsHostsSettingsScreen({super.key});

  @override
  State<FontsHostsSettingsScreen> createState() => _FontsHostsSettingsScreenState();
}

class _FontsHostsSettingsScreenState extends State<FontsHostsSettingsScreen> {
  bool _running = false;

  static const List<int> _intervalMinutes = [15, 30, 60, 180, 360, 720, 1440];

  String _labelFromMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    return '$h h';
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      await Provider.of<FontProvider>(context, listen: false).checkAllFontsHostsNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hosts checked successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check hosts: $e')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: const Text('Fonts Host Monitor'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Consumer<FontProvider>(
        builder: (context, fontProvider, _) {
          final currentMinutes = fontProvider.fontHostCheckInterval.inMinutes;
          final intervalValue = _intervalMinutes.contains(currentMinutes)
              ? currentMinutes
              : 360;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                value: fontProvider.fontHostAutoCheckEnabled,
                onChanged: fontProvider.setFontHostAutoCheckEnabled,
                title: const Text('Automatic host checks'),
                subtitle: const Text('Detect if each source host is online/outdated'),
              ),
              ListTile(
                title: const Text('Auto-check interval'),
                subtitle: DropdownButton<int>(
                  value: intervalValue,
                  items: _intervalMinutes
                      .map(
                        (m) => DropdownMenuItem<int>(
                          value: m,
                          child: Text(_labelFromMinutes(m)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    fontProvider.setFontHostCheckInterval(Duration(minutes: value));
                  },
                ),
              ),
              ListTile(
                title: const Text('Last check'),
                subtitle: Text(fontProvider.fontHostLastCheckedAt?.toString() ?? 'Never'),
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
                label: const Text('Check now'),
              ),
              const SizedBox(height: 16),
              ...fontProvider.fonts.map((font) {
                final status = fontProvider.getFontHostStatus(font.name);
                Color statusColor;
                String statusText;
                switch (status) {
                  case FontHostStatus.online:
                    statusColor = Colors.green;
                    statusText = 'online';
                    break;
                  case FontHostStatus.outdated:
                    statusColor = Colors.redAccent;
                    statusText = 'outdated';
                    break;
                  case FontHostStatus.checking:
                    statusColor = Colors.orangeAccent;
                    statusText = 'checking';
                    break;
                  case FontHostStatus.unknown:
                    statusColor = Colors.grey;
                    statusText = 'unknown';
                    break;
                }
                return ListTile(
                  leading: Icon(Icons.circle, size: 10, color: statusColor),
                  title: Text(font.name),
                  subtitle: Text(statusText),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
