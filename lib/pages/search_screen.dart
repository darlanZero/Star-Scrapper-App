import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/search/source_results_carousel.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

class SearchScreen extends StatefulWidget {
  final List<String> initialQueries;
  final bool searchEnabledSources;
  final SourceContentType? sourceType;

  const SearchScreen({
    super.key,
    this.initialQueries = const [],
    this.searchEnabledSources = false,
    this.sourceType,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _searchController;

  List<Map<String, dynamic>> _libraryResults = [];
  Map<String, List<dynamic>> _onlineResults = {};
  Set<String> _onlinePendingSources = {};
  Set<String> _onlineFailedSources = {};
  bool _isSearchingOnline = false;
  bool _searchOnline = false;
  String _lastQuery = '';
  List<String> _sourceQueries = const [];
  int _onlineSearchGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialQueries.isEmpty ? '' : widget.initialQueries.first.trim();
    _searchController = TextEditingController(text: initial);
    _sourceQueries = widget.initialQueries;
    _searchOnline = widget.searchEnabledSources;
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onQueryChanged(initial, preserveSourceQueries: true);
      });
    }
  }

  void _onQueryChanged(
    String query, {
    bool preserveSourceQueries = false,
  }) {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final q = query.trim().toLowerCase();

    if (q == _lastQuery) return;
    _lastQuery = q;
    if (!preserveSourceQueries) _sourceQueries = [query.trim()];

    if (q.isEmpty) {
      _onlineSearchGeneration++;
      setState(() {
        _libraryResults = [];
        _onlineResults = {};
        _onlinePendingSources = {};
        _onlineFailedSources = {};
        _isSearchingOnline = false;
      });
      return;
    }

    // Busca local: favoritos + histórico sem duplicatas
    final allBooks = [
      ...fontProvider.favoritedBooks,
      ...fontProvider.readBooks.where(
        (rb) => !fontProvider.favoritedBooks.any((fb) => fb['id'] == rb['id']),
      ),
    ];

    setState(() {
      _libraryResults = allBooks.where((book) {
        final title = (book['title'] ?? '').toString().toLowerCase();
        return title.contains(q);
      }).toList();
      _onlineResults = {};
      _onlinePendingSources = {};
      _onlineFailedSources = {};
    });

    if (_searchOnline) _runOnlineSearch(_sourceQueries);
  }

  Future<void> _runOnlineSearch(List<String> queries) async {
    final generation = ++_onlineSearchGeneration;
    final normalizedQueries = <String>[];
    final seenQueries = <String>{};
    for (final query in queries.take(4)) {
      final value = query.trim();
      if (value.isNotEmpty && seenQueries.add(value.toLowerCase())) {
        normalizedQueries.add(value);
      }
    }
    if (normalizedQueries.isEmpty) return;
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final activeFonts = fontProvider.activeFonts
        .where((source) =>
            widget.sourceType == null ||
            source.contentType == widget.sourceType)
        .toList();
    if (activeFonts.isEmpty) return;

    setState(() {
      _isSearchingOnline = true;
      _onlineResults = {for (final font in activeFonts) font.name: []};
      _onlinePendingSources = {for (final font in activeFonts) font.name};
      _onlineFailedSources = {};
    });

    await Future.wait(activeFonts.map((font) async {
      var failed = false;
      final unique = <dynamic>[];
      try {
        final matches = await Future.wait(
          normalizedQueries.map(font.api.searchTitle),
        );
        final ids = <String>{};
        for (final list in matches) {
          for (final book in list) {
            final id = font.api.getBookId(book);
            final title = font.api.getTitle(book);
            final key = id.isEmpty ? title.toLowerCase() : id;
            if (ids.add(key)) unique.add(book);
          }
        }
      } catch (_) {
        failed = true;
      }
      if (!mounted || generation != _onlineSearchGeneration) return;
      setState(() {
        _onlineResults[font.name] = unique;
        _onlinePendingSources.remove(font.name);
        if (failed) _onlineFailedSources.add(font.name);
        _isSearchingOnline = _onlinePendingSources.isNotEmpty;
      });
    }));
  }

  void _onToggleOnlineSearch(bool value) {
    setState(() => _searchOnline = value);
    if (value && _lastQuery.isNotEmpty) {
      _runOnlineSearch(_sourceQueries);
    } else if (!value) {
      _onlineSearchGeneration++;
      setState(() {
        _onlineResults = {};
        _onlinePendingSources = {};
        _onlineFailedSources = {};
        _isSearchingOnline = false;
      });
    }
  }

  String _bookTabsLabel(Map<String, dynamic> book) {
    final tabs = book['tabs'];
    if (tabs is List && tabs.isNotEmpty) return tabs.join(', ');
    final tab = book['tab'];
    if (tab is String) return tab;
    return 'Library';
  }

  void _openMangaBook(Fonte source, dynamic book) {
    final normalizedBook = Map<String, dynamic>.from(book as Map);
    normalizedBook['coverImageUrl'] ??= source.api.getCoverImageUrl(book);
    normalizedBook['title'] ??= source.api.getTitle(book);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookDetailsScreen(
          bookDetails: normalizedBook,
          scrapper: source.api,
        ),
      ),
    );
  }

  List<SourceResultsPanel> _resultPanels() {
    final provider = context.read<FontProvider>();
    final sourcesByName = {
      for (final source in provider.activeFonts) source.name: source,
    };
    final panels = <SourceResultsPanel>[
      SourceResultsPanel(
        id: 'library',
        title: 'Your library',
        icon: Icons.library_books_rounded,
        resultCount: _libraryResults.length,
        previewCount: _libraryResults.length,
        emptyState: const Center(child: Text('No results in your library.')),
        itemBuilder: (context, index) {
          final book = _libraryResults[index];
          return _BookListTile(
            title: (book['title'] ?? 'Untitled').toString(),
            subtitle: _bookTabsLabel(book),
            coverUrl: book['coverImageUrl'] ?? book['imageurl'] ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BookDetailsScreen(bookDetails: book),
              ),
            ),
          );
        },
      ),
    ];
    if (!_searchOnline) return panels;
    for (final source in provider.activeFonts) {
      if (!sourcesByName.containsKey(source.name) ||
          !_onlineResults.containsKey(source.name)) {
        continue;
      }
      final results = _onlineResults[source.name] ?? const [];
      final isLoading = _onlinePendingSources.contains(source.name);
      final failed = _onlineFailedSources.contains(source.name);
      final previewCount = results.length > 8 ? 8 : results.length;
      panels.add(
        SourceResultsPanel(
          id: source.id,
          title: source.name,
          icon: Icons.public_rounded,
          resultCount: results.length,
          previewCount: previewCount,
          isLoading: isLoading,
          onMore: isLoading || failed
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MangaSourceSearchResultsScreen(
                        source: source,
                        initialQueries: _sourceQueries,
                      ),
                    ),
                  ),
          emptyState: failed
              ? const Center(child: Text('Could not search this source.'))
              : const Center(child: Text('No results in this source.')),
          itemBuilder: (context, index) {
            final book = results[index];
            return _BookListTile(
              title: source.api.getTitle(book),
              subtitle: (book['status'] ?? '').toString(),
              coverUrl: source.api.getCoverImageUrl(book),
              onTap: () => _openMangaBook(source, book),
            );
          },
        ),
      );
    }
    return panels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          'Search',
          style: TextStyle(
            color: theme.selectedTheme.textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 10.0)],
          ),
        ),
        iconTheme: IconThemeData(
            color: theme.selectedTheme.textTheme.titleMedium?.color),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelText: 'Search titles...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                      )
                    : null,
              ),
              style: TextStyle(
                  color: theme.selectedTheme.textTheme.displayMedium?.color),
              controller: _searchController,
              onChanged: _onQueryChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Search enabled sources',
                  style: TextStyle(
                      color: theme.selectedTheme.textTheme.displaySmall?.color),
                ),
                Row(
                  children: [
                    if (_isSearchingOnline) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Switch(
                        value: _searchOnline, onChanged: _onToggleOnlineSearch),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _lastQuery.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'Type to search your library',
                          style: TextStyle(
                              color: theme
                                  .selectedTheme.textTheme.displaySmall?.color),
                        ),
                      ],
                    ),
                  )
                : SourceResultsCarousel(
                    key: ValueKey(
                      'manga-panels-${_onlineResults.keys.join('-')}',
                    ),
                    panels: _resultPanels(),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _BookListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String coverUrl;
  final VoidCallback onTap;

  const _BookListTile({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: coverUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                coverUrl,
                width: 40,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, size: 40),
              ),
            )
          : const Icon(Icons.book, size: 40),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
      onTap: onTap,
    );
  }
}

