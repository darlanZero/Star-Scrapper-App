import 'dart:async';

import 'package:flutter/material.dart';
import 'package:star_scrapper_app/application/library/chapter_update_scheduler.dart';
import 'package:star_scrapper_app/application/library/library_organizer.dart';
import 'package:star_scrapper_app/application/library/library_organization_contracts.dart';
import 'package:star_scrapper_app/application/library/library_update_tracker.dart';
import 'package:star_scrapper_app/application/library/reading_progress_controller.dart';
import 'package:star_scrapper_app/application/library/tabs_state.dart';
import 'package:star_scrapper_app/application/notifications/library_update_notifier.dart';
import 'package:star_scrapper_app/application/sources/source_controller.dart';
import 'package:star_scrapper_app/application/sources/anime_source_controller.dart';
import 'package:star_scrapper_app/application/sources/source_health_monitor.dart';
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:star_scrapper_app/data/library/library_storage.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

export 'package:star_scrapper_app/application/sources/source_health_monitor.dart'
    show FontHostStatus;

class FontProvider with ChangeNotifier implements LibraryOrganizationUpdater {
  late final Future<void> _sourcesLoaded;
  late final SourceController _sourceController;
  late final AnimeSourceController _animeSourceController;
  late final SourceHealthMonitor _sourceHealthMonitor;
  late final ChapterUpdateScheduler _chapterUpdateScheduler;
  late final LibraryOrganizer _libraryOrganizer;
  late final LibraryUpdateTracker _libraryUpdateTracker;
  late final ReadingProgressController _readingProgress;
  final LibraryUpdateNotifier _libraryUpdateNotifier = LibraryUpdateNotifier();
  final LibraryStorage _libraryStorage = LibraryStorage();

  FontProvider(TabsState tabsState) {
    _libraryOrganizer = LibraryOrganizer(tabsState: tabsState);
    _readingProgress = ReadingProgressController(
      storage: _libraryStorage,
      onChanged: notifyListeners,
    );
    _sourceController = SourceController(onChanged: notifyListeners);
    _animeSourceController = AnimeSourceController(onChanged: notifyListeners);
    _sourceHealthMonitor = SourceHealthMonitor(
      sources: _sourceController.sources,
      onChanged: notifyListeners,
    );
    _libraryUpdateTracker = LibraryUpdateTracker(onChanged: notifyListeners);
    _chapterUpdateScheduler = ChapterUpdateScheduler(
      onRun: _updateLibraryBooks,
      onChanged: notifyListeners,
    );
    _sourcesLoaded = Future.wait([
      _sourceController.initialize(),
      _animeSourceController.initialize(),
    ]);
    unawaited(_loadLibraryState());

    unawaited(_chapterUpdateScheduler.initialize());
    unawaited(_libraryUpdateTracker.initialize());
    unawaited(_sourceHealthMonitor.initialize());

    notifyListeners();
  }

  void setTabsState(TabsState tabsState) {
    _libraryOrganizer.tabsState = tabsState;
  }

  List<Fonte> get fonts => _sourceController.sources;
  List<AnimeSource> get animeSources => _animeSourceController.sources;
  List<AnimeSource> get activeAnimeSources => _animeSourceController.active;
  List<AnimeSource> get inactiveAnimeSources => _animeSourceController.inactive;
  Future<void> get sourcesLoaded => _sourcesLoaded;
  List<Map<String, dynamic>> get favoritedBooks => _libraryOrganizer.books;
  List<Map<String, dynamic>> get readBooks => _readingProgress.readBooks;
  Fonte get selectedFont => _sourceController.selected;
  Scrapper get selectedFontApi => _sourceController.selectedApi;

  /// Detecta o scrapper correto para um livro a partir da URL da capa (ou link).
  ///
  /// Útil quando [BookDetailsScreen] é aberto sem um scrapper explícito
  /// (ex.: ao abrir da biblioteca/favoritos). Evita usar [selectedFontApi]
  /// incorretamente quando a fonte ativa não é a que gerou o livro.
  ///
  /// Estratégia: compara o host da URL com a base ou a imagem de cada fonte.
  Scrapper? findScrapperForBook(Map<String, dynamic> book) =>
      _sourceController.findScrapperForBook(book);

  Map<String, List<Map<String, String>>> get selectedChapterIds =>
      _readingProgress.selectedChapterIds;
  Map<String, Map<String, String>> get lastReadedChapterId =>
      _readingProgress.lastReadChapterIds;

