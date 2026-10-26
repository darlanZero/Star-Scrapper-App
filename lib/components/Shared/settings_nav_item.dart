import 'package:flutter/material.dart';
import 'package:star_scrapper_app/classes/app_state.dart';

class SettingsNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final ThemeProvider theme;
  final VoidCallback onTap;

  const SettingsNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    required this.theme,
    required this.onTap,
  });

  Future<void> _showDescription(BuildContext context) async {
    final details = description;
    if (details == null || details.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon),
        title: Text(label, textAlign: TextAlign.center),
        content: Text(details, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final colors = theme.selectedTheme.colorScheme;
    return Semantics(
      button: true,
      hint: description == null
          ? null
          : 'Open. Touch and hold for a short explanation.',
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress:
              description == null ? null : () => _showDescription(context),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 18 : 14,
              vertical: isWide ? 17 : 14,
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      icon,
                      color: colors.onPrimaryContainer,
                      size: isWide ? 26 : 21,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.selectedTheme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                  size: isWide ? 24 : 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
