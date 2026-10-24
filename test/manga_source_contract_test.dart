import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('reader preloading keeps a four-page moving window', () {
    expect(
      mangaReaderPreloadIndexes(currentPage: 0, pageCount: 10),
      [0, 1, 2, 3],
    );
    expect(
      mangaReaderPreloadIndexes(currentPage: 4, pageCount: 10),
      [4, 5, 6, 7],
    );
    expect(
      mangaReaderPreloadIndexes(currentPage: 9, pageCount: 10),
      [9],
    );
    expect(
      mangaReaderPreloadIndexes(
        currentPage: 4,
        pageCount: 10,
        reverse: true,
      ),
      [4, 3, 2, 1],
    );
  });

  test('manga source contract covers catalog, details and chapter reading',
      () async {
    final source = _FakeMangaSource();

    final page = await source.browse();
    final details = await source.getDetails(page.items.single.id);
    final pages = await source
        .readChapter(
          mangaId: details.item.id,
          chapterId: details.chapters.single.id,
        )
        .toList();

    expect(source.id, 'fake_manga');
    expect(page.hasMore, isTrue);
    expect(details.status, MangaStatus.ongoing);
    expect(details.chapters.single.number, '1');
    expect(pages, hasLength(2));
    expect(pages.first.isLocal, isTrue);
    expect(pages.last.uri.toString(), 'https://cdn.example/2.webp');
    expect(pages.last.headers['Referer'], source.baseUri.toString());
  });

  test('contract collections cannot be mutated by consumers', () {
    final details = MangaDetails(
      item: const MangaCatalogItem(id: 'one', title: 'One'),
      genres: const ['Action'],
      chapters: const [MangaChapter(id: 'c1', number: '1')],
    );

    expect(() => details.genres.add('Drama'), throwsUnsupportedError);
    expect(
      () => details.chapters.add(const MangaChapter(id: 'c2')),
      throwsUnsupportedError,
    );
  });

  test('reader page rejects empty sources', () {
    expect(() => MangaReaderPage.file(''), throwsArgumentError);
  });

  test('catalog metadata omits missing values and normalizes chapters', () {
    expect(
      mangaCatalogSubtitle(
        latestChapter: 'Capítulo 12.5',
        format: 'Manhwa',
        status: MangaStatus.ongoing,
        rating: 8.4,
      ),
      '12.5 Ch • Manhwa • Ongoing • 8.4',
    );
    expect(
      mangaCatalogSubtitle(totalChapters: 86, status: MangaStatus.completed),
      '86 Ch • Completed',
    );
  });

  test('details round-trip through the legacy book map preserves keys', () {
    final original = MangaDetails(
      item: MangaCatalogItem(
        id: 'manga-1',
        title: 'Example Manga',
        coverUri: Uri.parse('https://cdn.example/cover.jpg'),
        subtitle: 'Ch. 12',
      ),
      description: 'A description',
      alternativeTitles: const [
        {'en': 'Example'},
        {'ja': '例'},
      ],
      genres: const ['Action', 'Drama'],
      author: 'Jane Doe',
      artist: 'John Roe',
      status: MangaStatus.ongoing,
      externalUri: Uri.parse('https://example.com/manga/manga-1'),
      chapters: const [
        MangaChapter(
          id: 'ch-1',
          title: 'Start',
          number: '1',
          volume: '1',
          language: 'pt-br',
          pages: '20',
          uploader: 'Team',
          publishedAt: '2026-01-01',
        ),
      ],
    );

    final json = original.toJson();

    // Legacy keys the storage layer and the UI depend on.
    expect(json['id'], 'manga-1');
    expect(json['coverImageUrl'], 'https://cdn.example/cover.jpg');
    expect(json['tags'], ['Action', 'Drama']);
    expect(json['mangaUrl'], 'https://example.com/manga/manga-1');
    expect((json['chapters'] as List).single['translatedLanguage'], 'pt-br');
    expect((json['chapters'] as List).single['chapter'], '1');

    final restored = MangaDetails.fromJson(json);
    expect(restored.item.id, original.item.id);
    expect(restored.item.title, original.item.title);
    expect(restored.item.coverUri, original.item.coverUri);
    expect(restored.description, original.description);
    expect(restored.genres, original.genres);
    expect(restored.author, original.author);
    expect(restored.artist, original.artist);
    expect(restored.status, original.status);
    expect(restored.externalUri, original.externalUri);
    expect(restored.chapters.single.id, 'ch-1');
    expect(restored.chapters.single.number, '1');
    expect(restored.chapters.single.pages, '20');
  });

  test('details tolerate a map-shaped author and plain altTitles', () {
    final details = MangaDetails.fromJson(const {
      'id': 'm2',
      'title': 'Mapped',
      'author': {'id': 'a1', 'name': 'Mapped Author'},
      'altTitles': ['Solo String Title'],
      'status': 'Em Andamento',
    });

    expect(details.author, 'Mapped Author');
    expect(details.alternativeTitles.single[''], 'Solo String Title');
    expect(details.status, MangaStatus.ongoing);
  });
}

class _FakeMangaSource implements MangaSource {
  @override
  String get id => 'fake_manga';

  @override
  String get name => 'Fake Manga';

  @override
  Uri get baseUri => Uri.parse('https://manga.example/');

  @override
  Map<String, String> get requestHeaders =>
      const {'Accept': 'application/json'};

  @override
  Map<String, String> get coverImageHeaders =>
      const {'Referer': 'https://manga.example/'};

  @override
  List<MangaCatalogFilter> get catalogFilters =>
      const [MangaCatalogFilter.popular, MangaCatalogFilter.recent];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    return MangaCatalogPage(
      items: const [MangaCatalogItem(id: 'manga-1', title: 'Example Manga')],
      nextCursor: 'page-2',
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) => browse();

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    return MangaDetails(
      item: MangaCatalogItem(id: mangaId, title: 'Example Manga'),
      description: 'Example description',
      genres: const ['Action'],
      status: MangaStatus.ongoing,
      chapters: const [MangaChapter(id: 'ch-1', number: '1')],
    );
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    yield MangaReaderPage.file('/tmp/$chapterId/1.webp');
    yield MangaReaderPage.network(
      Uri.parse('https://cdn.example/2.webp'),
      headers: {'Referer': baseUri.toString()},
    );
  }
}
