import 'package:flutter/material.dart';  
import 'package:provider/provider.dart';  
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
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

  Widget _buildFontTile(Fonte font) {  
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fontSize = isMobile ? 12.0 : 16.0;

    final popularButton = OutlinedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FontBooksGalleryScreen(
              initialView: 'popular',
              selectedFont: font,
            ),
          ),
        );
      },
      child: Text(
        'Popular',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          color: Colors.deepPurple.shade400,
        ),
      ),
    );

    final recentButton = OutlinedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FontBooksGalleryScreen(
              initialView: 'recent',
              selectedFont: font,
            ),
          ),
        );
      },
      child: Text(
        'Recent',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          color: Colors.deepPurple.shade400,
        ),
      ),
    );

    final pinButton = IconButton(
      icon: Icon(
        pinnedFonts.contains(font) ? Icons.push_pin : Icons.push_pin_outlined,
      ),
      onPressed: () => togglePinned(font),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: isMobile
            ? Column(
                children: [
                  Row(
                    children: [
                      _buildSafeFontIcon(font, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                font.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.green,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1.0, 1.0),
                                      blurRadius: 3.0,
                                      color: Color.fromARGB(255, 65, 62, 62),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildStatusBadge(font),
                          ],
                        ),
                      ),
                      pinButton,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: [popularButton, recentButton],
                  ),
                ],
              )
            : Row(
                children: [
                  _buildSafeFontIcon(font, size: 25),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            font.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: fontSize,
                              color: Colors.green,
                              shadows: const [
                                Shadow(
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 3.0,
                                  color: Color.fromARGB(255, 65, 62, 62),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(font),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  popularButton,
                  const SizedBox(width: 8),
                  recentButton,
                  const SizedBox(width: 8),
                  pinButton,
                ],
              ),
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
