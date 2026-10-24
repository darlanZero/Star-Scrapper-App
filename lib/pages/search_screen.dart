import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
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
  bool _isSearchingOnline = false;
  bool _searchOnline = false;
  String _lastQuery = '';
  List<String> _sourceQueries = const [];

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
      setState(() {
        _libraryResults = [];
        _onlineResults = {};
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
    });

    if (_searchOnline) _runOnlineSearch(_sourceQueries);
  }

  Future<void> _runOnlineSearch(List<String> queries) async {
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

    setState(() => _isSearchingOnline = true);

    try {
      final results = await Future.wait(
        activeFonts.map((font) async {
          try {
            final matches = await Future.wait(
              normalizedQueries.map((q) => font.api.search(q)),
            );
            final unique = <Map<String, dynamic>>[];
            final ids = <String>{};
            for (final page in matches) {
              for (final item in page.items) {
                final key =
                    item.id.isEmpty ? item.title.toLowerCase() : item.id;
                if (ids.add(key)) unique.add(item.toJson());
              }
            }
            return MapEntry(font.name, unique);
          } catch (_) {
            return MapEntry(font.name, <dynamic>[]);
          }
        }),
      );
      if (mounted) {
        setState(() {
          _onlineResults = Map.fromEntries(results);
          _isSearchingOnline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingOnline = false);
    }
  }

  void _onToggleOnlineSearch(bool value) {
    setState(() => _searchOnline = value);
    if (value && _lastQuery.isNotEmpty) {
      _runOnlineSearch(_sourceQueries);
    } else if (!value) {
      setState(() => _onlineResults = {});
    }
  }

  String _bookTabsLabel(Map<String, dynamic> book) {
    final tabs = book['tabs'];
    if (tabs is List && tabs.isNotEmpty) return tabs.join(', ');
    final tab = book['tab'];
    if (tab is String) return tab;
    return 'Library';
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
                : ListView(
                    children: [
                      // ── Biblioteca ──
                      _SectionHeader(
                        label: 'In your library (${_libraryResults.length})',
                        icon: Icons.library_books,
                      ),
                      if (_libraryResults.isEmpty)
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('No results in your library.',
                              style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ..._libraryResults.map((book) => _BookListTile(
                              title: (book['title'] ?? 'Untitled').toString(),
                              subtitle: _bookTabsLabel(book),
                              coverUrl: book['coverImageUrl'] ??
                                  book['imageurl'] ??
                                  '',
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        BookDetailsScreen(bookDetails: book),
                                  )),
                            )),

                      // ── Online por fonte ──
                      if (_searchOnline) ...[
                        const SizedBox(height: 8),
                        for (final entry in _onlineResults.entries) ...[
                          _SectionHeader(
                              label: '${entry.key} (${entry.value.length})',
                              icon: Icons.public),
                          if (entry.value.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Text('No results.',
                                  style: TextStyle(color: Colors.grey)),
                            )
                          else
                            ...entry.value.take(10).map((book) {
                              final fontProvider = Provider.of<FontProvider>(
                                  context,
                                  listen: false);
                              final font = fontProvider.activeFonts.firstWhere(
                                (f) => f.name == entry.key,
                                orElse: () => fontProvider.fonts.first,
                              );
                              return _BookListTile(
                                title: (book['title'] ?? '').toString(),
                                subtitle: (book['latestChapter'] ?? '')
                                    .toString(),
                                coverUrl:
                                    (book['coverImageUrl'] ?? '').toString(),
                                onTap: () {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BookDetailsScreen(
                                          bookDetails:
                                              Map<String, dynamic>.from(
                                                  book as Map),
                                          scrapper: font.api,
                                        ),
                                      ));
                                },
                              );
                            }),
                        ],
                      ],
                    ],
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

// ── Widgets auxiliares ──

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.lightGreen),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.lightGreen,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
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
