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
  bool _trackerEnabled = true;
  int _trackerLastCheckedAtMs = 0;
  Map<String, String> _lastKnownLatestChapterTokenByBook = {};
  Cron? _cron;
  late TabsState _tabsState;

  FontProvider(TabsState tabsState) {
    _tabsState = tabsState;
    _loadFonts();
    _loadFavoritedBooks();
    _loadReadBooks();

    _loadUpdateSettings();
    _loadTrackerState();

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

  /// Detecta o scrapper correto para um livro a partir da URL da capa (ou link).
  ///
  /// Útil quando [BookDetailsScreen] é aberto sem um scrapper explícito
  /// (ex.: ao abrir da biblioteca/favoritos). Evita usar [selectedFontApi]
  /// incorretamente quando a fonte ativa não é a que gerou o livro.
  ///
  /// Estratégia: verifica se a URL da capa contém o domínio de cada fonte,
  /// usando [ScrapperProfile.baseUrl] ou o domínio do favicon da fonte.
  Scrapper? findScrapperForBook(Map<String, dynamic> book) {
    final coverUrl = (book['coverImageUrl'] ?? book['link'] ?? '').toString();
    if (coverUrl.isEmpty) return null;

    for (final font in _fonts) {
      // 1. Tenta via baseUrl do ScrapperProfile (LuraToons, MediocreScan, etc.)
      final baseUrl = font.api.scrapperProfile?.baseUrl ?? '';
      if (baseUrl.isNotEmpty) {
        final baseDomain = Uri.tryParse(baseUrl)?.host ?? '';
        if (baseDomain.isNotEmpty && coverUrl.contains(baseDomain)) {
          return font.api;
        }
      }
      // 2. Fallback: domínio do favicon da fonte (cobre MangaDex e outros sem profile)
      final imageDomain = Uri.tryParse(font.image)?.host ?? '';
      if (imageDomain.isNotEmpty && coverUrl.contains(imageDomain)) {
        return font.api;
      }
    }
    return null;
  }
  Map<String, List<Map<String, String>>> get selectedChapterIds => _selectedChapterIds;
  Map<String, Map<String, String>> get lastReadedChapterId => _lastReadedChapterId;

  Duration get updateInterval => _updateInterval;
  Set<String> get tabsToUpdate => _tabsToUpdate;
  bool get trackerEnabled => _trackerEnabled;
  DateTime? get trackerLastCheckedAt => _trackerLastCheckedAtMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_trackerLastCheckedAtMs);

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
      final currentSubTabsByPrimary = _bookSubTabsByPrimary(_favoritedBooks[favIndex]);
      updatedBookDetails['tabs'] = currentTabs;
      updatedBookDetails['subTabsByPrimary'] = currentSubTabsByPrimary;
      updatedBookDetails.remove('tab');
      updatedBookDetails.remove('subTabs');
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

  void setTrackerEnabled(bool value) {
    _trackerEnabled = value;
    _saveUpdateSettings();
    if (value) {
      _scheduleAutomaticUpdates();
    } else {
      _cron?.close();
      _cron = null;
    }
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
    if (!_trackerEnabled) return;
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
    _saveUpdateSettings();
    notifyListeners();
  }

  void _saveUpdateSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('updateIntervalHours', _updateInterval.inHours);
    prefs.setStringList('tabsToUpdate', _tabsToUpdate.toList());
    prefs.setBool('trackerEnabled', _trackerEnabled);
  }

  void _clearUpdateSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('updateIntervalHours');
    await prefs.remove('tabsToUpdate');
    await prefs.remove('trackerEnabled');
  }

  Future<void> _loadUpdateSettings() async {
    final prefs = await SharedPreferences.getInstance();

    int hours = prefs.getInt('updateIntervalHours') ?? 24;
    _updateInterval = Duration(hours: hours);
    List<String> tabs = prefs.getStringList('tabsToUpdate') ?? [];
    _tabsToUpdate = Set.from(tabs);
    _trackerEnabled = prefs.getBool('trackerEnabled') ?? true;

    _scheduleAutomaticUpdates();
    notifyListeners();
  }

  Future<void> _loadTrackerState() async {
    final prefs = await SharedPreferences.getInstance();
    _trackerLastCheckedAtMs = prefs.getInt('trackerLastCheckedAtMs') ?? 0;
    final raw = prefs.getString('lastKnownLatestChapterTokenByBook') ?? '{}';
    final Map<String, dynamic> decoded = jsonDecode(raw);
    _lastKnownLatestChapterTokenByBook = decoded.map(
      (key, value) => MapEntry(key, value.toString()),
    );
    notifyListeners();
  }

  Future<void> _saveTrackerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('trackerLastCheckedAtMs', _trackerLastCheckedAtMs);
    await prefs.setString(
      'lastKnownLatestChapterTokenByBook',
      jsonEncode(_lastKnownLatestChapterTokenByBook),
    );
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
      final currentSubTabsByPrimary = _bookSubTabsByPrimary(stored);
      updatedBook['tabs'] = currentTabs;
      updatedBook['subTabsByPrimary'] = currentSubTabsByPrimary;
      updatedBook.remove('tab');
      _favoritedBooks[index] = updatedBook;
      _saveFavoritedBooks();
      notifyListeners();
    }
  }

  void _replaceBookPreservingOrganization(Map<String, dynamic> updatedBook) {
    final bookId = updatedBook['id']?.toString() ?? '';
    if (bookId.isEmpty) return;

    final index = _favoritedBooks.indexWhere((book) => book['id'].toString() == bookId);
    if (index == -1) return;

    final stored = Map<String, dynamic>.from(_favoritedBooks[index]);
    updatedBook['tabs'] = _bookTabs(stored);
    updatedBook['subTabsByPrimary'] = _bookSubTabsByPrimary(stored);
    updatedBook.remove('tab');
    updatedBook.remove('subTabs');
    _favoritedBooks[index] = updatedBook;
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
    if (!_trackerEnabled) return;

    List<Map<String, dynamic>> allUpdatedBooks = [];
    final Map<String, Map<String, dynamic>> booksToTrackById = {};

    for (final tab in _tabsToUpdate) {
      for (final book in getBooksInTab(tab)) {
        final id = book['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          booksToTrackById[id] = book;
        }
      }
    }

    for (final entry in booksToTrackById.entries) {
      final bookId = entry.key;
      final book = entry.value;
      final currentToken = _lastKnownLatestChapterTokenByBook[bookId] ??
          _extractLatestChapterToken(book);

      final readChapters = _selectedChapterIds[bookId] ?? <Map<String, String>>[];

      try {
        final scrapper = findScrapperForBook(book) ?? selectedFontApi;
        final updatedBookDetails = await scrapper.getBookDetails(bookId);
        final latestToken = _extractLatestChapterToken(updatedBookDetails);

        _replaceBookPreservingOrganization(updatedBookDetails);
        _selectedChapterIds[bookId] = readChapters;

        if (latestToken.isNotEmpty) {
          _lastKnownLatestChapterTokenByBook[bookId] = latestToken;
        }

        if (currentToken.isNotEmpty &&
            latestToken.isNotEmpty &&
            currentToken != latestToken) {
          allUpdatedBooks.add(updatedBookDetails);
        }
      } catch (e) {
        // keep loop resilient for background tracker
      }
    }

    _trackerLastCheckedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _saveFavoritedBooks();
    await _saveSelectedChapterIdsSilently();
    await _saveTrackerState();

    if (allUpdatedBooks.isNotEmpty) {
      await _showUpdatedNotification(allUpdatedBooks);
    }
    notifyListeners();
  }

  Future<void> runTrackerNow() async {
    await _updateLibraryBooks();
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

  Future<void> _loadFonts() async {
    final prefs = await SharedPreferences.getInstance();
    final activeFontNames = prefs.getStringList('activeFonts') ?? [];
    for (var font in _fonts) {
      font.isActive = activeFontNames.contains(font.name);
    }
    notifyListeners();
  }

  Future<void> _saveFonts() async {
    final prefs = await SharedPreferences.getInstance();
    final activeFontNames = _fonts.where((font) => font.isActive).map((font) => font.name).toList();
    prefs.setStringList('activeFonts', activeFontNames);
  }

  // Favorited Books
  Future<void> _loadFavoritedBooks() async {
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

  Future<void> _saveFavoritedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritedBooks = _favoritedBooks.map((book) => jsonEncode(book)).toList();
    prefs.setStringList('favoritedBooks', favoritedBooks);
  }

  Future<void> clearSelectedChapterIds() async {
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

  Future<void> _saveSelectedChapterIdsSilently() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedChapterIds', jsonEncode(_selectedChapterIds));
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

  Future<void> _loadReadBooks() async {
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

  Future<void> _saveReadBooks() async {
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

  Future<void> clearLastReadedChapterId() async {
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

  Future<void> refreshFromStorage() async {
    await _loadFonts();
    await _loadFavoritedBooks();
    await _loadReadBooks();
    await _loadUpdateSettings();
    await _loadTrackerState();
    await loadSelectedChapterId();
    await loadLastReadedChapterId();
    notifyListeners();
  }

  String _extractLatestChapterToken(Map<String, dynamic> bookDetails) {
    final chapters = bookDetails['chapters'];
    if (chapters is! List || chapters.isEmpty) return '';

    int bestEpoch = 0;
    String bestId = '';

    for (final raw in chapters) {
      if (raw is! Map) continue;
      final chapter = Map<String, dynamic>.from(raw);
      final id = (chapter['id'] ?? '').toString();
      final candidates = <String?>[
        chapter['updatedAt']?.toString(),
        chapter['publishedAt']?.toString(),
        chapter['createdAt']?.toString(),
      ];
      int epoch = 0;
      for (final c in candidates) {
        if (c == null || c.isEmpty) continue;
        final dt = DateTime.tryParse(c);
        if (dt != null && dt.millisecondsSinceEpoch > epoch) {
          epoch = dt.millisecondsSinceEpoch;
        }
      }
      if (epoch > bestEpoch) {
        bestEpoch = epoch;
        bestId = id;
      }
    }

    if (bestId.isEmpty) {
      final first = chapters.first;
      if (first is Map && first['id'] != null) {
        bestId = first['id'].toString();
      }
    }

    return '$bestId@$bestEpoch';
  }

  Map<String, List<String>> _bookSubTabsByPrimary(Map<String, dynamic> book) {
    final raw = book['subTabsByPrimary'];
    if (raw is Map) {
      return raw.map((key, value) {
        if (value is List) {
          return MapEntry(key.toString(), value.map((e) => e.toString()).toList());
        }
        return MapEntry(key.toString(), <String>[]);
      });
    }

    // fallback legado: subTabs global para todas as tabs atuais
    final legacy = <String>[];
    final rawLegacy = book['subTabs'];
    if (rawLegacy is List) {
      legacy.addAll(rawLegacy.map((e) => e.toString()));
    } else if (book['isRead'] == true) {
      legacy.add('Read');
    } else {
      legacy.add('Unread');
    }

    final byPrimary = <String, List<String>>{};
    final tabs = _bookTabs(book);
    for (final tab in tabs) {
      byPrimary[tab] = List<String>.from(legacy.isEmpty ? ['Unread'] : legacy);
    }
    return byPrimary;
  }

  List<String> _bookSubTabsForPrimary(Map<String, dynamic> book, String primaryTab) {
    final byPrimary = _bookSubTabsByPrimary(book);
    final fromBook = byPrimary[primaryTab];
    if (fromBook != null && fromBook.isNotEmpty) return List<String>.from(fromBook);
    final fallback = _tabsState.getDefaultSubTabForPrimary(primaryTab);
    return fallback.isEmpty ? <String>[] : <String>[fallback];
  }

  List<Map<String, dynamic>> getBooksInTab(String tabName) {
    if (_tabsState.libraryTabs.contains(tabName)) {
      return _favoritedBooks.where((book) => _bookTabs(book).contains(tabName)).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> getBooksInSubTab(String subTabName) {
    return _favoritedBooks.where((book) {
      final byPrimary = _bookSubTabsByPrimary(book);
      return byPrimary.values.any((subTabs) => subTabs.contains(subTabName));
    }).toList();
  }

  List<Map<String, dynamic>> getBooksByTabAndSubTab(String tabName, String subTabName) {
    return _favoritedBooks.where((book) {
      return _bookTabs(book).contains(tabName) &&
          _bookSubTabsForPrimary(book, tabName).contains(subTabName);
    }).toList();
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
      final byPrimary = _bookSubTabsByPrimary(stored);
      final defaultSub = _tabsState.getDefaultSubTabForPrimary(effectiveTab);
      byPrimary.putIfAbsent(effectiveTab, () {
        return defaultSub.isEmpty ? <String>[] : <String>[defaultSub];
      });
      stored['tabs'] = tabs;
      stored['subTabsByPrimary'] = byPrimary;
      stored.remove('tab');
      stored.remove('subTabs');
      _favoritedBooks[existingIndex] = stored;
    } else {
      final bookCopy = Map<String, dynamic>.from(book);
      final defaultSub = _tabsState.getDefaultSubTabForPrimary(effectiveTab);
      bookCopy['tabs'] = [effectiveTab];
      bookCopy['subTabsByPrimary'] = {
        effectiveTab: defaultSub.isEmpty ? <String>[] : <String>[defaultSub],
      };
      bookCopy.remove('tab');
      bookCopy.remove('subTabs');
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
    final byPrimary = _bookSubTabsByPrimary(stored);
    byPrimary.remove(tabName);

    if (tabs.isEmpty) {
      _favoritedBooks.removeAt(index);
    } else {
      stored['tabs'] = tabs;
      stored['subTabsByPrimary'] = byPrimary;
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
    renamePrimaryTabBooks(oldName, newName);
  }

  void renamePrimaryTabBooks(String oldName, String newName) {
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final tabs = _bookTabs(book);
      final idx = tabs.indexOf(oldName);
      if (idx != -1) {
        tabs[idx] = newName;
        final byPrimary = _bookSubTabsByPrimary(book);
        final oldSubTabs = byPrimary[oldName] ?? <String>[];
        byPrimary.remove(oldName);
        byPrimary[newName] = List<String>.from(oldSubTabs);
        book['tabs'] = tabs;
        book['subTabsByPrimary'] = byPrimary;
        book.remove('tab');
        book.remove('subTabs');
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
        final byPrimary = _bookSubTabsByPrimary(book);
        final removedSubTabs = byPrimary.remove(removedTab) ?? <String>[];
        byPrimary.putIfAbsent(defaultTab, () => List<String>.from(removedSubTabs));
        book['tabs'] = tabs;
        book['subTabsByPrimary'] = byPrimary;
        book.remove('tab');
        book.remove('subTabs');
        _favoritedBooks[i] = book;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void addBookToSubTab(String primaryTab, String subTabName, Map<String, dynamic> book) {
    final availableSubTabs = _tabsState.getSubTabsForPrimary(primaryTab);
    final effectiveSubTab = availableSubTabs.contains(subTabName)
        ? subTabName
        : (availableSubTabs.isNotEmpty ? availableSubTabs.first : subTabName);

    final existingIndex = _favoritedBooks.indexWhere((b) => b['id'] == book['id']);
    if (existingIndex != -1) {
      final stored = Map<String, dynamic>.from(_favoritedBooks[existingIndex]);
      final tabs = _bookTabs(stored);
      if (!tabs.contains(primaryTab)) tabs.add(primaryTab);

      final byPrimary = _bookSubTabsByPrimary(stored);
      final subTabs = byPrimary[primaryTab] ?? <String>[];
      if (!subTabs.contains(effectiveSubTab)) subTabs.add(effectiveSubTab);
      byPrimary[primaryTab] = subTabs;
      stored['subTabsByPrimary'] = byPrimary;
      stored['tabs'] = tabs;
      _favoritedBooks[existingIndex] = stored;
    } else {
      final bookCopy = Map<String, dynamic>.from(book);
      bookCopy['tabs'] = [primaryTab];
      bookCopy['subTabsByPrimary'] = {primaryTab: [effectiveSubTab]};
      _favoritedBooks.add(bookCopy);
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void removeBookFromSubTab(String primaryTab, String subTabName, Map<String, dynamic> book) {
    final index = _favoritedBooks.indexWhere((b) => b['id'] == book['id']);
    if (index == -1) return;

    final stored = Map<String, dynamic>.from(_favoritedBooks[index]);
    final byPrimary = _bookSubTabsByPrimary(stored);
    final subTabs = List<String>.from(byPrimary[primaryTab] ?? const <String>[]);
    subTabs.remove(subTabName);

    if (subTabs.isEmpty) {
      final fallback = _tabsState.getDefaultSubTabForPrimary(primaryTab);
      if (fallback.isNotEmpty) {
        subTabs.add(fallback);
      }
    }

    byPrimary[primaryTab] = subTabs;
    stored['subTabsByPrimary'] = byPrimary;
    stored['tabs'] = _bookTabs(stored);
    _favoritedBooks[index] = stored;
    _saveFavoritedBooks();
    notifyListeners();
  }

  void renameSubTabBooks(String primaryTab, String oldName, String newName) {
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final byPrimary = _bookSubTabsByPrimary(book);
      final subTabs = List<String>.from(byPrimary[primaryTab] ?? const <String>[]);
      final idx = subTabs.indexOf(oldName);
      if (idx != -1) {
        subTabs[idx] = newName;
        byPrimary[primaryTab] = subTabs;
        book['subTabsByPrimary'] = byPrimary;
        book['tabs'] = _bookTabs(book);
        _favoritedBooks[i] = book;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void remapBooksFromRemovedSubTab(
    String primaryTab,
    String removedSubTab,
    String defaultSubTab,
  ) {
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final byPrimary = _bookSubTabsByPrimary(book);
      final subTabs = List<String>.from(byPrimary[primaryTab] ?? const <String>[]);
      if (subTabs.contains(removedSubTab)) {
        subTabs.remove(removedSubTab);
        if (subTabs.isEmpty && defaultSubTab.isNotEmpty) subTabs.add(defaultSubTab);
        byPrimary[primaryTab] = subTabs;
        book['subTabsByPrimary'] = byPrimary;
        book['tabs'] = _bookTabs(book);
        _favoritedBooks[i] = book;
      }
    }
    _saveFavoritedBooks();
    notifyListeners();
  }

  void nestPrimaryAsSubTab(String oldPrimaryTab, String targetPrimary) {
    for (int i = 0; i < _favoritedBooks.length; i++) {
      final book = Map<String, dynamic>.from(_favoritedBooks[i]);
      final tabs = _bookTabs(book);
      final byPrimary = _bookSubTabsByPrimary(book);

      if (!tabs.contains(oldPrimaryTab)) continue;

      tabs.remove(oldPrimaryTab);
      if (!tabs.contains(targetPrimary)) tabs.add(targetPrimary);

      final movedSubTabs = byPrimary.remove(oldPrimaryTab) ?? <String>[oldPrimaryTab];
      final currentTarget = byPrimary[targetPrimary] ?? <String>[];
      for (final sub in movedSubTabs) {
        if (!currentTarget.contains(sub)) currentTarget.add(sub);
      }
      if (!currentTarget.contains(oldPrimaryTab)) currentTarget.add(oldPrimaryTab);
      byPrimary[targetPrimary] = currentTarget;

      book['tabs'] = tabs;
      book['subTabsByPrimary'] = byPrimary;
      _favoritedBooks[i] = book;
    }
    _saveFavoritedBooks();
    notifyListeners();
  }
}
