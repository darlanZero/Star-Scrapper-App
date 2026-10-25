import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/infrastructure/images/native_image_composer.dart';

/// LuraToons (https://luratoons.net) — Vue.js SPA + Django REST backend.
///
/// Catalog/details come from the REST API. Chapter pages use the same native
/// protocol as the Mihon extension: encrypted metadata followed by encrypted
/// ZIP archives whose image slices are joined into one page.
typedef LuraToonsBrowserHtmlLoad = Future<String> Function(
  Uri uri,
  String userAgent,
);
typedef LuraToonsPageComposer = Future<void> Function(
  List<Uint8List> slices,
  String outputPath,
);
typedef LuraToonsTemporaryDirectory = Future<Directory> Function();
typedef LuraToonsBinaryLoad
    = Future<({int statusCode, Uint8List body, Map<String, String> headers})>
        Function(
  Uri uri,
  Map<String, String> headers,
);

class LuraToonsSource extends BaseHtmlMangaSource
    implements WebViewChapterMangaSource, ChapterNavigationMangaSource {
  static const String _base = 'https://luratoons.net';
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';

  /// Google OAuth entry point (used by the auth WebView).
  static const String googleLoginUrl =
      '$_base/accounts/google/login/?process=login';

  List<MangaCatalogItem>? _cachedCatalog;
  final LuraToonsBrowserHtmlLoad? _browserHtmlLoader;
  final LuraToonsPageComposer _pageComposer;
  final LuraToonsTemporaryDirectory _temporaryDirectory;
  final LuraToonsBinaryLoad? _binaryLoader;

  LuraToonsSource({
    http.Client? client,
    LuraToonsBrowserHtmlLoad? browserHtmlLoader,
    LuraToonsPageComposer? pageComposer,
    LuraToonsTemporaryDirectory? temporaryDirectory,
    LuraToonsBinaryLoad? binaryLoader,
  })  : _browserHtmlLoader = browserHtmlLoader,
        _pageComposer = pageComposer ?? NativeImageComposer.composeVertical,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _binaryLoader = binaryLoader,
        super(_profile, client: client);

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'LuraToons',
    baseUrl: _base,
    contentType: ContentType.spa,
    auth: AuthConfig(
      loginUrl: '$_base/accounts/login/',
      type: AuthType.djangoForm,
      usernameFieldName: 'login',
      passwordFieldName: 'password',
      csrfFieldName: 'csrfmiddlewaretoken',
      csrfCookieName: 'csrftoken',
      successUrlFragment: '/',
      sessionValidationUrl: '$_base/api/user-info/',
      sessionValidationJsonField: 'user_authenticated',
      sessionCookieNames: ['sessionid', 'csrftoken'],
      logoutUrl: '$_base/accounts/logout/',
    ),
    buildDetailUrl: (id, base) => '$base/api/obra/$id/',
    buildChapterUrl: (id, base) => '$base/$id/',
    buildListUrl: (filter, page, base) => filter.toLowerCase() == 'recent'
        ? '$base/api/main/'
        : '$base/api/obras/',
    extractId: (url) {
      try {
        final uri = Uri.parse(url);
        return uri.pathSegments.where((s) => s.isNotEmpty).join('/');
      } catch (_) {
        return url;
      }
    },
  );

  @override
  String get id => 'luratoons';

  @override
  String get name => 'LuraToons';

  @override
  Uri get baseUri => Uri.parse(_base);

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => const {'Referer': '$_base/'};

  @override
  List<MangaCatalogFilter> get catalogFilters =>
      const [MangaCatalogFilter.popular, MangaCatalogFilter.recent];

  // ─── Catalog ───────────────────────────────────────────────────────────────

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    if (filter == MangaCatalogFilter.recent) {
      final data = await _jsonGet('$_base/api/main/');
      final lancamentos = (data['lancamentos'] ?? []) as List<dynamic>;
      return MangaCatalogPage(
        items: lancamentos.map(_recentItem).whereType<MangaCatalogItem>(),
      );
    }
    final catalog = await _fetchCatalog();
    return MangaCatalogPage(items: catalog);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final catalog = await _fetchCatalog();
    final normalized = query.toLowerCase();
    return MangaCatalogPage(
      items: catalog.where(
        (item) => item.title.toLowerCase().contains(normalized),
      ),
    );
  }

  Future<List<MangaCatalogItem>> _fetchCatalog() async {
    if (_cachedCatalog != null) return _cachedCatalog!;
    final data = await _jsonGet('$_base/api/obras/');
    final obras = (data['obras'] ?? []) as List<dynamic>;
    final items =
        obras.map(_catalogItem).whereType<MangaCatalogItem>().toList();
    _cachedCatalog = items;
    return items;
  }

  MangaCatalogItem? _catalogItem(dynamic raw) {
    final obra = raw as Map<String, dynamic>;
    final slug = obra['slug']?.toString() ?? '';
    if (slug.isEmpty) return null;
    return MangaCatalogItem(
      id: slug,
      title: obra['title']?.toString() ?? '',
      coverUri: _coverUri(obra['capa']?.toString() ?? ''),
    );
  }

  MangaCatalogItem? _recentItem(dynamic raw) {
    final item = raw as Map<String, dynamic>;
    final slug = item['slug']?.toString() ?? '';
    if (slug.isEmpty) return null;
    final caps = (item['caps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final latest = caps.isNotEmpty ? caps.first : null;
    return MangaCatalogItem(
      id: slug,
      title: item['title']?.toString() ?? '',
      coverUri: _coverUri(item['capa']?.toString() ?? ''),
      subtitle: latest != null
          ? mangaCatalogSubtitle(latestChapter: latest['num']?.toString())
          : null,
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final data = await _jsonGet('$_base/api/obra/$mangaId/');
    final caps = (data['caps'] ?? []) as List<dynamic>;
    final generos = (data['generos'] ?? []) as List<dynamic>;

    final chapters = caps
        .map((c) {
          final cap = c as Map<String, dynamic>;
          final slug = cap['slug']?.toString() ?? '';
          if (slug.isEmpty) return null;
          return MangaChapter(
            id: slug,
            number: cap['num']?.toString() ?? '',
            language: 'pt-br',
            publishedAt: cap['data']?.toString(),
          );
        })
        .whereType<MangaChapter>()
        .toList();

    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaId,
        title: data['titulo']?.toString() ?? '',
        coverUri: _coverUri(data['capa']?.toString() ?? ''),
      ),
      description: data['sinopse']?.toString() ?? '',
      genres: generos
          .map((g) => (g as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
      author: data['autor']?.toString(),
      status: mangaStatusFromString(data['status']),
      externalUri: Uri.tryParse('$_base/obra/$mangaId'),
      chapters: chapters,
    );
  }

  // ─── Native reading ────────────────────────────────────────────────────────

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final userResponse = await _readerGet('$_base/api/user-info/');
    _assertReaderResponse(userResponse, 'user information');
    final user = _decodeJson(userResponse.body);
    if (user['user_authenticated'] != true) {
      throw const MangaSourceSessionRequired('authentication_required');
    }
    final userId = user['userid']?.toString() ?? '';
    if (userId.isEmpty) {
      throw const FormatException('LuraToons did not return the user ID.');
    }

    final manifestResponse = await _readerGet(
      '$_base/api/484d2a13/$mangaId/$chapterId/',
      headers: const {'Cache-Control': 'no-cache'},
    );
    _assertReaderResponse(manifestResponse, 'chapter manifest');
    final manifestBytes = _decrypt(
      manifestResponse.bodyBytes,
      '$chapterId$mangaId$userId',
      prefixLength: 8,
    );
    final manifest = _decodeJson(utf8.decode(manifestBytes));
    final work = manifest['obra'];
    final workId = work is Map ? work['id']?.toString() ?? '' : '';
    final files = manifest['files'];
    // LuraToons currently returns the page total as an integer. Accept a list
    // as well for compatibility with older/test payloads that enumerated the
    // files explicitly.
    final pageCount = switch (files) {
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      List value => value.length,
      _ => 0,
    };
    if (workId.isEmpty || pageCount == 0) {
      throw const FormatException(
        'LuraToons returned an empty chapter manifest.',
      );
    }

    final root = await _temporaryDirectory();
    final outputDir = Directory(
      '${root.path}${Platform.pathSeparator}luratoons_reader'
      '${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}',
    );
    await outputDir.create(recursive: true);
    final pageKey = '$workId$chapterId$userId';
    final token = manifestResponse.headers['token'];

    for (var index = 0; index < pageCount; index++) {
      final response = await _readerGet(
        '$_base/download/$workId/$chapterId/$index/?api=2',
        headers: {
          'Referer': chapterWebUri(
            mangaId: mangaId,
            chapterId: chapterId,
          ).toString(),
          if (index == 0 && token != null && token.isNotEmpty) 'Token': token,
        },
      );
      _assertReaderResponse(response, 'page ${index + 1}');
      final zipBytes = _decrypt(
        response.bodyBytes,
        '6514b4a8$pageKey',
        prefixLength: 16,
      );
      final slices = _extractImageSlices(zipBytes);
      final outputPath = '${outputDir.path}${Platform.pathSeparator}'
          '${index.toString().padLeft(4, '0')}.jpg';
      await _pageComposer(slices, outputPath);
      yield MangaReaderPage.file(outputPath);
    }
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) =>
      Uri.parse('$_base/$mangaId/$chapterId/');

  // ─── Chapter navigation ────────────────────────────────────────────────────

  @override
  Future<String?> nextChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapterId(mangaId, currentChapterId, true);

  @override
  Future<String?> previousChapterId(String mangaId, String currentChapterId) =>
      _adjacentChapterId(mangaId, currentChapterId, false);

  Future<String?> _adjacentChapterId(
    String mangaId,
    String currentChapterId,
    bool isNext,
  ) async {
    final details = await getDetails(mangaId);
    final chapters = [...details.chapters]..sort((a, b) =>
        (double.tryParse(a.number) ?? 0)
            .compareTo(double.tryParse(b.number) ?? 0));
    final index = chapters.indexWhere((c) => c.id == currentChapterId);
    if (index == -1) return null;
    final target = isNext ? index + 1 : index - 1;
    if (target < 0 || target >= chapters.length) return null;
    return chapters[target].id;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _jsonGet(String url) async {
    final res = await httpGet(url);
    if (res.statusCode == 403 && _browserHtmlLoader != null) {
      final browserBody = await _browserHtmlLoader(Uri.parse(url), _userAgent);
      return _decodeJson(browserBody);
    }
    assertAuthResponse(res);
    return _decodeJson(res.body);
  }

  Map<String, dynamic> _decodeJson(String raw) {
    var body = raw.trim();
    if (body.startsWith('<')) {
      final document = html_parser.parse(body);
      final text = document.body?.text.trim() ?? '';
      if (text.contains('Conecte-se') ||
          body.contains('/accounts/login/') ||
          body.contains('/login/?next=')) {
        throw const MangaSourceSessionRequired('authentication_required');
      }
      body = text;
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('LuraToons retornou JSON inválido.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _assertReaderResponse(http.Response response, String stage) {
    if (response.statusCode == 402) {
      throw Exception('This LuraToons chapter requires VIP access.');
    }
    if (response.statusCode == 429) {
      throw Exception('LuraToons rate limit reached while loading $stage.');
    }
    assertAuthResponse(response);
  }

  Future<http.Response> _readerGet(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (_binaryLoader != null) {
      try {
        final native = await _binaryLoader(
          Uri.parse(url),
          // Android's CookieManager is the authoritative session jar. This is
          // the same arrangement used by Mihon: the login WebView and native
          // requests consume the very same cookies.
          {...requestHeaders, ...headers},
        );
        final nativeResponse = http.Response.bytes(
          native.body,
          native.statusCode,
          headers: native.headers,
          request: http.Request('GET', Uri.parse(url)),
        );
        if (native.statusCode != 401 && native.statusCode != 403) {
          return nativeResponse;
        }

        // Migration fallback for installs that previously kept a second,
        // potentially different cookie copy in SharedPreferences. A valid
        // persisted session may be used once while the user renews the shared
        // WebView jar; it never overrides a successful browser session.
        final persistedResponse = await httpGet(url, headers: headers);
        if (persistedResponse.statusCode != 401 &&
            persistedResponse.statusCode != 403) {
          debugPrint(
            '[LuraToons] WebView session was rejected; recovered with the '
            'validated legacy session.',
          );
          return persistedResponse;
        }
        return nativeResponse;
      } catch (error, stackTrace) {
        // Desktop/test platforms may not provide the Android binary channel.
        debugPrint('[LuraToons] Native request failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    return httpGet(url, headers: headers);
  }

  static Uint8List _decrypt(
    Uint8List encrypted,
    String key, {
    required int prefixLength,
  }) {
    if (encrypted.length <= prefixLength) {
      throw const FormatException(
          'LuraToons returned truncated encrypted data.');
    }
    final keyBytes = Uint8List.fromList(sha256.convert(utf8.encode(key)).bytes);
    final iv = Uint8List.fromList(encrypted.sublist(0, prefixLength));
    final cipher = StreamCipher('AES/CTR')
      ..init(false, ParametersWithIV(KeyParameter(keyBytes), iv));
    return cipher.process(
      Uint8List.sublistView(encrypted, prefixLength),
    );
  }

  static List<Uint8List> _extractImageSlices(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final entries = archive.files.where((entry) => entry.isFile).toList()
      ..sort((a, b) => _entryIndex(a.name).compareTo(_entryIndex(b.name)));
    final slices = <Uint8List>[];
    final base64Pattern = RegExp(r'base64,([0-9a-zA-Z/+=\s]+)');
    for (final entry in entries) {
      final bytes = entry.readBytes();
      if (bytes == null || bytes.isEmpty) continue;
      final extension = entry.name.split('.').length > 1
          ? entry.name.split('.').last.toLowerCase()
          : '';
      if (extension.isEmpty || extension == 'avif') {
        slices.add(bytes);
        continue;
      }
      final match = base64Pattern.firstMatch(utf8.decode(bytes));
      if (match != null) {
        slices.add(base64Decode(match.group(1)!.replaceAll(RegExp(r'\s'), '')));
      }
    }
    if (slices.isEmpty) {
      throw const FormatException(
        'LuraToons page archive did not contain readable image slices.',
      );
    }
    return slices;
  }

  static int _entryIndex(String name) {
    final basename = name.split('/').last.split('.').first;
    return int.tryParse(basename) ?? 0x7fffffff;
  }

  static Uri? _coverUri(String path) {
    if (path.isEmpty) return null;
    return Uri.tryParse(path.startsWith('http') ? path : '$_base$path');
  }
}
