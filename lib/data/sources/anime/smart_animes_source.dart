import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// Brazilian Portuguese catalog backed by smartanimes.net.
///
/// Cloudflare's browser verification is completed in a WebView and its
/// resulting cookies are reused here. Episode host redirects are deliberately
/// resolved only when the user starts playback.
class SmartAnimesSource
    implements
        AnimeSource,
        FilterableAnimeSource,
        BrowserSessionAnimeSource,
        BrowserPlaybackAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://smartanimes.net/');
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
  static const _cookiesKey = 'smart_animes_browser_cookies';
  static const _userAgentKey = 'smart_animes_browser_user_agent';

  final http.Client _client;
  final Uri _baseUri;
  Map<String, String> _cookies = const {};
  String _userAgent = _defaultUserAgent;
  bool _sessionLoaded = false;

  SmartAnimesSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri;

  @override
  String get id => 'smart_animes';

  @override
  String get name => 'Smart Animes';

  @override
  Uri get baseUri => _baseUri;

  @override
  Uri get sessionUri => _baseUri.resolve('anime/?order=update');

  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.7',
        'User-Agent': _userAgent,
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; '),
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.updated,
        AnimeCatalogFilter.added,
        AnimeCatalogFilter.popular,
      ];

  @override
  Future<void> updateBrowserSession({
    required Map<String, String> cookies,
    required String userAgent,
  }) async {
    _cookies = Map.unmodifiable(cookies);
    _userAgent = userAgent.trim().isEmpty ? _defaultUserAgent : userAgent;
    _sessionLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiesKey, jsonEncode(_cookies));
    await prefs.setString(_userAgentKey, _userAgent);
  }

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.updated,
    String? cursor,
  }) {
    final order = switch (filter) {
      AnimeCatalogFilter.popular => 'popular',
      AnimeCatalogFilter.added => 'latest',
      _ => 'update',
    };
    return _catalog(_animeUri({'order': order}, cursor));
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
    final params = <String, dynamic>{
      if (request.query.trim().isNotEmpty) 's': request.query.trim(),
      if (request.genres.isNotEmpty) 'genre[]': request.genres.toList(),
      if (request.season != null) 'season[]': [request.season!],
      if (request.studio != null) 'studio[]': [request.studio!],
      if (request.status != null) 'status': request.status!,
      if (request.type != null) 'type': request.type!,
      if (request.language != null) 'sub': request.language!,
      if (request.sort != AnimeSearchSort.defaultOrder)
        'order': _sortValue(request.sort),
    };
    return _catalog(_animeUri(params, cursor));
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final document = await _getDocument(_baseUri.resolve('anime/'));
    List<AnimeFilterOption> inputs(String name) => document
        .querySelectorAll('input[name="$name"]')
        .map((input) {
          final value = input.attributes['value']?.trim() ?? '';
          final label = input.id.isEmpty
              ? input.parent?.text.trim() ?? value
              : document
                      .querySelector('label[for="${input.id}"]')
                      ?.text
                      .trim() ??
                  input.parent?.text.trim() ??
                  value;
          return AnimeFilterOption(value: value, label: label);
        })
        .where((option) => option.value.isNotEmpty)
        .toList(growable: false);
    List<AnimeFilterOption> select(String name) => document
        .querySelectorAll('select[name="$name"] option')
        .map((option) => AnimeFilterOption(
              value: option.attributes['value']?.trim() ?? '',
              label: option.text.trim(),
            ))
        .where((option) => option.value.isNotEmpty)
        .toList(growable: false);

    return AnimeSearchOptions(
      genres: inputs('genre[]'),
      seasons: inputs('season[]'),
      studios: inputs('studio[]'),
      types: select('type'),
      statuses: select('status'),
      languages: select('sub'),
      sorts: const [
        AnimeSearchSort.defaultOrder,
        AnimeSearchSort.latestUpdated,
        AnimeSearchSort.latestAdded,
        AnimeSearchSort.score,
        AnimeSearchSort.name,
        AnimeSearchSort.nameDescending,
        AnimeSearchSort.mostViewed,
      ],
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final document = await _getDocument(_animeDetailsUri(animeId));
    final title =
        document.querySelector('.entry-title')?.text.trim() ?? animeId;
    final cover = _imageUri(document.querySelector('.thumbook img'));
    final metadata = _metadata(document);
    final alternatives = (document.querySelector('.alter')?.text ?? '')
        .split(RegExp(r'[,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != title);
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: animeId,
        title: title,
        coverUri: cover,
        subtitle: metadata['Tipo'],
      ),
      description: document
              .querySelector(
                  '.bixbox.synp .entry-content, .entry-content[itemprop="description"]')
              ?.text
              .trim() ??
          '',
      alternativeTitles: alternatives,
      genres: document
          .querySelectorAll('.genxed a[href*="/genres/"]')
          .map((link) => link.text.trim())
          .where((value) => value.isNotEmpty),
      status: _status(metadata['Status']),
      studios: _linkedMetadata(document, 'Estúdio'),
      producers: _linkedMetadata(document, 'Produtores'),
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final document = await _getDocument(_animeDetailsUri(animeId));
    return document
        .querySelectorAll('.eplister li a[href]')
        .map((anchor) {
          final href = _resolveUri(anchor.attributes['href']);
          final numberText =
              anchor.querySelector('.epl-num')?.text.trim() ?? '';
          final number = double.tryParse(
            RegExp(r'[\d.]+').firstMatch(numberText)?.group(0) ?? '',
          );
          final title = anchor.querySelector('.epl-title')?.text.trim();
          return AnimeEpisode(
            id: _episodeId(href),
            animeId: animeId,
            title: title?.isNotEmpty == true
                ? title!
                : 'Episódio ${_displayNumber(number)}',
            number: number,
            releasedAt: _date(anchor.querySelector('.epl-date')?.text.trim()),
          );
        })
        .where((episode) => episode.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final document = await _getDocument(_episodeUri(episodeId));
    final choices = <AnimePlaybackChoice>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final rowText = _playbackRowText(anchor);
      final lower = '${anchor.text} $rowText'.toLowerCase();
      if (!lower.contains('assistir') && !lower.contains('baixar')) continue;
      final provider = lower.contains('google drive')
          ? 'Google Drive'
          : lower.contains('send')
              ? 'SEND'
              : null;
      if (provider == null) continue;
      final uri = _resolveUri(anchor.attributes['href']);
      if (uri == null) continue;
      final quality = RegExp(r'(\d{3,4}p)', caseSensitive: false)
              .firstMatch(rowText)
              ?.group(1) ??
          'Auto';
      final key = '$provider|$quality|$uri';
      if (!seen.add(key)) continue;
      choices.add(
        AnimePlaybackChoice(
          entryUri: uri,
          provider: provider,
          quality: quality,
        ),
      );
    }
    if (choices.isEmpty) {
      throw StateError(
          'Smart Animes não retornou um servidor para este episódio.');
    }
    throw AnimePlaybackResolutionRequired(choices);
  }

  @override
  Future<AnimePlayback> playbackFromResolvedUri(
    Uri uri, {
    String quality = 'Auto',
    String provider = 'Browser',
  }) async {
    final isSend = provider.toLowerCase() == 'send';
    return AnimePlayback(
      streams: [
        AnimeVideoStream(
          uri: uri,
          protocol: _protocol(uri),
          quality: quality,
          language: 'pt-BR',
          headers: {
            'Referer':
                isSend ? 'https://send.now/' : 'https://drive.google.com/',
            'User-Agent': _userAgent,
          },
        ),
      ],
    );
  }

  String _playbackRowText(Element anchor) {
    Element? current = anchor;
    for (var depth = 0; current != null && depth < 5; depth++) {
      if (current.localName == 'li' ||
          current.localName == 'tr' ||
          current.classes.contains('server')) {
        return current.text.trim();
      }
      current = current.parent;
    }
    return anchor.parent?.parent?.text.trim() ?? anchor.text.trim();
  }

  Future<AnimeCatalogPage> _catalog(Uri uri) async {
    final document = await _getDocument(uri);
    final items = document
        .querySelectorAll('article.bs')
        .map((article) {
          final anchor = article.querySelector('.bsx > a[href], a[href]');
          final href = _resolveUri(anchor?.attributes['href']);
          final image = article.querySelector('.limit img, img');
          final title =
              article.querySelector('.tt h2, .tt')?.text.trim().isNotEmpty ==
                      true
                  ? article.querySelector('.tt h2, .tt')!.text.trim()
                  : image?.attributes['title']?.trim() ?? 'Sem título';
          final subtitle = article
              .querySelectorAll('.bt span, .typez')
              .map((node) => node.text.trim())
              .where((value) => value.isNotEmpty)
              .join(' · ');
          return AnimeCatalogItem(
            id: _animeId(href),
            title: title,
            coverUri: _imageUri(image),
            subtitle: subtitle.isEmpty ? null : subtitle,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    final next = document.querySelector('a.next, a[rel="next"]') ??
        document.querySelectorAll('a[href*="page="]').where((anchor) {
          return anchor.text.toLowerCase().contains('próximo');
        }).firstOrNull;
    final nextUri = _resolveUri(next?.attributes['href']);
    return AnimeCatalogPage(
      items: items,
      nextCursor: nextUri?.queryParameters['page'],
    );
  }

  Future<Document> _getDocument(Uri uri) async {
    await _loadSession();
    final response = await _client.get(uri, headers: requestHeaders);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode == 403 ||
        body.toLowerCase().contains('just a moment') ||
        body.toLowerCase().contains('cf-chl-')) {
      throw const AnimeSourceSessionRequired(
        'Smart Animes precisa concluir a verificação do navegador.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Smart Animes retornou HTTP ${response.statusCode}.',
        uri,
      );
    }
    return html_parser.parse(body);
  }

  Future<void> _loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    _userAgent = prefs.getString(_userAgentKey) ?? _defaultUserAgent;
    final encoded = prefs.getString(_cookiesKey);
    if (encoded == null) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        _cookies = decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      _cookies = const {};
    }
  }

  Uri _animeUri(Map<String, dynamic> params, String? cursor) =>
      _baseUri.resolve('anime/').replace(queryParameters: {
        ...params,
        if (cursor != null) 'page': cursor,
      });

  Uri _animeDetailsUri(String id) => _baseUri.resolve('anime/$id/');

  Uri _episodeUri(String id) => _baseUri.resolve('$id/');

  Uri? _resolveUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _baseUri.resolve(value.trim());
  }

  Uri? _imageUri(Element? image) => _resolveUri(
        image?.attributes['data-src'] ??
            image?.attributes['data-lazy-src'] ??
            image?.attributes['src'],
      );

  static String _animeId(Uri? uri) {
    if (uri == null) return '';
    final segments =
        uri.pathSegments.where((value) => value.isNotEmpty).toList();
    final index = segments.indexOf('anime');
    return index >= 0 && index + 1 < segments.length ? segments[index + 1] : '';
  }

  static String _episodeId(Uri? uri) => uri == null
      ? ''
      : uri.pathSegments.where((value) => value.isNotEmpty).lastOrNull ?? '';

  static Map<String, String> _metadata(Document document) {
    final result = <String, String>{};
    for (final span in document.querySelectorAll('.spe span')) {
      final text = span.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      final separator = text.indexOf(':');
      if (separator > 0) {
        result[text.substring(0, separator).trim()] =
            text.substring(separator + 1).trim();
      }
    }
    return result;
  }

  static Iterable<String> _linkedMetadata(Document document, String label) {
    for (final span in document.querySelectorAll('.spe span')) {
      if (!span.text.trim().toLowerCase().startsWith(label.toLowerCase())) {
        continue;
      }
      return span
          .querySelectorAll('a')
          .map((link) => link.text.trim())
          .where((value) => value.isNotEmpty);
    }
    return const [];
  }

  static AnimeStatus _status(String? value) {
    final status = value?.toLowerCase() ?? '';
    if (status.contains('andamento')) {
      return AnimeStatus.ongoing;
    }
    if (status.contains('conclu') || status.contains('finaliz')) {
      return AnimeStatus.completed;
    }
    if (status.contains('próximo') || status.contains('proximo')) {
      return AnimeStatus.upcoming;
    }
    if (status.contains('hiato')) return AnimeStatus.hiatus;
    return AnimeStatus.unknown;
  }

  static String _sortValue(AnimeSearchSort sort) => switch (sort) {
        AnimeSearchSort.latestUpdated => 'update',
        AnimeSearchSort.latestAdded => 'latest',
        AnimeSearchSort.score => 'rating',
        AnimeSearchSort.name => 'title',
        AnimeSearchSort.nameDescending => 'titlereverse',
        AnimeSearchSort.mostViewed => 'popular',
        AnimeSearchSort.defaultOrder ||
        AnimeSearchSort.releaseDate ||
        AnimeSearchSort.episodeCount =>
          '',
      };

  static VideoProtocol _protocol(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('.m3u8')) return VideoProtocol.hls;
    if (value.contains('.mpd')) return VideoProtocol.dash;
    return VideoProtocol.progressive;
  }

  static DateTime? _date(String? value) {
    if (value == null || value.isEmpty) return null;
    const months = {
      'jan': 1,
      'fev': 2,
      'mar': 3,
      'abr': 4,
      'mai': 5,
      'jun': 6,
      'jul': 7,
      'ago': 8,
      'set': 9,
      'out': 10,
      'nov': 11,
      'dez': 12,
    };
    final match =
        RegExp(r'(\d{1,2})\s+([a-zç]{3})\s+(\d{4})', caseSensitive: false)
            .firstMatch(value.toLowerCase());
    if (match == null) return null;
    final month = months[match.group(2)];
    if (month == null) return null;
    return DateTime(
        int.parse(match.group(3)!), month, int.parse(match.group(1)!));
  }

  static String _displayNumber(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
}
