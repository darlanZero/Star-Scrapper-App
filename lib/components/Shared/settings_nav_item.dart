import 'package:flutter/material.dart';
import 'package:star_scrapper_app/classes/app_state.dart';

class SettingsNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeProvider theme;
  final VoidCallback onTap;

  const SettingsNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            color: theme.selectedTheme.textTheme.displayMedium?.color,
            size: isWide ? 30 : 20,
          ),
          SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: isWide ? 16 : 12,
              fontWeight: FontWeight.bold,
              color: theme.selectedTheme.textTheme.displayMedium?.color,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 6),
          Icon(
            Icons.chevron_right,
            color: theme.selectedTheme.textTheme.displayMedium?.color,
            size: isWide ? 20 : 16,
          ),
        ],
      ),
    );
  }
}
