import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/infrastructure/playback/hls_extension_proxy.dart';

void main() {
  test('rewrites disguised playlists and fragments through loopback', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedHeaders = <String, String?>{};
    final serving = upstream.forEach((request) async {
      receivedHeaders['origin'] = request.headers.value('origin');
      receivedHeaders['referer'] = request.headers.value('referer');
      receivedHeaders['range'] = request.headers.value('range');
      switch (request.uri.path) {
        case '/h.jpg':
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
            'variant/p.jpg\n',
          );
        case '/variant/p.jpg':
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-MAP:URI="init.jpg"\n'
            '#EXTINF:4.0,\n'
            '1.jpg\n'
            '#EXT-X-ENDLIST\n',
          );
        case '/variant/init.jpg':
          request.response.add([0, 1, 2]);
        case '/variant/1.jpg':
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('content-range', 'bytes 0-2/3');
          request.response.add([3, 4, 5]);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = await HlsExtensionProxy.start(
      manifestUri: Uri.parse(
        'http://${upstream.address.address}:${upstream.port}/h.jpg',
      ),
      headers: const {
        'Origin': 'https://animefire.one',
        'Referer': 'https://animefire.one/',
      },
    );

    try {
      expect(proxy.entryUri.host, InternetAddress.loopbackIPv4.address);
      expect(proxy.entryUri.path, endsWith('.m3u8'));

      final master = await http.get(proxy.entryUri);
      final variantUri = Uri.parse(
        const LineSplitter()
            .convert(master.body)
            .firstWhere((line) => line.startsWith('http://')),
      );
      expect(variantUri.path, endsWith('.m3u8'));

      final variant = await http.get(variantUri);
      final lines = const LineSplitter().convert(variant.body);
      final mapUri = Uri.parse(
        RegExp(r'URI="([^"]+)"')
            .firstMatch(lines.firstWhere((line) => line.contains('MAP')))!
            .group(1)!,
      );
      final segmentUri = Uri.parse(
        lines.firstWhere((line) => line.endsWith('.m4s')),
      );
      expect(mapUri.path, endsWith('.bin'));
      expect(segmentUri.path, endsWith('.m4s'));

      final segment = await http.get(
        segmentUri,
        headers: const {'Range': 'bytes=0-2'},
      );
      expect(segment.statusCode, HttpStatus.partialContent);
      expect(segment.bodyBytes, [3, 4, 5]);
      expect(receivedHeaders, {
        'origin': 'https://animefire.one',
        'referer': 'https://animefire.one/',
        'range': 'bytes=0-2',
      });
    } finally {
      await proxy.close();
      await upstream.close(force: true);
      await serving;
    }
  });
}
