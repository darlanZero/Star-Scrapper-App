import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/data/sources/manga/onisaga_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps OniSaga filters and keeps both Top Rated sorts distinct',
      () async {
    Uri? requested;
    final source = OniSagaSource(
      browserHtmlLoader: (uri, _) async {
        requested = uri;
        return _browseFixture;
      },
    );

    final options = await source.getSearchOptions();
    expect(options.genres.single.label, 'Action');
    expect(options.sorts, contains(MangaSearchSort.mostLiked));
    expect(options.sorts, contains(MangaSearchSort.rating));

    await source.filterCatalog(
      MangaSearchRequest(
        formats: {'MANHWA'},
        statuses: {'ongoing'},
        genres: {'559', '707'},
        minimumChapters: 100,
        releaseStart: '01/02/2020',
        releaseEnd: '2021-12-31',
        sort: MangaSearchSort.mostLiked,
      ),
      cursor: '2',
    );

    expect(requested?.path, '/browse');
    expect(requested?.queryParameters['platform'], 'MANHWA');
    expect(requested?.queryParameters['status'], 'ongoing');
    expect(requested?.queryParameters['min_chapters'], '100');
    expect(requested?.queryParameters['release_start'], '2020-01-02');
    expect(requested?.queryParameters['release_end'], '2021-12-31');
    expect(requested?.queryParameters['sort'], 'like_count');
    expect(requested?.queryParameters['genre[0]'], '559');
    expect(requested?.queryParameters['genre[1]'], '707');
    expect(requested?.queryParameters['page'], '2');

    await source.filterCatalog(
      MangaSearchRequest(sort: MangaSearchSort.mostViewed),
    );
    expect(requested?.queryParameters['sort'], 'view');
  });

  test('parses details and all chapters returned after expansion', () async {
    String? clickedSelector;
    int? clickLimit;
    final source = OniSagaSource(
      browserHtmlLoader: (_, __) async => _browseFixture,
      interactedHtmlLoader: (
        _,
        __,
        selector, {
        required maxClicks,
      }) async {
        clickedSelector = selector;
        clickLimit = maxClicks;
        return _detailsFixture;
      },
    );

    final details = await source.getDetails('ao-ashi');

    expect(clickedSelector, contains('loadMoreChapters'));
    expect(clickLimit, 20);
    expect(details.item.title, 'Ao Ashi');
    expect(details.description, contains('footballer'));
    expect(details.author, 'Yuugo Kobayashi');
    expect(details.genres, ['Sports']);
    expect(details.status, MangaStatus.completed);
    expect(details.chapters, hasLength(2));
    expect(details.chapters.first.number, '2');
    expect(details.chapters.first.pages, '42');
  });

  test('parses a Livewire card before its visible title link is hydrated',
      () async {
    final source = OniSagaSource(
      browserHtmlLoader: (_, __) async => _partialCardFixture,
    );

    final page = await source.browse(filter: MangaCatalogFilter.recent);

    expect(page.items, hasLength(1));
    expect(page.items.single.title, 'Katayama-kun, Meshiagare!');
    expect(
      page.items.single.coverUri.toString(),
      endsWith('/uploads/katayama.jpg'),
    );
  });
}

const _browseFixture = '''
<html><body>
  <input id="genre559" name="genre[]" value="559">
  <label for="genre559">Action</label>
  <div class="group">
    <a href="/manga/ao-ashi"><img src="/uploads/ao.jpg"></a>
    <a href="/manga/ao-ashi">Ao Ashi</a>
    <span>Manga</span><span>Completed</span><span>9.2</span>
  </div>
</body></html>
''';

const _detailsFixture = '''
<html><head><meta property="og:image" content="/uploads/ao.jpg"></head><body>
  <div>
    <div><span>Manga</span><span>Completed</span><span>2015</span></div>
    <h1>Ao Ashi</h1>
    <p class="italic">Aoashi | Blue Feet</p>
    <p><a href="/author/yuugo-kobayashi">Yuugo Kobayashi</a></p>
    <div><p class="leading-relaxed">A talented young footballer changes Japanese football.</p></div>
    <a href="/genre/sports">Sports</a>
  </div>
  <a href="/read/ao-ashi/11">1 Chapter 1 Vol. 1 · 62p · 1 year ago</a>
  <a href="/read/ao-ashi/12">2 Chapter 2 Vol. 1 · 42p · 1 year ago</a>
</body></html>
''';

const _partialCardFixture = '''
<html><body><main>
  <div class="group">
    <img src="/uploads/katayama.jpg">
    <a href="/manga/katayama-kun-meshiagare"
       class="absolute inset-0 z-10"
       aria-label="Katayama-kun, Meshiagare!"></a>
    <span>Manga</span><span>Ongoing</span>
  </div>
</main></body></html>
''';
