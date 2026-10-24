import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/application/sources/anime_multi_source_search.dart';
import 'package:star_scrapper_app/domain/library/anime_library_record.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/pages/anime_multi_source_search_screen.dart';

void main() {
  test('searches every enabled anime source and keeps results grouped',
      () async {
    final first = _FakeAnimeSource(
      id: 'first',
      results: {
        'Preferred': const [AnimeCatalogItem(id: '1', title: 'First result')],
      },
    );
    final second = _FakeAnimeSource(
      id: 'second',
      results: {
        'English': const [AnimeCatalogItem(id: '2', title: 'Second result')],
      },
    );

    final groups = await const AnimeMultiSourceSearch().search(
      sources: [first, second],
      queries: ['Preferred', 'English'],
    );

    expect(first.queries, ['Preferred', 'English']);
    expect(second.queries, ['Preferred', 'English']);
    expect(groups.map((group) => group.source.id), ['first', 'second']);
    expect(groups[0].items.single.title, 'First result');
    expect(groups[0].query, 'Preferred');
    expect(groups[1].items.single.title, 'Second result');
    expect(groups[1].query, 'English');
  });

  test('isolates a failed source and deduplicates alternate-title matches',
      () async {
    final working = _FakeAnimeSource(
      id: 'working',
      results: {
        'Title': const [AnimeCatalogItem(id: 'same', title: 'Result')],
        'Alias': const [AnimeCatalogItem(id: 'same', title: 'Result')],
      },
    );
    final failing = _FakeAnimeSource(id: 'failing', error: StateError('down'));

    final groups = await const AnimeMultiSourceSearch().search(
      sources: [working, failing],
      queries: ['Title', 'Alias'],
    );

    expect(groups[0].items, hasLength(1));
    expect(groups[0].error, isNull);
    expect(groups[1].items, isEmpty);
    expect(groups[1].error, isA<StateError>());
  });

  test('emits each source as soon as that source completes', () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final first = _FakeAnimeSource(
      id: 'first',
      gate: firstGate,
      results: {
        'Title': const [AnimeCatalogItem(id: '1', title: 'First result')],
      },
    );
    final second = _FakeAnimeSource(
      id: 'second',
      gate: secondGate,
      results: {
        'Title': const [AnimeCatalogItem(id: '2', title: 'Second result')],
      },
    );
    final iterator = StreamIterator(
      const AnimeMultiSourceSearch().searchProgressively(
        sources: [first, second],
        queries: ['Title'],
      ),
    );

    secondGate.complete();
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.source.id, 'second');
    firstGate.complete();
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.source.id, 'first');
    expect(await iterator.moveNext(), isFalse);
  });

  test('searches the anime library with the same title variants', () {
    final records = [
      const AnimeLibraryRecord(
        sourceId: 'first',
        animeId: '1',
        title: 'Ghost in the Shell',
        addedAtMillis: 1,
      ),
      const AnimeLibraryRecord(
        sourceId: 'second',
        animeId: '2',
        title: 'Another anime',
        addedAtMillis: 2,
      ),
    ];

    final matches = const AnimeMultiSourceSearch().searchLibrary(
      records: records,
      queries: ['Koukaku Kidoutai', 'Ghost in the Shell'],
    );

    expect(matches.map((record) => record.animeId), ['1']);
  });

  testWidgets('renders results from every supplied source', (tester) async {
    final first = _FakeAnimeSource(
      id: 'First source',
      results: {
        'Title': const [AnimeCatalogItem(id: '1', title: 'First result')],
      },
    );
    final second = _FakeAnimeSource(
      id: 'Second source',
      results: {
        'Title': const [AnimeCatalogItem(id: '2', title: 'Second result')],
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AnimeLibraryController(),
        child: MaterialApp(
          home: AnimeMultiSourceSearchScreen(
            sources: [first, second],
            initialQueries: const ['Title'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your library (0)'), findsOneWidget);
    expect(find.text('First source (1)'), findsOneWidget);
    expect(find.text('First result'), findsOneWidget);
    expect(find.text('Second source (1)'), findsOneWidget);
    expect(find.text('Second result'), findsOneWidget);

    final firstResults = tester.widget<ListView>(
      find.byKey(const ValueKey('source-results-First source')),
    );
    expect(firstResults.scrollDirection, Axis.horizontal);
  });

  testWidgets('shows completed sources while another source is still searching',
      (tester) async {
    final fastGate = Completer<void>();
    final slowGate = Completer<void>();
    final fast = _FakeAnimeSource(
      id: 'Fast source',
      gate: fastGate,
      results: {
        'Title': const [AnimeCatalogItem(id: '1', title: 'Fast result')],
      },
    );
    final slow = _FakeAnimeSource(
      id: 'Slow source',
      gate: slowGate,
      results: {
        'Title': const [AnimeCatalogItem(id: '2', title: 'Slow result')],
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AnimeLibraryController(),
        child: MaterialApp(
          home: AnimeMultiSourceSearchScreen(
            sources: [fast, slow],
            initialQueries: const ['Title'],
          ),
        ),
      ),
    );
    await tester.pump();
    fastGate.complete();
    await tester.pump();

    expect(find.text('Fast source (1)'), findsOneWidget);
    expect(find.text('Fast result'), findsOneWidget);
    expect(find.text('Slow source · Searching…'), findsOneWidget);

    slowGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Slow source (1)'), findsOneWidget);
    expect(find.text('Slow result'), findsOneWidget);
  });
}

class _FakeAnimeSource implements AnimeSource {
  @override
  final String id;
  final Map<String, List<AnimeCatalogItem>> results;
  final Object? error;
  final Completer<void>? gate;
  final List<String> queries = [];

  _FakeAnimeSource({
    required this.id,
    this.results = const {},
    this.error,
    this.gate,
  });

  @override
  String get name => id;

  @override
  Uri get baseUri => Uri.parse('https://$id.test');

  @override
  List<AnimeCatalogFilter> get catalogFilters => AnimeCatalogFilter.values;

  @override
  Map<String, String> get requestHeaders => const {};

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) async {
    queries.add(query);
    await gate?.future;
    if (error != null) throw error!;
    return AnimeCatalogPage(items: results[query] ?? const []);
  }

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.popular,
    String? cursor,
  }) async =>
      AnimeCatalogPage(items: const []);

  @override
  Future<AnimeDetails> getDetails(String animeId) => throw UnimplementedError();

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) =>
      throw UnimplementedError();

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) =>
      throw UnimplementedError();
}
