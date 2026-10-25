import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/components/Shared/anime_source_image.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/pages/anime_player_screen.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/application/library/tabs_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/pages/anime_source_webview_screen.dart';

class AnimeSourceDetailsScreen extends StatefulWidget {
  final AnimeSource source;
  final AnimeCatalogItem item;

  const AnimeSourceDetailsScreen({
    super.key,
    required this.source,
    required this.item,
  });

  @override
  State<AnimeSourceDetailsScreen> createState() =>
      _AnimeSourceDetailsScreenState();
}

class _AnimeSourceDetailsScreenState extends State<AnimeSourceDetailsScreen> {
  _AnimePageData? _data;
  Object? _error;
  String? _loadingEpisodeId;
  bool _syncingTrackers = false;
  bool _sessionPromptOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final details = await widget.source.getDetails(widget.item.id);
      final rawEpisodes = await widget.source.getEpisodes(widget.item.id);
      final episodes = rawEpisodes
          .map(
            (episode) => AnimeEpisode(
              id: episode.id,
              animeId: details.item.id,
              title: episode.title,
              number: episode.number,
              season: episode.season,
              releasedAt: episode.releasedAt,
              thumbnailUri: episode.thumbnailUri,
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      await context.read<AnimeLibraryController>().refreshFavoriteMetadata(
            sourceId: widget.source.id,
            details: details,
          );
      if (!mounted) return;
      setState(() => _data = _AnimePageData(details, episodes));
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
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
    if (verified == true && mounted) _load();
  }

  Future<void> _play(AnimeEpisode episode) async {
    if (_loadingEpisodeId != null) return;
    setState(() => _loadingEpisodeId = episode.id);
    try {
      AnimePlayback playback;
      try {
        playback = await widget.source.getPlayback(
          animeId: widget.item.id,
          episodeId: episode.id,
        );
      } on AnimePlaybackResolutionRequired catch (request) {
        if (widget.source is! BrowserPlaybackAnimeSource || !mounted) rethrow;
        final source = widget.source as BrowserPlaybackAnimeSource;
        final choice = request.choices.length == 1
            ? request.choices.single
            : await _choosePlaybackServer(request.choices);
        if (choice == null || !mounted) return;
        final resolved = await Navigator.of(context).push<AnimePlayback>(
          MaterialPageRoute(
            builder: (_) => AnimePlaybackResolverScreen(
              source: source,
              request: request.selecting(choice),
            ),
          ),
        );
        if (resolved == null) return;
        playback = resolved;
      }
      if (!mounted) return;
      final library = context.read<AnimeLibraryController>();
      await library.markEpisodeViewed(
        sourceId: widget.source.id,
        episode: episode,
        details: _data?.details,
      );
      final initialPosition = library.resumePosition(
        sourceId: widget.source.id,
        animeId: episode.animeId,
        episodeId: episode.id,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AnimePlayerScreen(
            playback: playback,
            title: _data?.details.item.title ?? widget.item.title,
            episodeTitle: episode.title,
            initialPosition: initialPosition,
            onProgressChanged: (position, duration) async {
              final newlyCompleted = await library.saveEpisodePosition(
                sourceId: widget.source.id,
                episode: episode,
                position: position,
                duration: duration,
                details: _data?.details,
              );
              final episodeNumber = episode.number?.floor();
              if (!newlyCompleted ||
                  episodeNumber == null ||
                  episodeNumber < 1) {
                return;
              }
              if (!mounted) return;
              try {
                await context
                    .read<TrackerController>()
                    .updateAnimeProgressOnConnectedTrackers(
                      title: _data?.details.item.title ?? widget.item.title,
                      episode: episodeNumber,
                      malId: int.tryParse(
                        _data?.details.externalIds['mal'] ?? '',
                      ),
                      aniListId: int.tryParse(
                        _data?.details.externalIds['anilist'] ?? '',
                      ),
                    );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Episode saved locally. Tracker sync failed: $error'),
                  ),
                );
              }
            },
          ),
        ),
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open this episode: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingEpisodeId = null);
    }
  }

  Future<AnimePlaybackChoice?> _choosePlaybackServer(
    List<AnimePlaybackChoice> choices,
  ) {
    return showModalBottomSheet<AnimePlaybackChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Choose a video server'),
              subtitle: Text('You can try another server if playback fails.'),
            ),
            for (final choice in choices)
              ListTile(
                leading: Icon(
                  choice.provider == 'SEND'
                      ? Icons.cloud_download_outlined
                      : Icons.video_library_outlined,
                ),
                title: Text(choice.label),
                subtitle: Text(
                  switch (choice.provider) {
                    'SEND' => 'May require a one-time security verification',
                    'Google Drive' => 'Uses your Google Drive WebView session',
                    'NHPlayer' =>
                      'Complete the player verification to continue natively',
                    _ => 'Opens the video host to resolve the native stream',
                  },
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, choice),
              ),
          ],
        ),
      ),
    );
  }

  AnimeLibraryRecord? _libraryRecord(AnimeLibraryController library) =>
      library.favorites
          .where(
            (record) =>
                record.sourceId == widget.source.id &&
                record.animeId == (_data?.details.item.id ?? widget.item.id),
          )
          .firstOrNull;

  Future<void> _renameAnime(AnimeLibraryRecord record) async {
    final controller = TextEditingController(text: record.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename anime'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Library title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty || !mounted) return;
    await context.read<AnimeLibraryController>().renameAnime(record, title);
  }

  Future<void> _manageTabs(AnimeLibraryRecord record) async {
    final tabs = context.read<AnimeTabsState>();
    final selection =
        await showModalBottomSheet<({String tab, String? subtab})>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Manage anime tabs')),
            for (final tab in tabs.libraryTabs)
              if (tabs.getSubTabsForPrimary(tab).isEmpty)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(tab),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    (tab: tab, subtab: null),
                  ),
                )
              else
                ExpansionTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(tab),
                  children: [
                    for (final subtab in tabs.getSubTabsForPrimary(tab))
                      ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 52, right: 16),
                        title: Text(subtab),
                        onTap: () => Navigator.pop(
                          sheetContext,
                          (tab: tab, subtab: subtab),
                        ),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
    if (selection == null || !mounted) return;
    await context.read<AnimeLibraryController>().moveTo(
          record: record,
          primaryTab: selection.tab,
          subTab: selection.subtab,
        );
  }

  Future<void> _migrateAnime(AnimeLibraryRecord record) async {
    final alternatives = context
        .read<FontProvider>()
        .activeAnimeSources
        .where((source) => source.id != widget.source.id)
        .toList();
    if (alternatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable another anime source before migrating.'),
        ),
      );
      return;
    }

    final matches = <({AnimeSource source, AnimeCatalogItem item})>[];
    for (final source in alternatives) {
      try {
        final page = await source.search(_data!.details.item.title);
        matches.addAll(
          page.items.take(5).map((item) => (source: source, item: item)),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<
        ({AnimeSource source, AnimeCatalogItem item})>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: matches.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No matching title was found in enabled sources.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Migrate anime to')),
                  for (final match in matches)
                    ListTile(
                      leading: match.item.coverUri == null
                          ? const Icon(Icons.movie_outlined)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: AnimeSourceImage(
                                source: match.source,
                                uri: match.item.coverUri!,
                                width: 42,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                      title: Text(match.item.title),
                      subtitle: Text(match.source.name),
                      onTap: () => Navigator.pop(sheetContext, match),
                    ),
                ],
              ),
      ),
    );
    if (selected == null || !mounted) return;
    final details = await selected.source.getDetails(selected.item.id);
    final episodes = await selected.source.getEpisodes(selected.item.id);
    final oldEpisodes = _data!.episodes;
    final matchesByOldId = <String, AnimeEpisode>{};
    for (final old in oldEpisodes) {
      final target = episodes
          .where((candidate) =>
              candidate.number != null && candidate.number == old.number)
          .firstOrNull;
      if (target != null) matchesByOldId[old.id] = target;
    }
    if (!mounted) return;
    await context.read<AnimeLibraryController>().migrateAnime(
          record: record,
          targetSourceId: selected.source.id,
          targetDetails: details,
          episodeMatches: matchesByOldId,
        );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AnimeSourceDetailsScreen(
          source: selected.source,
          item: selected.item,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.item.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 52),
                const SizedBox(height: 12),
                Text(_error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _error is AnimeSourceSessionRequired
                      ? _verifySession
                      : _load,
                  child: Text(
                    _error is AnimeSourceSessionRequired
                        ? 'Verify in browser'
                        : 'Try again',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.item.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final data = _data!;
    final details = data.details;
    final library = context.watch<AnimeLibraryController>();
    final record = _libraryRecord(library);
    final displayTitle = record?.title ?? details.item.title;
    final isFavorite = library.isFavorite(widget.source.id, details.item.id);
    final lastProgress = library.lastProgressForAnime(
      sourceId: widget.source.id,
      animeId: details.item.id,
    );
    final lastEpisode = lastProgress == null
        ? null
        : data.episodes.cast<AnimeEpisode?>().firstWhere(
              (episode) => episode!.id == lastProgress.episodeId,
              orElse: () => null,
            );
    final colors = Theme.of(context).colorScheme;
    final trackers = context.watch<TrackerController>();
    final image = details.bannerUri ?? details.item.coverUri;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: Text(displayTitle),
            actions: [
              if (trackers.connectedTrackerCount > 0)
                IconButton.filledTonal(
                  tooltip: 'Add to connected trackers',
                  onPressed: _syncingTrackers
                      ? null
                      : () async {
                          setState(() => _syncingTrackers = true);
                          try {
                            final names =
                                await trackers.addAnimeToConnectedTrackers(
                              title: details.item.title,
                              malId: int.tryParse(
                                details.externalIds['mal'] ?? '',
                              ),
                              aniListId: int.tryParse(
                                details.externalIds['anilist'] ?? '',
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Added to ${names.join(' and ')}.',
                                ),
                              ),
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$error')),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _syncingTrackers = false);
                            }
                          }
                        },
                  icon: _syncingTrackers
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_alt_rounded),
                ),
              IconButton.filledTonal(
                tooltip: isFavorite ? 'Remove from library' : 'Add to library',
                onPressed: () async {
                  final added = await library.toggleFavorite(
                    sourceId: widget.source.id,
                    details: details,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        added
                            ? 'Added to your anime library.'
                            : 'Removed from your anime library.',
                      ),
                    ),
                  );
                },
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Anime options',
                enabled: record != null,
                onSelected: (value) {
                  if (record == null) return;
                  switch (value) {
                    case 'rename':
                      _renameAnime(record);
                    case 'migrate':
                      _migrateAnime(record);
                    case 'tabs':
                      _manageTabs(record);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename anime'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'migrate',
                    child: ListTile(
                      leading: Icon(Icons.swap_horiz_rounded),
                      title: Text('Migrate anime'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'tabs',
                    child: ListTile(
                      leading: Icon(Icons.folder_copy_outlined),
                      title: Text('Manage tabs'),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
            expandedHeight: 390,
            flexibleSpace: FlexibleSpaceBar(
              background: _AnimeHero(
                details: details,
                title: displayTitle,
                background: image,
                source: widget.source,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (details.alternativeTitles.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details.alternativeTitles.join(' · '),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  if (details.description.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Synopsis',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      details.description,
                      style: const TextStyle(height: 1.45),
                    ),
                  ],
                  if (lastProgress != null && lastEpisode != null) ...[
                    const SizedBox(height: 18),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(
                          lastProgress.completed
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        title: Text(
                          lastProgress.completed
                              ? 'Replay ${lastEpisode.title}'
                              : 'Continue ${lastEpisode.title}',
                        ),
                        subtitle: Text(
                          lastProgress.completed
                              ? 'Last watched episode'
                              : 'Resume at ${_duration(lastProgress.position)}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _play(lastEpisode),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'Episodes (${data.episodes.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (data.episodes.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No episodes available.')),
              ),
            )
          else
            SliverList.builder(
              itemCount: data.episodes.length,
              itemBuilder: (context, index) {
                final episode = data.episodes[index];
                final loading = _loadingEpisodeId == episode.id;
                final progress = library.progressFor(
                  sourceId: widget.source.id,
                  animeId: episode.animeId,
                  episodeId: episode.id,
                );
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  leading: Badge(
                    isLabelVisible: progress?.completed == true,
                    backgroundColor: colors.primary,
                    label: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    child: CircleAvatar(
                      backgroundColor: progress?.viewed == true
                          ? colors.primaryContainer
                          : null,
                      child: Text(
                        episode.number == null
                            ? '${index + 1}'
                            : _episodeNumber(episode.number!),
                      ),
                    ),
                  ),
                  title: Text(episode.title),
                  subtitle: Text([
                    if (episode.releasedAt != null) _date(episode.releasedAt!),
                    if (progress?.completed == true) 'Watched',
                    if (progress?.canResume == true)
                      'Resume at ${_duration(progress!.position)}',
                  ].join(' · ')),
                  trailing: loading
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : progress?.completed == true
                          ? Chip(
                              avatar: const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                              ),
                              label: const Text('Watched'),
                              visualDensity: VisualDensity.compact,
                            )
                          : const Icon(Icons.play_circle_fill_rounded),
                  onTap: loading ? null : () => _play(episode),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _AnimePageData {
  final AnimeDetails details;
  final List<AnimeEpisode> episodes;

  const _AnimePageData(this.details, this.episodes);
}

class _AnimeHero extends StatelessWidget {
  final AnimeDetails details;
  final String title;
  final Uri? background;
  final AnimeSource source;

  const _AnimeHero({
    required this.details,
    required this.title,
    required this.background,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final cover = details.item.coverUri;
    final credits = [
      if (details.studios.isNotEmpty) 'Studio: ${details.studios.join(', ')}',
      if (details.producers.isNotEmpty)
        'Producer: ${details.producers.join(', ')}',
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (background != null)
          AnimeSourceImage(
            source: source,
            uri: background!,
            fit: BoxFit.cover,
          )
        else
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .16),
                Colors.black.withValues(alpha: .46),
                Colors.black.withValues(alpha: .96),
              ],
              stops: const [0, .45, 1],
            ),
          ),
        ),
        Positioned(
          left: 18,
          bottom: 22,
          child: Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            elevation: 8,
            child: SizedBox(
              width: 112,
              height: 168,
              child: cover == null
                  ? const Icon(Icons.movie_outlined, size: 48)
                  : AnimeSourceImage(
                      source: source,
                      uri: cover,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ),
        Positioned(
          left: 146,
          right: 16,
          bottom: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
              if (credits.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final credit in credits)
                  Text(
                    credit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _HeroChip(label: _statusLabel(details.status)),
                  ...details.genres
                      .take(4)
                      .map((genre) => _HeroChip(label: genre)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

String _statusLabel(AnimeStatus status) => switch (status) {
      AnimeStatus.upcoming => 'Upcoming',
      AnimeStatus.ongoing => 'Ongoing',
      AnimeStatus.completed => 'Completed',
      AnimeStatus.hiatus => 'Hiatus',
      AnimeStatus.cancelled => 'Cancelled',
      AnimeStatus.unknown => 'Unknown status',
    };

String _episodeNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
