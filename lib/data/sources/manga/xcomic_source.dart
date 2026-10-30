import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

/// xComic — an all-languages catalog where one title can contain several
/// independent scan/source feeds. Chapters keep their scan and language so
/// releases with the same number are never collapsed together.
class XComicSource implements MangaSource, FilterableMangaSource {
  static const _site = 'https://xcomic.net';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; NX809J) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static const _pageSize = 30;

  static const _types = [
    MangaFilterOption(value: 'cartoon', label: 'Cartoon'),
    MangaFilterOption(value: 'imageset', label: 'Imageset'),
    MangaFilterOption(value: 'manga', label: 'Manga'),
    MangaFilterOption(value: 'manhua', label: 'Manhua'),
    MangaFilterOption(value: 'manhwa', label: 'Manhwa'),
    MangaFilterOption(value: 'oel', label: 'OEL'),
    MangaFilterOption(value: 'other', label: 'Other'),
    MangaFilterOption(value: 'western', label: 'Western'),
  ];
  static const _demographics = [
    MangaFilterOption(value: 'shounen', label: 'Shounen (B)'),
    MangaFilterOption(value: 'shoujo', label: 'Shoujo (G)'),
    MangaFilterOption(value: 'seinen', label: 'Seinen (M)'),
    MangaFilterOption(value: 'josei', label: 'Josei (W)'),
    MangaFilterOption(value: 'kodomo', label: 'Kodomo (Kid)'),
    MangaFilterOption(value: 'silver_golden', label: 'Silver & Golden'),
    MangaFilterOption(value: 'non_human', label: 'Non-human'),
    MangaFilterOption(value: 'male_oriented', label: 'Male Oriented'),
    MangaFilterOption(value: 'female_oriented', label: 'Female Oriented'),
    MangaFilterOption(
      value: 'male_female_author',
      label: 'Male Demographic with Female Author',
    ),
    MangaFilterOption(
      value: 'male_female_lead',
      label: 'Male Demographic with Female Lead',
    ),
    MangaFilterOption(
      value: 'female_male_lead',
      label: 'Female Demographic with Male Lead',
    ),
  ];
  static const _formats = [
    MangaFilterOption(value: '1_koma', label: '1-Koma'),
    MangaFilterOption(value: '2_koma', label: '2-Koma'),
    MangaFilterOption(value: '3_koma', label: '3-Koma'),
    MangaFilterOption(value: '4_koma', label: '4-Koma'),
    MangaFilterOption(value: 'adaptation', label: 'Adaptation'),
    MangaFilterOption(value: 'anthology', label: 'Anthology'),
    MangaFilterOption(value: 'artbook', label: 'Artbook'),
    MangaFilterOption(value: 'award_winning', label: 'Award Winning'),
    MangaFilterOption(value: 'doujinshi', label: 'Doujinshi'),
    MangaFilterOption(value: 'fan_colored', label: 'Fan Colored'),
    MangaFilterOption(value: 'full_color', label: 'Full Color'),
    MangaFilterOption(value: 'guidebook', label: 'Guidebook'),
    MangaFilterOption(value: 'illustration_book', label: 'Illustration Book'),
    MangaFilterOption(value: 'japanese_novel', label: 'Japanese Novel'),
    MangaFilterOption(value: 'light_novel', label: 'Light Novel'),
    MangaFilterOption(value: 'long_strip', label: 'Long Strip'),
    MangaFilterOption(value: 'novels', label: 'Novels'),
    MangaFilterOption(value: 'official_colored', label: 'Official Colored'),
    MangaFilterOption(value: 'oneshot', label: 'Oneshot'),
    MangaFilterOption(value: 'web_comic', label: 'Web Comic'),
    MangaFilterOption(value: 'web_novel', label: 'Web Novel'),
    MangaFilterOption(value: 'webtoon', label: 'Webtoon'),
  ];
  static const _genres = [
    'Action',
    'Adult',
    'Adventure',
    'Age Gap',
    'Aliens',
    'Animals',
    'Art-by-AI',
    'Bara',
    'Beasts',
    'Blackmail',
    'Bloody',
    'Bodyswap',
    'Boys Love',
    'Childhood Friends',
    'Comedy',
    'Cooking',
    'Crime',
    'Crossdressing',
    'Cultivation',
    'Death Game',
    'Delinquents',
    'Dementia',
    'Demons',
    'Drama',
    'Dungeons',
    'Ecchi',
    'Fantasy',
    'Female-protagonists',
    'Fetish',
    'Futa',
    'Game',
    'Genderswap',
    'Ghosts',
    'Girls Love',
    'Gore',
    'Gyaru',
    'Harem',
    'Hentai',
    'Historical',
    'Horror',
    'Incest',
    'Isekai',
    'Kids',
    'Loli',
    'Mafia',
    'Magic',
    'Magical Girls',
    'Mahjong',
    'Male-protagonists',
    'Martial Arts',
    'Master-Servant',
    'Mature',
    'Mecha',
    'Medical',
    'Military',
    'Monsters',
    'Mystery',
    'Office Workers',
    'Philosophical',
    'Psychological',
    'Reincarnation',
    'Romance',
    'Royal family',
    'School Life',
    'Sci-Fi',
    'Slice of Life',
    'Smut',
    'Sports',
    'Super Power',
    'Supernatural',
    'Survival',
    'Thriller',
    'Tragedy',
    'Vampires',
    'Video Games',
    'Violence',
    'Yakuzas',
    'Zombies',
  ];
  static const _statuses = [
    MangaFilterOption(value: 'releasing', label: 'Releasing'),
    MangaFilterOption(value: 'completed', label: 'Completed'),
    MangaFilterOption(value: 'hiatus', label: 'Hiatus'),
    MangaFilterOption(value: 'cancelled', label: 'Cancelled'),
    MangaFilterOption(value: 'upcoming', label: 'Upcoming'),
    MangaFilterOption(value: 'unknown', label: 'Unknown'),
  ];
  static const _originalLanguages = [
    MangaFilterOption(value: 'zh', label: 'Chinese'),
    MangaFilterOption(value: 'en', label: 'English'),
    MangaFilterOption(value: 'ja', label: 'Japanese'),
    MangaFilterOption(value: 'ko', label: 'Korean'),
  ];
  static const _translatedLanguages = [
    MangaFilterOption(value: 'pt-br', label: 'Portuguese (Brazil)'),
    MangaFilterOption(value: 'en', label: 'English'),
    MangaFilterOption(value: 'es', label: 'Spanish'),
    MangaFilterOption(value: 'fr', label: 'French'),
    MangaFilterOption(value: 'de', label: 'German'),
    MangaFilterOption(value: 'it', label: 'Italian'),
    MangaFilterOption(value: 'ja', label: 'Japanese'),
    MangaFilterOption(value: 'ko', label: 'Korean'),
    MangaFilterOption(value: 'zh', label: 'Chinese'),
    MangaFilterOption(value: 'ru', label: 'Russian'),
    MangaFilterOption(value: 'th', label: 'Thai'),
    MangaFilterOption(value: 'vi', label: 'Vietnamese'),
  ];
  static const _chapterPresets = [
    MangaFilterOption(value: '0', label: '0'),
    MangaFilterOption(value: '1', label: '1+'),
    MangaFilterOption(value: '10', label: '10+'),
    MangaFilterOption(value: '20', label: '20+'),
    MangaFilterOption(value: '30', label: '30+'),
    MangaFilterOption(value: '40', label: '40+'),
    MangaFilterOption(value: '50', label: '50+'),
    MangaFilterOption(value: '60', label: '60+'),
    MangaFilterOption(value: '70', label: '70+'),
    MangaFilterOption(value: '80', label: '80+'),
    MangaFilterOption(value: '90', label: '90+'),
    MangaFilterOption(value: '100', label: '100+'),
    MangaFilterOption(value: '200', label: '200+'),
    MangaFilterOption(value: '300', label: '300+'),
    MangaFilterOption(value: '1-9', label: '1–9'),
    MangaFilterOption(value: '10-19', label: '10–19'),
    MangaFilterOption(value: '20-29', label: '20–29'),
    MangaFilterOption(value: '30-39', label: '30–39'),
    MangaFilterOption(value: '40-49', label: '40–49'),
    MangaFilterOption(value: '50-59', label: '50–59'),
    MangaFilterOption(value: '60-69', label: '60–69'),
    MangaFilterOption(value: '70-79', label: '70–79'),
    MangaFilterOption(value: '80-89', label: '80–89'),
    MangaFilterOption(value: '90-99', label: '90–99'),
    MangaFilterOption(value: '100-199', label: '100–199'),
    MangaFilterOption(value: '200-299', label: '200–299'),
  ];

  final http.Client _client;
  final Uri _baseUri;
  final Map<String, MangaDetails> _detailsCache = {};

  XComicSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_site);

  @override
  String get id => 'xcomic';

  @override
  String get name => 'xComic';

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
        MangaCatalogFilter.updated,
        MangaCatalogFilter.added,
        MangaCatalogFilter.popular,
        MangaCatalogFilter.trending,
      ];

  @override
  Future<MangaCatalogPage> browse({
    MangaCatalogFilter filter = MangaCatalogFilter.popular,
    String? cursor,
  }) {
    final sort = switch (filter) {
      MangaCatalogFilter.updated => 'update',
      MangaCatalogFilter.added || MangaCatalogFilter.recent => 'create',
      MangaCatalogFilter.trending => 'comment',
      _ => 'follow',
    };
    return _catalog({'sortby': sort}, cursor);
  }

  @override
  Future<MangaCatalogPage> search(String query, {String? cursor}) {
    final word = query.trim();
    return _catalog(
        {if (word.isNotEmpty) 'word': word, 'sortby': 'update'}, cursor);
  }

  @override
  Future<MangaSearchOptions> getSearchOptions() async => MangaSearchOptions(
        types: _types,
        formats: _formats,
        statuses: _statuses,
        genres: [
          for (final genre in _genres)
            MangaFilterOption(value: _slugValue(genre), label: genre),
        ],
        demographics: _demographics,
        originalLanguages: _originalLanguages,
        translatedLanguages: _translatedLanguages,
        chapterPresets: _chapterPresets,
        sorts: const [
          MangaSearchSort.rating,
          MangaSearchSort.updated,
          MangaSearchSort.recentlyAdded,
          MangaSearchSort.titleAscending,
          MangaSearchSort.titleDescending,
          MangaSearchSort.mostFollows,
          MangaSearchSort.mostReviews,
          MangaSearchSort.mostComments,
          MangaSearchSort.chapterCount,
        ],
        supportsYearRange: true,
        supportsChapterRange: false,
      );

  @override
  Future<MangaCatalogPage> filterCatalog(
    MangaSearchRequest request, {
    String? cursor,
  }) {
    final genreValues = {...request.genres, ...request.formats};
    return _catalog({
      if (request.types.isNotEmpty) 'types': request.types.join(','),
      if (request.demographics.isNotEmpty)
        'demographic': request.demographics.join(','),
      if (genreValues.isNotEmpty) 'genres_in': genreValues.join(','),
      if (request.originalLanguages.isNotEmpty)
        'orig': request.originalLanguages.join(','),
      if (request.translatedLanguages.isNotEmpty)
        'lang': request.translatedLanguages.join(','),
      if (request.statuses.isNotEmpty) 'status': request.statuses.join(','),
      if (request.chapterPreset.isNotEmpty) 'chapters': request.chapterPreset,
      if (request.minimumYear != null) 'year_min': '${request.minimumYear}',
      if (request.maximumYear != null) 'year_max': '${request.maximumYear}',
      'sortby': switch (request.sort) {
        MangaSearchSort.rating => 'score',
        MangaSearchSort.updated => 'update',
        MangaSearchSort.title || MangaSearchSort.titleAscending => 'name_asc',
        MangaSearchSort.titleDescending => 'name_desc',
        MangaSearchSort.mostFollows || MangaSearchSort.popular => 'follow',
        MangaSearchSort.mostReviews => 'review',
        MangaSearchSort.mostComments => 'comment',
        MangaSearchSort.chapterCount => 'chapter',
        _ => 'create',
      },
    }, cursor);
  }

  Future<MangaCatalogPage> _catalog(
    Map<String, String> parameters,
    String? cursor,
  ) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final uri = _resolve('/search').replace(queryParameters: {
      ...parameters,
      'page': '$page',
    });
    final document = html_parser.parse(await _loadHtml(uri));
    final items = _catalogItems(document);
    final hasNext = document.querySelector(
          'a[href*="page=${page + 1}"]',
        ) !=
        null;
    return MangaCatalogPage(
      items: items,
      nextCursor: hasNext || items.length >= _pageSize ? '${page + 1}' : null,
    );
  }

  List<MangaCatalogItem> _catalogItems(Document document) {
    final items = <MangaCatalogItem>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href^="/title/"]')) {
      final uri = _uri(anchor.attributes['href']);
      if (uri == null || uri.pathSegments.length < 2) continue;
      final title = _text(anchor);
      final id = uri.pathSegments[1];
      if (title.isEmpty || !seen.add(id)) continue;
      final card = _ancestorWithImage(anchor);
      if (card == null) continue;
      final cardText = _text(card);
      final cover = _uri(card.querySelector('img')?.attributes['src']);
      final chapterCount = int.tryParse(
        RegExp(r'(\d[\d,]*)\s+chapters?', caseSensitive: false)
                .firstMatch(cardText)
                ?.group(1)
                ?.replaceAll(',', '') ??
            '',
      );
      final rating = double.tryParse(
        RegExp(r'\b(10(?:\.0)?|[0-9](?:\.[0-9]))\b')
                .firstMatch(cardText)
                ?.group(1) ??
            '',
      );
      final year = int.tryParse(
        RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(cardText)?.group(0) ?? '',
      );
      final type = _types.map((entry) => entry.label).firstWhere(
            (label) =>
                RegExp('\b${RegExp.escape(label)}\b', caseSensitive: false)
                    .hasMatch(cardText),
            orElse: () => '',
          );
      items.add(MangaCatalogItem(
        id: id,
        title: title,
        coverUri: cover,
        subtitle: mangaCatalogSubtitle(
          totalChapters: chapterCount,
          format: type.isEmpty ? null : type,
          status: _status(cardText),
          rating: rating,
          year: year,
        ),
      ));
    }
    return items;
  }

  @override
  Future<MangaDetails> getDetails(String mangaId) async {
    final id = _idFrom(mangaId, 'title');
    final cached = _detailsCache[id];
    if (cached != null) return cached;
    final uri = _resolve('/title/$id');
    final document = html_parser.parse(await _loadHtml(uri));
    final h1 = document.querySelector('main h1');
    final title = _text(h1);
    if (title.isEmpty) {
      throw StateError('xComic did not expose details for "$mangaId".');
    }
    final cover = _uri(document.querySelector('main img')?.attributes['src']);
    final description = document
            .querySelector('meta[name="description"]')
            ?.attributes['content']
            ?.trim() ??
        document.querySelector('.limit-html')?.text.trim() ??
        '';
    final allText = _text(document.querySelector('main'));
    final sources = _scanReferences(document);
    final chapters = await _loadAllScanChapters(sources);
    chapters.sort((a, b) {
      final numberOrder =
          _chapterNumber(b.number).compareTo(_chapterNumber(a.number));
      if (numberOrder != 0) return numberOrder;
      return a.language.compareTo(b.language);
    });
    final people = document
        .querySelectorAll('a[href^="/search?word="]')
        .map(_text)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final tags = document
        .querySelectorAll('a[href^="/tag/"]')
        .map(_text)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final alternativeTitles = _alternativeTitles(h1, title);
    final item = MangaCatalogItem(
      id: id,
      title: title,
      coverUri: cover,
      subtitle: mangaCatalogSubtitle(
        totalChapters: chapters.length,
        format: _typeIn(allText),
        status: _status(allText),
        rating: _ratingIn(allText),
        year: _yearIn(allText),
      ),
    );
    return _detailsCache[id] = MangaDetails(
      item: item,
      description: description,
      alternativeTitles: alternativeTitles,
      genres: tags,
      author: people.isEmpty ? null : people.join(', '),
      artist: people.isEmpty ? null : people.last,
      status: _status(allText),
      externalUri: uri,
      chapters: chapters,
    );
  }

  List<_XComicScan> _scanReferences(Document document) {
    final scans = <_XComicScan>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href^="/source/"]')) {
      final uri = _uri(anchor.attributes['href']);
      if (uri == null || uri.pathSegments.length < 2) continue;
      final id = uri.pathSegments[1];
      if (!seen.add(id)) continue;
      Element? card = anchor.parent;
      for (var i = 0; i < 7 && card != null; i++, card = card.parent) {
        final cardText = _text(card);
        if (cardText.contains('#$id') &&
            RegExp(r'\d+\s+chapters?', caseSensitive: false)
                .hasMatch(cardText)) {
          break;
        }
      }
      final text = _text(card);
      final labels = card
              ?.querySelectorAll('span')
              .map(_text)
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      final missing = labels
          .where((value) =>
              RegExp(r'^missing\s*\(', caseSensitive: false).hasMatch(value))
          .firstOrNull;
      final scanName = labels.where((value) {
        final normalized = value.toLowerCase();
        return !normalized.contains('chapter') &&
            !normalized.contains('follow') &&
            !normalized.startsWith('missing') &&
            !value.startsWith('#') &&
            !_isFlag(value) &&
            !{'completed', 'releasing', 'hiatus', 'cancelled'}
                .contains(normalized);
      }).lastOrNull;
      scans.add(_XComicScan(
        id: id,
        name: scanName ?? _text(anchor),
        language: _languageFrom(text),
        missingChapters: missing,
      ));
    }
    return scans;
  }

  Future<List<MangaChapter>> _loadAllScanChapters(
    List<_XComicScan> scans,
  ) async {
    final chapters = <MangaChapter>[];
    const concurrency = 6;
    for (var offset = 0; offset < scans.length; offset += concurrency) {
      final slice = scans.skip(offset).take(concurrency);
      final results = await Future.wait(slice.map((scan) async {
        try {
          return await _loadScanChapters(scan);
        } catch (_) {
          return const <MangaChapter>[];
        }
      }));
      for (final result in results) {
        chapters.addAll(result);
      }
    }
    return chapters;
  }

  Future<List<MangaChapter>> _loadScanChapters(_XComicScan scan) async {
    final uri = _resolve('/source/${scan.id}');
    final document = html_parser.parse(await _loadHtml(uri));
    final chapters = <MangaChapter>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href^="/chapter/"]')) {
      final chapterUri = _uri(anchor.attributes['href']);
      if (chapterUri == null || !seen.add(chapterUri.path)) continue;
      final label = _text(anchor);
      final number = RegExp(
            r'(?:Chapter|Ch\.?)[ ]*([0-9]+(?:\.[0-9]+)?)',
            caseSensitive: false,
          ).firstMatch(label)?.group(1) ??
          RegExp(r'([0-9]+(?:\.[0-9]+)?)')
              .allMatches(label)
              .lastOrNull
              ?.group(1) ??
          '';
      if (number.isEmpty) continue;
      final volume = RegExp(
        r'(?:Volume|Vol\.?)\s*([0-9]+(?:\.[0-9]+)?)',
        caseSensitive: false,
      ).firstMatch(label)?.group(1);
      final row = anchor.parent;
      final published = row?.querySelector('time span')?.text.trim();
      chapters.add(MangaChapter(
        id: chapterUri.path,
        title: label,
        number: number,
        volume: volume,
        language: scan.language,
        publishedAt: published,
        scanId: scan.id,
        scanName: scan.name,
        missingChapters: scan.missingChapters,
      ));
    }
    return chapters;
  }

  @override
  Stream<MangaReaderPage> readChapter({
    required String mangaId,
    required String chapterId,
  }) async* {
    final chapterUri = _uri(chapterId) ??
        _resolve('/chapter/${_idFrom(chapterId, 'chapter')}');
    final html = await _loadHtml(chapterUri);
    final document = html_parser.parse(html);
    final seen = <String>{};
    for (final image in document.querySelectorAll(
      '[data-name="image-item"] img[src], [data-name="image-show"] img[src]',
    )) {
      final imageUri = _uri(image.attributes['src']);
      if (imageUri == null || !seen.add(imageUri.toString())) continue;
      yield MangaReaderPage.network(imageUri, headers: {
        ...coverImageHeaders,
        'Referer': chapterUri.toString(),
      });
    }

    // xComic renders the reader with Qwik. Before hydration the page images
    // are stored in the serialized SSR state instead of actual <img> nodes.
    // Reading that manifest keeps the native reader independent of WebView.
    if (seen.isEmpty) {
      for (final imageUri in _qwikReaderImages(html)) {
        if (!seen.add(imageUri.toString())) continue;
        yield MangaReaderPage.network(imageUri, headers: {
          ...coverImageHeaders,
          'Referer': chapterUri.toString(),
        });
      }
    }
    if (seen.isEmpty) {
      throw StateError('xComic did not expose reader images for "$chapterId".');
    }
  }

  Iterable<Uri> _qwikReaderImages(String html) sync* {
    final start = html.indexOf('"imageUrls"');
    if (start < 0) return;
    final manifestEnd = html.indexOf(',0,"prevChapter"', start);
    final end = manifestEnd >= 0
        ? manifestEnd
        : (start + 16000).clamp(start, html.length);
    final manifest = html.substring(start, end);
    for (final match in RegExp(r'"(https?://[^"\\]+(?:\\.[^"\\]*)*)"')
        .allMatches(manifest)) {
      try {
        final decoded = jsonDecode(match.group(0)!) as String;
        final uri = _uri(decoded);
        if (uri != null) yield uri;
      } on FormatException {
        continue;
      }
    }
  }

  Future<String> _loadHtml(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'xComic request failed (${response.statusCode})',
        uri,
      );
    }
    return response.body;
  }

  Uri _resolve(String value) => _baseUri.resolve(value);

  Uri? _uri(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty || normalized.startsWith('data:')) return null;
    return _baseUri.resolve(normalized);
  }

  static String _text(Node? node) =>
      (node?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _slugValue(String value) => value
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  static Element? _ancestorWithImage(Element anchor) {
    Element? current = anchor.parent;
    for (var i = 0; i < 8 && current != null; i++, current = current.parent) {
      if (current.querySelector('img') != null &&
          current.querySelectorAll('a[href^="/title/"]').length >= 2) {
        return current;
      }
    }
    return null;
  }

  static String _idFrom(String value, String segment) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final index = uri.pathSegments.indexOf(segment);
      if (index >= 0 && index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }
    return value.split('/').where((part) => part.isNotEmpty).last;
  }

  static double _chapterNumber(String value) => double.tryParse(value) ?? -1;

  static MangaStatus _status(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('completed')) return MangaStatus.completed;
    if (normalized.contains('hiatus')) return MangaStatus.hiatus;
    if (normalized.contains('cancelled')) return MangaStatus.cancelled;
    if (normalized.contains('releasing') || normalized.contains('ongoing')) {
      return MangaStatus.ongoing;
    }
    return MangaStatus.unknown;
  }

  static String? _typeIn(String text) {
    for (final type in _types) {
      if (RegExp('\b${RegExp.escape(type.label)}\b', caseSensitive: false)
          .hasMatch(text)) {
        return type.label;
      }
    }
    return null;
  }

  static double? _ratingIn(String text) => double.tryParse(
        RegExp(r'\b(10(?:\.0)?|[0-9](?:\.[0-9]))\b')
                .firstMatch(text)
                ?.group(1) ??
            '',
      );

  static int? _yearIn(String text) => int.tryParse(
        RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(text)?.group(0) ?? '',
      );

  static List<Map<String, String>> _alternativeTitles(
    Element? h1,
    String title,
  ) {
    Element? area = h1?.parent;
    for (var i = 0; i < 3 && area != null; i++, area = area.parent) {
      final candidates = _text(area)
          .split('/')
          .map((value) => value.trim())
          .where((value) =>
              value.isNotEmpty && value != title && value.length < 180)
          .toSet()
          .take(20)
          .map((value) => {'': value})
          .toList();
      if (candidates.isNotEmpty) return candidates;
    }
    return const [];
  }

  static bool _isFlag(String value) =>
      value.runes.length <= 3 && RegExp(r'[^\x00-\x7F]').hasMatch(value);

  static String _languageFrom(String text) {
    const flags = {
      '🇧🇷': 'pt-br',
      '🇵🇹': 'pt',
      '🇬🇧': 'en',
      '🇺🇸': 'en',
      '🇯🇵': 'ja',
      '🇰🇷': 'ko',
      '🇨🇳': 'zh',
      '🇹🇼': 'zh-hant',
      '🇪🇸': 'es',
      '🇫🇷': 'fr',
      '🇩🇪': 'de',
      '🇮🇹': 'it',
      '🇷🇺': 'ru',
      '🇹🇭': 'th',
      '🇻🇳': 'vi',
      '🇮🇩': 'id',
    };
    for (final entry in flags.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return 'und';
  }
}

class _XComicScan {
  final String id;
  final String name;
  final String language;
  final String? missingChapters;

  const _XComicScan({
    required this.id,
    required this.name,
    required this.language,
    this.missingChapters,
  });
}
