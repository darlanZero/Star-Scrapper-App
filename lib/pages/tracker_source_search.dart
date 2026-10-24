import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/pages/search_screen.dart';
import 'package:star_scrapper_app/pages/anime_multi_source_search_screen.dart';

void openTrackerSourceSearch(BuildContext context, TrackerMedia media) {
  final sourceType = media.type == TrackedMediaType.anime
      ? SourceContentType.anime
      : SourceContentType.manga;
  final provider = context.read<FontProvider>();
  if (sourceType == SourceContentType.anime) {
    final sources = provider.activeAnimeSources;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enable an anime source before searching.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeMultiSourceSearchScreen(
          sources: sources,
          initialQueries: media.title.searchTerms,
        ),
      ),
    );
    return;
  }
  final hasMatchingSource = context
      .read<FontProvider>()
      .activeFonts
      .any((source) => source.contentType == sourceType);
  if (!hasMatchingSource) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sourceType == SourceContentType.anime
              ? 'No anime source is available yet.'
              : 'Enable a manga source before searching.',
        ),
      ),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SearchScreen(
        initialQueries: media.title.searchTerms,
        searchEnabledSources: true,
        sourceType: sourceType,
      ),
    ),
  );
}
