import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/manga/porn_comic_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  test('maps each feed, its pagination and feed-specific right ranking',
      () async {
    final requested = <Uri>[];
    final source = PornComicMangaSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async {
        requested.add(request.url);
        return _html('''
          <ul id="list"><li>
            <a class="thumb" href="/h/10.html" title="Recent work">
              <picture><source srcset="https://img.test/recent.webp 450w"></picture>
            </a><span><a href="/h/10.html">Recent work</a></span>
            <i class="lang">English</i><i class="view">42</i>
          </li></ul>
          <div class="page"><a class="a1" href="/h/index-3.html">Next</a></div>
          <div class="right"><div class="ranking">
            <a href="/h/99.html" title="Monthly hit"><img src="/hit.webp"></a>
          </div></div>
        ''');
      }),
    );

    expect(
      source.catalogVariants(MangaCatalogFilter.recent).map((e) => e.id),
      ['h', 'hentai', 'full_color', 'western'],
    );
    final recent = await source.browseVariant(
      MangaCatalogFilter.recent,
      'full_color',
      cursor: '2',
    );
    expect(requested.last.path, '/tags/full-color-2.html');
    expect(recent.items.single.title, 'Recent work');
    expect(recent.items.single.coverUri,
        Uri.parse('https://img.test/recent.webp'));
    expect(recent.nextCursor, '3');

    final popular = await source.browseVariant(
      MangaCatalogFilter.popular,
      'h',
    );
    expect(popular.items.single.title, 'Monthly hit');
    expect(popular.nextCursor, isNull);
  });

  test('maps the feed-specific right taxonomies', () async {
    final source = PornComicMangaSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async {
        final content = switch (request.url.path) {
          '/h' =>
            '<div class="right"><a href="/tags/full-color.html">Full color</a></div>',
          '/tags/full-color.html' => '''
            <div class="right">
              <a href="/tags/sole-female.html">Sole female</a>
              <a href="/characters/zelda.html"><img src="/zelda.webp">Zelda</a>
              <a href="/anime/zelda.html">Legend of Zelda</a>
            </div>''',
          '/hentai' =>
            '<div class="right"><a href="/artist/stoker.html">Stoker</a></div>',
          '/cos' =>
            '<div class="right"><a href="/artist/model.html">Model</a></div>',
          _ => '',
        };
        return _html(content);
      }),
    );

    final tags = await source.getTaxonomy(MangaTaxonomyKind.tag);
    expect(tags.map((e) => e.name), containsAll(['Full color', 'Sole female']));
    final artists = await source.getTaxonomy(
      MangaTaxonomyKind.artist,
      query: 'model',
    );
    expect(artists.single.id, '/artist/model.html');
    final characters = await source.getTaxonomy(MangaTaxonomyKind.character);
    expect(
        characters.single.imageUri, Uri.parse('https://porn.test/zelda.webp'));
  });

  test('streams every paged gallery image progressively', () async {
    final requested = <String>[];
    final source = PornComicMangaSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async {
        requested.add(request.url.path);
        if (request.method == 'HEAD') {
          final isJpgPage = request.url.path.endsWith('_3.jpg');
          final isWebpPage = request.url.path.endsWith('_2.webp');
          return http.Response(
            '',
            isJpgPage || isWebpPage ? 200 : 404,
            headers: {
              'content-type': isJpgPage ? 'image/jpeg' : 'image/webp',
            },
          );
        }
        return _html('''
          <h1 class="title">Paged gallery</h1>
          <div class="info"><a class="lang_cat">Japanese</a></div>
          <div class="summary"><a href="/artist/test.html">Artist</a></div>
          <p class="manga-picture"><img src="https://img.test/gallery_1.webp"></p>
          <div id="pages">
            <a href="/h/10-2.html">2</a><a href="/h/10-3.html">3</a>
          </div>
        ''');
      }),
    );

    final details = await source.getDetails('/h/10.html');
    expect(details.chapters.single.pages, '3');
    expect(details.item.subtitle, '3 pages • Japanese');

    final pages = await source
        .readChapter(mangaId: '/h/10.html', chapterId: '/h/10.html')
        .toList();
    expect(pages.map((e) => e.uri.toString()), [
      'https://img.test/gallery_1.webp',
      'https://img.test/gallery_2.webp',
      'https://img.test/gallery_3.jpg',
    ]);
    expect(requested, isNot(contains('/h/10-2.html')));
    expect(requested, isNot(contains('/h/10-3.html')));
  });

  test('maps a Western work and its real chapter list', () async {
    final source = PornComicMangaSource(
      baseUri: Uri.parse('https://porn.test'),
      client: MockClient((request) async => _html('''
        <dl class="webtoon-info">
          <dt class="webtoon-thumb"><img src="/cover.jpg"></dt>
          <dd class="webtoon-desc"><h1>Western work</h1>
            <div class="webtoon-content">Description.</div>
            <div class="summary">Status: ongoing
              <a href="/artist/a.html">Artist A</a>
              <a href="/tags/action.html">Action</a>
            </div>
          </dd>
        </dl>
        <dd class="chapters"><a class="chapter-name" href="/western/20.html">
          <h3>Chapter 2</h3><span class="time">2026-11-01</span>
        </a></dd>
      ''')),
    );

    final details = await source.getDetails('/western/comic-1.html');
    expect(details.description, 'Description.');
    expect(details.status, MangaStatus.ongoing);
    expect(details.chapters.single.id, '/western/20.html');
    expect(details.chapters.single.number, '2');
  });
}

http.Response _html(String body) => http.Response(body, 200, headers: {
      'content-type': 'text/html; charset=utf-8',
    });
