import 'dart:convert';
import 'dart:io' show Platform;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/UI/about_application_card_component.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AboutApplicationScreen extends StatelessWidget {
  const AboutApplicationScreen({Key? key}) : super(key: key);

  Future<void> _checkForUpdates(BuildContext context) async {
    final url = 'https://api.github.com/repos/darlanZero/Star-Scrapper-App/releases';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> releases = jsonDecode(response.body);
        if (releases.isNotEmpty) {
          final latestRelease = releases[0];
          final versionName = latestRelease['tag_name'];
          final assets = latestRelease['assets'] as List;

          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          String currentVersionName = packageInfo.version;

          if (versionName != currentVersionName) {
            String? downloadUrl;
            if (Platform.isAndroid) {
              downloadUrl = assets.firstWhere((asset) => asset['name'].endsWith('.apk'), orElse: () => null)?['browser_download_url'];
            } else if (Platform.isWindows) {
              downloadUrl = assets.firstWhere((asset) => asset['name'].endsWith('.exe'), orElse: () => null)?['browser_download_url'];
            }

            if (downloadUrl != null) {
              _showUpdateDialog(context, versionName, downloadUrl);
            } else {
              _showNoSuitableDownloadDialog(context);
            }
          } else {
            _showNoUpdateDialog(context);
          }

        } else {
          print('Failed to fetch updates. Status code: ${response.statusCode}');
        }
      }
    } catch (e) {
      _showErrorDialog(context);
    }
  }

  void _showUpdateDialog(BuildContext context, String versionName, String downloadUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update available'),
          content: Text('The version you are using is out of date. The latest version $versionName of the app is available. Do you want to update now?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                if (await canLaunchUrl(Uri.parse(downloadUrl))) {
                  await launchUrl(Uri.parse(downloadUrl));
                }
                Navigator.of(context).pop();
              },
              child: const Text('Update now'),
            ),
          ],
        );
      },
    );
  }

  void _showNoUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('No updates available'),
          content: const Text('You are using the latest version of the app.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showNoSuitableDownloadDialog (BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('No suitable download found'),
          content: const Text('No suitable download found for the current platform.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: const Text('Failed to fetch updates.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  } 

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'About StarsScrapper', 
              style: TextStyle(
                color: theme.selectedTheme.textTheme.titleSmall?.color,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),

            aboutApplicationCardComponent(),
            SizedBox(height: 20),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: Text(
                    'Our Socials',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(FontAwesomeIcons.github),
                      color: Colors.blue,
                      onPressed: () {
                        launchUrl(Uri.parse('https://github.com/darlanZero/Star-Scrapper-App'));
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.link_rounded),
                      color: Colors.purple,
                      onPressed: () {
                        launchUrl(Uri.parse('https://star-scrapper.com'));
                      },
                    ),
                  ]
                ),
              ],
            ),


            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _checkForUpdates(context);
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Check for updates'),
            ),
          ],
        ),
      ),
    );
  }
}