import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/sources/anime/cartoon_porn_video_source.dart';
import 'package:star_scrapper_app/data/sources/anime/hentai18_video_source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

void main() {
  test('CartoonPorn sends its exact rich filter query and parses cards',
      () async {
    late Uri requested;
    final source = CartoonPornVideoSource(
      baseUri: Uri.parse('https://cartoon.test/'),
      client: MockClient((request) async {
        requested = request.url;
        return _html('''
          <article class="cptv-card">
            <a class="cptv-card__link" href="/cartoon-porn-videos/sample/">
              <img class="cptv-card__img" src="/cover.webp">
            </a>
            <h3 class="cptv-card__title">Sample video</h3>
            <span class="cptv-card__dur">2:30</span>
            <span class="cptv-card__views">12K views</span>
          </article>
          <a href="/cartoon-porn-videos/videos/page/3/">Next</a>
        ''');
      }),
    );

    final page = await source.filter(
      AnimeSearchRequest(
        query: 'hero',
        type: 'videos',
        formats: {'m'},
        year: 'week',
        sort: AnimeSearchSort.mostViewed,
      ),
      cursor: '2',
    );

    expect(requested.path, '/cartoon-porn-videos/videos/page/2/');
    expect(requested.queryParameters, {
      'sort': 'views',
      'window': 'week',
      'dur': 'm',
      'q': 'hero',
    });
    expect(page.items.single.title, 'Sample video');
    expect(page.items.single.subtitle, '2:30 • 12K views');
    expect(page.nextCursor, '3');
  });

  test('CartoonPorn exposes direct MP4 as native progressive playback',
      () async {
    final source = CartoonPornVideoSource(
      baseUri: Uri.parse('https://cartoon.test/'),
      client: MockClient((request) async => _html('''
        <video poster="/poster.webp"><source src="https://cdn.test/movie.mp4" type="video/mp4"></video>
      ''')),
    );

    final playback = await source.getPlayback(
      animeId: '/cartoon-porn-videos/sample/',
      episodeId: '/cartoon-porn-videos/sample/',
    );

    expect(
        playback.streams.single.uri, Uri.parse('https://cdn.test/movie.mp4'));
    expect(playback.streams.single.protocol, VideoProtocol.progressive);
    expect(playback.streams.single.headers['Referer'],
        'https://cartoon.test/cartoon-porn-videos/sample/');
  });

  test('Hentai18 decodes the embedded player token into native HLS', () async {
    final token = base64Url.encode(utf8.encode(
      ';https://img.test/poster.webp;https://video.test/stream/index.m3u8;Episode 2',
    ));
    final source = Hentai18VideoSource(
      baseUri: Uri.parse('https://h18.test/'),
      client: MockClient((request) async => _html('''
        <div class="hx-player"><iframe src="https://player.test/videos/player/$token"></iframe></div>
      ''')),
    );

    final playback = await source.getPlayback(
      animeId: '/watch-hentai/example',
      episodeId: '/watch-hentai/example-episode-2',
    );

    expect(playback.streams.single.uri,
        Uri.parse('https://video.test/stream/index.m3u8'));
    expect(playback.streams.single.protocol, VideoProtocol.hls);
    expect(playback.streams.single.headers['Referer'],
        'https://player.test/videos/player/$token');
    expect(playback.streams.single.headers['Origin'], 'https://player.test');
  });

  test('Hentai18 video feed keeps each episode title and thumbnail', () async {
    final source = Hentai18VideoSource(
      baseUri: Uri.parse('https://h18.test/'),
      client: MockClient((request) async => _html('''
        <article class="hx-card hx-vcard">
          <a class="hx-card-cover" href="/watch-hentai/work-episode-2"
            title="Work Episode 2">
            <img src="/thumbs/work-episode-2.webp">
          </a>
          <h3 class="hx-card-title">
            <a href="/watch-hentai/work-episode-2" title="Work Episode 2">
              Work Episode 2
            </a>
          </h3>
        </article>
      ''')),
    );

    final page = await source.browse();

    expect(page.items.single.title, 'Work Episode 2');
    expect(page.items.single.coverUri,
        Uri.parse('https://h18.test/thumbs/work-episode-2.webp'));
  });
}

http.Response _html(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
