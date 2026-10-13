import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// AniTube catalog and MegaPlay playback implementation.
///
/// Catalog calls use AniTube's JSON API. Playback URLs are deliberately
/// resolved only in [getPlayback], because the provider may rotate them.
class AnitubeSource implements AnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://anitube.online/');
  static final Uri _defaultPlayerUri = Uri.parse('https://megaplay.buzz/');

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
  static const _payloadKey = 'i?LMTAx0Q6,:}50U';
  static const _payloadIv = "W0;27ToaUpl_P%'c";

  final http.Client _client;
  final Uri _catalogBaseUri;
  final Uri _playerBaseUri;

  AnitubeSource({
    http.Client? client,
    Uri? catalogBaseUri,
    Uri? playerBaseUri,
  })  : _client = client ?? http.Client(),
        _catalogBaseUri = catalogBaseUri ?? _defaultBaseUri,
        _playerBaseUri = playerBaseUri ?? _defaultPlayerUri;

  @override
  String get id => 'anitube';

  @override
  String get name => 'AniTube';

  @override
  Uri get baseUri => _catalogBaseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.popular,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.popular,
    String? cursor,
  }) async {
    if (filter == AnimeCatalogFilter.popular) {
      final payload = await _getJson(_catalogUri('api/trending-anime'));
      final rows = _list(payload['data']);
      return AnimeCatalogPage(items: rows.map(_trendingItem));
    }

    final page = int.tryParse(cursor ?? '') ?? 1;
    final uri = _catalogUri('api/recent-anime').replace(
      queryParameters: {'page': '$page', 'per_page': '30'},
    );
    final payload = await _getJson(uri);
    final pagination = _map(payload['pagination']);
    final totalPages = _integer(pagination['total_pages']) ?? page;
    return AnimeCatalogPage(
      items: _list(payload['data']).map(_catalogItem),
      nextCursor: page < totalPages ? '${page + 1}' : null,
    );
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return AnimeCatalogPage(items: const []);
    final uri = _catalogUri('api/search').replace(
      queryParameters: {'q': normalized},
    );
    final payload = await _getJson(uri);
    return AnimeCatalogPage(
      items: _list(payload['data']).map(_catalogItem),
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final series = await _series(animeId);
    final anime = _map(series['anime']);
    final alternatives = <String>{};
    void addTitle(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        alternatives.add(value.trim());
      } else if (value is Iterable) {
        for (final title in value) {
          addTitle(title);
        }
      } else if (value is Map) {
        for (final title in value.values) {
          addTitle(title);
        }
      }
    }

    addTitle(anime['alternative']);
    addTitle(anime['titles']);
    addTitle(anime['native']);
    alternatives.remove(anime['title']?.toString().trim());

    final terms = _map(anime['terms_by_type']);
    return AnimeDetails(
      item: _catalogItem(anime),
      description: _plainText(anime['description']),
      alternativeTitles: alternatives,
      genres: _names(terms['genre']),
      status: _status(anime['status']),
      bannerUri: _uri(anime['background_image']),
      externalIds: {
        if (anime['mal_id'] != null) 'mal': anime['mal_id'].toString(),
        if (anime['ani_id'] != null) 'anilist': anime['ani_id'].toString(),
      },
      studios: {
        ..._names(terms['studio']),
        ..._names(terms['studios']),
        ..._names(anime['studios']),
      },
      producers: {
        ..._names(terms['producer']),
        ..._names(terms['producers']),
        ..._names(anime['producers']),
      },
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final resolvedId = await _resolveAnimeId(animeId);
    final payload = await _getJson(_catalogUri('api/series/$resolvedId'));
    final data = _map(payload['data']);
    return _list(data['episodes']).map((episode) {
      final number = _number(episode['number']);
      return AnimeEpisode(
        id: episode['id'].toString(),
        animeId: animeId,
        title: _episodeTitle(episode, number),
        number: number,
        releasedAt: DateTime.tryParse(episode['updated_at']?.toString() ?? ''),
        thumbnailUri: _uri(episode['thumbnail']),
      );
    }).toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final series = await _series(animeId);
    final episode =
        _list(series['episodes']).cast<Map<String, dynamic>?>().firstWhere(
              (row) => row?['id'].toString() == episodeId,
              orElse: () => null,
            );
    if (episode == null) {
      throw StateError('AniTube episode $episodeId was not found.');
    }

    final embeds = _map(episode['embed_url']);
    final streams = <AnimeVideoStream>[];
    final subtitles = <AnimeSubtitleTrack>[];
    final skipSegments = <AnimeSkipSegment>[];
    final failures = <Object>[];

    for (final language in const ['sub', 'dub']) {
      final embedUri = _uri(embeds[language]);
      if (embedUri == null) continue;
      try {
        final manifest = await _resolvePlayer(embedUri, language);
        streams.addAll(manifest.streams);
        for (final subtitle in manifest.subtitles) {
          if (!subtitles.any((item) => item.uri == subtitle.uri)) {
            subtitles.add(subtitle);
          }
        }
        for (final segment in manifest.skipSegments) {
          if (!skipSegments.any(
            (item) => item.type == segment.type && item.start == segment.start,
          )) {
            skipSegments.add(segment);
          }
        }
      } catch (error) {
        failures.add(error);
      }
    }

    if (streams.isEmpty) {
      throw StateError(
        failures.isEmpty
            ? 'AniTube returned no playable stream for this episode.'
            : 'AniTube playback resolution failed: ${failures.first}',
      );
    }
    return AnimePlayback(
      streams: streams,
      subtitles: subtitles,
      skipSegments: skipSegments,
    );
  }

  Future<_PlayerManifest> _resolvePlayer(Uri embedUri, String language) async {
    final embedResponse = await _get(
      embedUri,
      headers: {'Referer': _catalogBaseUri.toString()},
    );
    final match =
        RegExp(r'''data-id=["'](\d+)["']''').firstMatch(embedResponse.body);
    if (match == null) {
      throw const FormatException('MegaPlay data-id is missing.');
    }

    final playerId = match.group(1)!;
    final sourceUri = _playerBaseUri.resolve('stream/getSourcesNew').replace(
      queryParameters: {'id': playerId, 'type': language},
    );
    final payload = await _getJson(
      sourceUri,
      headers: {
        'Referer': _playerBaseUri.toString(),
        'Origin': _origin(_playerBaseUri),
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
    final sourceData = payload['enc'] is String
        ? _decryptPayload(payload['enc'] as String)
        : payload;
    final mediaHeaders = {
      'Referer': _playerBaseUri.toString(),
      'Origin': _origin(_playerBaseUri),
      'User-Agent': _userAgent,
    };

    return _PlayerManifest(
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
          headers: mediaHeaders,
        );
      }),
      subtitles: _subtitleTracks(payload, mediaHeaders),
      skipSegments: [
        if (_skipSegment(payload['intro'], AnimeSkipType.intro)
            case final value?)
          value,
        if (_skipSegment(payload['outro'], AnimeSkipType.outro)
            case final value?)
          value,
      ],
    );
  }

  Future<Map<String, dynamic>> _series(String animeId) async {
    final resolvedId = await _resolveAnimeId(animeId);
    final payload = await _getJson(_catalogUri('api/series/$resolvedId'));
    return _map(payload['data']);
  }

  Future<String> _resolveAnimeId(String animeId) async {
    if (!animeId.startsWith('mal:')) return animeId;
    final parts = animeId.split(':');
    if (parts.length < 3) throw FormatException('Invalid AniTube id: $animeId');
    final malId = parts[1];
    final title = utf8.decode(base64Url.decode(base64Url.normalize(parts[2])));
    final uri = _catalogUri('api/search').replace(
      queryParameters: {'q': title},
    );
    final payload = await _getJson(uri);
    final match =
        _list(payload['data']).cast<Map<String, dynamic>?>().firstWhere(
              (item) => item?['mal_id']?.toString() == malId,
              orElse: () => null,
            );
    if (match == null) throw StateError('AniTube could not resolve $title.');
    return match['id'].toString();
  }

  AnimeCatalogItem _catalogItem(Map<String, dynamic> anime) {
    final rawId = anime['id'].toString();
    return AnimeCatalogItem(
      id: rawId,
      title: (anime['title'] ?? anime['name'] ?? 'Untitled').toString(),
      coverUri: _uri(anime['poster']),
      subtitle: _catalogSubtitle(anime),
    );
  }

  AnimeCatalogItem _trendingItem(Map<String, dynamic> anime) {
    final title = (anime['title'] ?? anime['name'] ?? 'Untitled').toString();
    final encodedTitle =
        base64Url.encode(utf8.encode(title)).replaceAll('=', '');
    final malId = anime['mal_id']?.toString() ?? '';
    return AnimeCatalogItem(
      id: 'mal:$malId:$encodedTitle',
      title: title,
      coverUri: _uri(anime['poster']),
      subtitle: _catalogSubtitle(anime),
    );
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.get(
      uri,
      headers: {...requestHeaders, ...headers},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        '$name returned HTTP ${response.statusCode}.',
        uri,
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _get(uri, headers: headers);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('AniTube returned invalid JSON.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Object _decryptPayload(String encoded) {
    final key = Uint8List(32);
    final keyBytes = utf8.encode(_payloadKey);
    key.setRange(0, keyBytes.length, keyBytes);
    final iv = Uint8List.fromList(utf8.encode(_payloadIv));
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    )..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    return jsonDecode(utf8.decode(cipher.process(bytes)));
  }

  Uri _catalogUri(String path) => _catalogBaseUri.resolve(path);

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
      result.add(
        AnimeSubtitleTrack(
          uri: uri,
          label: label,
          language: _subtitleLanguage(uri, label),
          format: uri.pathSegments.lastOrNull?.split('.').last,
          isDefault: track['default'] == true,
          headers: headers,
        ),
      );
    }
    return result;
  }

  static AnimeSkipSegment? _skipSegment(Object? value, AnimeSkipType type) {
    final range = _map(value);
    final start = _number(range['start']);
    final end = _number(range['end']);
    if (start == null || end == null || end <= start) return null;
    return AnimeSkipSegment(
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      type: type,
    );
  }

  static AnimeStatus _status(Object? value) {
    final status = value?.toString().toLowerCase() ?? '';
    if (status.contains('currently') || status.contains('airing')) {
      return AnimeStatus.ongoing;
    }
    if (status.contains('finished') || status.contains('complete')) {
      return AnimeStatus.completed;
    }
    if (status.contains('not yet') || status.contains('upcoming')) {
      return AnimeStatus.upcoming;
    }
    if (status.contains('hiatus')) return AnimeStatus.hiatus;
    if (status.contains('cancel')) return AnimeStatus.cancelled;
    return AnimeStatus.unknown;
  }

  static VideoProtocol _protocol(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('.m3u8')) return VideoProtocol.hls;
    if (value.contains('.mpd')) return VideoProtocol.dash;
    return VideoProtocol.progressive;
  }

  static String _episodeTitle(Map<String, dynamic> episode, double? number) {
    final title = episode['title']?.toString().trim();
    if (title != null && title.isNotEmpty) return title;
    return number == null ? 'Episode' : 'Episode ${_displayNumber(number)}';
  }

  static String? _catalogSubtitle(Map<String, dynamic> anime) {
    final values = <String>[
      if (anime['type'] != null) anime['type'].toString(),
      if (anime['episodes_count'] != null)
        '${anime['episodes_count']} episodes'
      else if (anime['episodes'] != null)
        '${anime['episodes']} episodes',
    ];
    return values.isEmpty ? null : values.join(' · ');
  }

  static String _plainText(Object? value) =>
      html_parser.parseFragment(value?.toString() ?? '').text?.trim() ?? '';

  static List<String> _names(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) {
          if (item is String) return item.trim();
          if (item is Map) {
            final mapped = Map<String, dynamic>.from(item);
            return (mapped['name'] ?? mapped['title'] ?? mapped['slug'])
                ?.toString()
                .trim();
          }
          return null;
        })
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String _subtitleLanguage(Uri uri, String label) {
    final match = RegExp(r'_([a-z]{2,3})\.vtt$', caseSensitive: false)
        .firstMatch(uri.path);
    final code = match?.group(1)?.toLowerCase();
    const aliases = {
      'eng': 'en',
      'por': 'pt-BR',
      'spa': 'es',
      'ara': 'ar',
      'fre': 'fr',
      'fra': 'fr',
      'ger': 'de',
      'deu': 'de',
      'ita': 'it',
      'rus': 'ru',
    };
    if (code != null) return aliases[code] ?? code;
    final lower = label.toLowerCase();
    if (lower.contains('portuguese')) return 'pt-BR';
    if (lower.contains('english')) return 'en';
    return 'und';
  }

  static String _origin(Uri uri) =>
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

  static String _displayNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static Uri? _uri(Object? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value.toString());
    return uri != null && uri.hasScheme ? uri : null;
  }

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];
}

class _PlayerManifest {
  final Iterable<AnimeVideoStream> streams;
  final Iterable<AnimeSubtitleTrack> subtitles;
  final Iterable<AnimeSkipSegment> skipSegments;

  const _PlayerManifest({
    required this.streams,
    required this.subtitles,
    required this.skipSegments,
  });
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
