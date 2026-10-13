import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/application/library/library_organization_contracts.dart';

class _FakeTabConfiguration implements LibraryTabConfiguration {
  @override
  final List<String> libraryTabs;
  final Map<String, List<String>> subtabs;

  const _FakeTabConfiguration(this.libraryTabs, this.subtabs);

  @override
  List<String> getSubTabsForPrimary(String primaryTab) =>
      subtabs[primaryTab] ?? const [];

  @override
  String getDefaultSubTabForPrimary(String primaryTab) =>
      getSubTabsForPrimary(primaryTab).firstOrNull ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const item = AnimeCatalogItem(
    id: 'anime-1',
    title: 'Anime One',
  );
  final details = AnimeDetails(item: item, description: 'Description');
  const episode = AnimeEpisode(
    id: 'episode-1',
    animeId: 'anime-1',
    title: 'Episode 1',
    number: 1,
  );

  test('favorites survive controller recreation', () async {
    final controller = AnimeLibraryController();
    await controller.initialize();

    expect(
      await controller.toggleFavorite(sourceId: 'source-1', details: details),
      isTrue,
    );
    expect(controller.isFavorite('source-1', 'anime-1'), isTrue);

    final restored = AnimeLibraryController();
    await restored.initialize();
    expect(restored.isFavorite('source-1', 'anime-1'), isTrue);
    expect(restored.favorites.single.title, 'Anime One');
  });

  test('new favorites use the first configured anime tab and subtab', () async {
    const tabs = _FakeTabConfiguration(
      ['Plan to watch', 'Completed'],
      {
        'Plan to watch': ['Queue', 'Next'],
        'Completed': [],
      },
    );
    final controller = AnimeLibraryController();
    controller.configureTabs(tabs);
    await controller.initialize();

    await controller.toggleFavorite(sourceId: 'source-1', details: details);

    final favorite = controller.favorites.single;
    expect(favorite.tabs, ['Plan to watch']);
    expect(favorite.subTabsByPrimary, {
      'Plan to watch': ['Queue'],
    });
    expect(
      controller.favoritesInTabAndSubtab('Plan to watch', 'Queue'),
      hasLength(1),
    );
  });

  test('repairs favorites whose saved tabs no longer exist', () async {
    SharedPreferences.setMockInitialValues({
      'anime_library_favorites_v1': [
        '{"sourceId":"source-1","animeId":"anime-1","title":"Anime One",'
            '"addedAtMillis":1,"tabs":["Watching"],'
            '"subTabsByPrimary":{"Watching":["Watching"]}}',
      ],
    });
    const tabs = _FakeTabConfiguration(
      ['Backlog'],
      {
        'Backlog': ['Unwatched'],
      },
    );
    final controller = AnimeLibraryController();
    controller.configureTabs(tabs);
    await controller.initialize();

    final favorite = controller.favorites.single;
    expect(favorite.tabs, ['Backlog']);
    expect(favorite.subTabsByPrimary, {
      'Backlog': ['Unwatched'],
    });

    final restored = AnimeLibraryController();
    restored.configureTabs(tabs);
    await restored.initialize();
    expect(
      restored.favoritesInTabAndSubtab('Backlog', 'Unwatched'),
      hasLength(1),
    );
  });

  test('records viewed episodes and resumes from the saved position', () async {
    final controller = AnimeLibraryController();
    await controller.initialize();

    await controller.markEpisodeViewed(
      sourceId: 'source-1',
      episode: episode,
    );
    final newlyCompleted = await controller.saveEpisodePosition(
      sourceId: 'source-1',
      episode: episode,
      position: const Duration(minutes: 8, seconds: 12),
      duration: const Duration(minutes: 24),
    );
    expect(newlyCompleted, isFalse);

    final progress = controller.progressFor(
      sourceId: 'source-1',
      animeId: 'anime-1',
      episodeId: 'episode-1',
    );
    expect(progress?.viewed, isTrue);
    expect(progress?.completed, isFalse);
    expect(
      controller.resumePosition(
        sourceId: 'source-1',
        animeId: 'anime-1',
        episodeId: 'episode-1',
      ),
      const Duration(minutes: 8, seconds: 12),
    );

    final restored = AnimeLibraryController();
    await restored.initialize();
    expect(
      restored
          .lastProgressForAnime(
            sourceId: 'source-1',
            animeId: 'anime-1',
          )
          ?.position,
      const Duration(minutes: 8, seconds: 12),
    );
  });

