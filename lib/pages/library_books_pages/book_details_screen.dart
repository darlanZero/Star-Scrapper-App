import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, kDebugMode;
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/pages/library_books_pages/chapter_book_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class BookDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bookDetails;

  /// Scrapper a ser usado nesta tela. Se null, usa o selectedFontApi global.
  final MangaSource? scrapper;
  final void Function(MangaTaxonomyKind kind, String id, String name)?
      onTaxonomySelected;
  const BookDetailsScreen({
    super.key,
    required this.bookDetails,
    this.scrapper,
    this.onTaxonomySelected,
  });

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  late Map<String, dynamic> bookDetails;
  bool _isChapterReversed = false;
  String _selectedLanguagePrefix = '';
  bool _showWebView = false;
  // ignore: unused_field
  bool _isLoadingChapter = false;
  String? _selectedChapterId;
  bool _syncingTrackers = false;

  Future<void>? _updateFuture;

  Widget _buildTagChip(String rawTag, TextStyle? style) {
    final tag = rawTag.trim();
    final canSearch =
        {'nhentai', 'nhentai_xxx'}.contains(widget.scrapper?.id) &&
            widget.onTaxonomySelected != null &&
            tag.isNotEmpty;
    final chip = Chip(
      label: Text(tag, style: style),
      backgroundColor: Colors.black.withValues(alpha: .62),
      shadowColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const StadiumBorder(),
      side: const BorderSide(color: Colors.white24),
    );
    if (!canSearch) return chip;
    return GestureDetector(
      onTap: () => _applyTagSearch([tag]),
      onLongPress: _showCombinedTagSearch,
      child: chip,
    );
  }

  Widget _buildScrollableTags() {
    final tags = ((bookDetails['tags'] as List?) ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (tags.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'Manga tags. Swipe horizontally to see more.',
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: tags.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) => _buildTagChip(
            tags[index],
            const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _applyTagSearch(List<String> tags) {
    if (tags.isEmpty || widget.onTaxonomySelected == null) return;
    final ids = tags.map((tag) => '/tag/${_slug(tag)}/').join('|');
    widget.onTaxonomySelected!(MangaTaxonomyKind.tag, ids, tags.join(', '));
    Navigator.of(context).pop();
  }

  Future<void> _showCombinedTagSearch() async {
    final tags = ((bookDetails['tags'] as List?) ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final selected = <String>{};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Combine tags'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      label: Text(tag),
                      selected: selected.contains(tag),
                      onSelected: (value) => setDialogState(() =>
                          value ? selected.add(tag) : selected.remove(tag)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, selected.toList()),
              child: Text('Search (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) _applyTagSearch(result);
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Widget _sourceCoverImage({
    required MangaSource? source,
    required String imageUrl,
    required BoxFit fit,
    double? width,
    double? height,
    Color? color,
    BlendMode? colorBlendMode,
  }) {
    final uri = Uri.tryParse(imageUrl);
    if (source case final BrowserImageMangaSource browserSource
        when uri != null) {
      return FutureBuilder(
        future: browserSource.loadBrowserImage(uri),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ColoredBox(
              color: Colors.black12,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const ColoredBox(
              color: Colors.black12,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            color: color,
            colorBlendMode: colorBlendMode,
            gaplessPlayback: true,
          );
        },
      );
    }
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      headers: source?.coverImageHeaders,
      color: color,
      colorBlendMode: colorBlendMode,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    bookDetails = widget.bookDetails;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fontProvider = Provider.of<FontProvider>(context, listen: false);
      fontProvider.addBookToReadBooks(bookDetails);

      // Se o livro veio da busca online (sem capítulos), busca os detalhes completos.
      // Usa o scrapper explícito, ou tenta detectá-lo pelo domínio da capa.
      final hasChapters =
          (bookDetails['chapters'] as List?)?.isNotEmpty == true;
      final effectiveScrapper =
          widget.scrapper ?? fontProvider.findScrapperForBook(bookDetails);
      if (!hasChapters && effectiveScrapper != null) {
        setState(() {
          _updateFuture = fontProvider
              .updateBookDetails(
            bookDetails['id'],
            scrapper: effectiveScrapper,
          )
              .then((_) {
            // Atualiza o estado local com os dados carregados
            final updated = fontProvider.favoritedBooks.firstWhere(
              (b) => b['id'] == bookDetails['id'],
              orElse: () => fontProvider.readBooks.firstWhere(
                (b) => b['id'] == bookDetails['id'],
                orElse: () => bookDetails,
              ),
            );
            if (mounted) setState(() => bookDetails = updated);
          });
        });
      }
    });
    Provider.of<FontProvider>(context, listen: false).loadSelectedChapterId();
  }

  void _toogleChapterOrder() {
    setState(() {
      _isChapterReversed = !_isChapterReversed;
    });
  }

  void _filterChaptersByLanguage(String languagePrefix) {
    setState(() {
      _selectedLanguagePrefix = languagePrefix;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    bool isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
        backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
        body: _showWebView
            ? _buildWebView(context)
            : FutureBuilder<void>(
                future: _updateFuture,
                builder: (context, snapshot) {
                  if (_updateFuture == null) {
                    return _reactiveDetailsBook(
                        context, isDesktop, theme, bookDetails);
                  } else {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    } else {
                      return _reactiveDetailsBook(
                          context, isDesktop, theme, bookDetails);
                    }
                  }
                }),
        floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
          FloatingActionButton(
            heroTag: 'reverse_chapters',
            onPressed: _toogleChapterOrder,
            hoverColor: Colors.blueGrey,
            child: Icon(
              _isChapterReversed ? Icons.arrow_downward : Icons.arrow_upward,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8.0),
          FloatingActionButton(
              heroTag: 'update_book_details',
              onPressed: () async {
                final fontProvider =
                    Provider.of<FontProvider>(context, listen: false);
                final bookId = widget.bookDetails['id'];

                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Row(children: const [
                    Text('Updating book details...'),
                    SizedBox(width: 10),
                    CircularProgressIndicator(),
                  ]),
                  duration: const Duration(minutes: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0)),
                ));

                final effectiveScrapper = widget.scrapper ??
                    fontProvider.findScrapperForBook(bookDetails);
                try {
                  await fontProvider.updateBookDetails(bookId,
                      scrapper: effectiveScrapper);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Book details updated successfully!'),
                    duration: Duration(seconds: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0)),
                    backgroundColor: Colors.green,
                  ));

                  final updatedBook = fontProvider.favoritedBooks.firstWhere(
                    (book) => book['id'] == bookId,
                    orElse: () => bookDetails,
                  );

                  setState(() {
                    _updateFuture = null;
                    bookDetails = updatedBook;
                  }); // Refresh the screen
                } catch (e) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Failed to update book details: $e'),
                    duration: Duration(seconds: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0)),
                    backgroundColor: Colors.red,
                  ));

                  if (kDebugMode) {
                    print('Failed to update book details: $e');
                  }

                  setState(() {
                    _updateFuture = null;
                  });
                }
              },
              hoverColor: Colors.blueGrey,
              child: const Icon(
                Icons.update,
                color: Colors.white,
              ))
        ]));
  }

  Widget _reactiveDetailsBook(BuildContext context, bool isDesktop,
      ThemeProvider theme, Map<String, dynamic> bookDetails) {
    List<dynamic> chapters = List.from(bookDetails['chapters'] ?? []);

    if (_isChapterReversed) {
      chapters = chapters.reversed.toList();
    }

    if (_selectedLanguagePrefix.isNotEmpty) {
      chapters = chapters
          .where((chapter) => chapter['translatedLanguage']
              .toString()
              .startsWith(_selectedLanguagePrefix))
          .toList();
    }

    String imageUrl = bookDetails['coverImageUrl'] ??
        'https://static.thenounproject.com/png/482114-200.png';
    final effectiveScrapper = widget.scrapper ??
        Provider.of<FontProvider>(context, listen: false)
            .findScrapperForBook(bookDetails);
    final usesScanCards = effectiveScrapper?.id == 'xcomic';
    final trackers = context.watch<TrackerController>();

    void showManageTabsDialog(BuildContext context) {
      final fontProvider = Provider.of<FontProvider>(context, listen: false);
      final tabsState = Provider.of<TabsState>(context, listen: false);

      final storedBook = fontProvider.favoritedBooks.firstWhere(
        (b) => b['id'] == bookDetails['id'],
        orElse: () => bookDetails,
      );
      final rawTabs = storedBook['tabs'];
      final initialTabs = rawTabs is List
          ? List<String>.from(rawTabs)
          : (storedBook['tab'] is String
              ? [storedBook['tab'] as String]
              : <String>['Reading']);
      final rawSubTabsByPrimary = storedBook['subTabsByPrimary'];
      final Map<String, List<String>> initialSubTabsByPrimary = {};
      if (rawSubTabsByPrimary is Map) {
        rawSubTabsByPrimary.forEach((key, value) {
          if (value is List) {
            initialSubTabsByPrimary[key.toString()] =
                value.map((e) => e.toString()).toList();
          }
        });
      } else {
        for (final tab in initialTabs) {
          final fallback = tabsState.getDefaultSubTabForPrimary(tab);
          initialSubTabsByPrimary[tab] =
              fallback.isEmpty ? <String>[] : <String>[fallback];
        }
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          List<String> selectedTabs = List.from(initialTabs);
          final Map<String, List<String>> selectedSubTabsByPrimary =
              Map<String, List<String>>.from(initialSubTabsByPrimary);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Gerenciar Organização'),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('Tabs'),
                      ),
                      ...tabsState.libraryTabs.map((libraryTab) {
                        return CheckboxListTile(
                          title: Text(libraryTab),
                          value: selectedTabs.contains(libraryTab),
                          onChanged: (bool? checked) {
                            setDialogState(() {
                              if (checked == true) {
                                if (!selectedTabs.contains(libraryTab)) {
                                  selectedTabs.add(libraryTab);
                                  fontProvider.addBookToTab(
                                      libraryTab, bookDetails);
                                  selectedSubTabsByPrimary.putIfAbsent(
                                    libraryTab,
                                    () {
                                      final fallback =
                                          tabsState.getDefaultSubTabForPrimary(
                                              libraryTab);
                                      return fallback.isEmpty
                                          ? <String>[]
                                          : <String>[fallback];
                                    },
                                  );
                                }
                              } else if (selectedTabs.length > 1) {
                                selectedTabs.remove(libraryTab);
                                fontProvider.removeBookFromTab(
                                    libraryTab, bookDetails);
                              }
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 8),
                      ...selectedTabs.expand((primaryTab) {
                        final subTabs =
                            tabsState.getSubTabsForPrimary(primaryTab);
                        final selectedSubTabs =
                            selectedSubTabsByPrimary[primaryTab] ?? <String>[];

                        return <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('Subtabs de "$primaryTab"'),
                          ),
                          if (subTabs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(left: 12, bottom: 8),
                              child:
                                  Text('Sem subtabs para esta tab primária.'),
                            ),
                          ...subTabs.map((subTab) {
                            return CheckboxListTile(
                              title: Text(subTab),
                              value: selectedSubTabs.contains(subTab),
                              onChanged: (bool? checked) {
                                setDialogState(() {
                                  final current =
                                      selectedSubTabsByPrimary[primaryTab] ??
                                          <String>[];
                                  if (checked == true) {
                                    if (!current.contains(subTab)) {
                                      current.add(subTab);
                                      fontProvider.addBookToSubTab(
                                        primaryTab,
                                        subTab,
                                        bookDetails,
                                      );
                                    }
                                  } else if (current.length > 1) {
                                    current.remove(subTab);
                                    fontProvider.removeBookFromSubTab(
                                      primaryTab,
                                      subTab,
                                      bookDetails,
                                    );
                                  }
                                  selectedSubTabsByPrimary[primaryTab] =
                                      current;
                                });
                              },
                            );
                          }),
                          const SizedBox(height: 8),
                        ];
                      }),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: const Text('Fechar'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          iconTheme: const IconThemeData(
              color: Colors.blueGrey,
              size: 30.0,
              shadows: <Shadow>[
                Shadow(color: Colors.black, blurRadius: 10.0),
              ]),
          expandedHeight: isDesktop ? 500.0 : 250.0,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  child: _sourceCoverImage(
                    source: effectiveScrapper,
                    imageUrl: imageUrl,
                    fit: isDesktop ? BoxFit.cover : BoxFit.fill,
                    color: Colors.black.withValues(alpha: 0.5),
                    colorBlendMode: BlendMode.darken,
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black,
                          Colors.transparent,
                        ]),
                  ),
                ),
                Positioned(
                    top: 16.0,
                    left: 16.0,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _sourceCoverImage(
                          source: effectiveScrapper,
                          imageUrl: imageUrl,
                          width: isDesktop ? 200 : 100,
                          height: isDesktop ? 300 : 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )),
                Positioned(
                  top: 16.0,
                  left: isDesktop ? 240 : 130,
                  child: Text(
                    widget.bookDetails['type'] ?? 'No type available',
                    style: const TextStyle(
                        fontSize: 24.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black, blurRadius: 10.0),
                        ]),
                  ),
                ),
                if (!isDesktop)
                  Positioned(
                      bottom: 52.0,
                      left: 130.0,
                      right: 16.0,
                      child: _buildScrollableTags()),
                if (isDesktop)
                  Positioned(
                    top: 16.0,
                    right: 16.0,
                    child: SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        child: Text(
                          bookDetails['description'] ??
                              'No description Available',
                          style: const TextStyle(
                              fontSize: 16.0, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 16.0,
                  left: 16.0,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _extractPersonName(bookDetails['author']) ??
                              'No author available',
                          style: TextStyle(
                              fontSize: isDesktop ? 16.0 : 8.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          _extractPersonName(bookDetails['artist']) ??
                              'No artist available',
                          style: TextStyle(
                              fontSize: isDesktop ? 16.0 : 8.0,
                              color: Colors.grey),
                        )
                      ]),
                )
              ],
            ),
          ),
          actions: [
            if (trackers.aniListConnectedAndEnabled)
              IconButton(
                tooltip: 'Add manga to AniList',
                onPressed: _syncingTrackers
                    ? null
                    : () => _addMangaToAniList(trackers),
                icon: _syncingTrackers
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_alt_rounded),
              ),
            Consumer<FontProvider>(
              builder: (context, favoritedBooksState, child) {
                final isFavorited =
                    favoritedBooksState.isFavorited(bookDetails);
                return IconButton(
                    icon: Icon(
                      isFavorited ? Icons.favorite : Icons.favorite_border,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      favoritedBooksState.toggleFavorite(bookDetails);
                      setState(() {});
                    });
              },
            ),
            const SizedBox(width: 16.0),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () {
                setState(() {
                  _showWebView = !_showWebView;
                });
              },
            ),
            const SizedBox(width: 16.0),
            PopupMenuButton(
                onSelected: (String value) {
                  if (value == 'Manage Tabs') {
                    showManageTabsDialog(context);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'Rename Book',
                        child: Text('Rename book'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'Migrate Book',
                        child: Text('Migrate book'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'Manage Tabs',
                        child: Text('Gerenciar tabs'),
                      ),
                    ]),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: isDesktop
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  bookDetails['title'] ?? 'No title available',
                  style: TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                      color: theme.selectedTheme.textTheme.titleMedium?.color,
                      shadows: const <Shadow>[
                        Shadow(
                            color: Color.fromARGB(255, 87, 25, 25),
                            blurRadius: 2.0),
                        Shadow(
                            color: Color.fromARGB(255, 0, 0, 0),
                            blurRadius: 2.0),
                      ]),
                ),
                if (bookDetails['altTitles'] != null &&
                    bookDetails['altTitles'].isNotEmpty)
                  Card(
                    margin: EdgeInsets.only(top: 16.0),
                    surfaceTintColor: Colors.blueGrey,
                    color: theme.selectedTheme.cardTheme.color,
                    shadowColor: theme.selectedTheme.cardTheme.shadowColor,
                    elevation: theme.selectedTheme.cardTheme.elevation,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            bookDetails['altTitles'].map<Widget>((altTitle) {
                          return Text(altTitle.values.first,
                              style: TextStyle(
                                  fontSize: 16.0,
                                  color: theme.selectedTheme.textTheme
                                      .displayMedium?.color));
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 16.0),
                if (!isDesktop)
                  Text(
                    bookDetails['description'] ?? 'No description Available',
                    style: TextStyle(
                        fontSize: 16.0,
                        color:
                            theme.selectedTheme.textTheme.displayMedium?.color),
                  ),
                if (isDesktop) _buildScrollableTags(),
                Text(
                  'Chapters',
                  style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color:
                          theme.selectedTheme.textTheme.displayMedium?.color),
                ),
                const SizedBox(height: 8.0),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _buildLanguageFilterButtons(),
                    ))
              ],
            ),
          ),
        ),
        if (usesScanCards)
          SliverToBoxAdapter(
            child: _buildXComicScanCarousel(chapters, theme),
          )
        else
          SliverList(
              delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              if (index >= chapters.length) {
                return const SizedBox.shrink();
              }

              final chapter = chapters[index];
              final fontProvider =
                  Provider.of<FontProvider>(context, listen: false);
              final readChapterIds =
                  (fontProvider.selectedChapterIds[bookDetails['id']] ?? [])
                      .map((c) => c['id'] as String)
                      .toSet();
              final isRead =
                  readChapterIds.contains(chapter['id'] as String? ?? '');

              return ListTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _buildChapterLabel(chapter),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                              color: theme
                                  .selectedTheme.textTheme.titleSmall?.color,
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (chapter['volume'] != null)
                        Text(
                          'Vol. ${_formatVolume(chapter['volume']?.toString())}',
                          style: TextStyle(
                            color:
                                theme.selectedTheme.textTheme.titleSmall?.color,
                            fontSize: 16.0,
                          ),
                        ),
                      SizedBox(width: 8.0),
                      Text(
                        '${chapter['translatedLanguage'] ?? ''}',
                        style: TextStyle(
                          color:
                              theme.selectedTheme.textTheme.titleSmall?.color,
                          fontSize: 16.0,
                        ),
                      )
                    ],
                  ),
                  leading: Icon(
                    isRead ? Icons.check_circle : Icons.circle_outlined,
                    color: isRead ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  tileColor: _selectedChapterId == chapter['id']
                      ? const Color(0xFF483D8B).withAlpha(150)
                      : isRead
                          ? Colors.green.withValues(alpha: 0.08)
                          : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  subtitle: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (chapter['pages'] != null)
                        Text(
                          '${chapter['pages']} pages',
                          style: TextStyle(
                            color: theme
                                .selectedTheme.textTheme.displayMedium?.color,
                            fontSize: 14.0,
                          ),
                        ),
                      if (chapter['uploader'] != null)
                        Text(
                          chapter['uploader'],
                          style: TextStyle(
                            color: theme
                                .selectedTheme.textTheme.displayMedium?.color,
                            fontSize: 14.0,
                          ),
                        ),
                      Text(
                        _formatDate(chapter['publishedAt']?.toString()),
                        style: TextStyle(
                          color: theme
                              .selectedTheme.textTheme.displayMedium?.color,
                          fontSize: 14.0,
                        ),
                      )
                    ],
                  ),
                  onTap: () => _openChapter(chapter));
            },
            childCount: chapters.length,
          ))
      ],
    );
  }

  Widget _buildXComicScanCarousel(
    List<dynamic> chapters,
    ThemeProvider theme,
  ) {
    final grouped = <String, List<Map<dynamic, dynamic>>>{};
    for (final rawChapter in chapters) {
      if (rawChapter is! Map) continue;
      final chapter = Map<dynamic, dynamic>.from(rawChapter);
      final scanId = _xComicScanId(chapter);
      grouped.putIfAbsent(scanId, () => []).add(chapter);
    }
    if (grouped.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * .86).clamp(300.0, 390.0);
    return SizedBox(
      height: 520,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 24, 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: grouped.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final entry = grouped.entries.elementAt(index);
          final scanChapters = entry.value;
          final first = scanChapters.first;
          final scanName = _xComicScanName(first);
          final language = first['translatedLanguage']?.toString().trim() ?? '';
          final missing = first['missingChapters']?.toString().trim() ?? '';
          return SizedBox(
            width: cardWidth,
            child: Card(
              clipBehavior: Clip.antiAlias,
              color: theme.selectedTheme.cardTheme.color,
              elevation: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            scanName.isEmpty
                                ? '#${entry.key}'
                                : '#${entry.key} · $scanName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (language.isNotEmpty)
                          Chip(
                            label: Text(language),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  if (missing.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              missing,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      primary: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: scanChapters.length,
                      itemBuilder: (context, chapterIndex) {
                        final chapter = scanChapters[chapterIndex];
                        final chapterId = chapter['id']?.toString() ?? '';
                        final title = chapter['title']?.toString().trim() ?? '';
                        final number =
                            chapter['chapter']?.toString().trim() ?? '';
                        final isRead = _isChapterRead(chapterId);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isRead ? Icons.check_circle : Icons.circle_outlined,
                            color: isRead ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          title: Text(
                            title.isNotEmpty
                                ? title
                                : number.isNotEmpty
                                    ? 'Chapter $number'
                                    : 'Chapter ?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _formatChapterDate(
                              chapter['publishedAt']?.toString(),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: _selectedChapterId == chapterId,
                          selectedTileColor:
                              const Color(0xFF483D8B).withAlpha(90),
                          onTap: () => _openChapter(chapter),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _xComicScanId(Map<dynamic, dynamic> chapter) {
    final explicit = chapter['scanId']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) return explicit;

    // Compatibility with xComic details cached before scan metadata became a
    // first-class part of MangaChapter. Those builds appended the scan id to
    // the chapter title/uploader.
    for (final value in [chapter['uploader'], chapter['title']]) {
      final match = RegExp(r'#([a-zA-Z0-9_-]+)').firstMatch('$value');
      if (match != null) return match.group(1)!;
    }
    return 'unknown';
  }

  String _xComicScanName(Map<dynamic, dynamic> chapter) {
    final explicit = chapter['scanName']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final uploader = chapter['uploader']?.toString().trim() ?? '';
    if (uploader.isEmpty || uploader.startsWith('missing')) return '';
    return uploader.replaceFirst(RegExp(r'\s*#[a-zA-Z0-9_-]+\s*$'), '').trim();
  }

  String _formatChapterDate(String? rawDate) {
    final value = rawDate?.trim() ?? '';
    if (value.isEmpty) return 'No date';
    if (RegExp(
      r'^(?:today|yesterday|\d+\s*(?:s|m|h|d|w|mo|y)(?:inute|our|ay|eek|onth|ear)?s?\s+ago)$',
      caseSensitive: false,
    ).hasMatch(value)) {
      return value;
    }
    return _formatDate(value);
  }

  bool _isChapterRead(String chapterId) {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    return (fontProvider.selectedChapterIds[bookDetails['id']] ?? [])
        .any((chapter) => chapter['id']?.toString() == chapterId);
  }

  Future<void> _openChapter(Map<dynamic, dynamic> chapter) async {
    final chapterId = (chapter['id'] ?? '').toString();
    final chapterNumber = (chapter['chapter'] ?? '').toString();
    setState(() {
      _isLoadingChapter = true;
      _selectedChapterId = chapterId;
    });

    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    await fontProvider.saveSingleSelectedChapterId(
      bookDetails['id'],
      chapterId,
      chapterNumber,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Text('Loading chapter...'),
        SizedBox(width: 10),
        CircularProgressIndicator(),
      ]),
      duration: const Duration(minutes: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
    ));

    try {
      final fontApi = widget.scrapper ??
          fontProvider.findScrapperForBook(bookDetails) ??
          fontProvider.selectedFontApi;
      final webViewUrl = fontApi is WebViewChapterMangaSource
          ? (fontApi as WebViewChapterMangaSource)
              .chapterWebUri(
                mangaId: bookDetails['id'].toString(),
                chapterId: chapterId,
              )
              .toString()
          : '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChapterBookScreen(
            bookTitle: bookDetails['title'],
            chapterId: chapterId,
            chapterTitle: chapter['title'],
            mangaID: bookDetails['id'].toString(),
            chapterNumber: chapterNumber,
            chapterWebViewUrl: webViewUrl,
            scrapper: fontApi,
            onChapterCompleted: _mangaProgressCallback(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to load chapter: $error'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      if (kDebugMode) print('Failed to load chapter: $error');
    } finally {
      if (mounted) setState(() => _isLoadingChapter = false);
    }
  }

  Future<void> _addMangaToAniList(TrackerController trackers) async {
    setState(() => _syncingTrackers = true);
    try {
      final names = await trackers.addMangaToConnectedTrackers(
        title: bookDetails['title']?.toString() ?? '',
        aniListId: _externalTrackerId('anilist'),
        malId: _externalTrackerId('mal'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${names.join(' and ')}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _syncingTrackers = false);
    }
  }

  Future<void> Function(int chapter)? _mangaProgressCallback() {
    final trackers = context.read<TrackerController>();
    if (!trackers.aniListConnectedAndEnabled) return null;
    final title = bookDetails['title']?.toString() ?? '';
    final aniListId = _externalTrackerId('anilist');
    final malId = _externalTrackerId('mal');
    return (chapter) async {
      await trackers.updateMangaProgressOnConnectedTrackers(
        title: title,
        chapter: chapter,
        aniListId: aniListId,
        malId: malId,
      );
    };
  }

  int? _externalTrackerId(String tracker) {
    final externalIds = bookDetails['externalIds'];
    final candidates = <dynamic>[
      if (externalIds is Map) externalIds[tracker],
      if (externalIds is Map) externalIds['${tracker}Id'],
      bookDetails[tracker],
      bookDetails['${tracker}Id'],
    ];
    for (final value in candidates) {
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<Widget> _buildLanguageFilterButtons() {
    List<String> languagePrefixes = ((bookDetails['chapters'] as List?) ?? [])
        .map<String>((chapter) => chapter['translatedLanguage'].toString())
        .toSet()
        .toList();

    return languagePrefixes.map((prefix) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () {
            _filterChaptersByLanguage(prefix);
          },
          child: Text(prefix),
        ),
      );
    }).toList();
  }

  Widget _buildWebView(BuildContext context) {
    final String url = bookDetails['mangaUrl'] ?? 'https://www.google.com';
    Widget webViewContent;

    if (kIsWeb) {
      return Center(
        child: Text('Web view not supported on this platform.'),
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final controller = flutter_webview.WebViewController();
      controller.setJavaScriptMode(flutter_webview.JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0x00000000));
      controller.setNavigationDelegate(flutter_webview.NavigationDelegate(
        onProgress: (int progress) {
          // Update loading bar
        },
        onPageStarted: (String url) {},
        onPageFinished: (String url) {},
        onWebResourceError: (flutter_webview.WebResourceError error) {},
        onNavigationRequest: (flutter_webview.NavigationRequest request) {
          return flutter_webview.NavigationDecision.navigate;
        },
      ));
      controller.loadRequest(Uri.parse(url));

      webViewContent = flutter_webview.WebViewWidget(
        controller: controller,
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      webViewContent = FutureBuilder<webview_windows.WebviewController>(
          future: _initializeWebviewController(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final controller = snapshot.data!;
              controller.loadUrl(url);

              return webview_windows.Webview(controller);
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          });
    } else {
      webViewContent = Center(
        child: Text('Platform not supported.'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(bookDetails['title']),
        backgroundColor: Color.fromARGB(29, 60, 16, 180),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _showWebView = false;
            });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              launchUrl(Uri.parse(url));
            },
          ),
        ],
      ),
      body: webViewContent,
    );
  }
}

Future<webview_windows.WebviewController> _initializeWebviewController() async {
  final controller = webview_windows.WebviewController();
  await controller.initialize();
  return controller;
}

/// Constrói o label do capítulo tratando os diferentes formatos de scrapper:
///   MangaDex : title pode ser vazio,  chapter = '1'   → 'Chapter 1'
///   LuraToons: title é vazio,         chapter = '1.0' → 'Chapter 1.0'
///   MediocreScan: title = 'Capítulo 1', chapter = null → 'Capítulo 1'
String _buildChapterLabel(Map chapter) {
  final title = chapter['title']?.toString().trim() ?? '';
  final num = chapter['chapter']?.toString().trim() ?? '';
  if (title.isNotEmpty && num.isNotEmpty) return '$title - Chapter $num';
  if (title.isNotEmpty) return title;
  if (num.isNotEmpty) return 'Chapter $num';
  return 'Chapter ?';
}

/// Extrai o nome de um campo de pessoa que pode vir em formatos distintos:
///   - String direta: 'Brandon Chen'         → retorna a própria string
///   - Map com 'name': {'name': 'X', ...}    → retorna map['name']
///   - null                                  → retorna null
String? _extractPersonName(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is Map) return value['name']?.toString();
  return value.toString();
}

String _formatDate(String? date) {
  if (date == null) {
    return 'No date';
  }

  try {
    final DateTime parsedDate = DateTime.parse(date);
    return DateFormat('dd MMM yyyy').format(parsedDate);
  } catch (e) {
    return 'Invalid date';
  }
}

String _formatVolume(String? volume) {
  if (volume == null) {
    return 'No volume';
  }

  try {
    final int parsedVolume = int.parse(volume);
    return parsedVolume.toString();
  } catch (e) {
    return 'Invalid volume';
  }
}
