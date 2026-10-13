import 'package:star_scrapper_app/application/library/library_organization_contracts.dart';
import 'package:star_scrapper_app/domain/library/book_record.dart';

/// Owns the in-memory rules for placing books in library tabs and subtabs.
class LibraryOrganizer {
  LibraryTabConfiguration tabsState;
  final List<BookRecord> _books = [];

  LibraryOrganizer({required this.tabsState});

  List<Map<String, dynamic>> get books =>
      _books.map((book) => book.toJson()).toList(growable: false);

  void replaceAll(Iterable<Map<String, dynamic>> newBooks) {
    _books
      ..clear()
      ..addAll(newBooks.map(BookRecord.fromJson));
  }

  bool isFavorited(Map<String, dynamic> book) {
    final bookId = BookRecord.fromJson(book).id;
    return _books.any((stored) => stored.id == bookId);
  }

  void toggleFavorite(Map<String, dynamic> book) {
    final index = _indexOf(book);
    if (index != -1) {
      _books.removeAt(index);
    } else {
      addBookToTab('Reading', book);
    }
  }

  List<String> bookTabs(Map<String, dynamic> book) =>
      BookRecord.fromJson(book).tabs;

  Map<String, List<String>> bookSubTabsByPrimary(
    Map<String, dynamic> book,
  ) =>
      BookRecord.fromJson(book).subTabsByPrimary;

  List<Map<String, dynamic>> getBooksInTab(String tabName) {
    if (!tabsState.libraryTabs.contains(tabName)) return [];
    return _books
        .where((book) => book.tabs.contains(tabName))
        .map((book) => book.toJson())
        .toList();
  }

  List<Map<String, dynamic>> getBooksInSubTab(String subTabName) {
    return _books
        .where(
          (book) => book.subTabsByPrimary.values.any(
            (subTabs) => subTabs.contains(subTabName),
          ),
        )
        .map((book) => book.toJson())
        .toList();
  }

  List<Map<String, dynamic>> getBooksByTabAndSubTab(
    String tabName,
    String subTabName,
  ) {
    return _books
        .where(
          (book) =>
              book.tabs.contains(tabName) &&
              _bookSubTabsForPrimary(book, tabName).contains(subTabName),
        )
        .map((book) => book.toJson())
        .toList();
  }

  void setBooksInTab(String tabName, List<Map<String, dynamic>> newBooks) {
    for (var index = 0; index < _books.length; index++) {
      final book = _books[index].toJson();
      final tabs = bookTabs(book);
      if (!tabs.remove(tabName)) continue;
      book['tabs'] = tabs;
      book.remove('tab');
      if (tabs.isEmpty) {
        _books.removeAt(index--);
      } else {
        _store(index, book);
      }
    }
    for (final book in newBooks) {
      addBookToTab(tabName, book);
    }
  }

  bool replaceBookPreservingOrganization(Map<String, dynamic> updatedBook) {
    final bookId = updatedBook['id']?.toString() ?? '';
    if (bookId.isEmpty) return false;
    final index = _books.indexWhere((book) => book.id == bookId);
    if (index == -1) return false;

    _books[index].applyOrganizationTo(updatedBook);
    _store(index, updatedBook);
    return true;
  }

  void addBookToTab(String tabName, Map<String, dynamic> book) {
    final effectiveTab = tabsState.libraryTabs.contains(tabName)
        ? tabName
        : (tabsState.libraryTabs.isNotEmpty
            ? tabsState.libraryTabs.first
            : 'Reading');
    final existingIndex = _indexOf(book);

    if (existingIndex != -1) {
      final stored = _books[existingIndex].toJson();
      final tabs = bookTabs(stored);
      if (!tabs.contains(effectiveTab)) tabs.add(effectiveTab);
      final byPrimary = bookSubTabsByPrimary(stored);
      final defaultSub = tabsState.getDefaultSubTabForPrimary(effectiveTab);
      byPrimary.putIfAbsent(
        effectiveTab,
        () => defaultSub.isEmpty ? <String>[] : <String>[defaultSub],
      );
      stored['tabs'] = tabs;
      stored['subTabsByPrimary'] = byPrimary;
      stored.remove('tab');
      stored.remove('subTabs');
      _store(existingIndex, stored);
      return;
    }

    final bookCopy = Map<String, dynamic>.from(book);
    final defaultSub = tabsState.getDefaultSubTabForPrimary(effectiveTab);
    bookCopy['tabs'] = [effectiveTab];
    bookCopy['subTabsByPrimary'] = {
      effectiveTab: defaultSub.isEmpty ? <String>[] : <String>[defaultSub],
    };
    bookCopy.remove('tab');
    bookCopy.remove('subTabs');
    _books.add(BookRecord.fromJson(bookCopy));
  }

