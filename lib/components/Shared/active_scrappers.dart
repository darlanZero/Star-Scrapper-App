import 'package:flutter/material.dart';  
import 'package:flutter_svg/flutter_svg.dart';  
import 'package:provider/provider.dart';  
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';
import 'package:star_scrapper_app/pages/pages.dart';  

class ScrapperActiveFonts extends StatefulWidget {  
  const ScrapperActiveFonts({Key? key}) : super(key: key);  

  @override  
  State<ScrapperActiveFonts> createState() => _ScrapperActiveFontsState();  
}  

class _ScrapperActiveFontsState extends State<ScrapperActiveFonts> {  
  List<LanguageGroup> languageGroups = [];  
  List<Fonte> pinnedFonts = [];  

  @override  
  void initState() {  
    super.initState();  
    loadActiveFonts();  
  }  

  Future<void> loadActiveFonts() async {  
    final prefs = await SharedPreferences.getInstance();  
    final fontProvider = Provider.of<FontProvider>(context, listen: false);  
    fontProvider.fonts.forEach((font) {  
      font.isActive = prefs.getBool(font.name) ?? false;  
    });  

    setState(() {  
      var grouped = Map<String, List<Fonte>>();  
      for (var font in fontProvider.activeFonts) {  
        grouped.putIfAbsent(font.languagePrefix, () => []).add(font);  
      }  

      languageGroups = grouped.entries  
          .map((entry) => LanguageGroup(  
                languagePrefix: entry.key,  
                fonts: entry.value,  
              ))  
          .toList();  

      pinnedFonts = fontProvider.activeFonts  
          .where((font) => prefs.getBool('${font.name}_pinned') ?? false)  
          .toList();  
      pinnedFonts.sort((a, b) => a.name.compareTo(b.name));  
    });  
  }  

  Future<void> togglePinned(Fonte font) async {  
    final prefs = await SharedPreferences.getInstance();  
    final isPinned = !(prefs.getBool('${font.name}_pinned') ?? false);  
    await prefs.setBool('${font.name}_pinned', isPinned);  

    setState(() {  
      if (isPinned) {  
        pinnedFonts.add(font);  
        pinnedFonts.sort((a, b) => a.name.compareTo(b.name));  
      } else {  
        pinnedFonts.removeWhere((f) => f.name == font.name);  
      }  
    });  
  }  

  bool isSvgImage(String url) {  
    return url.toLowerCase().endsWith('.svg');  
  }  

  Widget _buildFontTile(Fonte font) {  
    return ListTile(  
      leading: Row(  
        mainAxisSize: MainAxisSize.min,  
        children: [  
          isSvgImage(font.image)  
              ? SvgPicture.network(font.image, width: 25, height: 25)  
              : Image.network(font.image, width: 25, height: 25),  
          SizedBox(width: 10),  
          Text(
            font.name, 
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12,
              color: Colors.green,
              shadows: const <Shadow>[  
                Shadow(  
                  offset: Offset(1.0, 1.0),  
                  blurRadius: 3.0,  
                  color: Color.fromARGB(255, 65, 62, 62),  
                ),
              ],  
            ) 
          ),  
        ],  
      ),  
      trailing: Row(  
        mainAxisSize: MainAxisSize.min,  
        children: [  
          OutlinedButton(  
            onPressed: () {  
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FontBooksGalleryScreen(
                    initialView: 'Popular',
                    selectedFont: font,
                  ),
                ),
              );
            },  
            child: Text(
              'Trending', 
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12,
                color: Colors.deepPurple.shade400,  
              )
            ),
              
          ),  
          SizedBox(width: 10),  
          OutlinedButton(  
            onPressed: () {  
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FontBooksGalleryScreen(
                    initialView: 'Recent',
                    selectedFont: font,
                  ),
                ),
              );
            },  
            child: Text(
              'Recents',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12, 
                color: Colors.deepPurple.shade400,  
              )
            ),  
          ),  
          SizedBox(width: 10),  
          IconButton(  
            icon: Icon(  
              pinnedFonts.contains(font) ? Icons.push_pin : Icons.push_pin_outlined,  
            ),  
            onPressed: () => togglePinned(font),  
          ),  
        ],  
      ),  
    );  
  }  

  @override  
  Widget build(BuildContext context) {  
    return Consumer<FontProvider>(  
      builder: (context, fontProvider, child) {  
        return ListView(  
          children: [  
            if (pinnedFonts.isNotEmpty) ...[  
              ExpansionTile(  
                title: Text(
                  'Pinned',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12,
                    color: Color.fromARGB(255, 204, 204, 204),  
                  )
                ),  
                children: pinnedFonts.map(_buildFontTile).toList(),
              ),  
            ],  
            ...languageGroups.map((group) => ExpansionTile(  
                  title: Text(
                    group.languagePrefix,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: MediaQuery.of(context).size.width >= 600 ? 16 : 12,
                      color: Color.fromARGB(255, 204, 204, 204),  
                    )
                  ),  
                  children: group.fonts  
                      .where((font) => !pinnedFonts.contains(font))  
                      .map(_buildFontTile)  
                      .toList(),  
                )),  
          ],  
        );  
      },  
    );  
  }  
}