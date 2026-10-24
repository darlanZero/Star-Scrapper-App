import 'dart:async';

import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

class AnimeSourceSearchGroup {
  final AnimeSource source;
  final List<AnimeCatalogItem> items;
  final String query;
  final Object? error;
  final bool isLoading;

  const AnimeSourceSearchGroup({
    required this.source,
    required this.items,
    required this.query,
    this.error,
    this.isLoading = false,
  });

  factory AnimeSourceSearchGroup.loading({
    required AnimeSource source,
    required String query,
  }) =>
      AnimeSourceSearchGroup(
        source: source,
        items: const [],
        query: query,
        isLoading: true,
      );
}

/// Searches every enabled anime source while keeping failures isolated.
class AnimeMultiSourceSearch {
  const AnimeMultiSourceSearch();

  List<AnimeLibraryRecord> searchLibrary({
    required Iterable<AnimeLibraryRecord> records,
    required Iterable<String> queries,
  }) {
    final normalizedQueries = queries
        .map((query) => query.trim().toLowerCase())
        .where((query) => query.isNotEmpty)
        .toSet();
    if (normalizedQueries.isEmpty) return const [];
    return records.where((record) {
      final title = record.title.toLowerCase();
      return normalizedQueries.any(title.contains);
    }).toList(growable: false);
  }

  Future<List<AnimeSourceSearchGroup>> search({
    required Iterable<AnimeSource> sources,
    required Iterable<String> queries,
  }) async {
    final sourceList = sources.toList(growable: false);
    final completed = await searchProgressively(
      sources: sourceList,
      queries: queries,
    ).toList();
    final bySource = {for (final group in completed) group.source.id: group};
    return [
      for (final source in sourceList)
        if (bySource[source.id] case final group?) group,
    ];
  }

  /// Emits one completed group as soon as each source finishes. A slow or
  /// blocked provider never prevents already completed providers from showing.
  Stream<AnimeSourceSearchGroup> searchProgressively({
    required Iterable<AnimeSource> sources,
    required Iterable<String> queries,
  }) {
    final sourceList = sources.toList(growable: false);
    final normalizedQueries = _normalizeQueries(queries);
    if (sourceList.isEmpty || normalizedQueries.isEmpty) {
      return const Stream.empty();
    }

    late final StreamController<AnimeSourceSearchGroup> controller;
    controller = StreamController<AnimeSourceSearchGroup>(onListen: () {
      var remaining = sourceList.length;
      for (final source in sourceList) {
        _searchSource(source, normalizedQueries).then((group) {
          if (!controller.isClosed) controller.add(group);
        }).onError((Object error, StackTrace stackTrace) {
          if (!controller.isClosed) {
            controller.add(
              AnimeSourceSearchGroup(
                source: source,
                items: const [],
                query: normalizedQueries.first,
                error: error,
              ),
            );
          }
        }).whenComplete(() {
          remaining--;
          if (remaining == 0 && !controller.isClosed) controller.close();
        });
      }
    });
    return controller.stream;
  }

  List<String> _normalizeQueries(Iterable<String> queries) {
    final normalizedQueries = <String>[];
    final seenQueries = <String>{};
    for (final query in queries) {
      final value = query.trim();
      if (value.isNotEmpty && seenQueries.add(value.toLowerCase())) {
        normalizedQueries.add(value);
      }
      if (normalizedQueries.length == 4) break;
    }
    return normalizedQueries;
  }

  Future<AnimeSourceSearchGroup> _searchSource(
    AnimeSource source,
    List<String> queries,
  ) async {
    final pages = await Future.wait(
      queries.map((query) async {
        try {
          return (
            query: query,
            page: await source.search(query),
            error: null as Object?
          );
        } catch (error) {
          return (query: query, page: null as AnimeCatalogPage?, error: error);
        }
      }),
    );

    final items = <AnimeCatalogItem>[];
    final seenItems = <String>{};
    for (final result in pages) {
      for (final item in result.page?.items ?? const <AnimeCatalogItem>[]) {
        final key = item.id.isEmpty ? item.title.toLowerCase() : item.id;
        if (seenItems.add(key)) items.add(item);
      }
    }
    final errors = pages.map((result) => result.error).whereType<Object>();
    final allQueriesFailed = pages.every((result) => result.page == null);
    return AnimeSourceSearchGroup(
      source: source,
      items: List.unmodifiable(items),
      query: pages
              .where((result) => result.page?.items.isNotEmpty == true)
              .map((result) => result.query)
              .firstOrNull ??
          queries.first,
      error: allQueriesFailed ? errors.firstOrNull : null,
    );
  }
}
