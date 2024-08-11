// font_provider.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  List<Map<String, dynamic>> _favoritedBooks = [];

  FontProvider() {
    _loadFonts();
    _loadFavoritedBooks();
  }

  List<Fonte> get fonts => _fonts;
  List<Map<String, dynamic>> get favoritedBooks => _favoritedBooks;

  Fonte get selectedFont => _fonts.firstWhere((font) => font.isActive, orElse: () => _fonts.first);

  dynamic get selectedFontApi => selectedFont.api;

  void toggleFontState(Fonte font) {
    font.isActive = !font.isActive;
    _saveFonts();
    notifyListeners();
  }

  void toggleFavorite(Map<String, dynamic> book) {
    final isFavorited = _favoritedBooks.contains(book);
    if (isFavorited) {
      _favoritedBooks.remove(book);
    } else {
      _favoritedBooks.add(book);
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  bool isFavorited(Map<String, dynamic> book) {
    return _favoritedBooks.contains(book);
  }

  List<Fonte> get activeFonts => _fonts.where((font) => font.isActive).toList();
  List<Fonte> get inactiveFonts => _fonts.where((font) => !font.isActive).toList();

  void _loadFonts() async {
    final prefs = await SharedPreferences.getInstance();
    final activeFontNames = prefs.getStringList('activeFonts') ?? [];
    for (var font in _fonts) {
      font.isActive = activeFontNames.contains(font.name);
    }
    notifyListeners();
  }

  void _saveFonts() async {
    final prefs = await SharedPreferences.getInstance();
    final activeFontNames = _fonts.where((font) => font.isActive).map((font) => font.name).toList();
    prefs.setStringList('activeFonts', activeFontNames);
  }

  void _loadFavoritedBooks() async {
  final prefs = await SharedPreferences.getInstance();
  final favoritedBooks = prefs.getStringList('favoritedBooks') ?? [];
  _favoritedBooks = favoritedBooks.map((book) {
    try {
      return jsonDecode(book) as Map<String, dynamic>?;
    } catch (e) {
      return null; // ou você pode retornar um mapa vazio ou um valor padrão
    }
  }).where((book) => book != null).cast<Map<String, dynamic>>().toList();
  notifyListeners();
}

void _saveFavoritedBooks() async {
  final prefs = await SharedPreferences.getInstance();
  final favoritedBooks = _favoritedBooks.map((book) => jsonEncode(book)).toList();
  prefs.setStringList('favoritedBooks', favoritedBooks);
}
}