  test('completed episodes restart from the beginning', () async {
    final controller = AnimeLibraryController();
    await controller.initialize();

    final newlyCompleted = await controller.saveEpisodePosition(
      sourceId: 'source-1',
      episode: episode,
      position: const Duration(minutes: 23, seconds: 45),
      duration: const Duration(minutes: 24),
    );
    expect(newlyCompleted, isTrue);

    expect(
      await controller.saveEpisodePosition(
        sourceId: 'source-1',
        episode: episode,
        position: const Duration(minutes: 23, seconds: 50),
        duration: const Duration(minutes: 24),
      ),
      isFalse,
    );

    expect(
      controller
          .progressFor(
            sourceId: 'source-1',
            animeId: 'anime-1',
            episodeId: 'episode-1',
          )
          ?.completed,
      isTrue,
    );
    expect(
      controller.resumePosition(
        sourceId: 'source-1',
        animeId: 'anime-1',
        episodeId: 'episode-1',
      ),
      Duration.zero,
    );
  });

  test('organizes anime with independent primary tabs and subtabs', () async {
    final controller = AnimeLibraryController();
    await controller.initialize();
    await controller.toggleFavorite(sourceId: 'source-1', details: details);

    final record = controller.favorites.single;
    await controller.moveTo(
      record: record,
      primaryTab: 'Finished',
      subTab: 'Favorites',
    );

    expect(controller.favoritesInTab('Watching'), isEmpty);
    expect(
      controller.favoritesInTabAndSubtab('Finished', 'Favorites').single.title,
      'Anime One',
    );

    final restored = AnimeLibraryController();
    await restored.initialize();
    expect(
      restored.favoritesInTabAndSubtab('Finished', 'Favorites'),
      hasLength(1),
    );
  });

  test('keeps anime metadata in episode history', () async {
    final controller = AnimeLibraryController();
    await controller.initialize();
    await controller.markEpisodeViewed(
      sourceId: 'source-1',
      episode: episode,
      details: details,
    );

    expect(controller.history.single.animeTitle, 'Anime One');
  });

  test('renames and migrates a favorite with matched episode progress',
      () async {
    final controller = AnimeLibraryController();
    await controller.initialize();
    await controller.toggleFavorite(sourceId: 'source-1', details: details);
    await controller.saveEpisodePosition(
      sourceId: 'source-1',
      episode: episode,
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 24),
      details: details,
    );
    await controller.renameAnime(controller.favorites.single, 'Custom title');

    const targetItem = AnimeCatalogItem(id: 'anime-2', title: 'Anime Two');
    final targetDetails = AnimeDetails(item: targetItem);
    const targetEpisode = AnimeEpisode(
      id: 'target-episode-1',
      animeId: 'anime-2',
      title: 'Episode 1',
      number: 1,
    );
    await controller.migrateAnime(
      record: controller.favorites.single,
      targetSourceId: 'source-2',
      targetDetails: targetDetails,
      episodeMatches: const {'episode-1': targetEpisode},
    );

    expect(controller.favorites.single.title, 'Custom title');
    expect(controller.favorites.single.sourceId, 'source-2');
    expect(
      controller
          .progressFor(
            sourceId: 'source-2',
            animeId: 'anime-2',
            episodeId: 'target-episode-1',
          )
          ?.position,
      const Duration(minutes: 5),
    );
  });
}
