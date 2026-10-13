import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/components/UI/tracker_media_card.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/pages/tracker_media_details_screen.dart';
import 'package:star_scrapper_app/pages/tracker_source_search.dart';

class TrackerSeasonScreen extends StatefulWidget {
  const TrackerSeasonScreen({super.key});

  @override
  State<TrackerSeasonScreen> createState() => _TrackerSeasonScreenState();
}

class _TrackerSeasonScreenState extends State<TrackerSeasonScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<TrackerMedia> _items = [];
  late int _year;
  late AnimeSeason _season;
  TrackerSort _sort = TrackerSort.popularity;
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  int _generation = 0;
  String _trackerSignature = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _season = _seasonForMonth(now.month);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tracker = context.watch<TrackerController>();
    final signature = [
      tracker.initialized,
      tracker.aniListEnabled,
      tracker.malEnabled,
      tracker.includeAdult,
      tracker.malClientId,
    ].join(':');
    if (_trackerSignature == signature) return;
    _trackerSignature = signature;
    _reload();
  }

  void _reload() {
    final generation = ++_generation;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    _loadPage(generation);
  }

  Future<void> _loadPage(int generation) async {
    if (_loading || !_hasMore || generation != _generation) return;
    setState(() => _loading = true);
    try {
      final result = await context.read<TrackerController>().loadSeason(
            year: _year,
            season: _season,
            sort: _sort,
            page: _page + 1,
          );
      if (!mounted || generation != _generation) return;
      final known = _items.map(_key).toSet();
      setState(() {
        _items.addAll(result.items.where((item) => known.add(_key(item))));
        _page = result.page;
        _hasMore = result.hasNextPage;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 500) {
      _loadPage(_generation);
    }
  }

  String _key(TrackerMedia media) => media.malId == null
      ? '${media.tracker.name}:${media.id}'
      : 'mal:${media.malId}';

  void _openDetails(TrackerMedia media) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackerMediaDetailsScreen(media: media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years =
        List.generate(currentYear - 1940 + 2, (i) => currentYear + 1 - i);
    return Scaffold(
      appBar: AppBar(title: const Text('Season archive')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Browse any anime season',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Choose a season and year, then scroll to load more titles.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<AnimeSeason>(
                            initialValue: _season,
                            decoration: const InputDecoration(
                              labelText: 'Season',
                              prefixIcon:
                                  Icon(Icons.calendar_view_month_rounded),
                            ),
                            items: AnimeSeason.values
                                .map(
                                  (season) => DropdownMenuItem(
                                    value: season,
                                    child: Text(_seasonLabel(season)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              _season = value;
                              _reload();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _year,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                            ),
                            items: years
                                .map(
                                  (year) => DropdownMenuItem(
                                    value: year,
                                    child: Text('$year'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              _year = value;
                              _reload();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<TrackerSort>(
                      initialValue: _sort,
                      decoration: const InputDecoration(
                        labelText: 'Order by',
                        prefixIcon: Icon(Icons.sort_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: TrackerSort.popularity,
                          child: Text('Popularity'),
                        ),
                        DropdownMenuItem(
                          value: TrackerSort.highestRated,
                          child: Text('Highest rated'),
                        ),
                        DropdownMenuItem(
                          value: TrackerSort.mostRecent,
                          child: Text('Most recent'),
                        ),
                        DropdownMenuItem(
                          value: TrackerSort.trending,
                          child: Text('Trending'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _sort = value;
                        _reload();
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_items.isEmpty && _loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty && _error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _SeasonError(error: _error, onRetry: _reload),
              )
            else if (_items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No titles found for this season.')),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                sliver: SliverGrid.builder(
                  itemCount: _items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.66,
                  ),
                  itemBuilder: (context, index) {
                    final media = _items[index];
                    return TrackerMediaCard(
                      media: media,
                      onTap: () => _openDetails(media),
                      onLongPress: () =>
                          openTrackerSourceSearch(context, media),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : _error != null
                            ? TextButton.icon(
                                onPressed: () => _loadPage(_generation),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try loading more again'),
                              )
                            : _hasMore
                                ? const SizedBox.shrink()
                                : const Text('You reached the end.'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

AnimeSeason _seasonForMonth(int month) => switch (month) {
      <= 3 => AnimeSeason.winter,
      <= 6 => AnimeSeason.spring,
      <= 9 => AnimeSeason.summer,
      _ => AnimeSeason.fall,
    };

String _seasonLabel(AnimeSeason season) => switch (season) {
      AnimeSeason.winter => 'Winter',
      AnimeSeason.spring => 'Spring',
      AnimeSeason.summer => 'Summer',
      AnimeSeason.fall => 'Fall',
    };

class _SeasonError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _SeasonError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
