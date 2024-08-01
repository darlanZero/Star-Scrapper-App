import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:star_scrapper_app/components/UI/about_application_card_component.dart';
import 'package:http/http.dart' as http;

class AboutApplicationScreen extends StatelessWidget {
  const AboutApplicationScreen({Key? key}) : super(key: key);

  Future<void> _checkForUpdates(BuildContext context) async {
    final url = 'https://api.github.com/repos/darlanZero/Star-Scrapper-App/releases';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final latestRelease = data[0];
          final versionName = latestRelease['name'];
          final downloadUrl = latestRelease['assets'][0]['browser_download_url'];

          _showUpdateDialog(context, versionName, downloadUrl);
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
              onPressed: () {
                http.get(Uri.parse(downloadUrl));
                Navigator.of(context).pop();
              },
              child: const Text('Update now'),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'About StarsScrapper', 
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),

            aboutApplicationCardComponent(),
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