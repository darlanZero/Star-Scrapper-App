import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';

class FontProvider with ChangeNotifier {
  List<Fonte> _fonts = [
    Fonte(
      image: 'https://mangadex.org/img/brand/mangadex-logo.svg',
      name: 'Mangadex',
      languagePrefix: 'All',
      flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
      isActive: false,
      api: MangadexScrapper(),
      isRRated: true,
    ),
    // Add more fonts here
  ];

  List<Map<String, dynamic>> _favoritedBooks = [];
  String? _selectedChapterId;

  FontProvider() {
    _loadFonts();
    _loadFavoritedBooks();
    notifyListeners();
  }

  List<Fonte> get fonts => _fonts;
  List<Map<String, dynamic>> get favoritedBooks => _favoritedBooks;

  Fonte get selectedFont => _fonts.firstWhere((font) => font.isActive, orElse: () => _fonts.first);

  dynamic get selectedFontApi => selectedFont.api;

  String? get selectedChapterId => _selectedChapterId;

  void toggleFontState(Fonte font) {
    font.isActive = !font.isActive;
    _saveFonts();
    notifyListeners();
  }

  void toggleFavorite(Map<String, dynamic> book, BuildContext context) {  
    final index = _favoritedBooks.indexWhere((favorited) => favorited['id'] == book['id']);  
    final isFavorited = index != -1;  
    if (isFavorited) {  
      _favoritedBooks.remove(book);  
    } else {  
      addBookToTab('Reading', book, context);  
    }  
    _saveFavoritedBooks();  
    notifyListeners();  
  }

  bool isFavorited(Map<String, dynamic> book) {
    return _favoritedBooks.any((favorited) => favorited['id'] == book['id']);
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

  // Favorited Books
  void _loadFavoritedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritedBooks = prefs.getStringList('favoritedBooks') ?? [];
    _favoritedBooks = favoritedBooks.map((book) {
      try {
        return jsonDecode(book) as Map<String, dynamic>?;
      } catch (e) {
        return null;
      }
    }).where((book) => book != null).cast<Map<String, dynamic>>().toList();
    notifyListeners();
  }

  void _saveFavoritedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritedBooks = _favoritedBooks.map((book) => jsonEncode(book)).toList();
    prefs.setStringList('favoritedBooks', favoritedBooks);
  }

  Future<void> loadSelectedChapterId() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedChapterId = prefs.getString('selectedChapterId');
    notifyListeners();
  }

  Future<void> saveSelectedChapterId(String chapterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedChapterId', chapterId);
    _selectedChapterId = chapterId;
    notifyListeners();
  }

  // Books tabs
  List<Map<String, dynamic>> getBooksInTab(String tabName, BuildContext context) {  
    final tabsState = Provider.of<TabsState>(context, listen: false);  
    if (tabsState.libraryTabs.contains(tabName)) {  
      return _favoritedBooks.where((book) => book['tab'] == tabName).toList();  
    }  
    return [];  
  }

  void addBookToTab(String tabName, Map<String, dynamic> book, BuildContext context) {  
    final tabsState = Provider.of<TabsState>(context, listen: false);  
    if (tabsState.libraryTabs.contains('Reading')) {  
      book['tab'] = 'Reading';  
    } else if (tabsState.libraryTabs.isNotEmpty) {  
      book['tab'] = tabsState.libraryTabs.first;  
    } else {  
      // Se não houver tabs disponíveis, não adicione o livro  
      return;  
    }  

    if (!_favoritedBooks.contains(book)) {  
      _favoritedBooks.add(book);  
    }  
    _saveFavoritedBooks();  
    notifyListeners();  
  }

  void renameTabBooks(String oldName, String newName, BuildContext context) {
    for (var book in _favoritedBooks) {
      if (book['tab'] == oldName) {
        book['tab'] = newName;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void removeBookFromTab(String tabName, Map<String, dynamic> book, BuildContext context) {
    final tabsState = Provider.of<TabsState>(context, listen: false);
    
    if (tabName == 'Reading' || tabsState.libraryTabs.contains(tabName)) {
      _favoritedBooks.remove(book);
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void moveBookInTab(String oldTabName, String newTabName, Map<String, dynamic> book, BuildContext context) {
    removeBookFromTab(oldTabName, book, context);
    addBookToTab(newTabName, book, context);
  }

  void remapBooksFromRemovedTab(String removedTab, String defaultTab) {  
    final booksToMove = _favoritedBooks.where((book) => book['tab'] == removedTab).toList();  
    for (var book in booksToMove) {  
      book['tab'] = defaultTab;  
    }  
    _saveFavoritedBooks();  
    notifyListeners();  
  }
}