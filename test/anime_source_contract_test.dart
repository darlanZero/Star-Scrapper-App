import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('anime source contract covers catalog, episodes and playback', () async {
    final source = _FakeAnimeSource();

    final page = await source.browse();
    final details = await source.getDetails(page.items.single.id);
    final episodes = await source.getEpisodes(details.item.id);
    final playback = await source.getPlayback(
      animeId: details.item.id,
      episodeId: episodes.single.id,
    );

    expect(source.id, 'fake_anime');
    expect(page.hasMore, isTrue);
    expect(details.status, AnimeStatus.ongoing);
    expect(episodes.single.number, 1);
    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(
        playback.streams.single.headers['Referer'], source.baseUri.toString());
    expect(playback.subtitles.single.language, 'en');
    expect(playback.skipSegments.single.displayLabel, 'Skip intro');
    expect(
      playback.skipSegments.single.contains(const Duration(seconds: 30)),
      isTrue,
    );
  });

  test('contract collections cannot be mutated by consumers', () {
    final page = AnimeCatalogPage(
      items: const [AnimeCatalogItem(id: 'one', title: 'One')],
    );
    final details = AnimeDetails(
      item: page.items.single,
      genres: const ['Action'],
    );

    expect(
      () => page.items.add(const AnimeCatalogItem(id: 'two', title: 'Two')),
      throwsUnsupportedError,
    );
    expect(() => details.genres.add('Drama'), throwsUnsupportedError);
  });

  test('playback requires at least one video stream', () {
    expect(
      () => AnimePlayback(streams: const []),
      throwsArgumentError,
    );
  });

  test('skip segments reject invalid ranges', () {
    expect(
      () => AnimeSkipSegment(
        start: const Duration(seconds: 90),
        end: const Duration(seconds: 30),
      ),
      throwsArgumentError,
    );
  });
}

class _FakeAnimeSource implements AnimeSource {
  @override
  Uri get baseUri => Uri.parse('https://anime.example/');

  @override
  String get id => 'fake_anime';

  @override
  String get name => 'Fake Anime';

  @override
  Map<String, String> get requestHeaders =>
      const {'Accept': 'application/json'};

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.popular,
    String? cursor,
  }) async {
    return AnimeCatalogPage(
      items: const [AnimeCatalogItem(id: 'anime-1', title: 'Example Anime')],
      nextCursor: 'page-2',
    );
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => browse();

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    return AnimeDetails(
      item: AnimeCatalogItem(id: animeId, title: 'Example Anime'),
      description: 'Example description',
      genres: const ['Action'],
      status: AnimeStatus.ongoing,
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    return [
      AnimeEpisode(
        id: 'episode-1',
        animeId: animeId,
        title: 'Episode 1',
        number: 1,
      ),
    ];
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    return AnimePlayback(
      streams: [
        AnimeVideoStream(
          uri: Uri.parse('https://cdn.example/video.m3u8'),
          protocol: VideoProtocol.hls,
          quality: '1080p',
          headers: {'Referer': baseUri.toString()},
        ),
      ],
      subtitles: [
        AnimeSubtitleTrack(
          uri: Uri.parse('https://cdn.example/subtitles.vtt'),
          label: 'English',
          language: 'en',
        ),
      ],
      skipSegments: [
        AnimeSkipSegment(
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 95),
        ),
      ],
    );
  }
}
