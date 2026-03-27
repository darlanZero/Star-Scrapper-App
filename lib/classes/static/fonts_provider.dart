import 'dart:convert';

import 'package:cron/cron.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/pt-br/demon_sect_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/sites/luratoons_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/sites/mediocrescan_scrapper.dart';
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
    // ── Sites com autenticação ────────────────────────────────────────────────
    // auth via AuthWebViewScreen (OAuth/Cloudflare) ou authenticateWithCredentials.
    Fonte(
      image: 'https://luratoons.net/media/images/cropped-lura_scans.format-webp.width-250.webp',
      name: 'LuraToons',
      languagePrefix: 'Pt-BR',
      flags: ['https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png'],
      isActive: false,
      api: LuraToonsScrapper(),
      isRRated: false,
    ),
    Fonte(
      image: 'https://mediocrescan.com/_next/image?url=%2Flogo.png&w=48&q=75',
      name: 'MediocreScan',
      languagePrefix: 'Pt-BR',
      flags: ['https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png'],
      isActive: false,
      api: MediocreScanScrapper(),
      isRRated: false,
    ),
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
  Scrapper get selectedFontApi => selectedFont.api;
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
  Future<void> updateBookDetails(String bookId, {Scrapper? scrapper}) async {
    final fontApi = scrapper ?? selectedFontApi;

    Map<String, dynamic> updatedBookDetails = await fontApi.getBookDetails(bookId);

    List<Map<String, String>> readChapters = _selectedChapterIds[bookId] ?? [];

    // Atualiza em _favoritedBooks preservando as tabs atuais
    int favIndex = _favoritedBooks.indexWhere((book) => book['id'] == bookId);
    if (favIndex != -1) {
      final currentTabs = _bookTabs(_favoritedBooks[favIndex]);
      updatedBookDetails['tabs'] = currentTabs;
      updatedBookDetails.remove('tab');
      _favoritedBooks[favIndex] = updatedBookDetails;
      _saveFavoritedBooks();
    }

    // Atualiza em _readBooks também
    int readIndex = _readBooks.indexWhere((book) => book['id'] == bookId);
    if (readIndex != -1) {
      _readBooks[readIndex] = updatedBookDetails;
      _saveReadBooks();
    }

    _selectedChapterIds[bookId] = readChapters;
    await saveSelectedChapterId(bookId, readChapters);

    notifyListeners();
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
    // Remove o tab de todos os livros que o tinham
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final tabs = _bookTabs(book);
      if (tabs.contains(tab)) {
        tabs.remove(tab);
        book['tabs'] = tabs;
        book.remove('tab');
        if (tabs.isEmpty) {
          _favoritedBooks.removeAt(i--);
        } else {
          _favoritedBooks[i] = book;
        }
      }
    }
    // Adiciona os novos livros ao tab
    for (var book in books) {
      addBookToTab(tab, book);
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void updateBookInTab(String tab, Map<String, dynamic> updatedBook) {
    final index = _favoritedBooks.indexWhere((book) => book['id'] == updatedBook['id']);
    if (index != -1) {
      final stored = Map<String, dynamic>.from(_favoritedBooks[index]);
      final currentTabs = _bookTabs(stored);
      updatedBook['tabs'] = currentTabs;
      updatedBook.remove('tab');
      _favoritedBooks[index] = updatedBook;
      _saveFavoritedBooks();
      notifyListeners();
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
    if (index != -1) {
      _favoritedBooks.removeAt(index);
      _saveFavoritedBooks();
    } else {
      addBookToTab('Reading', book);
    }
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
        if (decodedBook is Map<String, dynamic>) {
          // Migração: converte campo antigo 'tab' (String) → 'tabs' (List)
          if (!decodedBook.containsKey('tabs') && decodedBook.containsKey('tab')) {
            decodedBook['tabs'] = [decodedBook['tab']];
            decodedBook.remove('tab');
          } else if (!decodedBook.containsKey('tabs')) {
            decodedBook['tabs'] = ['Reading'];
          }
          return decodedBook;
        }
        return null;
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

  // Books tabs — modelo multi-tab: cada livro tem 'tabs': List<String>

  List<String> _bookTabs(Map<String, dynamic> book) {
    final raw = book['tabs'];
    if (raw is List) return List<String>.from(raw);
    // migração de dados antigos: campo 'tab' único
    final legacy = book['tab'];
    if (legacy is String) return [legacy];
    return ['Reading'];
  }

  List<Map<String, dynamic>> getBooksInTab(String tabName) {
    if (_tabsState.libraryTabs.contains(tabName)) {
      return _favoritedBooks.where((book) => _bookTabs(book).contains(tabName)).toList();
    }
    return [];
  }

  void addBookToTab(String tabName, Map<String, dynamic> book) {
    final effectiveTab = _tabsState.libraryTabs.contains(tabName)
        ? tabName
        : (_tabsState.libraryTabs.isNotEmpty ? _tabsState.libraryTabs.first : 'Reading');

    final existingIndex = _favoritedBooks.indexWhere((b) => b['id'] == book['id']);
    if (existingIndex != -1) {
      final stored = Map<String, dynamic>.from(_favoritedBooks[existingIndex]);
      final tabs = _bookTabs(stored);
      if (!tabs.contains(effectiveTab)) tabs.add(effectiveTab);
      stored['tabs'] = tabs;
      stored.remove('tab');
      _favoritedBooks[existingIndex] = stored;
    } else {
      final bookCopy = Map<String, dynamic>.from(book);
      bookCopy['tabs'] = [effectiveTab];
      bookCopy.remove('tab');
      _favoritedBooks.add(bookCopy);
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void removeBookFromTab(String tabName, Map<String, dynamic> book) {
    final index = _favoritedBooks.indexWhere((b) => b['id'] == book['id']);
    if (index == -1) return;

    final stored = Map<String, dynamic>.from(_favoritedBooks[index]);
    final tabs = _bookTabs(stored);
    tabs.remove(tabName);

    if (tabs.isEmpty) {
      _favoritedBooks.removeAt(index);
    } else {
      stored['tabs'] = tabs;
      stored.remove('tab');
      _favoritedBooks[index] = stored;
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  // Adiciona à nova tab SEM remover da antiga (multi-tab)
  void moveBookInTab(String oldTabName, String newTabName, Map<String, dynamic> book) {
    addBookToTab(newTabName, book);
  }

  void renameTabBooks(String oldName, String newName) {
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final tabs = _bookTabs(book);
      final idx = tabs.indexOf(oldName);
      if (idx != -1) {
        tabs[idx] = newName;
        book['tabs'] = tabs;
        book.remove('tab');
        _favoritedBooks[i] = book;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void remapBooksFromRemovedTab(String removedTab, String defaultTab) {
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final tabs = _bookTabs(book);
      if (tabs.contains(removedTab)) {
        tabs.remove(removedTab);
        if (tabs.isEmpty) tabs.add(defaultTab);
        book['tabs'] = tabs;
        book.remove('tab');
        _favoritedBooks[i] = book;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }
}