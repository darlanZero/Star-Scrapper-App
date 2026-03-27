import 'dart:convert';

import 'package:cron/cron.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/pt-br/demon_sect_scrapper.dart';
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
    Fonte(
      image: 'https://seitacelestial.com/wp-content/uploads/2024/08/logo-extended.png', 
      name: 'Seita Celestial', 
      languagePrefix: 'Pt-BR', 
      flags: ['https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png'], 
      api: DemonSectScrapper(),
      isRRated: false,
    ),
    // Add more fonts here
  ];

  //Maps of books
  List<Map<String, dynamic>> _favoritedBooks = [];
  List<Map<String, dynamic>> _readBooks = [];
  Map<String, List<Map<String, String>>> _selectedChapterIds = {};
  Map<String, Map<String, String>> _lastReadedChapterId = {};

  //Tabs
  Duration _updateInterval = Duration(hours: 24);
  Set<String> _tabsToUpdate = {};
  Cron? _cron;
  late TabsState _tabsState;

  FontProvider(TabsState tabsState) {
    _tabsState = tabsState;
    _loadFonts();
    _loadFavoritedBooks();
    _loadReadBooks();

    _loadUpdateSettings();

    loadSelectedChapterId();
    loadLastReadedChapterId();

    notifyListeners();
  }

  void setTabsState(TabsState tabsState) {
    _tabsState = tabsState;
  }

  List<Fonte> get fonts => _fonts;
  List<Map<String, dynamic>> get favoritedBooks => _favoritedBooks;
  List<Map<String, dynamic>> get readBooks => _readBooks;
  Fonte get selectedFont => _fonts.firstWhere((font) => font.isActive, orElse: () => _fonts.first);
  dynamic get selectedFontApi => selectedFont.api;
  Map<String, List<Map<String, String>>> get selectedChapterIds => _selectedChapterIds;
  Map<String, Map<String, String>> get lastReadedChapterId => _lastReadedChapterId;

  Duration get updateInterval => _updateInterval;
  Set<String> get tabsToUpdate => _tabsToUpdate;

  void toggleFontState(Fonte font) {
    font.isActive = !font.isActive;
    _saveFonts();
    notifyListeners();
  }

  //update single book details
  Future<void> updateBookDetails(String bookId) async {
    final fontApi = selectedFontApi;

    Map<String, dynamic> updatedBookDetails = await fontApi.getBookDetails(bookId);

    if (updatedBookDetails != null) {
      List<Map<String, String>> readChapters = _selectedChapterIds[bookId] ?? [];

      int index = _favoritedBooks.indexWhere((book) => book['id'] == bookId);
      if (index != -1) {
        String currentTab = _favoritedBooks[index]['tab'] ?? 'Reading';
        updatedBookDetails['tab'] = currentTab;
        _favoritedBooks[index] = updatedBookDetails;
      }

      _selectedChapterIds[bookId] = readChapters;

      _saveFavoritedBooks();
      await saveSelectedChapterId(bookId, readChapters);

      notifyListeners();
    }
  }

  void setUpdateInterval(Duration interval) {
    _updateInterval = interval;
    _scheduleAutomaticUpdates();
    _saveUpdateSettings();
    notifyListeners();
  }

  String _getCronExpression(Duration interval) {
    if (interval.inHours == 24) {
      return '0 0 * * *';
    } else {
      return '0 */${interval.inHours} * * *';
    }
  }

  void _scheduleAutomaticUpdates() {
    _cron?.close();

    _cron = Cron();
    final cronExp = _getCronExpression(_updateInterval);
    try {
      _cron!.schedule(Schedule.parse(cronExp), () async {
        await _updateLibraryBooks();
      });
    } catch (e) {
      print('Error scheduling automatic updates: $e');
    }
  }

  void setTabsToUpdate(Set<String> tabs) {
    _tabsToUpdate = tabs;
    notifyListeners();
  }

  void _saveUpdateSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('updateIntervalHours', _updateInterval.inHours);
    prefs.setStringList('tabsToUpdate', _tabsToUpdate.toList());
  }

  void _clearUpdateSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('updateIntervalHours');
    await prefs.remove('tabsToUpdate');
  }

  void _loadUpdateSettings() async {
    final prefs = await SharedPreferences.getInstance();

    int hours = prefs.getInt('updateIntervalHours') ?? 24;
    _updateInterval = Duration(hours: hours);
    List<String> tabs = prefs.getStringList('tabsToUpdate') ?? [];
    _tabsToUpdate = Set.from(tabs);

    _scheduleAutomaticUpdates();
    notifyListeners();
  }

  void setBooksInTab(String tab, List<Map<String, dynamic>> books) {
    for (var book in books) {
      book['tab'] = tab;
    }
    _favoritedBooks.removeWhere((book) => book['tab'] == tab);
    _favoritedBooks.addAll(books);
    _saveFavoritedBooks();
    notifyListeners();
  }

  void updateBookInTab(String tab, Map<String, dynamic> updatedBook) {
    List<Map<String, dynamic>> booksInTab = getBooksInTab(tab);
    int index = booksInTab.indexWhere((book) => book['id'] == updatedBook['id']);
    if (index != -1) {
      booksInTab[index] = updatedBook;
      setBooksInTab(tab, booksInTab);
    }
  }

  Future<void> _showUpdatedNotification(List<Map<String, dynamic>> updatedBooks) async {
    if (updatedBooks.isEmpty) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'books_updates_channel',
      'Books Updates',
      importance: Importance.max,
      priority: Priority.high,
      channelDescription: 'Channel for books updates',
      showWhen: false,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    String bookTitles = updatedBooks.map((book) => book['title']).join(', ');

    await FlutterLocalNotificationsPlugin().show(
      0,
      'Books Updated',
      'The following books have been updated: $bookTitles',
      platformChannelSpecifics,
      payload: jsonEncode(updatedBooks),
    );
  }

  Future<void> _updateLibraryBooks() async {
    List<Map<String, dynamic>> allUpdatedBooks = [];

    for (String tab in _tabsToUpdate) {
      List<Map<String, dynamic>> booksInTab = getBooksInTab(tab);

      for (var book in booksInTab) {
        String bookId = book['id'];

        List<Map<String, String>> readChapters = _selectedChapterIds[bookId] ?? [];
        Map<String, dynamic> updatedBookDetails = await selectedFontApi.getBookDetails(bookId);

        if (updatedBookDetails != null) {
          updateBookInTab(tab, updatedBookDetails);
          _selectedChapterIds[bookId] = readChapters;
          await saveSelectedChapterId(bookId, readChapters);

          allUpdatedBooks.add(updatedBookDetails);
        }
      }
    }

    if (allUpdatedBooks.isNotEmpty) {
      await _showUpdatedNotification(allUpdatedBooks);
    }
    notifyListeners();
  }

  //General Functions

  void toggleFavorite(Map<String, dynamic> book) {
    final index = _favoritedBooks.indexWhere((favorited) => favorited['id'] == book['id']);
    final isFavorited = index != -1;
    if (isFavorited) {
      _favoritedBooks.remove(book);
    } else {
      addBookToTab('Reading', book);
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
        final decodedBook = jsonDecode(book);
        if (decodedBook is  Map<String, dynamic>) {
          return decodedBook;
        } else {
          return null;
        }
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

  void clearSelectedChapterIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedChapterIds');
  }

  Future<Map<String, List<Map<String, String>>>> loadSelectedChapterId() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedChapterIdsString = prefs.getString('selectedChapterIds') ?? '{}';
    final Map<String, dynamic> selectedChapterIds = jsonDecode(selectedChapterIdsString);

    _selectedChapterIds = selectedChapterIds.map((key, value) {
      if (value is List) {
        return MapEntry(
          key,
          value.map<Map<String, String>>((item) {
            return Map<String, String>.from(item as Map);
          }).toList(),
        );
      } else {
        return MapEntry(key, <Map<String, String>>[]);
      }
    });

    notifyListeners();
    return _selectedChapterIds;
  }

  Future<void> saveSelectedChapterId(String bookId, List<Map<String, String>> chapters) async {
    final prefs = await SharedPreferences.getInstance();
    _selectedChapterIds[bookId] = chapters;
    await prefs.setString('selectedChapterIds', jsonEncode(_selectedChapterIds)); 
    notifyListeners();
  }

  SaveSingleSelectedChapterId(String bookId,String chapterId, String chapterTitle) async {
    _selectedChapterIds[bookId] ??= [];
   bool chapterExists = _selectedChapterIds[bookId]!.any((chapter) => chapter['id'] == chapterId);

    if (!chapterExists) {
      _selectedChapterIds[bookId]!.add({'id': chapterId, 'title': chapterTitle});
      await saveSelectedChapterId(bookId, _selectedChapterIds[bookId]!);

      await saveLastReadedChapterId();
    }
  }

  //Readed books

  void _loadReadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final readBooks = prefs.getStringList('readBooks') ?? [];
    _readBooks = readBooks.map((book) {
      try {
        return jsonDecode(book) as Map<String, dynamic>;
      } catch (e) {
        return null;
      }
    }).where((book) => book != null).cast<Map<String, dynamic>>().toList();
    notifyListeners();
  }

  void _saveReadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final readBooks = _readBooks.map((book) => jsonEncode(book)).toList();
    prefs.setStringList('readBooks', readBooks);
  }

  void addBookToReadBooks(Map<String, dynamic> book) {
    if (!_readBooks.any((b) => b['id'] == book['id'])) {
      _readBooks.add(book);
      _saveReadBooks();
      notifyListeners();
    }
  }

  void clearLastReadedChapterId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastReadedChapterId');
  }

  Future<void> saveLastReadedChapterId() async {
    _lastReadedChapterId = {};
    final prefs = await SharedPreferences.getInstance();
    _selectedChapterIds.forEach((bookId, chapters) {
      if (chapters.isNotEmpty) {
        final lastChapter = chapters.last;
        _lastReadedChapterId[bookId] = {
          'id': lastChapter['id']!,
          'title': lastChapter['title']!,
        };
      }
    });
    await prefs.setString('lastReadedChapterId', jsonEncode(_lastReadedChapterId));

    notifyListeners();
  }

  Future<Map<String, Map<String, String>>> loadLastReadedChapterId() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReadedChapterIdString = prefs.getString('lastReadedChapterId') ?? '{}';
    final Map<String, dynamic> decodedData = jsonDecode(lastReadedChapterIdString);

    _lastReadedChapterId = decodedData.map((key, value) {
      return MapEntry(key, Map<String, String>.from(value as Map));
    });
    notifyListeners();
    return _lastReadedChapterId;
  }

  // Books tabs
  List<Map<String, dynamic>> getBooksInTab(String tabName) {
    if (_tabsState.libraryTabs.contains(tabName)) {
      return _favoritedBooks.where((book) => book['tab'] == tabName).toList();
    }
    return [];
  }

  void addBookToTab(String tabName, Map<String, dynamic> book) {
    if (_tabsState.libraryTabs.contains('Reading')) {
      book['tab'] = 'Reading';
    } else if (_tabsState.libraryTabs.isNotEmpty) {
      book['tab'] = _tabsState.libraryTabs.first;
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

  void renameTabBooks(String oldName, String newName) {
    for (var book in _favoritedBooks) {
      if (book['tab'] == oldName) {
        book['tab'] = newName;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void removeBookFromTab(String tabName, Map<String, dynamic> book) {
    if (tabName == 'Reading' || _tabsState.libraryTabs.contains(tabName)) {
      _favoritedBooks.remove(book);
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void moveBookInTab(String oldTabName, String newTabName, Map<String, dynamic> book) {
    removeBookFromTab(oldTabName, book);
    addBookToTab(newTabName, book);
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