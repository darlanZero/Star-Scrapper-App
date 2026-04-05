import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class Fonte {
  final String image;
  final String name;
  final String languagePrefix;
  List<String> flags;
  final Scrapper api;
  bool isActive = false;
  bool isRRated = false;
  bool isOutdated = false;

  Fonte({
    required this.image,
    required this.name,
    required this.languagePrefix,
    required this.flags,
    required this.api,
    this.isActive = false,
    this.isRRated = false,
    this.isOutdated = false,
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
 
  List<LanguageGroup> languageGroups = [];


  Widget _buildOutdatedDummy(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.public_off_rounded,
        size: size * 0.75,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildSafeFontIcon(Fonte font, {double size = 25}) {
    final status = Provider.of<FontProvider>(context, listen: false)
        .getFontHostStatus(font.name);
    if (status == FontHostStatus.outdated) return _buildOutdatedDummy(size);

    return Image.network(
      font.image,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _buildOutdatedDummy(size),
    );
  }

  Widget _buildStatusBadge(Fonte font) {
    final status = Provider.of<FontProvider>(context, listen: false)
        .getFontHostStatus(font.name);
    String label;
    Color color;
    switch (status) {
      case FontHostStatus.online:
        label = 'ONLINE';
        color = Colors.green;
        break;
      case FontHostStatus.outdated:
        label = 'OUTDATED';
        color = Colors.redAccent;
        break;
      case FontHostStatus.checking:
        label = 'CHECKING';
        color = Colors.orangeAccent;
        break;
      case FontHostStatus.unknown:
        label = 'UNKNOWN';
        color = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

List<Fonte> ActiveFonts = [];
List<Fonte> InactiveFonts = [];

  @override
  void initState() {
    super.initState();
    loadFontState();
  }

  List<Fonte> get fonts => Provider.of<FontProvider>(context, listen: false).fonts;

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
    return Consumer<FontProvider>(builder: (context, _, __) {
      return Card(  
        color: Color(0xFF262335),
        margin: EdgeInsets.all(8.0),
        elevation: 4.0,
        borderOnForeground: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
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
      leading: _buildSafeFontIcon(font, size: 25),  
      title: Center(  
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(  
                font.name,  
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
            const SizedBox(width: 8),
            _buildStatusBadge(font),
          ],
        ),  
      ),  
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            font.isRRated ? Icons.remove_red_eye : Icons.remove_red_eye_outlined,
            color: font.isRRated ? Colors.red : Colors.green,
          ),
          IconButton(  
            icon: Icon(  
              isActive ? Icons.toggle_on : Icons.toggle_off,  
              color: isActive ? Colors.green : Colors.red,  
            ),  
            onPressed: () => toggleFontState(font),  
          ),
        ],
      ),  
    );  
  }
}