  Duration get updateInterval => _chapterUpdateScheduler.interval;
  Set<String> get tabsToUpdate => _chapterUpdateScheduler.tabs;
  bool get trackerEnabled => _chapterUpdateScheduler.enabled;
  DateTime? get trackerLastCheckedAt => _libraryUpdateTracker.lastCheckedAt;
  bool get fontHostAutoCheckEnabled => _sourceHealthMonitor.autoCheckEnabled;
  Duration get fontHostCheckInterval => _sourceHealthMonitor.checkInterval;
  DateTime? get fontHostLastCheckedAt => _sourceHealthMonitor.lastCheckedAt;
  Map<String, FontHostStatus> get fontHostStatuses =>
      _sourceHealthMonitor.statusesByName;

  FontHostStatus getFontHostStatus(String fontName) =>
      _sourceHealthMonitor.statusForName(fontName);

  Future<void> toggleFontState(Fonte font) async {
    await _sourceController.toggle(font);
  }

  bool isAnimeSourceActive(AnimeSource source) =>
      _animeSourceController.isActive(source);

  Future<void> toggleAnimeSource(AnimeSource source) =>
      _animeSourceController.toggle(source);

  //update single book details
  Future<void> updateBookDetails(String bookId, {Scrapper? scrapper}) async {
    final fontApi = scrapper ?? selectedFontApi;

    Map<String, dynamic> updatedBookDetails =
        await fontApi.getBookDetails(bookId);

    if (_libraryOrganizer
        .replaceBookPreservingOrganization(updatedBookDetails)) {
      await _saveFavoritedBooks();
    }

    await _readingProgress.replaceBookDetails(updatedBookDetails);

    notifyListeners();
  }

  void setUpdateInterval(Duration interval) {
    unawaited(_chapterUpdateScheduler.setInterval(interval));
  }

  void setTrackerEnabled(bool value) {
    unawaited(_chapterUpdateScheduler.setEnabled(value));
  }

  void setTabsToUpdate(Set<String> tabs) {
    unawaited(_chapterUpdateScheduler.setTabs(tabs));
  }

  void setFontHostAutoCheckEnabled(bool value) {
    _sourceHealthMonitor.setAutoCheckEnabled(value);
  }

  void setFontHostCheckInterval(Duration interval) {
    _sourceHealthMonitor.setCheckInterval(interval);
  }

  Future<void> checkAllFontsHostsNow() => _sourceHealthMonitor.checkAllNow();

  void setBooksInTab(String tab, List<Map<String, dynamic>> books) {
    _libraryOrganizer.setBooksInTab(tab, books);
    unawaited(_saveFavoritedBooks());
    notifyListeners();
  }

  void updateBookInTab(String tab, Map<String, dynamic> updatedBook) {
    if (_libraryOrganizer.replaceBookPreservingOrganization(updatedBook)) {
      unawaited(_saveFavoritedBooks());
      notifyListeners();
    }
  }

  void _replaceBookPreservingOrganization(Map<String, dynamic> updatedBook) {
    _libraryOrganizer.replaceBookPreservingOrganization(updatedBook);
  }

  Future<void> _updateLibraryBooks() async {
    if (!_chapterUpdateScheduler.enabled) return;

    final booksToTrack = <Map<String, dynamic>>[];
    for (final tab in _chapterUpdateScheduler.tabs) {
      booksToTrack.addAll(getBooksInTab(tab));
    }

    final updatedBooks = await _libraryUpdateTracker.checkBooks(
      books: booksToTrack,
      loadDetails: (book, bookId) async {
        final scrapper = findScrapperForBook(book) ?? selectedFontApi;
        final Map<String, dynamic> details =
            await scrapper.getBookDetails(bookId);
        return details;
      },
      onBookRefreshed: _replaceBookPreservingOrganization,
    );

    await _saveFavoritedBooks();
    await _readingProgress.saveSelectedChaptersSilently();

    if (updatedBooks.isNotEmpty) {
      await _libraryUpdateNotifier.notifyUpdatedBooks(updatedBooks);
    }
    notifyListeners();
  }

  Future<void> runTrackerNow() async {
    await _updateLibraryBooks();
  }

  //General Functions

  void toggleFavorite(Map<String, dynamic> book) {
    _libraryOrganizer.toggleFavorite(book);
    unawaited(_saveFavoritedBooks());
    notifyListeners();
  }

  bool isFavorited(Map<String, dynamic> book) =>
      _libraryOrganizer.isFavorited(book);

  List<Fonte> get activeFonts => _sourceController.active;
  List<Fonte> get inactiveFonts => _sourceController.inactive;

  // Favorited Books
  Future<void> _loadFavoritedBooks() async {
    _libraryOrganizer.replaceAll(await _libraryStorage.loadFavoriteBooks());
    notifyListeners();
  }

  Future<void> _saveFavoritedBooks() =>
      _libraryStorage.saveFavoriteBooks(_libraryOrganizer.books);

