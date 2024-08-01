import 'package:flutter/material.dart';

Widget aboutApplicationCardComponent() {
  return Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10.0),
    ),
    elevation: 10,
    margin: EdgeInsets.all(10),
    color: Color(0xFF262335),
    child: Column(
      children: [
        Image.asset(
          'lib/assets/starscrapper.png',
          width: 100,
          height: 100,
        ),
        Padding(
          padding: EdgeInsets.all(10),
          child: Column(children: [
            Text(
            'StarsScrapper is a Flutter application developed on purpose to help you keep track of your favorite books around the world, completely for free and without ads.',
              style: TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.lerp(FontWeight.bold, FontWeight.normal, 0.5),
                fontFamily: 'Roboto',
              ),
            ),

            Text(
              'However, this application still is on development, but you can favorite, read, and browse troubly many books and scrappers we have.',
              style: TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.lerp(FontWeight.bold, FontWeight.normal, 0.5),
                fontFamily: 'Roboto',
              ),
            ),

            Text(
              'None of this application is intended to be used for illegal purposes, and the content is not affiliated with the authors or publishers. The application is not affiliated with the authors or publishers.',
              style: TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.lerp(FontWeight.bold, FontWeight.normal, 0.5),
                fontFamily: 'Roboto',
              ),
            ),
          ],)
        ),
      ] 
    )
  );
}
