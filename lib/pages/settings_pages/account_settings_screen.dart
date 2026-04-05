import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/settings_nav_item.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/scrapper_logins_screen.dart';

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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Account Settings',
              style: theme.selectedTheme.textTheme.headlineMedium,
            ),
            SizedBox(height: 20),
            Text(
              'Manage your account information, security settings, and preferences.',
              style: theme.selectedTheme.textTheme.bodyMedium,
            ),
            SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: 
                [
                  SettingsNavItem(
                    icon: Icons.manage_accounts_outlined,
                    label: 'Scrapper Logins',
                    theme: theme,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ScrapperLoginsScreen()),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}