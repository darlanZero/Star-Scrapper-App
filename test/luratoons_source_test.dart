import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/sources/manga/luratoons_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('uses the authenticated browser when Cloudflare blocks catalog HTTP',
      () async {
    late Uri browserUri;
    final source = LuraToonsSource(
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
      browserHtmlLoader: (uri, userAgent) async {
        browserUri = uri;
        expect(userAgent, contains('Android 14'));
        return _browserJson({
          'lancamentos': [
            {
              'slug': 'imperador-magico',
              'title': 'Imperador Demoníaco',
              'capa': '/media/imperador.webp',
              'caps': [
                {'num': '927'}
              ],
            },
          ],
        });
      },
    );

    final page = await source.browse(filter: MangaCatalogFilter.recent);

    expect(browserUri.path, '/api/main/');
    expect(page.items.single.id, 'imperador-magico');
    expect(page.items.single.subtitle, '927 Ch');
    expect(
      page.items.single.coverUri.toString(),
      'https://luratoons.net/media/imperador.webp',
    );
  });

  test('parses authenticated details returned by the browser JSON viewer',
      () async {
    final source = LuraToonsSource(
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
      browserHtmlLoader: (uri, userAgent) async => _browserJson({
        'titulo': 'Imperador Demoníaco',
        'capa': '/media/imperador.webp',
        'sinopse': 'Sinopse de teste',
        'autor': 'Ye Xiao',
        'status': 'Em Lançamento',
        'generos': [
          {'name': 'Ação'},
          {'name': 'Cultivo'},
        ],
        'caps': [
          {
            'slug': '01',
            'num': '1',
            'data': '2024-12-30T18:47:25.787Z',
          },
        ],
      }),
    );

    final details = await source.getDetails('imperador-magico');

    expect(details.item.title, 'Imperador Demoníaco');
    expect(details.author, 'Ye Xiao');
    expect(details.status, MangaStatus.ongoing);
    expect(details.genres, ['Ação', 'Cultivo']);
    expect(details.chapters.single.id, '01');
    expect(
      source
          .chapterWebUri(mangaId: 'imperador-magico', chapterId: '01')
          .toString(),
      'https://luratoons.net/imperador-magico/01/',
    );
  });

  test('reports an expired session when browser fallback reaches login',
      () async {
    final source = LuraToonsSource(
      client: MockClient(
        (request) async =>
            http.Response('<title>Just a moment...</title>', 403),
      ),
      browserHtmlLoader: (uri, userAgent) async => '''
        <html><body><main><a href="/accounts/login/">Conecte-se</a></main></body></html>
      ''',
    );

    await expectLater(
      source.browse(filter: MangaCatalogFilter.recent),
      throwsA(isA<MangaSourceSessionRequired>()),
    );
  });

  test('decrypts chapter archives and streams composed native pages', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'luratoons-source-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    const mangaSlug = 'regressor-da-familia-caida';
    const chapterSlug = '01';
    const userId = '77';
    const workId = '321';
    final manifest = utf8.encode(jsonEncode({
      'id': 1,
      'obra': {'id': int.parse(workId)},
      'files': 1,
    }));
    final svg = utf8.encode(
      '<svg><image href="data:image/png;base64,${base64Encode([
            1,
            2,
            3
          ])}"/></svg>',
    );
    final archive = Archive()..addFile(ArchiveFile('0.svg', svg.length, svg));
    final zip = ZipEncoder().encode(archive);
    late http.Request pageRequest;

    final source = LuraToonsSource(
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/user-info/':
            return http.Response(
              jsonEncode({'user_authenticated': true, 'userid': userId}),
              200,
            );
          case '/api/484d2a13/$mangaSlug/$chapterSlug/':
            return http.Response.bytes(
              _encrypt(Uint8List.fromList(manifest),
                  '$chapterSlug$mangaSlug$userId', 8),
              200,
              headers: {'token': 'first-page-token'},
            );
          case '/download/$workId/$chapterSlug/0/':
            pageRequest = request;
            return http.Response.bytes(
              _encrypt(Uint8List.fromList(zip),
                  '6514b4a8$workId$chapterSlug$userId', 16),
              200,
            );
          default:
            return http.Response('not found', 404);
        }
      }),
      temporaryDirectory: () async => temporaryDirectory,
      pageComposer: (slices, outputPath) async {
        expect(slices, hasLength(1));
        expect(slices.single, [1, 2, 3]);
        await File(outputPath).writeAsBytes([9, 8, 7]);
      },
    );

    final pages = await source
        .readChapter(mangaId: mangaSlug, chapterId: chapterSlug)
        .toList();

    expect(pages, hasLength(1));
    expect(await File(pages.single.filePath!).readAsBytes(), [9, 8, 7]);
    expect(pageRequest.headers['Token'], 'first-page-token');
    expect(pageRequest.url.queryParameters['api'], '2');
  });
}

String _browserJson(Map<String, dynamic> payload) =>
    '<html><body><pre>${jsonEncode(payload)}</pre></body></html>';

Uint8List _encrypt(Uint8List clear, String key, int prefixLength) {
  final iv = Uint8List.fromList(List<int>.generate(prefixLength, (i) => i + 1));
  final keyBytes = Uint8List.fromList(sha256.convert(utf8.encode(key)).bytes);
  final cipher = StreamCipher('AES/CTR')
    ..init(true, ParametersWithIV(KeyParameter(keyBytes), iv));
  return Uint8List.fromList([...iv, ...cipher.process(clear)]);
}
