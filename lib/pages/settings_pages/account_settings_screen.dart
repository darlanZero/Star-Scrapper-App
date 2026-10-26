import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/settings_nav_item.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/scrapper_logins_screen.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/tracker_settings_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Account Settings',
                textAlign: TextAlign.center,
                style: theme.selectedTheme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 28),
              SettingsNavItem(
                icon: Icons.manage_accounts_outlined,
                label: 'Source logins',
                description:
                    'Sign in to sources that require an account, renew browser sessions, or disconnect stored source access.',
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ScrapperLoginsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SettingsNavItem(
                icon: Icons.sync_alt_rounded,
                label: 'Trackers',
                description:
                    'Connect and configure services such as AniList and MyAnimeList for Discover, progress, and library tracking.',
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TrackerSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
