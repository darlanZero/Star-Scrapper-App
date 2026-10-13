import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/library_books_history.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/pages/anime_source_details_screen.dart';

enum _HistoryKind { manga, anime }

class LibraryHistory extends StatefulWidget {
  const LibraryHistory({super.key});

  @override
  State<LibraryHistory> createState() => _LibraryHistoryState();
}

class _LibraryHistoryState extends State<LibraryHistory> {
  _HistoryKind _kind = _HistoryKind.manga;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<_HistoryKind>(
              segments: const [
                ButtonSegment(
                  value: _HistoryKind.manga,
                  icon: Icon(Icons.menu_book_rounded),
                  label: Text('Manga'),
                ),
                ButtonSegment(
                  value: _HistoryKind.anime,
                  icon: Icon(Icons.play_circle_rounded),
                  label: Text('Anime'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.first),
            ),
          ),
          Expanded(
            child: _kind == _HistoryKind.manga
                ? const LibraryBooksHistory()
                : const _AnimeHistory(),
          ),
        ],
      );
}

class _AnimeHistory extends StatelessWidget {
  const _AnimeHistory();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<AnimeLibraryController>();
    final sources = context.watch<FontProvider>().animeSources;
    final latestByAnime = <String, AnimeEpisodeProgress>{};
    for (final progress in library.history) {
      latestByAnime.putIfAbsent(
        '${progress.sourceId}::${progress.animeId}',
        () => progress,
      );
    }
    final entries = latestByAnime.values.toList();
    if (entries.isEmpty) {
      return const Center(child: Text('No watched anime yet.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: .74,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final progress = entries[index];
        final favorite = library.favorites
            .where((item) =>
                item.sourceId == progress.sourceId &&
                item.animeId == progress.animeId)
            .firstOrNull;
        final source =
            sources.where((item) => item.id == progress.sourceId).firstOrNull;
        final title = progress.animeTitle ?? favorite?.title ?? 'Anime';
        final cover = progress.animeCoverUrl ?? favorite?.coverUrl;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: source == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AnimeSourceDetailsScreen(
                          source: source,
                          item: favorite?.toCatalogItem() ??
                              AnimeLibraryRecord(
                                sourceId: progress.sourceId,
                                animeId: progress.animeId,
                                title: title,
                                coverUrl: cover,
                                addedAtMillis: progress.lastPlayedAtMillis,
                              ).toCatalogItem(),
                        ),
                      ),
                    ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)
                else
                  const ColoredBox(
                    color: Color(0xff211b2b),
                    child: Icon(Icons.movie_outlined, size: 48),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${progress.episodeTitle} · ${_duration(progress.position)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _duration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0
      ? '${value.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}
