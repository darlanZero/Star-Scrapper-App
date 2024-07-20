import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';

class Fonte {
  final String image;
  final String name;
  final String languagePrefix;
  List<String> flags;
  final api;
  bool isActive = false;

  Fonte({
    required this.image,
    required this.name,
    required this.languagePrefix,
    required this.flags,
    required this.api,
    this.isActive = false,
  });

  void toggleActive() {
    isActive = !isActive;
  }
}

class LanguageGroup {
  final String languagePrefix;
  final List<Fonte> fonts;

  LanguageGroup({
    required this.languagePrefix,
    required this.fonts,
  });
}

class ScrapperDownloaderFonts extends StatefulWidget {
  const ScrapperDownloaderFonts({Key? key}) : super(key: key);

  @override
  State<ScrapperDownloaderFonts> createState() => _ScrapperDownloaderFontsState();
}

class _ScrapperDownloaderFontsState extends State<ScrapperDownloaderFonts> {
  List<Fonte> fonts = [
    Fonte(
      image: 'https://mangadex.org/img/brand/mangadex-logo.svg', 
      name: 'Mangadex', 
      languagePrefix: 'All', 
      flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
      isActive: false,
      api: MangadexScrapper()
    ),
  ];
  List<LanguageGroup> languageGroups = [];

  bool isSvgImage(String url) {
    return url.toLowerCase().endsWith('.svg');
  }

List<Fonte> ActiveFonts = [];
List<Fonte> InactiveFonts = [];

  @override
  void initState() {
    super.initState();
    loadFontState();
  }

  Future<void> loadFontState() async {
    final prefs = await SharedPreferences.getInstance();
    for (var font in fonts) {
      font.isActive = prefs.getBool(font.name) ?? false;
    }
    updateFontLists();
  }

  var groupedFonts = {};
  var grouped = Map<String, List<Fonte>>();

  void updateFontLists() {
    

    setState(() {
      grouped.clear();
      for (var font in fonts) {
        grouped.putIfAbsent(font.languagePrefix, () => []).add(font);
      }
      languageGroups = grouped.entries.map((entry) => LanguageGroup(
        languagePrefix: entry.key,
        fonts: entry.value,
      )).toList();
    });
  }

  Future<void> toggleFontState(Fonte font) async {
    final prefs = await SharedPreferences.getInstance();
    font.toggleActive();
    prefs.setBool(font.name, font.isActive);
    updateFontLists();
  }

  @override  
  Widget build(BuildContext context) {  
    return Card(  
      color: Color(0xFF262335),  
      child: ListView(  
        padding: EdgeInsets.all(16.0),  
        scrollDirection: Axis.vertical,  
        physics: BouncingScrollPhysics(),  
        children: [  
          SizedBox(height: 10),  
          _buildFontSection('Active Fonts', true),  
          SizedBox(height: 10),  
          _buildFontSection('Inactive Fonts', false),  
        ],  
      ),  
    );  
  }  

  Widget _buildFontSection(String title, bool isActive) {  
    return Column(  
      children: [  
        Center(  
          child: Text(  
            title,  
            textAlign: TextAlign.center,  
            style: TextStyle(  
              color: Colors.white,  
              fontWeight: FontWeight.normal,  
              decoration: TextDecoration.underline,  
              fontSize: MediaQuery.of(context).size.width >= 600 ? 20 : 16,  
              decorationColor: isActive ? Colors.green : Colors.red,  
            ),  
          ),  
        ),  
        ...languageGroups.map((group) => ExpansionTile(  
          initiallyExpanded: group.languagePrefix == 'All',  
          shape: RoundedRectangleBorder(  
            borderRadius: BorderRadius.circular(10),  
          ),  
          title: Text(  
            group.languagePrefix,  
            style: TextStyle(  
              color: isActive ? Colors.lightGreenAccent : Colors.red,  
              fontWeight: FontWeight.normal,  
              fontSize: MediaQuery.of(context).size.width >= 600 ? 20 : 16,  
            ),  
          ),  
          children: group.fonts  
              .where((font) => font.isActive == isActive)  
              .map((font) => _buildFontTile(font, isActive))  
              .toList(),  
        )),  
      ],  
    );  
  }  

  Widget _buildFontTile(Fonte font, bool isActive) {  
    return ListTile(  
      leading: isSvgImage(font.image)  
          ? SvgPicture.network(font.image, width: 25, height: 25)  
          : Image.network(font.image, width: 25, height: 25),  
      title: Center(  
        child: Text(  
          font.name,  
          style: TextStyle(  
            color: isActive ? Colors.green : Colors.red,  
            decoration: isActive ? null : TextDecoration.lineThrough,  
            shadows: const <Shadow>[  
              Shadow(  
                offset: Offset(1.0, 1.0),  
                blurRadius: 3.0,  
                color: Color.fromARGB(255, 0, 0, 0),  
              ),  
            ],  
            fontSize: MediaQuery.of(context).size.width >= 600 ? 20 : 16,  
          ),  
        ),  
      ),  
      trailing: IconButton(  
        icon: Icon(  
          isActive ? Icons.toggle_on : Icons.toggle_off,  
          color: isActive ? Colors.green : Colors.red,  
        ),  
        onPressed: () => toggleFontState(font),  
      ),  
    );  
  }
}