class MangaSourceSearchResultsScreen extends StatefulWidget {
  final Fonte source;
  final List<String> initialQueries;

  const MangaSourceSearchResultsScreen({
    super.key,
    required this.source,
    required this.initialQueries,
  });

  @override
  State<MangaSourceSearchResultsScreen> createState() =>
      _MangaSourceSearchResultsScreenState();
}

class _MangaSourceSearchResultsScreenState
    extends State<MangaSourceSearchResultsScreen> {
  late final TextEditingController _controller;
  List<dynamic> _results = const [];
  Object? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialQueries.firstOrNull ?? '',
    );
    _load(widget.initialQueries);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load(List<String> queries) async {
    final generation = ++_generation;
    final normalized = <String>[];
    final seenQueries = <String>{};
    for (final query in queries) {
      final value = query.trim();
      if (value.isNotEmpty && seenQueries.add(value.toLowerCase())) {
        normalized.add(value);
      }
      if (normalized.length == 4) break;
    }
    if (normalized.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await Future.wait(
        normalized.map(widget.source.api.searchTitle),
      );
      final results = <dynamic>[];
      final ids = <String>{};
      for (final list in matches) {
        for (final book in list) {
          final id = widget.source.api.getBookId(book);
          final title = widget.source.api.getTitle(book);
          if (ids.add(id.isEmpty ? title.toLowerCase() : id)) {
            results.add(book);
          }
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _open(dynamic book) {
    final normalized = Map<String, dynamic>.from(book as Map);
    normalized['coverImageUrl'] ??= widget.source.api.getCoverImageUrl(book);
    normalized['title'] ??= widget.source.api.getTitle(book);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailsScreen(
          bookDetails: normalized,
          scrapper: widget.source.api,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.source.name)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _controller,
                hintText: 'Search ${widget.source.name}',
                leading: const Icon(Icons.search_rounded),
                onSubmitted: (query) => _load([query]),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Could not search ${widget.source.name}: $_error',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _results.isEmpty
                          ? const Center(child: Text('No titles found.'))
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final book = _results[index];
                                return _BookListTile(
                                  title: widget.source.api.getTitle(book),
                                  subtitle: (book['status'] ?? '').toString(),
                                  coverUrl:
                                      widget.source.api.getCoverImageUrl(book),
                                  onTap: () => _open(book),
                                );
                              },
                            ),
            ),
          ],
        ),
      );
}
