import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/pages/tracker_media_details_screen.dart';
import 'package:star_scrapper_app/pages/tracker_season_screen.dart';
import 'package:star_scrapper_app/pages/tracker_source_search.dart';

class TrackerHomepage extends StatefulWidget {
  const TrackerHomepage({super.key});

  @override
  State<TrackerHomepage> createState() => _TrackerHomepageState();
}

class _TrackerHomepageState extends State<TrackerHomepage> {
  static const _tutorialSeenKey = 'discover_tracker_tutorial_seen_v1';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  TrackedMediaType _type = TrackedMediaType.anime;
  TrackerSort _sort = TrackerSort.popularity;
  final Set<String> _tags = {};
  final Set<String> _genres = {};
  Future<TrackerHomeData>? _homeFuture;
  Future<TrackerTaxonomy>? _taxonomyFuture;
  final List<TrackerMedia> _searchItems = [];
  bool _searchActive = false;
  bool _searchLoading = false;
  bool _searchHasMore = false;
  Object? _searchError;
  int _searchPage = 0;
  int _searchGeneration = 0;
  String _activeSearchQuery = '';
  List<String> _activeSearchTags = const [];
  List<String> _activeSearchGenres = const [];
  TrackerSort _activeSearchSort = TrackerSort.popularity;
  TrackedMediaType _activeSearchType = TrackedMediaType.anime;
  bool _showFilters = false;
  String _trackerSignature = '';
  bool _tutorialCheckStarted = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  Future<void> _showTutorialOnFirstUse() async {
    if (_tutorialCheckStarted) return;
    _tutorialCheckStarted = true;
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || preferences.getBool(_tutorialSeenKey) == true) return;
    await _showDiscoverTutorial();
    await preferences.setBool(_tutorialSeenKey, true);
  }

  Future<void> _showDiscoverTutorial() => showDialog<void>(
        context: context,
        builder: (dialogContext) => const _DiscoverTutorialDialog(),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDiscoverVisible = context.watch<AppState>().currentIndex == 1;
    if (isDiscoverVisible && !_tutorialCheckStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTutorialOnFirstUse();
      });
    }
    final tracker = context.watch<TrackerController>();
    final signature = [
      tracker.initialized,
      tracker.aniListEnabled,
      tracker.malEnabled,
      tracker.malClientId,
      tracker.includeAdult,
      tracker.connectedUsername,
      _type,
    ].join(':');
    if (_trackerSignature == signature) return;
    _trackerSignature = signature;
    _resetSearchState();
    _homeFuture = tracker.loadHome(_type);
    _taxonomyFuture = tracker.loadTaxonomy();
  }

  void _reloadHome() {
    final controller = context.read<TrackerController>();
    setState(() {
      _resetSearchState();
      _homeFuture = controller.loadHome(_type);
    });
  }

  void _runSearch() {
    final generation = ++_searchGeneration;
    setState(() {
      _searchActive = true;
      _searchItems.clear();
      _searchPage = 0;
      _searchHasMore = true;
      _searchError = null;
      _activeSearchQuery = _searchController.text;
      _activeSearchTags = List.of(_tags);
      _activeSearchGenres = List.of(_genres);
      _activeSearchSort = _sort;
      _activeSearchType = _type;
    });
    _loadSearchPage(generation);
  }

  Future<void> _loadSearchPage(int generation) async {
    if (_searchLoading || !_searchHasMore || generation != _searchGeneration) {
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final page = await context.read<TrackerController>().search(
            query: _activeSearchQuery,
            type: _activeSearchType,
            tags: _activeSearchTags,
            genres: _activeSearchGenres,
            sort: _activeSearchSort,
            page: _searchPage + 1,
          );
      if (!mounted || generation != _searchGeneration) return;
      final known = _searchItems.map(_mediaKey).toSet();
      setState(() {
        _searchItems.addAll(
          page.items.where((item) => known.add(_mediaKey(item))),
        );
        _searchPage = page.page;
        _searchHasMore = page.hasNextPage;
        _searchError = null;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searchError = error);
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searchLoading = false);
      }
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        !_searchActive ||
        _searchLoading ||
        !_searchHasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 520) {
      _loadSearchPage(_searchGeneration);
    }
  }

  String _mediaKey(TrackerMedia media) => media.malId == null
      ? '${media.tracker.name}:${media.id}'
      : 'mal:${media.malId}';

  void _resetSearchState() {
    _searchGeneration++;
    _searchActive = false;
    _searchItems.clear();
    _searchPage = 0;
    _searchHasMore = false;
    _searchLoading = false;
    _searchError = null;
  }

  void _clearSearch() {
    _searchController.clear();
    _tags.clear();
    _genres.clear();
    _reloadHome();
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TrackerController>();

    return RefreshIndicator(
      onRefresh: () async {
        _reloadHome();
        await _homeFuture;
      },
      child: CustomScrollView(
        controller: _scrollController,
        key: PageStorageKey(_type),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tracker.connectedUsername == null
                              ? 'Discover'
                              : 'Welcome back, ${tracker.connectedUsername}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      FilterChip(
                        selected: tracker.includeAdult,
                        avatar: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Adult'),
                        onSelected: (value) async {
                          await tracker.setIncludeAdult(value);
                          if (mounted) _reloadHome();
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'How Discover works',
                        onPressed: _showDiscoverTutorial,
                        icon: const Icon(Icons.help_outline_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<TrackedMediaType>(
                    segments: const [
                      ButtonSegment(
                        value: TrackedMediaType.anime,
                        icon: Icon(Icons.play_circle_outline_rounded),
                        label: Text('Anime'),
                      ),
                      ButtonSegment(
                        value: TrackedMediaType.manga,
                        icon: Icon(Icons.menu_book_rounded),
                        label: Text('Manga'),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (selection) {
                      _type = selection.first;
                      _clearSearch();
                    },
                  ),
                  if (_type == TrackedMediaType.anime) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TrackerSeasonScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: const Text('Browse season archive'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SearchBar(
                    controller: _searchController,
                    hintText: 'Search tracker titles',
                    leading: const Icon(Icons.search_rounded),
                    trailing: [
                      IconButton(
                        tooltip: 'Filters',
                        onPressed: () => setState(
                          () => _showFilters = !_showFilters,
                        ),
                        icon: Badge(
                          isLabelVisible:
                              _tags.isNotEmpty || _genres.isNotEmpty,
                          label: Text('${_tags.length + _genres.length}'),
                          child: const Icon(Icons.tune_rounded),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty ||
                          _tags.isNotEmpty ||
                          _genres.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear search',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                    onSubmitted: (_) => _runSearch(),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_showFilters) ...[
                    const SizedBox(height: 12),
                    _SearchFilters(
                      selectedTags: _tags,
                      selectedGenres: _genres,
                      taxonomyFuture: _taxonomyFuture,
                      sort: _sort,
                      onTagChanged: (tag, selected) {
                        setState(() {
                          selected ? _tags.add(tag) : _tags.remove(tag);
                        });
                      },
                      onGenreChanged: (genre, selected) {
                        setState(() {
                          selected ? _genres.add(genre) : _genres.remove(genre);
                        });
                      },
                      onSortChanged: (sort) => setState(() => _sort = sort),
                      onApply: _runSearch,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!tracker.hasEnabledTracker)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _NoTrackers(onOpenSettings: _openSettings),
            )
          else if (_searchActive)
            _SearchResults(
              items: _searchItems,
              loading: _searchLoading,
              hasMore: _searchHasMore,
              error: _searchError,
              onRetry: () => _loadSearchPage(_searchGeneration),
              onOpenDetails: _openDetails,
              onSearchSources: (media) =>
                  openTrackerSourceSearch(context, media),
            )
          else
            _HomeContent(
              future: _homeFuture,
              type: _type,
              onOpenDetails: _openDetails,
              onSearchSources: (media) =>
                  openTrackerSourceSearch(context, media),
              onRetry: _reloadHome,
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  void _openSettings() {
    context.read<AppState>().setIndex(3);
    context.read<TabsState>().setActivePageIndex(3);
  }

  void _openDetails(TrackerMedia media) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackerMediaDetailsScreen(media: media),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _DiscoverTutorialDialog extends StatelessWidget {
  const _DiscoverTutorialDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: colors.onPrimaryContainer,
            size: 30,
          ),
        ),
      ),
      title: const Text('Discover at a glance', textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TutorialStep(
              icon: Icons.swap_horizontal_circle_outlined,
              title: 'Choose what to explore',
              description:
                  'Switch between Anime and Manga. Discover combines the trackers enabled in Account Settings.',
            ),
            SizedBox(height: 10),
            _TutorialStep(
              icon: Icons.manage_search_rounded,
              title: 'Search the tracker catalog',
              description:
                  'Type a title or use filters to browse by popularity, rating, genres, and tags.',
            ),
            SizedBox(height: 10),
            _TutorialStep(
              icon: Icons.touch_app_outlined,
              title: 'Open or find a source',
              description:
                  'Tap a title for tracker details. Touch and hold it to search your enabled sources for that same title.',
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Start exploring'),
        ),
      ],
    );
  }
}

class _TutorialStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final Future<TrackerHomeData>? future;
  final TrackedMediaType type;
  final ValueChanged<TrackerMedia> onOpenDetails;
  final ValueChanged<TrackerMedia> onSearchSources;
  final VoidCallback onRetry;

  const _HomeContent({
    required this.future,
    required this.type,
    required this.onOpenDetails,
    required this.onSearchSources,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<TrackerHomeData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _TrackerError(error: snapshot.error, onRetry: onRetry),
          );
        }
        final data = snapshot.data!;
        return SliverList.list(
          children: [
            if (data.librarySections.isNotEmpty) ...[
              _LibraryHeading(type: type),
              for (final section in data.librarySections)
                _MediaCarousel(
                  section: section,
                  onOpenDetails: onOpenDetails,
                  onSearchSources: onSearchSources,
                ),
            ],
            if (type == TrackedMediaType.anime && data.schedule.isNotEmpty)
              _ScheduleCarousel(
                entries: data.schedule,
                onOpenDetails: onOpenDetails,
                onSearchSources: onSearchSources,
              ),
            for (final section in data.sections)
              _MediaCarousel(
                section: section,
                onOpenDetails: onOpenDetails,
                onSearchSources: onSearchSources,
              ),
          ],
        );
      },
    );
  }
}

class _LibraryHeading extends StatelessWidget {
  final TrackedMediaType type;

  const _LibraryHeading({required this.type});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Row(
        children: [
          Icon(
            type == TrackedMediaType.anime
                ? Icons.playlist_play_rounded
                : Icons.library_books_rounded,
          ),
          const SizedBox(width: 8),
          Text(
            type == TrackedMediaType.anime ? 'Your anime' : 'Your manga',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<TrackerMedia> items;
  final bool loading;
  final bool hasMore;
  final Object? error;
  final VoidCallback onRetry;
  final ValueChanged<TrackerMedia> onOpenDetails;
  final ValueChanged<TrackerMedia> onSearchSources;

  const _SearchResults({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.onRetry,
    required this.onOpenDetails,
    required this.onSearchSources,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && loading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty && error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _TrackerError(error: error, onRetry: onRetry),
      );
    }
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('No tracker results found.')),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          sliver: SliverGrid.builder(
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) => _MediaCard(
              media: items[index],
              onTap: () => onOpenDetails(items[index]),
              onLongPress: () => onSearchSources(items[index]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : error != null
                      ? TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try loading more again'),
                        )
                      : hasMore
                          ? const SizedBox.shrink()
                          : const Text('You reached the end.'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleCarousel extends StatelessWidget {
  final List<TrackerScheduleEntry> entries;
  final ValueChanged<TrackerMedia> onOpenDetails;
  final ValueChanged<TrackerMedia> onSearchSources;

  const _ScheduleCarousel({
    required this.entries,
    required this.onOpenDetails,
    required this.onSearchSources,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: 'Release calendar',
      child: SizedBox(
        height: 112,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return SizedBox(
              width: 210,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onOpenDetails(entry.media),
                  onLongPress: () => onSearchSources(entry.media),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        _Cover(uri: entry.media.coverUri, width: 58),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('EEE, MMM d')
                                    .format(entry.releaseAt),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context
                                    .watch<TrackerController>()
                                    .displayTitle(entry.media),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (entry.releaseNumber != null)
                                Text(
                                  'Episode ${entry.releaseNumber}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MediaCarousel extends StatelessWidget {
  final TrackerSection section;
  final ValueChanged<TrackerMedia> onOpenDetails;
  final ValueChanged<TrackerMedia> onSearchSources;

  const _MediaCarousel({
    required this.section,
    required this.onOpenDetails,
    required this.onSearchSources,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: section.title,
      child: SizedBox(
        height: 242,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: section.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final media = section.items[index];
            return SizedBox(
              width: 132,
              child: _MediaCard(
                media: media,
                onTap: () => onOpenDetails(media),
                onLongPress: () => onSearchSources(media),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final TrackerMedia media;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MediaCard({
    required this.media,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(uri: media.coverUri),
                  if (media.score != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${media.score}%'),
                        avatar: const Icon(Icons.star_rounded, size: 14),
                      ),
                    ),
                  if (media.progress != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.history_rounded, size: 14),
                        label: Text(
                          media.progressTotal == null ||
                                  media.progressTotal == 0
                              ? '${media.progress}'
                              : '${media.progress}/${media.progressTotal}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                context.watch<TrackerController>().displayTitle(media),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final Uri? uri;
  final double? width;

  const _Cover({required this.uri, this.width});

  @override
  Widget build(BuildContext context) {
    if (uri == null || uri.toString().isEmpty) {
      return Container(
        width: width,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return CachedNetworkImage(
      imageUrl: uri.toString(),
      width: width,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SearchFilters extends StatefulWidget {
  final Set<String> selectedTags;
  final Set<String> selectedGenres;
  final Future<TrackerTaxonomy>? taxonomyFuture;
  final TrackerSort sort;
  final void Function(String, bool) onTagChanged;
  final void Function(String, bool) onGenreChanged;
  final ValueChanged<TrackerSort> onSortChanged;
  final VoidCallback onApply;

  const _SearchFilters({
    required this.selectedTags,
    required this.selectedGenres,
    required this.taxonomyFuture,
    required this.sort,
    required this.onTagChanged,
    required this.onGenreChanged,
    required this.onSortChanged,
    required this.onApply,
  });

  @override
  State<_SearchFilters> createState() => _SearchFiltersState();
}

class _SearchFiltersState extends State<_SearchFilters> {
  String _filter = '';
  bool _genresExpanded = false;
  bool _tagsExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<TrackerSort>(
              initialValue: widget.sort,
              decoration: const InputDecoration(labelText: 'Order by'),
              items: const [
                DropdownMenuItem(
                  value: TrackerSort.popularity,
                  child: Text('Popularity'),
                ),
                DropdownMenuItem(
                  value: TrackerSort.trending,
                  child: Text('Trending'),
                ),
                DropdownMenuItem(
                  value: TrackerSort.mostRecent,
                  child: Text('Most recent'),
                ),
                DropdownMenuItem(
                  value: TrackerSort.highestRated,
                  child: Text('Highest rated'),
                ),
              ],
              onChanged: (value) {
                if (value != null) widget.onSortChanged(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Find genres or tags',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              onChanged: (value) => setState(() {
                _filter = value.trim();
                if (_filter.isNotEmpty) {
                  _genresExpanded = true;
                  _tagsExpanded = true;
                }
              }),
            ),
            const SizedBox(height: 12),
            _buildTaxonomy(context),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: widget.onApply,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxonomy(BuildContext context) {
    final future = widget.taxonomyFuture;
    if (future == null) return const LinearProgressIndicator();
    return FutureBuilder<TrackerTaxonomy>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return Text('Could not load genres and tags: ${snapshot.error}');
        }
        final taxonomy = snapshot.data ?? TrackerTaxonomy.empty;
        final needle = _filter.toLowerCase();
        final genres = taxonomy.genres
            .where(
                (item) => needle.isEmpty || item.toLowerCase().contains(needle))
            .toList();
        final tags = taxonomy.tags
            .where((item) =>
                needle.isEmpty ||
                item.name.toLowerCase().contains(needle) ||
                item.category.toLowerCase().contains(needle))
            .toList();
        if (genres.isEmpty && tags.isEmpty) {
          return const Text('No matching genres or tags.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (genres.isNotEmpty) ...[
              ExpansionTile(
                key: ValueKey('genres-$_genresExpanded'),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _genresExpanded,
                onExpansionChanged: (value) =>
                    setState(() => _genresExpanded = value),
                leading: const Icon(Icons.category_outlined),
                title: Text(
                  widget.selectedGenres.isEmpty
                      ? 'Genres'
                      : 'Genres (${widget.selectedGenres.length} selected)',
                ),
                children: _genresExpanded
                    ? [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final genre in genres)
                                FilterChip(
                                  label: Text(genre),
                                  selected:
                                      widget.selectedGenres.contains(genre),
                                  onSelected: (selected) =>
                                      widget.onGenreChanged(genre, selected),
                                ),
                            ],
                          ),
                        ),
                      ]
                    : const [],
              ),
            ],
            if (tags.isNotEmpty) ...[
              ExpansionTile(
                key: ValueKey('tags-$_tagsExpanded'),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _tagsExpanded,
                onExpansionChanged: (value) =>
                    setState(() => _tagsExpanded = value),
                leading: const Icon(Icons.tag_rounded),
                title: Text(
                  widget.selectedTags.isEmpty
                      ? 'Tags'
                      : 'Tags (${widget.selectedTags.length} selected)',
                ),
                children: _tagsExpanded
                    ? [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final tag in tags)
                                FilterChip(
                                  tooltip: tag.category,
                                  label: Text(tag.name),
                                  selected:
                                      widget.selectedTags.contains(tag.name),
                                  onSelected: (selected) =>
                                      widget.onTagChanged(tag.name, selected),
                                ),
                            ],
                          ),
                        ),
                      ]
                    : const [],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TrackerError extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  const _TrackerError({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              error?.toString() ?? 'Could not load tracker data.',
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoTrackers extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _NoTrackers({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_disabled_rounded, size: 54),
            const SizedBox(height: 12),
            Text(
              'Enable a tracker to start discovering titles.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
