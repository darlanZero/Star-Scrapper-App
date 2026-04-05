import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key});

  @override
  State<HomePageScreen> createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> {
  static const String _sortPrefKey = 'home_sort_option';

  late TabsState _tabsState;
  final List<GlobalKey> _primaryTabKeys = [];
  final Map<String, int> _secondaryIndexByPrimary = {};

  _HomeSortOption _sortOption = _HomeSortOption.addedLast;
  int _primaryIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabsState = Provider.of<TabsState>(context, listen: false);
    _tabsState.removeListener(_rebuildTabControllers);
    _tabsState.addListener(_rebuildTabControllers);
    _rebuildTabControllers();
  }

  void _rebuildTabControllers() {
    final primary = _tabsState.libraryTabs;
    if (primary.isEmpty) return;

    _primaryIndex = _primaryIndex.clamp(0, primary.length - 1);
    _syncPrimaryTabKeys(primary.length);
    if (mounted) setState(() {});
  }

  void _syncPrimaryTabKeys(int length) {
    if (_primaryTabKeys.length == length) return;
    _primaryTabKeys
      ..clear()
      ..addAll(List.generate(length, (_) => GlobalKey()));
  }

  @override
  void dispose() {
    _tabsState.removeListener(_rebuildTabControllers);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final appBarBase = theme.selectedTheme.appBarTheme.backgroundColor ??
        theme.selectedTheme.primaryColor;
    final scaffoldBase = theme.selectedTheme.scaffoldBackgroundColor;
    final accent =
        theme.selectedTheme.textTheme.titleMedium?.color ?? const Color(0xFF82EA64);

    Color blend(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: FutureBuilder<void>(
            future: _tabsState.tabsLoaded,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 52,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }

              final primary = _tabsState.libraryTabs;
              _syncPrimaryTabKeys(primary.length);

              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPrimaryTabsBar(
                      labels: primary,
                      appBarBase: appBarBase,
                      scaffoldBase: scaffoldBase,
                      accent: accent,
                      blend: blend,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: _buildActiveGrid(),
          ),
          Positioned(
            left: 18,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'home_sort_fab',
              onPressed: _showSortSheet,
              backgroundColor: const Color.fromARGB(210, 52, 34, 120),
              tooltip: 'Sort books',
              child: const Icon(Icons.sort_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryTabsBar({
    required List<String> labels,
    required Color appBarBase,
    required Color scaffoldBase,
    required Color accent,
    required Color Function(Color, Color, double) blend,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: blend(appBarBase, scaffoldBase, 0.35).withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: labels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final isSelected = index == _primaryIndex;
              return GestureDetector(
                key: _primaryTabKeys[index],
                onTap: () => _onPrimaryTabTapped(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              blend(accent, appBarBase, 0.45),
                              blend(accent, scaffoldBase, 0.25),
                            ],
                          )
                        : null,
                  ),
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: MediaQuery.of(context).size.width >= 600 ? 14 : 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onPrimaryTabTapped(int index) async {
    final primaryTabs = _tabsState.libraryTabs;
    if (index < 0 || index >= primaryTabs.length) return;

    final primary = primaryTabs[index];
    final subTabs = _tabsState.getSubTabsForPrimary(primary);

    setState(() {
      _primaryIndex = index;
      _secondaryIndexByPrimary.putIfAbsent(primary, () => 0);
    });

    if (subTabs.isEmpty) return;

    final key = _primaryTabKeys[index];
    final ctx = key.currentContext;
    if (ctx == null) return;

    final box = ctx.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final initial = (_secondaryIndexByPrimary[primary] ?? 0).clamp(0, subTabs.length - 1);

    final picked = await _showSubTabGlassMenu(
      anchorTopLeft: topLeft,
      anchorBottomRight: bottomRight,
      overlaySize: overlay.size,
      labels: subTabs,
      initialIndex: initial,
    );

    if (picked == null) return;
    setState(() {
      _secondaryIndexByPrimary[primary] = picked;
    });
  }

  Future<int?> _showSubTabGlassMenu({
    required Offset anchorTopLeft,
    required Offset anchorBottomRight,
    required Size overlaySize,
    required List<String> labels,
    required int initialIndex,
  }) {
    final menuWidth = labels.isEmpty ? 180.0 : 220.0;
    final left = anchorTopLeft.dx.clamp(12.0, overlaySize.width - menuWidth - 12.0);
    final top = (anchorBottomRight.dy + 8).clamp(8.0, overlaySize.height - 220.0);

    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'subtab-menu',
      barrierColor: Colors.black.withOpacity(0.12),
      pageBuilder: (context, _, __) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: menuWidth,
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(170, 21, 26, 46),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color.fromARGB(170, 86, 138, 255),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(110, 90, 145, 255),
                          blurRadius: 14,
                          spreadRadius: 1.2,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        itemCount: labels.length,
                        itemBuilder: (context, i) {
                          final selected = i == initialIndex;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.of(context).pop(i),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: selected
                                    ? const Color.fromARGB(120, 80, 130, 255)
                                    : Colors.transparent,
                                border: selected
                                    ? Border.all(
                                        color: const Color.fromARGB(170, 145, 185, 255),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected ? Icons.check_circle : Icons.circle_outlined,
                                    size: 16,
                                    color: selected ? Colors.white : Colors.white70,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      labels[i],
                                      style: TextStyle(
                                        color: selected ? Colors.white : Colors.white70,
                                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 160),
    );
  }

  Widget _buildActiveGrid() {
    return Consumer<FontProvider>(
      builder: (context, fontProvider, _) {
        final primaryTabs = _tabsState.libraryTabs;
        if (primaryTabs.isEmpty) {
          return const Center(child: Text('Configure suas tabs na Settings.'));
        }

        final primaryLabel = primaryTabs[_primaryIndex.clamp(0, primaryTabs.length - 1)];
        final secondaryTabs = _tabsState.getSubTabsForPrimary(primaryLabel);
        if (secondaryTabs.isEmpty) {
          final books = _sortBooks(fontProvider.getBooksInTab(primaryLabel));
          return _buildBooksGridFromList(books, fontProvider);
        }
        final secondaryIndex = (_secondaryIndexByPrimary[primaryLabel] ?? 0)
            .clamp(0, secondaryTabs.length - 1);
        final secondaryLabel = secondaryTabs[secondaryIndex];

        final books = _sortBooks(
          fontProvider.getBooksByTabAndSubTab(primaryLabel, secondaryLabel),
        );

        return _buildBooksGridFromList(books, fontProvider);
      },
    );
  }

  Widget _buildBooksGridFromList(
      List<Map<String, dynamic>> booksInTab, FontProvider fontProvider) {
    return Center(
      child: booksInTab.isEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withOpacity(0.06),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 46, color: Colors.white60),
                      SizedBox(height: 8),
                      Text(
                        'Sem livros nesta combinação de tabs.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 1100
                    ? 6
                    : MediaQuery.of(context).size.width >= 700
                        ? 4
                        : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.7,
              ),
              itemCount: booksInTab.length,
              itemBuilder: (context, index) {
                final book = booksInTab[index];
                final scrapper = fontProvider.findScrapperForBook(book) ??
                    fontProvider.selectedFontApi;
                final coverUrl = scrapper.getCoverImageUrl(book);
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookDetailsScreen(
                          bookDetails: book,
                          scrapper: scrapper,
                        ),
                      ),
                    );
                  },
                  child: GridTile(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: coverUrl,
                            httpHeaders: scrapper.imageHeaders,
                            fit: BoxFit.cover,
                            errorWidget: (context, _, __) => Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: Colors.grey),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color.fromARGB(35, 0, 0, 0),
                                  Color.fromARGB(185, 0, 0, 0),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: Text(
                              (book['title'] ?? '').toString(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 24,
                                shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildBooksGrid(String tabName) {
    return Consumer<FontProvider>(
      builder: (context, fontProvider, child) {
        final booksInTab = _sortBooks(fontProvider.getBooksInTab(tabName));
        return Center(
          child: booksInTab.isEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white.withOpacity(0.06),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.library_books_outlined, size: 46, color: Colors.white60),
                        SizedBox(height: 8),
                        Text(
                          'Your library is empty, try adding some books!',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(4),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.of(context).size.width >= 1100
                      ? 6
                      : MediaQuery.of(context).size.width >= 700
                          ? 4
                          : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.7,
                ),
                itemCount: booksInTab.length,
                itemBuilder: (context, index) {
                  final book = booksInTab[index];
                  final scrapper = fontProvider.findScrapperForBook(book) ?? fontProvider.selectedFontApi;
                  final coverUrl = scrapper.getCoverImageUrl(book);
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BookDetailsScreen(
                            bookDetails: book,
                            scrapper: scrapper,
                          ),
                        ),
                      );
                    },
                    child: GridTile(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: coverUrl,
                              httpHeaders: scrapper.imageHeaders,
                              fit: BoxFit.cover,
                              errorWidget: (context, _, __) => Container(
                                color: Colors.grey.shade900,
                                child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                              ),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color.fromARGB(35, 0, 0, 0),
                                    Color.fromARGB(185, 0, 0, 0),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 10,
                              child: Text(
                                (book['title'] ?? '').toString(),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 24,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _sortBooks(List<Map<String, dynamic>> books) {
    final sorted = List<Map<String, dynamic>>.from(books);
    switch (_sortOption) {
      case _HomeSortOption.alphabetical:
        sorted.sort((a, b) => _bookTitle(a).compareTo(_bookTitle(b)));
        break;
      case _HomeSortOption.alphabeticalReverse:
        sorted.sort((a, b) => _bookTitle(b).compareTo(_bookTitle(a)));
        break;
      case _HomeSortOption.addedFirst:
        // Ordem original vinda do provider.
        break;
      case _HomeSortOption.addedLast:
        return sorted.reversed.toList();
      case _HomeSortOption.updatedRecent:
        sorted.sort((a, b) => _bookUpdatedEpoch(b).compareTo(_bookUpdatedEpoch(a)));
        break;
      case _HomeSortOption.updatedOldest:
        sorted.sort((a, b) => _bookUpdatedEpoch(a).compareTo(_bookUpdatedEpoch(b)));
        break;
    }
    return sorted;
  }

  String _bookTitle(Map<String, dynamic> book) =>
      (book['title'] ?? '').toString().toLowerCase();

  int _bookUpdatedEpoch(Map<String, dynamic> book) {
    final candidates = <String?>[
      book['updatedAt']?.toString(),
      book['latestChapterDate']?.toString(),
      book['publishedAt']?.toString(),
      book['createdAt']?.toString(),
    ];

    final chapters = book['chapters'];
    if (chapters is List) {
      for (final ch in chapters) {
        if (ch is Map) {
          candidates.add(ch['updatedAt']?.toString());
          candidates.add(ch['publishedAt']?.toString());
          candidates.add(ch['createdAt']?.toString());
        }
      }
    }

    int best = 0;
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      final parsed = DateTime.tryParse(c);
      if (parsed == null) continue;
      final ms = parsed.millisecondsSinceEpoch;
      if (ms > best) best = ms;
    }
    return best;
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _HomeSortOption.values.map((opt) {
              return RadioListTile<_HomeSortOption>(
                value: opt,
                groupValue: _sortOption,
                title: Text(opt.label),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _sortOption = value);
                  _saveSortPreference(value);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_sortPrefKey);
    if (stored == null) return;
    final parsed = _HomeSortOption.values.firstWhere(
      (v) => v.name == stored,
      orElse: () => _HomeSortOption.addedLast,
    );
    if (!mounted) return;
    setState(() => _sortOption = parsed);
  }

  Future<void> _saveSortPreference(_HomeSortOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefKey, option.name);
  }
}

enum _HomeSortOption {
  alphabetical('Alfabético (A-Z)'),
  alphabeticalReverse('Alfabético invertido (Z-A)'),
  addedFirst('Adicionados primeiro'),
  addedLast('Adicionados por último'),
  updatedRecent('Atualizados recentemente'),
  updatedOldest('Atualizados por último');

  const _HomeSortOption(this.label);
  final String label;
}
