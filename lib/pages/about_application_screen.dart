import 'package:flutter/material.dart';
import 'package:star_scrapper_app/components/UI/about_application_card_component.dart';

class AboutApplicationScreen extends StatelessWidget {
  const AboutApplicationScreen({Key? key}) : super(key: key);

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
          ],
        ),
      ),
    );
  }
}