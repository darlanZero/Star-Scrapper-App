// font_provider.dart  
import 'package:flutter/material.dart';
import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';  
 

class FontProvider with ChangeNotifier {  
  List<Fonte> _fonts = [  
    Fonte(  
      image: 'https://mangadex.org/img/brand/mangadex-logo.svg',  
      name: 'Mangadex',  
      languagePrefix: 'All',  
      flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],  
      isActive: false,  
      api: MangadexScrapper()  
    ),  
    // Add more fonts here  
  ];  

  List<Fonte> get fonts => _fonts;

  get selectedFont => null;  

  void toggleFontState(Fonte font) {  
    font.isActive = !font.isActive;  
    notifyListeners();  
  }  

  List<Fonte> get activeFonts => _fonts.where((font) => font.isActive).toList();  

  List<Fonte> get inactiveFonts => _fonts.where((font) => !font.isActive).toList();  
}