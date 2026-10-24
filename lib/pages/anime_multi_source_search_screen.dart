import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/application/sources/anime_multi_source_search.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/search/source_results_carousel.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/pages/anime_source_catalog_screen.dart';
import 'package:star_scrapper_app/pages/anime_source_details_screen.dart';
import 'package:star_scrapper_app/pages/anime_source_webview_screen.dart';

class AnimeMultiSourceSearchScreen extends StatefulWidget {
  final List<AnimeSource> sources;
  final List<String> initialQueries;
  final AnimeMultiSourceSearch searchService;

  const AnimeMultiSourceSearchScreen({
    super.key,
    required this.sources,
    this.initialQueries = const [],
    this.searchService = const AnimeMultiSourceSearch(),
  });

  @override
  State<AnimeMultiSourceSearchScreen> createState() =>
      _AnimeMultiSourceSearchScreenState();
}

class _AnimeMultiSourceSearchScreenState
    extends State<AnimeMultiSourceSearchScreen> {
  late final TextEditingController _searchController;
  List<AnimeSourceSearchGroup> _groups = const [];
  List<AnimeLibraryRecord> _libraryResults = const [];
  List<String> _queries = const [];
  bool _loading = false;
  int _requestGeneration = 0;
  StreamSubscription<AnimeSourceSearchGroup>? _searchSubscription;

  @override
  void initState() {
    super.initState();
    _queries = widget.initialQueries;
    final initial = widget.initialQueries.firstOrNull?.trim() ?? '';
    _searchController = TextEditingController(text: initial);
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(_queries));
    }
  }

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(List<String> queries) async {
    final generation = ++_requestGeneration;
    await _searchSubscription?.cancel();
    if (!mounted || generation != _requestGeneration) return;
    final hasQuery = queries.any((query) => query.trim().isNotEmpty);
    if (!hasQuery) {
      setState(() {
        _queries = const [];
        _groups = const [];
        _libraryResults = const [];
        _loading = false;
      });
      return;
    }
    final libraryResults = widget.searchService.searchLibrary(
      records: context.read<AnimeLibraryController>().favorites,
      queries: queries,
    );
    setState(() {
      _queries = queries;
      _groups = [
        for (final source in widget.sources)
          AnimeSourceSearchGroup.loading(
            source: source,
            query: queries.firstWhere((query) => query.trim().isNotEmpty),
          ),
      ];
      _libraryResults = libraryResults;
      _loading = widget.sources.isNotEmpty;
    });

    _searchSubscription = widget.searchService
        .searchProgressively(
      sources: widget.sources,
      queries: queries,
    )
        .listen(
      (completed) {
        if (!mounted || generation != _requestGeneration) return;
        setState(() {
          _groups = [
            for (final group in _groups)
              if (group.source.id == completed.source.id) completed else group,
          ];
          _loading = _groups.any((group) => group.isLoading);
        });
      },
      onDone: () {
        if (!mounted || generation != _requestGeneration) return;
        setState(() => _loading = false);
      },
    );
  }

  Future<void> _verifySource(AnimeSourceSearchGroup group) async {
    final source = group.source;
    if (source is! BrowserSessionAnimeSource) return;
    final browserSource = source as BrowserSessionAnimeSource;
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnimeSourceSessionScreen(source: browserSource),
      ),
    );
    if (verified == true && mounted) await _search(_queries);
  }

  void _openLibraryRecord(AnimeLibraryRecord record) {
    final source = context
        .read<FontProvider>()
        .animeSources
        .where((source) => source.id == record.sourceId)
        .firstOrNull;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This anime source is unavailable.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeSourceDetailsScreen(
          source: source,
          item: record.toCatalogItem(),
        ),
      ),
    );
  }

  List<SourceResultsPanel> _resultPanels() {
    final panels = <SourceResultsPanel>[
      SourceResultsPanel(
        id: 'library',
        title: 'Your library',
        icon: Icons.video_library_rounded,
        resultCount: _libraryResults.length,
        previewCount: _libraryResults.length,
        emptyState: const Center(child: Text('No results in your library.')),
        itemBuilder: (context, index) {
          final record = _libraryResults[index];
          return _AnimeSearchTile(
            title: record.title,
            subtitle: record.subtitle ?? 'Library',
            coverUrl: record.coverUrl,
            onTap: () => _openLibraryRecord(record),
          );
        },
      ),
    ];
    for (final group in _groups) {
      final previewCount = group.items.length > 8 ? 8 : group.items.length;
      panels.add(
        SourceResultsPanel(
          id: group.source.id,
          title: group.source.name,
          icon: Icons.public_rounded,
          resultCount: group.items.length,
          previewCount: group.error == null ? previewCount : 0,
          isLoading: group.isLoading,
          onMore: group.isLoading || group.error != null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AnimeSourceCatalogScreen(
                        source: group.source,
                        initialQuery: group.query,
                      ),
                    ),
                  ),
          emptyState: group.isLoading
              ? null
              : group.error == null
                  ? const Center(child: Text('No results in this source.'))
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 40),
                          const SizedBox(height: 10),
                          Text(
                            'Could not search ${group.source.name}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            group.error.toString(),
                            textAlign: TextAlign.center,
                          ),
                          if (group.error is AnimeSourceSessionRequired &&
                              group.source is BrowserSessionAnimeSource) ...[
                            const SizedBox(height: 10),
                            FilledButton.tonal(
                              onPressed: () => _verifySource(group),
                              child: const Text('Verify in browser'),
                            ),
                          ],
                        ],
                      ),
                    ),
          itemBuilder: (context, index) {
            final item = group.items[index];
            return _AnimeSearchTile(
              title: item.title,
              subtitle: item.subtitle ?? group.source.name,
              coverUrl: item.coverUri?.toString(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AnimeSourceDetailsScreen(
                    source: group.source,
                    item: item,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return panels;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search anime sources')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search enabled anime sources',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      _search(const []);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (query) => _search([query]),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _queries.isEmpty
                ? const _SearchMessage(
                    icon: Icons.search_rounded,
                    title: 'Search enabled sources',
                    message:
                        'Library and source results will be grouped separately.',
                  )
                : SourceResultsCarousel(
                    key: ValueKey(
                      'anime-panels-${_groups.map((group) => group.source.id).join('-')}',
                    ),
                    panels: _resultPanels(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnimeSearchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverUrl;
  final VoidCallback onTap;

  const _AnimeSearchTile({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: coverUrl == null || coverUrl!.isEmpty
          ? const SizedBox(
              width: 42,
              height: 58,
              child: Icon(Icons.movie_outlined),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: coverUrl!,
                width: 42,
                height: 58,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _SearchMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
