import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// Bato/BATOTO English catalog with native chapter reading.
class BatoSource implements MangaSource, FilterableMangaSource {
  static const _site = 'https://bato1.com';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, MangaDetails> _detailsCache = {};
  MangaSearchOptions? _searchOptionsCache;

  BatoSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'bato';

  @override
  String get name => 'Bato';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$_site/',
        'User-Agent': _userAgent,
      };

  @override
  Map<String, String> get coverImageHeaders => const {
        'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
        'Referer': '$_site/',
        'User-Agent': _userAgent,
      };

  @override
  List<MangaCatalogFilter> get catalogFilters => const [
        MangaCatalogFilter.recent,
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.recent,
    String? cursor,
  }) {
    final route = switch (filter) {
      MangaCatalogFilter.updated => '/updated',
      MangaCatalogFilter.added => '/added',
      _ => '/newest',
    };
    return _catalog(
        cursor == null ? _baseUri.resolve(route) : _resolve(cursor));
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final uri = cursor == null
        ? _baseUri.resolve('/filter').replace(queryParameters: {
            'keyword': query.trim(),
          })
        : _resolve(cursor);
    return _catalog(uri);
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async {
    final cached = _searchOptionsCache;
    if (cached != null) return cached;
    final document = await _getDocument(_baseUri.resolve('/filter'));
    final options = MangaSearchOptions(
      types: _inputOptions(document, 'type[]'),
      genres: _inputOptions(document, 'genre[]'),
      statuses: _inputOptions(document, 'status[]'),
      chapterPresets: _inputOptions(document, 'minchap'),
      sorts: const [
        MangaSearchSort.updated,
        MangaSearchSort.recentlyAdded,
        MangaSearchSort.releaseDate,
        MangaSearchSort.titleAscending,
      ],
      supportsYearRange: true,
      supportsChapterRange: false,
      supportsCategoryMode: true,
    );
    _searchOptionsCache = options;
    return options;
  }

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    if (cursor != null) return _catalog(_resolve(cursor));
    final parameters = <String, dynamic>{
      'keyword': '',
      if (request.types.isNotEmpty) 'type[]': request.types.toList(),
      if (request.genres.isNotEmpty) 'genre[]': request.genres.toList(),
      if (request.categoryMode == MangaCategoryMode.all) 'genre_mode': 'and',
      if (request.statuses.isNotEmpty) 'status[]': request.statuses.toList(),
      if (_yearValues(request) case final years when years.isNotEmpty)
        'year[]': years,
      if (request.chapterPreset.isNotEmpty) 'minchap': request.chapterPreset,
      'sort': switch (request.sort) {
        MangaSearchSort.updated => 'recently_updated',
        MangaSearchSort.releaseDate => 'release_date',
        MangaSearchSort.title || MangaSearchSort.titleAscending => 'title_az',
        _ => 'recently_added',
      },
    };
    return _catalog(
      _baseUri.resolve('/filter').replace(queryParameters: parameters),
    );
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final slug = _slug(mangaId);
    final cached = _detailsCache[slug];
    if (cached != null) return cached;

    final uri = _baseUri.resolve('/manga/$slug');
    final document = await _getDocument(uri);
    final title = document
            .querySelector('#manga-page .manga-detail h1[itemprop="name"]')
            ?.text
            .trim() ??
        document.querySelector('#manga-page h1')?.text.trim() ??
        slug.replaceAll('-', ' ');
    final cover = _imageUri(
      document.querySelector('#manga-page .manga-detail .poster img'),
    );
    final description =
        document.querySelector('#synopsisModal p')?.text.trim() ??
            document.querySelector('#manga-page .description')?.text.trim() ??
            '';
    final alternativeText = document
            .querySelector('#manga-page .manga-detail .info > h6')
            ?.text
            .trim() ??
        '';
    final alternativeTitles = alternativeText
        .split(RegExp(r'\s*,\s*'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != title)
        .map((value) => {'und': value})
        .toList(growable: false);
    final genres = document
        .querySelectorAll('#info-rating .meta a[href*="/genre/"]')
        .map((anchor) => anchor.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final statusText = document
            .querySelector('#manga-page .manga-detail .info > p')
            ?.text
            .trim() ??
        '';
    final format = document
            .querySelector('#manga-page .min-info a[href*="/type/"]')
            ?.text
            .trim() ??
        '';
    final chapters = await _loadChapters(slug, document, uri);
    final details = MangaDetails(
      item: MangaCatalogItem(
        id: slug,
        title: title,
        coverUri: cover,
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapters.length,
          format: format,
          status: _status(statusText),
        ),
      ),
      description: description,
      alternativeTitles: alternativeTitles,
      genres: genres,
      author: document
          .querySelector('#info-rating .meta a[itemprop="author"]')
          ?.text
          .trim(),
      status: _status(statusText),
      externalUri: uri,
      chapters: chapters,
    );
    _detailsCache[slug] = details;
    return details;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final uri = _resolve(chapterId);
    final document = await _getDocument(uri);
    final seen = <String>{};
    for (final image in document.querySelectorAll(
      '.chapter-images-container .page img[data-number]',
    )) {
      if (image.attributes['data-number'] == 'notice' ||
          image.parent?.parent?.classes.contains('notice-page') == true) {
        continue;
      }
      final value = image.attributes['data-src'] ??
          image.attributes['src'] ??
          image.attributes['data-fallback'];
      final pageUri = _uri(value);
      if (pageUri == null ||
          pageUri.scheme == 'data' ||
          !seen.add(pageUri.toString())) {
        continue;
      }
      yield MangaReaderPage.network(
        pageUri,
        headers: {
          'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
          'Referer': '${uri.scheme}://${uri.host}/',
          'User-Agent': _userAgent,
        },
      );
    }
  }

  Future<MangaCatalogPage> _catalog(Uri uri) async {
    final document = await _getDocument(uri);
    final seen = <String>{};
    final items = document
        .querySelectorAll('.unit.item-')
        .map((card) {
          final anchor = card.querySelector('.info > a[href*="/manga/"]') ??
              card.querySelector('a.poster[href*="/manga/"]');
          final href = anchor?.attributes['href'] ?? '';
          final slug = _slug(href);
          if (slug.isEmpty || !seen.add(slug)) return null;
          final image = card.querySelector('.poster img');
          final title =
              card.querySelector('.info > a[href*="/manga/"]')?.text.trim() ??
                  image?.attributes['alt']?.trim() ??
                  '';
          if (title.isEmpty) return null;
          final latestChapter = card
              .querySelector('.content li a span:first-child')
              ?.text
              .trim()
              .replaceFirst(RegExp(r':\s*$'), '');
          final format = card.querySelector('.info .type')?.text.trim();
          return MangaCatalogItem(
            id: slug,
            title: title,
            coverUri: _imageUri(image),
            subtitle: mangaCatalogSubtitle(
              latestChapter: latestChapter,
              format: format,
            ),
          );
        })
        .whereType<MangaCatalogItem>()
        .toList(growable: false);
    return MangaCatalogPage(
      items: items,
      nextCursor: document
          .querySelector('a.page-link[rel="next"][href], a[rel="next"][href]')
          ?.attributes['href']
          ?.trim(),
    );
  }

  Future<List<MangaChapter>> _loadChapters(
    String slug,
    Document fallback,
    Uri detailsUri,
  ) async {
    try {
      final uri = _baseUri.resolve('/get-chapter-list').replace(
        queryParameters: {'slug': slug},
      );
      final response = await _client.get(uri, headers: {
        ...requestHeaders,
        'Referer': detailsUri.toString(),
        'X-Requested-With': 'XMLHttpRequest',
      });
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map &&
            decoded['success'] == true &&
            decoded['data'] is List) {
          final chapters = (decoded['data'] as List)
              .whereType<Map>()
              .map((raw) => _jsonChapter(slug, raw))
              .whereType<MangaChapter>()
              .toList(growable: false);
          if (chapters.isNotEmpty) return _sortChapters(chapters);
        }
      }
    } catch (_) {
      // The initial HTML still contains the latest chapters as a safe fallback.
    }

    final chapters = fallback
        .querySelectorAll('#chapter-list li.item')
        .map((li) {
          final anchor = li.querySelector('a[href*="/read/"]');
          final id = anchor?.attributes['href']?.trim() ?? '';
          if (id.isEmpty) return null;
          final title = anchor?.attributes['title']?.trim() ??
              anchor?.querySelector('span')?.text.trim() ??
              'Chapter';
          return MangaChapter(
            id: id,
            title: title,
            number: _chapterNumber(title),
            language: 'en',
            publishedAt:
                anchor?.querySelectorAll('span').lastOrNull?.text.trim(),
          );
        })
        .whereType<MangaChapter>()
        .toList(growable: false);
    return _sortChapters(chapters);
  }

  MangaChapter? _jsonChapter(String slug, Map raw) {
    final chapterSlug = raw['chapter_slug']?.toString().trim() ?? '';
    final title = raw['chapter_name']?.toString().trim() ?? '';
    if (chapterSlug.isEmpty || title.isEmpty) return null;
    return MangaChapter(
      id: '/read/$slug/$chapterSlug',
      title: title,
      number: _numberText(raw['chapter_num']) ?? _chapterNumber(title),
      language: 'en',
      publishedAt: raw['updated_at']?.toString(),
    );
  }

  List<MangaChapter> _sortChapters(List<MangaChapter> chapters) => chapters
    ..sort((left, right) {
      final leftNumber = double.tryParse(left.number);
      final rightNumber = double.tryParse(right.number);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      return left.title.compareTo(right.title);
    });

  List<MangaFilterOption> _inputOptions(Document document, String name) =>
      document
          .querySelectorAll('input[name="$name"]')
          .map((input) {
            final value = input.attributes['value']?.trim() ?? '';
            final label = input.id.isEmpty
                ? value
                : document
                        .querySelector('label[for="${input.id}"]')
                        ?.text
                        .trim() ??
                    value;
            return value.isEmpty || label.isEmpty
                ? null
                : MangaFilterOption(value: value, label: label);
          })
          .whereType<MangaFilterOption>()
          .toList(growable: false);

  List<String> _yearValues(MangaSearchRequest request) {
    final minimum = request.minimumYear;
    final maximum = request.maximumYear;
    if (minimum == null && maximum == null) return const [];
    final now = DateTime.now().year;
    final start = (minimum ?? maximum!).clamp(1930, now);
    final end = (maximum ?? minimum!).clamp(start, now);
    final values = <String>{};
    for (var year = start; year <= end; year++) {
      if (year >= 2005) {
        values.add('$year');
      } else {
        values.add('${year ~/ 10 * 10}s');
      }
    }
    return values.toList(growable: false);
  }

  MangaStatus _status(String value) => switch (value.trim().toLowerCase()) {
        'ongoing' || 'releasing' => MangaStatus.ongoing,
        'completed' => MangaStatus.completed,
        'on hiatus' || 'on_hiatus' || 'hiatus' => MangaStatus.hiatus,
        'discontinued' || 'cancelled' => MangaStatus.cancelled,
        _ => MangaStatus.unknown,
      };

  String _chapterNumber(String value) =>
      RegExp(r'(\d+(?:\.\d+)?)').firstMatch(value)?.group(1) ?? value;

  String? _numberText(Object? value) {
    final number = num.tryParse(value?.toString() ?? '');
    if (number == null) return null;
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
  }

  Future<Document> _getDocument(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bato: HTTP ${response.statusCode}');
    }
    return html_parser.parse(response.body);
  }

  String _slug(String value) {
    final uri = Uri.tryParse(value);
    final segments = (uri?.path ?? value)
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final mangaIndex = segments.indexOf('manga');
    if (mangaIndex >= 0 && mangaIndex + 1 < segments.length) {
      return segments[mangaIndex + 1];
    }
    return segments.isEmpty ? value.trim() : segments.last;
  }

  Uri _resolve(String value) => _baseUri.resolve(value);

  Uri? _uri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _uri(
        image?.attributes['data-src'] ??
            image?.attributes['src'] ??
            image?.attributes['data-fallback'],
      );
}
