import 'package:flutter/material.dart';

class Appthemes {
  static final ThemeData purpleForest = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Color.fromARGB(29, 60, 16, 180),
    scaffoldBackgroundColor: Colors.black,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Color.fromARGB(29, 60, 16, 180),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Color.fromARGB(50, 60, 16, 180),
    ),
    useMaterial3: true,
     textTheme: TextTheme(

      displayMedium: TextStyle(color: Colors.grey),
      displaySmall: TextStyle(color: Colors.grey),
      titleMedium: TextStyle(color: Color.fromARGB(255, 17, 82, 19)),
      titleSmall: TextStyle(color: Colors.white),
    ),
    
  );

  static final ThemeData deepOcean = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.blue.shade900,
    scaffoldBackgroundColor: Colors.black,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue.shade900,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.blue.shade800,
    ),
    useMaterial3: true,
     textTheme: TextTheme(
      displayMedium: TextStyle(color: Colors.grey),
      displaySmall: TextStyle(color: Colors.grey),
      titleMedium: TextStyle(color: Color.fromARGB(255, 17, 82, 19)),
      titleSmall: TextStyle(color: Colors.white),
    )
  );

  static final ThemeData redRiver = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.red.shade900,
    scaffoldBackgroundColor: Colors.black,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.red.shade900,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.red.shade800,
    ),
    useMaterial3: true,
    textTheme: TextTheme(
      displayMedium: TextStyle(color: Colors.grey),
      displaySmall: TextStyle(color: Colors.grey),
      titleMedium: TextStyle(color: Color.fromARGB(255, 17, 82, 19)),
      titleSmall: TextStyle(color: Colors.white),
    )
  );

  static final ThemeData grayCity = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.grey.shade900,
    scaffoldBackgroundColor: Colors.black,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey.shade900,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.grey.shade800,
    ),
    useMaterial3: true,
    textTheme: TextTheme(
      displayMedium: TextStyle(color: Colors.grey),
      displaySmall: TextStyle(color: Colors.grey),
      titleMedium: TextStyle(color: Color.fromARGB(255, 17, 82, 19)),
      titleSmall: TextStyle(color: Colors.white),
    )
  );

  static final heavensDay = ThemeData(
    brightness: Brightness.light,
    primaryColor: Colors.lightBlue.shade100,
    scaffoldBackgroundColor: Colors.white,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.lightBlue.shade100,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.lightBlue.shade200,
    ),
    useMaterial3: true,
    textTheme: TextTheme(
      displayMedium: TextStyle(color: Color.fromARGB(255, 24, 22, 22)),
      displaySmall: TextStyle(color: Color.fromARGB(255, 24, 22, 22)),
      titleMedium: TextStyle(color: Color.fromARGB(255, 19, 226, 26)),
      titleSmall: TextStyle(color: Color.fromARGB(255, 4, 68, 163)),
    )
  );

  static final ThemeData sunsLight = ThemeData(
    brightness: Brightness.light,
    primaryColor: Colors.yellow.shade100,
    scaffoldBackgroundColor: Colors.white,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.yellow.shade100,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.yellow.shade200,
    ),
    useMaterial3: true,
    textTheme: TextTheme(
      displayMedium: TextStyle(color: Color.fromARGB(255, 24, 22, 22)),
      displaySmall: TextStyle(color: Color.fromARGB(255, 24, 22, 22)),
      titleMedium: TextStyle(color: Color.fromARGB(255, 19, 226, 26)),
      titleSmall: TextStyle(color: Colors.black),
    )
  );

  static final ThemeData frozenLake = ThemeData(
    brightness: Brightness.light,
    primaryColor: Colors.blue.shade100,
    scaffoldBackgroundColor: Colors.white,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue.shade100,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.blue.shade200,
    ),
    useMaterial3: true,
    textTheme: TextTheme(
      displayMedium: TextStyle(color: Color.fromARGB(255, 24, 22, 22)),
      displaySmall: TextStyle(color: Color.fromARGB(255, 24, 22, 22)),
      titleMedium: TextStyle(color: Color.fromARGB(255, 1, 255, 10)),
      titleSmall: TextStyle(color: Color.fromARGB(255, 4, 68, 163)),
    )
  );
}