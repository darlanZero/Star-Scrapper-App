import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/pages/anime_source_details_screen.dart';

class AnimeLibraryGrid extends StatelessWidget {
  final List<AnimeLibraryRecord>? records;

  const AnimeLibraryGrid({super.key, this.records});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<AnimeLibraryController>();
    final sources = context.watch<FontProvider>().animeSources;
    final visibleRecords = records ?? library.favorites;
    final colors = Theme.of(context).colorScheme;

    if (!library.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visibleRecords.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    size: 52,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your anime shelf is ready',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open an anime source and tap the heart to save a title.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      context.read<AppState>().setIndex(2);
                      context.read<TabsState>().setActivePageIndex(2);
                    },
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Explore anime sources'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width >= 1100
            ? 6
            : MediaQuery.sizeOf(context).width >= 700
                ? 4
                : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: visibleRecords.length,
      itemBuilder: (context, index) {
        final record = visibleRecords[index];
        final matching = sources.where(
          (candidate) => candidate.id == record.sourceId,
        );
        final source = matching.isEmpty ? null : matching.first;
        final progress = library.lastProgressForAnime(
          sourceId: record.sourceId,
          animeId: record.animeId,
        );
        return _AnimeLibraryCard(
          record: record,
          progress: progress,
          onTap: source == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AnimeSourceDetailsScreen(
                        source: source,
                        item: record.toCatalogItem(),
                      ),
                    ),
                  ),
          onLongPress: () => _moveAnime(context, library, record),
        );
      },
    );
  }
}

Future<void> _moveAnime(
  BuildContext context,
  AnimeLibraryController library,
  AnimeLibraryRecord record,
) async {
  final tabs = context.read<AnimeTabsState>();
  final selection = await showModalBottomSheet<({String tab, String? subtab})>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Move anime to')),
          for (final tab in tabs.libraryTabs)
            if (tabs.getSubTabsForPrimary(tab).isEmpty)
              ListTile(
                title: Text(tab),
                onTap: () =>
                    Navigator.pop(sheetContext, (tab: tab, subtab: null)),
              )
            else
              ExpansionTile(
                title: Text(tab),
                children: [
                  for (final subtab in tabs.getSubTabsForPrimary(tab))
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 32, right: 16),
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
  if (selection == null) return;
  await library.moveTo(
    record: record,
    primaryTab: selection.tab,
    subTab: selection.subtab,
  );
}

class _AnimeLibraryCard extends StatelessWidget {
  final AnimeLibraryRecord record;
  final AnimeEpisodeProgress? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _AnimeLibraryCard({
    required this.record,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (record.coverUrl == null)
              ColoredBox(
                color: colors.surfaceContainerHighest,
                child: const Icon(Icons.movie_outlined, size: 52),
              )
            else
              CachedNetworkImage(
                imageUrl: record.coverUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 44),
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
                    Color.fromARGB(220, 0, 0, 0),
                  ],
                ),
              ),
            ),
            if (progress != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    progress!.completed
                        ? 'Watched'
                        : _formatDuration(progress!.position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last: ${progress!.episodeTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                  if (record.studios.isNotEmpty ||
                      record.producers.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        ...record.studios,
                        ...record.producers,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 11),
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

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