  void removeBookFromTab(String tabName, Map<String, dynamic> book) {
    final index = _indexOf(book);
    if (index == -1) return;
    final stored = _books[index].toJson();
    final tabs = bookTabs(stored)..remove(tabName);
    final byPrimary = bookSubTabsByPrimary(stored)..remove(tabName);
    if (tabs.isEmpty) {
      _books.removeAt(index);
    } else {
      stored['tabs'] = tabs;
      stored['subTabsByPrimary'] = byPrimary;
      stored.remove('tab');
      _store(index, stored);
    }
  }

  void renamePrimaryTabBooks(String oldName, String newName) {
    for (var index = 0; index < _books.length; index++) {
      final book = _books[index].toJson();
      final tabs = bookTabs(book);
      final tabIndex = tabs.indexOf(oldName);
      if (tabIndex == -1) continue;
      tabs[tabIndex] = newName;
      final byPrimary = bookSubTabsByPrimary(book);
      final oldSubTabs = byPrimary.remove(oldName) ?? <String>[];
      byPrimary[newName] = List<String>.from(oldSubTabs);
      book['tabs'] = tabs;
      book['subTabsByPrimary'] = byPrimary;
      book.remove('tab');
      book.remove('subTabs');
      _store(index, book);
    }
  }

  void remapBooksFromRemovedTab(String removedTab, String defaultTab) {
    for (var index = 0; index < _books.length; index++) {
      final book = _books[index].toJson();
      final tabs = bookTabs(book);
      if (!tabs.remove(removedTab)) continue;
      if (tabs.isEmpty) tabs.add(defaultTab);
      final byPrimary = bookSubTabsByPrimary(book);
      final removedSubTabs = byPrimary.remove(removedTab) ?? <String>[];
      byPrimary.putIfAbsent(
        defaultTab,
        () => List<String>.from(removedSubTabs),
      );
      book['tabs'] = tabs;
      book['subTabsByPrimary'] = byPrimary;
      book.remove('tab');
      book.remove('subTabs');
      _store(index, book);
    }
  }

  void addBookToSubTab(
    String primaryTab,
    String subTabName,
    Map<String, dynamic> book,
  ) {
    final availableSubTabs = tabsState.getSubTabsForPrimary(primaryTab);
    final effectiveSubTab = availableSubTabs.contains(subTabName)
        ? subTabName
        : (availableSubTabs.isNotEmpty ? availableSubTabs.first : subTabName);
    final existingIndex = _indexOf(book);

    if (existingIndex == -1) {
      final bookCopy = Map<String, dynamic>.from(book);
      bookCopy['tabs'] = [primaryTab];
      bookCopy['subTabsByPrimary'] = {
        primaryTab: [effectiveSubTab],
      };
      _books.add(BookRecord.fromJson(bookCopy));
      return;
    }

    final stored = _books[existingIndex].toJson();
    final tabs = bookTabs(stored);
    if (!tabs.contains(primaryTab)) tabs.add(primaryTab);
    final byPrimary = bookSubTabsByPrimary(stored);
    final subTabs = byPrimary[primaryTab] ?? <String>[];
    if (!subTabs.contains(effectiveSubTab)) subTabs.add(effectiveSubTab);
    byPrimary[primaryTab] = subTabs;
    stored['subTabsByPrimary'] = byPrimary;
    stored['tabs'] = tabs;
    _store(existingIndex, stored);
  }

