import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/locale/locale_provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/config/themes.dart';
import 'package:star_scrapper_app/components/UI/theme_preview_widgets.dart';
import 'package:star_scrapper_app/components/Shared/settings_nav_item.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/fonts_hosts_settings_screen.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/library_settings_screen.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/playback_settings_screen.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider?>(context);
    final selectedTheme = theme.selectedTheme;
    final themes = [
      (name: 'Purple Forest', data: Appthemes.purpleForest),
      (name: 'Deep Ocean', data: Appthemes.deepOcean),
      (name: 'Red River', data: Appthemes.redRiver),
      (name: 'Gray City', data: Appthemes.grayCity),
      (name: 'Heaven\'s Day', data: Appthemes.heavensDay),
      (name: 'Sun\'s Light', data: Appthemes.sunsLight),
      (name: 'Frozen Lake', data: Appthemes.frozenLake),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.generalTitle,
                textAlign: TextAlign.center,
                style: selectedTheme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              SettingsNavItem(
                icon: Icons.local_library_outlined,
                label: l10n.generalLibraryTitle,
                description: l10n.generalLibraryDesc,
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LibrarySettingsScreen()),
                ),
              ),
              const SizedBox(height: 10),
              SettingsNavItem(
                icon: Icons.cloud_sync_outlined,
                label: l10n.generalSourcesTitle,
                description: l10n.generalSourcesDesc,
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FontsHostsSettingsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SettingsNavItem(
                icon: Icons.ondemand_video_rounded,
                label: l10n.generalPlaybackTitle,
                description: l10n.generalPlaybackDesc,
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlaybackSettingsScreen(),
                  ),
                ),
              ),
              if (localeProvider != null) ...[
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: Text(l10n.languageSectionTitle),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: localeProvider.localeTag,
                        onChanged: (value) {
                          if (value != null) {
                            localeProvider.setLocaleTag(value);
                          }
                        },
                        items: [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text(l10n.languageSystemDefault),
                          ),
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(l10n.languageEnglish),
                          ),
                          DropdownMenuItem(
                            value: 'pt_BR',
                            child: Text(l10n.languagePortugueseBrazil),
                          ),
                          DropdownMenuItem(
                            value: 'es',
                            child: Text(l10n.languageSpanish),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 30),
              Text(
                l10n.appearanceTitle,
                textAlign: TextAlign.center,
                style: selectedTheme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: themes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width >= 720 ? 3 : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.28,
                ),
                itemBuilder: (context, index) {
                  final option = themes[index];
                  return ThemePreviewWidgets(
                    themeData: option.data,
                    themeName: option.name,
                    isSelected: identical(selectedTheme, option.data),
                    onTap: () => theme.setSelectedTheme(option.data),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
