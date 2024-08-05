import 'package:flutter/material.dart';

class ThemePreviewWidgets extends StatelessWidget {
  final ThemeData themeData;
  final String themeName;
  final VoidCallback onTap;

  const ThemePreviewWidgets({
    required this.themeData,
    required this.themeName,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100.0,
        height: 200.0,
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: themeData.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: themeData.primaryColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              themeName,
              style: themeData.textTheme.headlineSmall?.copyWith(
                color: themeData.textTheme.titleMedium?.color,
              ),
            ),
            const SizedBox(height: 10.0),
            
            Container(
              height: 100.0,
              color: themeData.scaffoldBackgroundColor,
              child: Center(
                child: Text(
                  'Home Screen Preview', 
                  style: themeData.textTheme.bodySmall?.copyWith(
                    color: themeData.textTheme.displayMedium?.color
                  )
                ),
              ),
            )
          ],
        )
      )
    );
  }
  
}