  void removeBookFromSubTab(
    String primaryTab,
    String subTabName,
    Map<String, dynamic> book,
  ) {
    final index = _indexOf(book);
    if (index == -1) return;
    final stored = _books[index].toJson();
    final byPrimary = bookSubTabsByPrimary(stored);
    final subTabs = List<String>.from(byPrimary[primaryTab] ?? const <String>[])
      ..remove(subTabName);
    if (subTabs.isEmpty) {
      final fallback = tabsState.getDefaultSubTabForPrimary(primaryTab);
      if (fallback.isNotEmpty) subTabs.add(fallback);
    }
    byPrimary[primaryTab] = subTabs;
    stored['subTabsByPrimary'] = byPrimary;
    stored['tabs'] = bookTabs(stored);
    _store(index, stored);
  }

  void renameSubTabBooks(String primaryTab, String oldName, String newName) {
    for (var index = 0; index < _books.length; index++) {
      final book = _books[index].toJson();
      final byPrimary = bookSubTabsByPrimary(book);
      final subTabs = List<String>.from(
        byPrimary[primaryTab] ?? const <String>[],
      );
      final subTabIndex = subTabs.indexOf(oldName);
      if (subTabIndex == -1) continue;
      subTabs[subTabIndex] = newName;
      byPrimary[primaryTab] = subTabs;
      book['subTabsByPrimary'] = byPrimary;
      book['tabs'] = bookTabs(book);
      _store(index, book);
    }
  }

  void remapBooksFromRemovedSubTab(
    String primaryTab,
    String removedSubTab,
    String defaultSubTab,
  ) {
    for (var index = 0; index < _books.length; index++) {
      final book = _books[index].toJson();
      final byPrimary = bookSubTabsByPrimary(book);
      final subTabs = List<String>.from(
        byPrimary[primaryTab] ?? const <String>[],
      );
      if (!subTabs.remove(removedSubTab)) continue;
      if (subTabs.isEmpty && defaultSubTab.isNotEmpty) {
        subTabs.add(defaultSubTab);
      }
      byPrimary[primaryTab] = subTabs;
      book['subTabsByPrimary'] = byPrimary;
      book['tabs'] = bookTabs(book);
      _store(index, book);
    }
  }

  void nestPrimaryAsSubTab(String oldPrimaryTab, String targetPrimary) {
    for (var index = 0; index < _books.length; index++) {
      final book = _books[index].toJson();
      final tabs = bookTabs(book);
      final byPrimary = bookSubTabsByPrimary(book);
      if (!tabs.remove(oldPrimaryTab)) continue;
      if (!tabs.contains(targetPrimary)) tabs.add(targetPrimary);
      final movedSubTabs =
          byPrimary.remove(oldPrimaryTab) ?? <String>[oldPrimaryTab];
      final currentTarget = byPrimary[targetPrimary] ?? <String>[];
      for (final subTab in movedSubTabs) {
        if (!currentTarget.contains(subTab)) currentTarget.add(subTab);
      }
      if (!currentTarget.contains(oldPrimaryTab)) {
        currentTarget.add(oldPrimaryTab);
      }
      byPrimary[targetPrimary] = currentTarget;
      book['tabs'] = tabs;
      book['subTabsByPrimary'] = byPrimary;
      _store(index, book);
    }
  }

  List<String> _bookSubTabsForPrimary(
    BookRecord book,
    String primaryTab,
  ) {
    final fromBook = book.subTabsByPrimary[primaryTab];
    if (fromBook != null && fromBook.isNotEmpty) {
      return List<String>.from(fromBook);
    }
    final fallback = tabsState.getDefaultSubTabForPrimary(primaryTab);
    return fallback.isEmpty ? <String>[] : <String>[fallback];
  }

  int _indexOf(Map<String, dynamic> book) {
    final bookId = BookRecord.fromJson(book).id;
    return _books.indexWhere((stored) => stored.id == bookId);
  }

  void _store(int index, Map<String, dynamic> book) {
    _books[index] = BookRecord.fromJson(book);
  }
}