  Future<void> clearSelectedChapterIds() =>
      _readingProgress.clearSelectedChapters();

  Future<Map<String, List<Map<String, String>>>> loadSelectedChapterId() =>
      _readingProgress.reloadSelectedChapters();

  Future<void> saveSelectedChapterId(
    String bookId,
    List<Map<String, String>> chapters,
  ) =>
      _readingProgress.saveSelectedChapters(bookId, chapters);

  Future<void> saveSingleSelectedChapterId(
    String bookId,
    String chapterId,
    String chapterTitle,
  ) async {
    await _readingProgress.addReadChapter(bookId, chapterId, chapterTitle);
  }

  void addBookToReadBooks(Map<String, dynamic> book) {
    unawaited(_readingProgress.addBookToHistory(book));
  }

  Future<void> clearLastReadedChapterId() =>
      _readingProgress.clearLastReadChapters();

  Future<void> saveLastReadedChapterId() =>
      _readingProgress.rebuildLastReadChapters();

  Future<Map<String, Map<String, String>>> loadLastReadedChapterId() =>
      _readingProgress.reloadLastReadChapters();

  Future<void> _loadLibraryState() async {
    await _loadFavoritedBooks();
    await _readingProgress.initialize();
  }

  Future<void> refreshFromStorage() async {
    await _sourceController.initialize();
    await _animeSourceController.initialize();
    await _loadLibraryState();
    await _chapterUpdateScheduler.initialize();
    await _libraryUpdateTracker.initialize();
    await _sourceHealthMonitor.initialize();
    notifyListeners();
  }

  @override
  void dispose() {
    _sourceHealthMonitor.dispose();
    _chapterUpdateScheduler.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> getBooksInTab(String tabName) =>
      _libraryOrganizer.getBooksInTab(tabName);

  List<Map<String, dynamic>> getBooksInSubTab(String subTabName) =>
      _libraryOrganizer.getBooksInSubTab(subTabName);

  List<Map<String, dynamic>> getBooksByTabAndSubTab(
    String tabName,
    String subTabName,
  ) =>
      _libraryOrganizer.getBooksByTabAndSubTab(tabName, subTabName);

  void addBookToTab(String tabName, Map<String, dynamic> book) {
    _libraryOrganizer.addBookToTab(tabName, book);
    _persistLibraryOrganization();
  }

  void removeBookFromTab(String tabName, Map<String, dynamic> book) {
    _libraryOrganizer.removeBookFromTab(tabName, book);
    _persistLibraryOrganization();
  }

  void moveBookInTab(
    String oldTabName,
    String newTabName,
    Map<String, dynamic> book,
  ) {
    addBookToTab(newTabName, book);
  }

  void renameTabBooks(String oldName, String newName) {
    renamePrimaryTabBooks(oldName, newName);
  }

  @override
  void renamePrimaryTabBooks(String oldName, String newName) {
    _libraryOrganizer.renamePrimaryTabBooks(oldName, newName);
    _persistLibraryOrganization();
  }

  @override
  void remapBooksFromRemovedTab(String removedTab, String defaultTab) {
    _libraryOrganizer.remapBooksFromRemovedTab(removedTab, defaultTab);
    _persistLibraryOrganization();
  }

  void addBookToSubTab(
    String primaryTab,
    String subTabName,
    Map<String, dynamic> book,
  ) {
    _libraryOrganizer.addBookToSubTab(primaryTab, subTabName, book);
    _persistLibraryOrganization();
  }

  void removeBookFromSubTab(
    String primaryTab,
    String subTabName,
    Map<String, dynamic> book,
  ) {
    _libraryOrganizer.removeBookFromSubTab(primaryTab, subTabName, book);
    _persistLibraryOrganization();
  }

  @override
  void renameSubTabBooks(String primaryTab, String oldName, String newName) {
    _libraryOrganizer.renameSubTabBooks(primaryTab, oldName, newName);
    _persistLibraryOrganization();
  }

  @override
  void remapBooksFromRemovedSubTab(
    String primaryTab,
    String removedSubTab,
    String defaultSubTab,
  ) {
    _libraryOrganizer.remapBooksFromRemovedSubTab(
      primaryTab,
      removedSubTab,
      defaultSubTab,
    );
    _persistLibraryOrganization();
  }

  @override
  void nestPrimaryAsSubTab(String oldPrimaryTab, String targetPrimary) {
    _libraryOrganizer.nestPrimaryAsSubTab(oldPrimaryTab, targetPrimary);
    _persistLibraryOrganization();
  }

  void _persistLibraryOrganization() {
    unawaited(_saveFavoritedBooks());
    notifyListeners();
  }
}
