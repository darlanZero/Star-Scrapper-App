import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/config/themes.dart';
import 'package:star_scrapper_app/components/UI/theme_preview_widgets.dart';
import 'package:star_scrapper_app/components/Shared/settings_nav_item.dart';
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
    final theme = Provider.of<ThemeProvider>(context);
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
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('General', style: selectedTheme.textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Customize your library and content sources.',
            style: selectedTheme.textTheme.bodyMedium?.copyWith(
              color: selectedTheme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          SettingsNavItem(
            icon: Icons.local_library_outlined,
            label: 'Library',
            theme: theme,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibrarySettingsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          SettingsNavItem(
            icon: Icons.cloud_sync_outlined,
            label: 'Sources',
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
            label: 'Video playback',
            theme: theme,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PlaybackSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text('Appearance', style: selectedTheme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Choose a palette. Layout and contrast stay consistent.',
            style: selectedTheme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: themes.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 720 ? 3 : 2,
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
    );
  }
}
