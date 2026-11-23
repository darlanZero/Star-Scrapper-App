import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/hentai20_source.dart';
import 'package:star_scrapper_app/data/sources/manga/madara_adult_sources.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('Hentai20 keeps Recent on latest and exposes Most viewed separately',
      () async {
    final requested = <Uri>[];
    final source = Hentai20Source(
      baseUri: Uri.parse('https://h20.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/manga/work/') {
          return _html('''
            <h1 class="title-bigger">Operation Test Raw</h1>
            <ul class="chapter-list">
              <li><a href="/manga/work/chapter-13/">
                <span class="chapter-name">Chapter 13</span>
                <span class="ct-update">18 Nov 2026</span>
              </a></li>
              <li><a href="/manga/work/chapter-12/">
                <span class="chapter-name">Chapter 12</span>
                <span class="ct-update"><img alt="NEW"></span>
              </a></li>
            </ul>
          ''');
        }
        return _html('<main></main>');
      }),
    );

    await source.browse();
    await source.browse(filter: MangaCatalogFilter.updated);
    final details = await source.getDetails('/manga/work/');

    expect(requested.first.queryParameters['order'], 'latest');
    expect(requested[1].queryParameters['order'], 'views');
    expect(source.catalogFilters, contains(MangaCatalogFilter.updated));
    expect(
        source.catalogFilterLabel(MangaCatalogFilter.updated), 'Most viewed');
    expect(details.chapters.map((chapter) => chapter.title),
        ['Chapter 13', 'Chapter 12']);
    expect(details.chapters.first.publishedAt, '2026-11-18');
    expect(details.chapters.last.publishedAt, isNull);
    expect(details.chapters.first.language, 'und');
  });

  test('Pornhwaz keeps Recent on latest and normalizes chapter dates',
      () async {
    final requested = <Uri>[];
    final source = PornhwazSource(
      baseUri: Uri.parse('https://pornhwaz.test/'),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/webtoon/office-wife/') {
          return _html('''
            <div class="post-title"><h1>Office Wife</h1></div>
            <div class="summary_image"><img src="/cover.webp"></div>
            <ul class="listing-chapters_wrap">
              <li class="wp-manga-chapter">
                <a href="/webtoon/office-wife/chapter-5/">Chapter 5</a>
                <span class="chapter-release-date">13 Nov 2026</span>
              </li>
            </ul>
          ''');
        }
        return _html('<main></main>');
      }),
    );

    await source.browse();
    await source.browse(filter: MangaCatalogFilter.updated);
    final details = await source.getDetails('/webtoon/office-wife/');

    expect(requested.first.queryParameters['m_orderby'], 'latest');
    expect(requested[1].queryParameters['m_orderby'], 'views');
    expect(source.catalogFilters, contains(MangaCatalogFilter.updated));
    expect(
        source.catalogFilterLabel(MangaCatalogFilter.updated), 'Most viewed');
    expect(details.chapters.single.title, 'Chapter 5');
    expect(details.chapters.single.publishedAt, '2026-11-13');
  });

  test('CartoonPorn parses its custom chapters and taxonomy directories',
      () async {
    final source = CartoonPornMangaSource(
      baseUri: Uri.parse('https://cartoon.test/'),
      client: MockClient((request) async {
        if (request.url.path == '/tags/') {
          return _html('''
            <div class="terms-list">
              <a class="term-link" href="/tag/action/">
                <span class="term-name">Action</span>
                <span class="term-count">12</span>
              </a>
            </div>
          ''');
        }
        return _html('''
          <main>
            <h1 class="comic-hero__title">A Long Night</h1>
            <div class="comic-hero__cover"><img src="/cover.webp"></div>
            <div class="comic-hero__meta-grid">
              <a class="meta-tag meta-tag--artist" href="/artist/spageta/">Spageta</a>
              <a class="meta-tag meta-tag--series" href="/series/family-guy/">Family Guy</a>
              <a class="meta-tag meta-tag--character" href="/character/lois/">Lois</a>
              <a class="meta-tag meta-tag--genre" href="/tag/action/">Action</a>
            </div>
            <div id="chapters" class="chapters-preview manga-post-chapters">
              <ul><li>
                <a href="1-a-long-night-chapter-1-family-guy-spageta">
                  <p class="truncate font-medium">1 . A Long Night - Chapter 1</p>
                  <div class="release"><p>2 days ago</p></div>
                </a>
              </li></ul>
            </div>
          </main>
        ''');
      }),
    );

    final details = await source.getDetails('/porncomic/a-long-night/');
    final tags = await source.getTaxonomy(MangaTaxonomyKind.tag);

    expect(details.chapters.single.id,
        '/porncomic/a-long-night/1-a-long-night-chapter-1-family-guy-spageta');
    expect(details.chapters.single.publishedAt, '2 days ago');
    expect(
        details.taxonomyLinks.map((link) => link.kind),
        containsAll([
          MangaTaxonomyKind.artist,
          MangaTaxonomyKind.parody,
          MangaTaxonomyKind.character,
          MangaTaxonomyKind.tag,
        ]));
    expect(tags.single.name, 'Action');
    expect(tags.single.titleCount, 12);
  });

  test('CartoonPorn renders Livewire chapters when raw HTML is empty',
      () async {
    Uri? renderedUri;
    final source = CartoonPornMangaSource(
      baseUri: Uri.parse('https://cartoon.test/'),
      client: MockClient((request) async => _html('''
        <h1 class="comic-hero__title">Chel</h1>
        <div id="chapters"><ul></ul></div>
      ''')),
      browserHtmlLoader: (uri, userAgent) async {
        renderedUri = uri;
        return '''
          <h1 class="comic-hero__title">Chel</h1>
          <div id="chapters"><ul><li>
            <a href="chel-chapter-1">
              <p class="font-medium">Chel Chapter 1</p>
              <div class="release"><p>19 November 2026</p></div>
            </a>
          </li></ul></div>
        ''';
      },
    );

    final details = await source.getDetails('/porncomic/chel/');

    expect(renderedUri?.path, '/porncomic/chel/');
    expect(details.chapters.single.id, '/porncomic/chel/chel-chapter-1');
    expect(details.chapters.single.publishedAt, '2026-11-19');
  });

  test('CartoonPorn reads preloaded chapter images and figure.reader-page img.manga-img',
      () async {
    final source = CartoonPornMangaSource(
      baseUri: Uri.parse('https://cartoon.test/'),
      client: MockClient((request) async => _html('''
        <script type="text/javascript" id="chapter_preloaded_images">
          var chapter_images_per_page = 1,
              chapter_preloaded_images=[{"src":"https://cartoon.test/img/1.jpg"},{"src":"https://cartoon.test/img/2.jpg"}];
        </script>
        <figure class="reader-page">
          <img class="manga-img" src="https://cartoon.test/img/1.jpg" />
          <img class="manga-img" data-src="https://cartoon.test/img/3.jpg" />
        </figure>
      ''')),
    );

    final pages = await source
        .readChapter(
          mangaId: '/porncomic/chel/',
          chapterId: '/porncomic/chel/1-chel-chapter-1/',
        )
        .toList();

    expect(
      pages.map((p) => p.uri.toString()).toList(),
      [
        'https://cartoon.test/img/1.jpg',
        'https://cartoon.test/img/2.jpg',
        'https://cartoon.test/img/3.jpg',
      ],
    );
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
