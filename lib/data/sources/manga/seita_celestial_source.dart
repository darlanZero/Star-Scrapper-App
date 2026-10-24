import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Seita Celestial (ex-"Demon Sect", https://seitacelestial.com).
///
/// Dormant/legacy source: it is flagged as `outdated` in the app because the
/// original site is offline, and is kept only for a possible future
/// reactivation. It is ported 1:1 to the typed contract for consistency — HTML
/// scraping, random per-link local ids, no embedded reading (WebView only). No
/// behavior fix or reactivation is attempted here.
class SeitaCelestialSource
    implements MangaSource, WebViewChapterMangaSource {
  static const String _base = 'https://seitacelestial.com';

  final http.Client _client;
  final List<Map<String, dynamic>> _results = [];
  Map<String, String> _localIds = {};
  int _currentPage = 0;

  SeitaCelestialSource({http.Client? client})
      : _client = client ?? http.Client();

  @override
  String get id => 'seita_celestial';

  @override
  String get name => 'Seita Celestial';

  @override
  Uri get baseUri => Uri.parse(_base);

  @override
  Map<String, String> get requestHeaders => const {
        'Content-Type': 'text/html; charset=utf-8',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
                'image/webp,image/apng,*/*;q=0.8',
      };

  @override
  Map<String, String> get coverImageHeaders => const {'Referer': '$_base/'};

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.popular,
        MangaCatalogFilter.recent,
        MangaCatalogFilter.trending,
        MangaCatalogFilter.added,
        MangaCatalogFilter.alphabetical,
      ];

  // ─── Catalog ───────────────────────────────────────────────────────────────

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) async {
    _currentPage = int.tryParse(cursor ?? '') ?? 0;
    if (_currentPage == 0) _results.clear();
    await _loadLocalIds();
    final items = await _fetchResults(filter);
    return MangaCatalogPage(
      items: items,
      nextCursor: items.isEmpty ? null : '${_currentPage + 1}',
    );
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) async {
    final url = '$_base/?s=${Uri.encodeComponent(query)}';
    final response = await _client.get(Uri.parse(url), headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception('Seita Celestial search failed: ${response.statusCode}');
    }
    await _loadLocalIds();
    final document = html_parser.parse(response.body);
    final items = document.querySelectorAll('.listupd .bsx a').map((element) {
      final link = element.attributes['href'] ?? '';
      return MangaCatalogItem(
        id: _idForLink(link),
        title: element.querySelector('.bigor .tt')?.text.trim() ?? 'No title',
        coverUri: Uri.tryParse(
          element.querySelector('img')?.attributes['src'] ?? '',
        ),
        subtitle: element.querySelector('.adds .epxs')?.text.trim(),
      );
    }).toList();
    await _saveLocalIds();
    return MangaCatalogPage(items: items);
  }

  Future<List<MangaCatalogItem>> _fetchResults(MangaCatalogFilter filter) async {
    final order = switch (filter) {
      MangaCatalogFilter.recent => 'update',
      MangaCatalogFilter.trending => 'trending',
      MangaCatalogFilter.added => 'latest',
      MangaCatalogFilter.alphabetical => 'title',
      _ => 'popular',
    };
    final url =
        '$_base/comics/?page=${_currentPage + 1}&type=&order=$order';
    final response = await _client.get(Uri.parse(url), headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception('Seita Celestial page failed: ${response.statusCode}');
    }
    final document = html_parser.parse(response.body);
    final items = <MangaCatalogItem>[];
    for (final element in document.querySelectorAll('.listupd .bsx a')) {
      var link = element.attributes['href'] ?? '';
      if (link.isNotEmpty && !link.startsWith('/') && !link.startsWith('http')) {
        link = '$_base$link';
      }
      final id = _idForLink(link);
      _results.add({
        'id': id,
        'link': link,
        'title': element.querySelector('.bigor .tt')?.text.trim() ?? 'No title',
        'imageurl': element.querySelector('img')?.attributes['src'] ?? '',
      });
      items.add(MangaCatalogItem(
        id: id,
        title: element.querySelector('.bigor .tt')?.text.trim() ?? 'No title',
        coverUri: Uri.tryParse(
          element.querySelector('img')?.attributes['src'] ?? '',
        ),
        subtitle: element.querySelector('.adds .epxs')?.text.trim(),
      ));
    }
    await _saveLocalIds();
    return items;
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final cached = _results.firstWhere(
      (book) => book['id'] == mangaId,
      orElse: () => <String, dynamic>{},
    );
    final link = cached['link']?.toString() ?? '';
    final slug = _extractSlug(link);
    if (slug.isEmpty) {
      throw const MangaSourceSessionRequired(
        'Seita Celestial está desatualizada: abra o catálogo antes dos detalhes.',
      );
    }

    final url = '$_base/comics/$slug';
    final response = await _client.get(Uri.parse(url), headers: requestHeaders);
    if (response.statusCode != 200) {
      throw Exception('Seita Celestial details failed: ${response.statusCode}');
    }
    final document = html_parser.parse(response.body);

    return MangaDetails(
      item: MangaCatalogItem(
        id: mangaId,
        title: cached['title']?.toString() ?? '',
        coverUri: Uri.tryParse(cached['imageurl']?.toString() ?? ''),
      ),
      description:
          document.querySelector('.wd-full .desc')?.text.trim() ?? '',
      genres: document
          .querySelectorAll('.wd-full .mgen a')
          .map((e) => e.text.trim())
          .toList(),
      author: document
          .querySelector('.tsinfo .imptdt:nth-child(3) .author .name')
          ?.text
          .trim(),
      status: mangaStatusFromString(
        document.querySelector('.tsinfo .imptdt:nth-child(1) i')?.text.trim(),
      ),
      externalUri: Uri.tryParse(url),
      chapters: const [],
    );
  }

  // ─── Reading (WebView only) ─────────────────────────────────────────────────

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    // Not supported for this dormant source; reading falls back to the WebView.
  }

  @override
  Uri chapterWebUri({required String mangaId, required String chapterId}) {
    final cached = _results.firstWhere(
      (book) => book['id'] == mangaId,
      orElse: () => <String, dynamic>{},
    );
    final link = cached['link']?.toString() ?? _base;
    return Uri.parse(link.isEmpty ? _base : link);
  }

  // ─── Local id storage (ported 1:1) ─────────────────────────────────────────

  String _idForLink(String link) {
    final existing = _localIds[link];
    if (existing != null) return existing;
    final id = _randomId();
    if (link.isNotEmpty) _localIds[link] = id;
    return id;
  }

  String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(12, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<File> _localIdsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(path.join(directory.path, 'demon_sect_books_local_ids.json'));
  }

  Future<void> _loadLocalIds() async {
    try {
      final file = await _localIdsFile();
      if (await file.exists()) {
        _localIds = Map<String, String>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      }
    } catch (e) {
      debugPrint('[SeitaCelestial] failed to load local ids: $e');
    }
  }

  Future<void> _saveLocalIds() async {
    try {
      final file = await _localIdsFile();
      await file.writeAsString(jsonEncode(_localIds));
    } catch (e) {
      debugPrint('[SeitaCelestial] failed to save local ids: $e');
    }
  }

  String _extractSlug(String link) {
    if (link.isEmpty) return '';
    final trimmed = link.endsWith('/') ? link.substring(0, link.length - 1) : link;
    final segments = Uri.tryParse(trimmed)?.pathSegments ?? const [];
    final index = segments.indexOf('comics');
    if (index != -1 && index + 1 < segments.length) return segments[index + 1];
    return '';
  }
}
