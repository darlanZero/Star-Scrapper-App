import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// HTML/AJAX implementation for aniwave.gr.
///
/// Stable catalog ids are the site's watch slugs. Short-lived server and media
/// URLs are resolved only when playback starts.
class AniwaveSource implements AnimeSource, FilterableAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://aniwave.gr/');
  static final Uri _defaultPlayerUri = Uri.parse('https://megaplay.buzz/');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
  static const _payloadKey = 'i?LMTAx0Q6,:}50U';
  static const _payloadIv = "W0;27ToaUpl_P%'c";

  final http.Client _client;
  final Uri _baseUri;
  final Uri _playerUri;

  AniwaveSource({
    http.Client? client,
    Uri? baseUri,
    Uri? playerUri,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _playerUri = playerUri ?? _defaultPlayerUri;

  @override
  String get id => 'aniwave';

  @override
  String get name => 'AniWave';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'text/html,application/xhtml+xml,application/json',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.updated,
        AnimeCatalogFilter.added,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.airing,
        AnimeCatalogFilter.completed,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.updated,
    String? cursor,
  }) {
    final path = switch (filter) {
      AnimeCatalogFilter.popular ||
      AnimeCatalogFilter.popularWeek ||
      AnimeCatalogFilter.popularMonth =>
        'most-viewed',
      AnimeCatalogFilter.added => 'new-release',
      AnimeCatalogFilter.airing => 'status/currently-airing',
      AnimeCatalogFilter.completed => 'status/finished-airing',
      AnimeCatalogFilter.recent ||
      AnimeCatalogFilter.updated ||
      AnimeCatalogFilter.episodeMostViewed ||
      AnimeCatalogFilter.seriesNewest ||
      AnimeCatalogFilter.seriesPopular ||
      AnimeCatalogFilter.seriesMostViewed =>
        'latest-updated',
    };
    return _catalog(_pageUri(path, cursor));
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => filter(
        AnimeSearchRequest(query: query.trim()),
        cursor: cursor,
      );

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) {
    final params = <String, List<String>>{
      if (request.query.trim().isNotEmpty) 'keyword': [request.query.trim()],
      if (request.genres.isNotEmpty) 'genre[]': request.genres.toList(),
      if (request.season != null) 'season[]': [request.season!],
      if (request.year != null) 'year[]': [request.year!],
      if (request.type != null) 'term_type[]': [request.type!],
      if (request.status != null) 'status[]': [request.status!],
      if (request.language != null) 'language[]': [request.language!],
      if (request.rating != null) 'rating[]': [request.rating!],
      if (request.sort != AnimeSearchSort.defaultOrder)
        'sort': [_sortValue(request.sort)],
      if (cursor != null) 'page': [cursor],
    };
    return _catalog(_baseUri.resolve('filter').replace(
          queryParameters: params.map(
            (key, values) =>
                MapEntry(key, values.length == 1 ? values.first : values),
          ),
        ));
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final document = await _getDocument(_baseUri.resolve('filter'));
    List<AnimeFilterOption> options(String name) => document
        .querySelectorAll('input[name="$name"]')
        .map((input) {
          final value = input.attributes['value']?.trim() ?? '';
          final id = input.id;
          final label = id.isEmpty
              ? value
              : document.querySelector('label[for="$id"]')?.text.trim() ??
                  value;
          return AnimeFilterOption(value: value, label: label);
        })
        .where((option) => option.value.isNotEmpty)
        .toList(growable: false);

    return AnimeSearchOptions(
      genres: options('genre[]'),
      seasons: options('season[]'),
      years: options('year[]'),
      types: options('term_type[]'),
      statuses: options('status[]'),
      languages: options('language[]'),
      ratings: options('rating[]'),
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final document = await _watchDocument(animeId);
    final item = _detailsItem(document, animeId);
    final meta = _metadata(document);
    final episodeDocument = await _episodeDocument(document, animeId);
    final firstEpisode = episodeDocument.querySelector('.episodes a[data-mal]');
    final malId = firstEpisode?.attributes['data-mal']?.trim();
    final names = document.querySelector('#w-info .names')?.text.trim() ?? '';
    final alternatives = names
        .split(RegExp(r'[;,]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != item.title)
        .toSet();
    final background = _backgroundUri(
      document.querySelector('#player')?.attributes['style'],
    );

    return AnimeDetails(
      item: item,
      description:
          document.querySelector('#w-info .synopsis .content')?.text.trim() ??
              '',
      alternativeTitles: alternatives,
      genres: document
          .querySelectorAll('#w-info .bmeta a[href*="/genre/"]')
          .map((link) => link.text.trim())
          .where((value) => value.isNotEmpty),
      status: _status(meta['Status']),
      bannerUri: background,
      externalIds: {
        if (malId != null && malId.isNotEmpty) 'mal': malId,
      },
      studios: _splitNames(meta['Studios']),
      producers: _splitNames(meta['Producers']),
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final watch = await _watchDocument(animeId);
    final document = await _episodeDocument(watch, animeId);
    return document.querySelectorAll('.episodes a[data-num]').map((anchor) {
      final number = double.tryParse(anchor.attributes['data-num'] ?? '');
      final slug = anchor.attributes['data-slug']?.trim();
      final title = anchor.parent?.attributes['title']?.trim();
      return AnimeEpisode(
        id: slug?.isNotEmpty == true ? slug! : anchor.attributes['data-num']!,
        animeId: animeId,
        title: title?.isNotEmpty == true
            ? title!
            : 'Episode ${_displayNumber(number)}',
        number: number,
      );
    }).toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final watch = await _watchDocument(animeId);
    final episodes = await _episodeDocument(watch, animeId);
    final episode =
        episodes.querySelectorAll('.episodes a[data-ids]').firstWhere(
              (anchor) =>
                  anchor.attributes['data-slug'] == episodeId ||
                  anchor.attributes['data-num'] == episodeId,
              orElse: () => throw StateError(
                'AniWave episode $episodeId was not found.',
              ),
            );
    final serverIds = episode.attributes['data-ids'];
    if (serverIds == null || serverIds.isEmpty) {
      throw StateError('AniWave returned no servers for episode $episodeId.');
    }

    final serverPayload = await _getJson(
      _baseUri.resolve('ajax/server/list').replace(
        queryParameters: {'servers': serverIds},
      ),
      ajax: true,
      referer: _watchUri(animeId),
    );
    final serverDocument =
        html_parser.parseFragment(serverPayload['result']?.toString() ?? '');
    final streams = <AnimeVideoStream>[];
    final subtitles = <AnimeSubtitleTrack>[];
    final skipSegments = <AnimeSkipSegment>[];
    final failures = <Object>[];

    for (final type in serverDocument.querySelectorAll('.servers .type')) {
      final language = type.attributes['data-type']?.trim() ?? 'und';
      for (final server in type.querySelectorAll('[data-link-id]')) {
        final linkId = server.attributes['data-link-id'];
        if (linkId == null || linkId.isEmpty) continue;
        try {
          final payload = await _getJson(
            _baseUri.resolve('ajax/server').replace(
              queryParameters: {'get': linkId},
            ),
            ajax: true,
            referer: _watchUri(animeId),
          );
          final result = _map(payload['result']);
          final embedUri = _uri(result['url']);
          if (embedUri == null) continue;
          final manifest = await _resolveEmbed(embedUri, language);
          streams.addAll(manifest.streams);
          for (final subtitle in manifest.subtitles) {
            if (!subtitles.any((item) => item.uri == subtitle.uri)) {
              subtitles.add(subtitle);
            }
          }
          for (final segment in [
            ..._skipData(result['skip_data']),
            ...manifest.skipSegments,
          ]) {
            if (!skipSegments.any(
              (item) =>
                  item.type == segment.type && item.start == segment.start,
            )) {
              skipSegments.add(segment);
            }
          }
        } catch (error) {
          failures.add(error);
        }
      }
    }
    if (streams.isEmpty) {
      throw StateError(
        failures.isEmpty
            ? 'AniWave returned no playable stream for this episode.'
            : 'AniWave playback resolution failed: ${failures.first}',
      );
    }
    return AnimePlayback(
      streams: streams,
      subtitles: subtitles,
      skipSegments: skipSegments,
    );
  }

  Future<AnimeCatalogPage> _catalog(Uri uri) async {
    final document = await _getDocument(uri);
    final items = document
        .querySelectorAll('#list-items > .item')
        .map((node) {
          final link = node.querySelector('a.name') ??
              node.querySelector('a[href*="/watch/"]');
          final href = link?.attributes['href'];
          final slug = _watchSlug(href);
          final image = node.querySelector('.poster img');
          final title = link?.text.trim().isNotEmpty == true
              ? link!.text.trim()
              : image?.attributes['alt']?.trim() ?? 'Untitled';
          final meta = node
              .querySelectorAll('.info > .meta .m-item')
              .map((item) => item.text.trim().replaceAll(RegExp(r'\s+'), ' '))
              .where((value) => value.isNotEmpty)
              .join(' · ');
          return AnimeCatalogItem(
            id: slug,
            title: title,
            coverUri: _resolveUri(image?.attributes['src']),
            subtitle: meta.isEmpty ? null : meta,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    final current = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
    final hasNext =
        document.querySelectorAll('a[href*="page=${current + 1}"]').isNotEmpty;
    return AnimeCatalogPage(
      items: items,
      nextCursor: hasNext ? '${current + 1}' : null,
    );
  }

  Future<Document> _watchDocument(String animeId) =>
      _getDocument(_watchUri(animeId));

  Uri _watchUri(String animeId) => _baseUri.resolve('watch/$animeId');

  Future<DocumentFragment> _episodeDocument(
    Document watch,
    String animeId,
  ) async {
    final numericId = watch.querySelector('#watch-main')?.attributes['data-id'];
    if (numericId == null || numericId.isEmpty) {
      throw StateError('AniWave could not resolve $animeId.');
    }
    final payload = await _getJson(
      _baseUri.resolve('ajax/episode/list/$numericId'),
      ajax: true,
      referer: _watchUri(animeId),
    );
    return html_parser.parseFragment(payload['result']?.toString() ?? '');
  }

  AnimeCatalogItem _detailsItem(Document document, String animeId) {
    final titleNode = document.querySelector('#w-info h1.title');
    final title = titleNode?.text.trim() ?? animeId;
    final type = _metadata(document)['Type'];
    return AnimeCatalogItem(
      id: animeId,
      title: title,
      coverUri: _resolveUri(
        document.querySelector('#w-info .poster img')?.attributes['src'],
      ),
      subtitle: type?.isNotEmpty == true ? type : null,
    );
  }

  static Map<String, String> _metadata(Document document) {
    final result = <String, String>{};
    for (final row in document.querySelectorAll('#w-info .bmeta .meta > div')) {
      final text = row.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      final separator = text.indexOf(':');
      if (separator <= 0) continue;
      result[text.substring(0, separator).trim()] =
          text.substring(separator + 1).trim();
    }
    return result;
  }

  Future<_AniwaveManifest> _resolveEmbed(Uri embedUri, String language) async {
    final embedDocument = await _getDocument(
      embedUri,
      referer: _baseUri,
    );
    final frame = _resolveAgainst(
      embedUri,
      embedDocument.querySelector('iframe[src]')?.attributes['src'],
    );
    final player = frame ?? embedUri;
    final response = await _get(player, referer: embedUri);
    final match =
        RegExp(r'''data-id=["'](\d+)["']''').firstMatch(response.body);
    if (match == null) {
      throw const FormatException('MegaPlay data-id is missing.');
    }
    final sourcePayload = await _getJson(
      _playerUri.resolve('stream/getSourcesNew').replace(
        queryParameters: {'id': match.group(1)!, 'type': language},
      ),
      ajax: true,
      referer: _playerUri,
      origin: _origin(_playerUri),
    );
    final sourceData = sourcePayload['enc'] is String
        ? _decryptPayload(sourcePayload['enc'] as String)
        : sourcePayload;
    final headers = {
      'Referer': _playerUri.toString(),
      'Origin': _origin(_playerUri),
      'User-Agent': _userAgent,
    };
    return _AniwaveManifest(
      streams: _sourceEntries(sourceData).map((source) {
        final uri = _uri(source['file'] ?? source['url'] ?? source['src']);
        if (uri == null) {
          throw const FormatException(
              'MegaPlay returned an invalid stream URL.');
        }
        return AnimeVideoStream(
          uri: uri,
          protocol: _protocol(uri),
          quality: (source['label'] ?? source['quality'] ?? 'Auto').toString(),
          language: language,
          headers: headers,
        );
      }),
      subtitles: _subtitleTracks(sourcePayload, headers),
      skipSegments: [
        if (_skipMap(sourcePayload['intro'], AnimeSkipType.intro)
            case final value?)
          value,
        if (_skipMap(sourcePayload['outro'], AnimeSkipType.outro)
            case final value?)
          value,
      ],
    );
  }

  Future<Document> _getDocument(
    Uri uri, {
    Uri? referer,
  }) async =>
      html_parser.parse((await _get(uri, referer: referer)).body);

  Future<http.Response> _get(
    Uri uri, {
    bool ajax = false,
    Uri? referer,
    String? origin,
  }) async {
    final response = await _client.get(uri, headers: {
      ...requestHeaders,
      if (ajax) 'X-Requested-With': 'XMLHttpRequest',
      if (referer != null) 'Referer': referer.toString(),
      if (origin != null) 'Origin': origin,
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
          '$name returned HTTP ${response.statusCode}.', uri);
    }
    return response;
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    bool ajax = false,
    Uri? referer,
    String? origin,
  }) async {
    final response = await _get(
      uri,
      ajax: ajax,
      referer: referer,
      origin: origin,
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('AniWave returned invalid JSON.');
    }
    final result = Map<String, dynamic>.from(decoded);
    if (result['status'] is num && result['status'] != 200) {
      throw StateError(
          result['message']?.toString() ?? 'AniWave request failed.');
    }
    return result;
  }

  Uri _pageUri(String path, String? cursor) => _baseUri.resolve(path).replace(
        queryParameters: cursor == null ? null : {'page': cursor},
      );

  Uri? _resolveUri(String? value) => _resolveAgainst(_baseUri, value);

  static Uri? _resolveAgainst(Uri base, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return base.resolve(value.trim());
  }

  static String _watchSlug(String? href) {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null) return '';
    final index = uri.pathSegments.indexOf('watch');
    if (index < 0 || index + 1 >= uri.pathSegments.length) return '';
    return uri.pathSegments[index + 1];
  }

  static Uri? _backgroundUri(String? style) {
    final match = RegExp(r'''background-image:\s*url\(["']?([^"')]+)''')
        .firstMatch(style ?? '');
    return _uri(match?.group(1));
  }

  static Iterable<String> _splitNames(String? value) => (value ?? '')
      .split(RegExp(r'[,;]'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty);

  static String _sortValue(AnimeSearchSort sort) => switch (sort) {
        AnimeSearchSort.defaultOrder => 'default',
        AnimeSearchSort.latestUpdated => 'latest-updated',
        AnimeSearchSort.latestAdded => 'latest-added',
        AnimeSearchSort.score => 'score',
        AnimeSearchSort.name => 'name-az',
        AnimeSearchSort.nameDescending => 'name-za',
        AnimeSearchSort.releaseDate => 'release-date',
        AnimeSearchSort.mostViewed => 'most-viewed',
        AnimeSearchSort.episodeCount => 'number_of_episodes',
      };

  static AnimeStatus _status(String? value) {
    final status = value?.toLowerCase() ?? '';
    if (status.contains('currently')) return AnimeStatus.ongoing;
    if (status.contains('finished')) return AnimeStatus.completed;
    if (status.contains('not yet')) return AnimeStatus.upcoming;
    return AnimeStatus.unknown;
  }

  static String _displayNumber(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  }

  static List<AnimeSkipSegment> _skipData(Object? value) {
    final map = _map(value);
    return [
      if (_skipList(map['intro'], AnimeSkipType.intro) case final segment?)
        segment,
      if (_skipList(map['outro'], AnimeSkipType.outro) case final segment?)
        segment,
    ];
  }

  static AnimeSkipSegment? _skipList(Object? value, AnimeSkipType type) {
    if (value is! List || value.length < 2) return null;
    final start = _number(value[0]);
    final end = _number(value[1]);
    if (start == null || end == null || end <= start) return null;
    return AnimeSkipSegment(
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      type: type,
    );
  }

  static AnimeSkipSegment? _skipMap(Object? value, AnimeSkipType type) {
    final map = _map(value);
    final start = _number(map['start']);
    final end = _number(map['end']);
    if (start == null || end == null || end <= start) return null;
    return AnimeSkipSegment(
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      type: type,
    );
  }

  static List<Map<String, dynamic>> _sourceEntries(Object? value) {
    if (value is String) {
      return [
        {'file': value}
      ];
    }
    if (value is List) {
      return value.expand(_sourceEntries).toList(growable: false);
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map['file'] != null || map['url'] != null || map['src'] != null) {
        return [map];
      }
      for (final key in const ['sources', 'source', 'links']) {
        final nested = _sourceEntries(map[key]);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  static List<AnimeSubtitleTrack> _subtitleTracks(
    Map<String, dynamic> payload,
    Map<String, String> headers,
  ) {
    final result = <AnimeSubtitleTrack>[];
    for (final track in _list(payload['tracks'])) {
      final kind = track['kind']?.toString().toLowerCase();
      if (kind != null && kind != 'captions' && kind != 'subtitles') continue;
      final uri = _uri(track['file'] ?? track['url'] ?? track['src']);
      if (uri == null) continue;
      final label = (track['label'] ?? 'Subtitle').toString();
      result.add(AnimeSubtitleTrack(
        uri: uri,
        label: label,
        language: _subtitleLanguage(uri, label),
        format: uri.pathSegments.lastOrNull?.split('.').last,
        isDefault: track['default'] == true,
        headers: headers,
      ));
    }
    return result;
  }

  static String _subtitleLanguage(Uri uri, String label) {
    final match = RegExp(r'_([a-z]{2,3})\.vtt$', caseSensitive: false)
        .firstMatch(uri.path);
    final code = match?.group(1)?.toLowerCase();
    const aliases = {
      'eng': 'en',
      'por': 'pt-BR',
      'spa': 'es',
      'fre': 'fr',
      'ger': 'de'
    };
    if (code != null) return aliases[code] ?? code;
    final lower = label.toLowerCase();
    if (lower.contains('portuguese')) return 'pt-BR';
    if (lower.contains('english')) return 'en';
    return 'und';
  }

  static VideoProtocol _protocol(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('.m3u8')) return VideoProtocol.hls;
    if (value.contains('.mpd')) return VideoProtocol.dash;
    return VideoProtocol.progressive;
  }

  static Object _decryptPayload(String encoded) {
    final key = Uint8List(32);
    final bytes = utf8.encode(_payloadKey);
    key.setRange(0, bytes.length, bytes);
    final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(
              KeyParameter(key), Uint8List.fromList(utf8.encode(_payloadIv))),
          null,
        ),
      );
    return jsonDecode(utf8.decode(
        cipher.process(base64Url.decode(base64Url.normalize(encoded)))));
  }

  static Uri? _uri(Object? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value.toString());
    return uri != null && uri.hasScheme ? uri : null;
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static String _origin(Uri uri) =>
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}

class _AniwaveManifest {
  final Iterable<AnimeVideoStream> streams;
  final Iterable<AnimeSubtitleTrack> subtitles;
  final Iterable<AnimeSkipSegment> skipSegments;

  const _AniwaveManifest({
    required this.streams,
    required this.subtitles,
    required this.skipSegments,
  });
}
