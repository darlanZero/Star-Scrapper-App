import 'package:flutter/material.dart';
import 'package:star_scrapper_app/components/Shared/anime_source_image.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/pages/anime_source_details_screen.dart';
import 'package:star_scrapper_app/pages/anime_source_webview_screen.dart';

class AnimeSourceCatalogScreen extends StatefulWidget {
  final AnimeSource source;
  final AnimeCatalogFilter initialFilter;
  final String? initialQuery;

  const AnimeSourceCatalogScreen({
    super.key,
    required this.source,
    this.initialFilter = AnimeCatalogFilter.recent,
    this.initialQuery,
  });

  @override
  State<AnimeSourceCatalogScreen> createState() =>
      _AnimeSourceCatalogScreenState();
}

class _AnimeSourceCatalogScreenState extends State<AnimeSourceCatalogScreen> {
  final _scrollController = ScrollController();
  late final TextEditingController _searchController;
  late AnimeCatalogFilter _filter;
  final List<AnimeCatalogItem> _items = [];
  String? _nextCursor;
  String? _query;
  Object? _error;
  bool _loading = false;
  int _requestGeneration = 0;
  AnimeSearchRequest? _advancedRequest;
  bool _sessionPromptOpen = false;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _query = widget.initialQuery?.trim();
    _searchController = TextEditingController(text: _query);
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500 &&
        !_loading &&
        _nextCursor != null) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_requestGeneration : _requestGeneration;
    if (reset) {
      setState(() {
        _items.clear();
        _nextCursor = null;
        _error = null;
      });
    }
    setState(() => _loading = true);
    try {
      final cursor = reset ? null : _nextCursor;
      final page = switch (widget.source) {
        final FilterableAnimeSource source when _advancedRequest != null =>
          await source.filter(
            _advancedRequest!.copyWith(query: _query ?? ''),
            cursor: cursor,
          ),
        _ when (_query?.isNotEmpty ?? false) =>
          await widget.source.search(_query!, cursor: cursor),
        _ => await widget.source.browse(filter: _filter, cursor: cursor),
      };
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        final existingIds = _items.map((item) => item.id).toSet();
        _items.addAll(
          page.items.where((item) => existingIds.add(item.id)),
        );
        _nextCursor = page.nextCursor;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifySession() async {
    if (!mounted || _sessionPromptOpen) return;
    _sessionPromptOpen = true;
    final source = widget.source is BrowserSessionAnimeSource
        ? widget.source as BrowserSessionAnimeSource
        : null;
    final verified = source != null
        ? await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AnimeSourceSessionScreen(source: source),
            ),
          )
        : false;
    _sessionPromptOpen = false;
    if (verified == true && mounted) _load(reset: true);
  }

  void _search(String value) {
    final query = value.trim();
    setState(() => _query = query.isEmpty ? null : query);
    _load(reset: true);
  }

  void _selectFilter(AnimeCatalogFilter filter) {
    if (_filter == filter && _query == null) return;
    _searchController.clear();
    setState(() {
      _filter = filter;
      _query = null;
      _advancedRequest = null;
    });
    _load(reset: true);
  }

  Future<void> _showAdvancedFilters() async {
    final source = widget.source;
    if (source is! FilterableAnimeSource) return;
    final options = await (source as FilterableAnimeSource).getSearchOptions();
    if (!mounted) return;
    final selected = await showModalBottomSheet<AnimeSearchRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AdvancedFilterSheet(
        options: options,
        initial: _advancedRequest,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _advancedRequest = selected.hasFilters ? selected : null);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.name)),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    SearchBar(
                      controller: _searchController,
                      hintText: 'Search ${widget.source.name}',
                      leading: const Icon(Icons.search_rounded),
                      trailing: [
                        if (widget.source is FilterableAnimeSource)
                          IconButton(
                            tooltip: 'Advanced filters',
                            onPressed: _showAdvancedFilters,
                            icon: Badge(
                              isLabelVisible:
                                  _advancedRequest?.hasFilters == true,
                              child: const Icon(Icons.tune_rounded),
                            ),
                          ),
                        if (_query != null)
                          IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _search('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                      onSubmitted: _search,
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.source.catalogFilters
                            .map(
                              (filter) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  selected: _advancedRequest == null &&
                                      _filter == filter,
                                  label: Text(
                                    _catalogFilterLabel(filter, widget.source),
                                  ),
                                  avatar: Icon(
                                    _catalogFilterIcon(filter),
                                    size: 18,
                                  ),
                                  onSelected: (_) => _selectFilter(filter),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _MessageState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load ${widget.source.name}',
                  message: _error.toString(),
                  actionLabel: _error is AnimeSourceSessionRequired
                      ? 'Verify in browser'
                      : 'Try again',
                  onAction: _error is AnimeSourceSessionRequired
                      ? _verifySession
                      : () => _load(reset: true),
                ),
              )
            else if (!_loading && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _MessageState(
                  icon: Icons.search_off_rounded,
                  title: 'No titles found',
                  message: 'Try another title or catalog.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                sliver: SliverGrid.builder(
                  itemCount: _items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) => _AnimeCatalogCard(
                    item: _items[index],
                    source: widget.source,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AnimeSourceDetailsScreen(
                          source: widget.source,
                          item: _items[index],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _loading
                    ? Padding(
                        key: const ValueKey('loading'),
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child:
                              CircularProgressIndicator(color: colors.primary),
                        ),
                      )
                    : const SizedBox(key: ValueKey('idle'), height: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimeCatalogCard extends StatelessWidget {
  final AnimeCatalogItem item;
  final AnimeSource source;
  final VoidCallback onTap;

  const _AnimeCatalogCard({
    required this.item,
    required this.source,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.coverUri == null
                  ? ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: const Icon(Icons.movie_outlined, size: 52),
                    )
                  : AnimeSourceImage(
                      source: source,
                      uri: item.coverUri!,
                      fit: BoxFit.cover,
                      placeholderBuilder: (_) => ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorBuilder: (_) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 44),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (item.subtitle case final subtitle?) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}

class _AdvancedFilterSheet extends StatefulWidget {
  final AnimeSearchOptions options;
  final AnimeSearchRequest? initial;

  const _AdvancedFilterSheet({required this.options, this.initial});

  @override
  State<_AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<_AdvancedFilterSheet> {
  late Set<String> _genres;
  String? _season;
  String? _year;
  String? _type;
  String? _status;
  String? _language;
  String? _rating;
  String? _studio;
  AnimeSearchSort _sort = AnimeSearchSort.defaultOrder;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _genres = {...?initial?.genres};
    _season = initial?.season;
    _year = initial?.year;
    _type = initial?.type;
    _status = initial?.status;
    _language = initial?.language;
    _rating = initial?.rating;
    _studio = initial?.studio;
    _sort = initial?.sort ?? AnimeSearchSort.defaultOrder;
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .88,
        minChildSize: .5,
        maxChildSize: .96,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Advanced filters',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    AnimeSearchRequest(),
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.options.seasons.isNotEmpty)
              _optionDropdown(
                label: 'Season',
                value: _season,
                options: widget.options.seasons,
                onChanged: (value) => setState(() => _season = value),
              ),
            if (widget.options.years.isNotEmpty)
              _optionDropdown(
                label: 'Year',
                value: _year,
                options: widget.options.years,
                onChanged: (value) => setState(() => _year = value),
              ),
            if (widget.options.types.isNotEmpty)
              _optionDropdown(
                label: 'Type',
                value: _type,
                options: widget.options.types,
                onChanged: (value) => setState(() => _type = value),
              ),
            if (widget.options.studios.isNotEmpty)
              _optionDropdown(
                label: 'Studio',
                value: _studio,
                options: widget.options.studios,
                onChanged: (value) => setState(() => _studio = value),
              ),
            if (widget.options.statuses.isNotEmpty)
              _optionDropdown(
                label: 'Status',
                value: _status,
                options: widget.options.statuses,
                onChanged: (value) => setState(() => _status = value),
              ),
            if (widget.options.languages.isNotEmpty)
              _optionDropdown(
                label: 'Language',
                value: _language,
                options: widget.options.languages,
                onChanged: (value) => setState(() => _language = value),
              ),
            if (widget.options.ratings.isNotEmpty)
              _optionDropdown(
                label: 'Rating',
                value: _rating,
                options: widget.options.ratings,
                onChanged: (value) => setState(() => _rating = value),
              ),
            DropdownButtonFormField<AnimeSearchSort>(
              initialValue: _sort,
              decoration: const InputDecoration(labelText: 'Order by'),
              items: widget.options.sorts
                  .map(
                    (sort) => DropdownMenuItem(
                      value: sort,
                      child: Text(_searchSortLabel(sort)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(
                () => _sort = value ?? AnimeSearchSort.defaultOrder,
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Genres'),
              subtitle: Text(
                _genres.isEmpty ? 'Any genre' : '${_genres.length} selected',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: widget.options.genres
                        .map(
                          (genre) => FilterChip(
                            label: Text(genre.label),
                            selected: _genres.contains(genre.value),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _genres.add(genre.value);
                              } else {
                                _genres.remove(genre.value);
                              }
                            }),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                AnimeSearchRequest(
                  genres: _genres,
                  season: _season,
                  year: _year,
                  type: _type,
                  status: _status,
                  language: _language,
                  rating: _rating,
                  studio: _studio,
                  sort: _sort,
                ),
              ),
              icon: const Icon(Icons.filter_alt_rounded),
              label: const Text('Apply filters'),
            ),
          ],
        ),
      );

  Widget _optionDropdown({
    required String label,
    required String? value,
    required List<AnimeFilterOption> options,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            ...options.map(
              (option) => DropdownMenuItem(
                value: option.value,
                child: Text(option.label),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      );
}

String _catalogFilterLabel(
  AnimeCatalogFilter filter,
  AnimeSource source,
) {
  if (source.id == 'goyabu') {
    return switch (filter) {
      AnimeCatalogFilter.popular => 'Today',
      AnimeCatalogFilter.popularWeek => 'This week',
      AnimeCatalogFilter.popularMonth => 'This month',
      _ => _defaultCatalogFilterLabel(filter),
    };
  }
  if (source.id == 'hentai_haven') {
    return switch (filter) {
      AnimeCatalogFilter.recent => 'Episodes · Newest',
      AnimeCatalogFilter.popular => 'Episodes · Popular',
      AnimeCatalogFilter.episodeMostViewed => 'Episodes · Most viewed',
      AnimeCatalogFilter.seriesNewest => 'Series · Newest',
      AnimeCatalogFilter.seriesPopular => 'Series · Popular',
      AnimeCatalogFilter.seriesMostViewed => 'Series · Most viewed',
      _ => _defaultCatalogFilterLabel(filter),
    };
  }
  return _defaultCatalogFilterLabel(filter);
}

String _defaultCatalogFilterLabel(AnimeCatalogFilter filter) =>
    switch (filter) {
      AnimeCatalogFilter.popular => 'Most viewed',
      AnimeCatalogFilter.popularWeek => 'This week',
      AnimeCatalogFilter.popularMonth => 'This month',
      AnimeCatalogFilter.recent => 'Latest',
      AnimeCatalogFilter.episodeMostViewed => 'Most viewed episodes',
      AnimeCatalogFilter.seriesNewest => 'Newest series',
      AnimeCatalogFilter.seriesPopular => 'Popular series',
      AnimeCatalogFilter.seriesMostViewed => 'Most viewed series',
      AnimeCatalogFilter.updated => 'Updated',
      AnimeCatalogFilter.added => 'Recently added',
      AnimeCatalogFilter.airing => 'Airing',
      AnimeCatalogFilter.completed => 'Completed',
    };

IconData _catalogFilterIcon(AnimeCatalogFilter filter) => switch (filter) {
      AnimeCatalogFilter.popular => Icons.trending_up_rounded,
      AnimeCatalogFilter.popularWeek => Icons.date_range_rounded,
      AnimeCatalogFilter.popularMonth => Icons.calendar_month_rounded,
      AnimeCatalogFilter.recent => Icons.schedule_rounded,
      AnimeCatalogFilter.episodeMostViewed => Icons.visibility_rounded,
      AnimeCatalogFilter.seriesNewest => Icons.video_library_rounded,
      AnimeCatalogFilter.seriesPopular => Icons.favorite_rounded,
      AnimeCatalogFilter.seriesMostViewed =>
        Icons.local_fire_department_rounded,
      AnimeCatalogFilter.updated => Icons.update_rounded,
      AnimeCatalogFilter.added => Icons.fiber_new_rounded,
      AnimeCatalogFilter.airing => Icons.live_tv_rounded,
      AnimeCatalogFilter.completed => Icons.task_alt_rounded,
    };

String _searchSortLabel(AnimeSearchSort sort) => switch (sort) {
      AnimeSearchSort.defaultOrder => 'Default',
      AnimeSearchSort.latestUpdated => 'Latest updated',
      AnimeSearchSort.latestAdded => 'Latest added',
      AnimeSearchSort.score => 'Score',
      AnimeSearchSort.name => 'Name A-Z',
      AnimeSearchSort.nameDescending => 'Name Z-A',
      AnimeSearchSort.releaseDate => 'Release date',
      AnimeSearchSort.mostViewed => 'Most viewed',
      AnimeSearchSort.episodeCount => 'Number of episodes',
    };
