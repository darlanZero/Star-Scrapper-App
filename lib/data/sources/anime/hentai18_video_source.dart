import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

class Hentai18VideoSource implements AnimeSource, TaxonomyBrowsableAnimeSource {
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  final http.Client _client;
  final Uri _baseUri;

  Hentai18VideoSource({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse('https://hentai18.net/');

  @override
  String get id => 'hentai18_video';
  @override
  String get name => 'Hentai18 Videos';
  @override
  Uri get baseUri => _baseUri;
  @override
  Map<String, String> get requestHeaders => {
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': _baseUri.toString(),
        'User-Agent': _ua,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.catalog,
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.adult,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.recent,
    String? cursor,
  }) {
    final path = switch (filter) {
      AnimeCatalogFilter.catalog => '/hentai-anime-videos',
      AnimeCatalogFilter.adult => '/hentai-video-tags/uncensored',
      AnimeCatalogFilter.popular => '/hentai-anime-videos?sort=popular',
      _ => '/hentai-videos',
    };
    return _catalog(path, cursor);
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) {
    final value = query.trim();
    if (value.isEmpty) return browse(cursor: cursor);
    return _catalog(
        '/search?type=video&q=${Uri.encodeQueryComponent(value)}', cursor);
  }

  Future<AnimeCatalogPage> _catalog(String route, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final base = _baseUri.resolve(route);
    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      if (page > 1) 'page': '$page',
    });
    final document = await _document(uri);
    final found = <String, AnimeCatalogItem>{};
    for (final root in document.querySelectorAll('.hx-card.hx-vcard')) {
      final anchor = root.querySelector('.hx-card-title a[href]') ??
          root.querySelector('.hx-card-cover[href]');
      final href = anchor?.attributes['href'] ?? '';
      final title = anchor?.attributes['title']?.trim().isNotEmpty == true
          ? anchor!.attributes['title']!.trim()
          : anchor?.text.trim() ?? '';
      if (href.isEmpty || title.isEmpty) continue;
      final itemUri = _baseUri.resolve(href);
      final duration = root.querySelector('.hx-vcard-dur')?.text.trim();
      final meta = root.querySelector('.hx-card-meta')?.text.trim();
      found[itemUri.path] = AnimeCatalogItem(
        id: itemUri.path,
        title: title,
        coverUri: _image(root.querySelector('.hx-card-cover img')),
        subtitle: [duration, meta]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .join(' • '),
      );
    }
    return AnimeCatalogPage(
      items: found.values,
      nextCursor: document.querySelector('a[href*="page=${page + 1}"]') == null
          ? null
          : '${page + 1}',
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final uri = _baseUri.resolve(animeId);
    final document = await _document(uri);
    final title = document
            .querySelector('.hx-player-poster')
            ?.attributes['alt']
            ?.trim() ??
        document.querySelector('.hx-watch-info h1')?.text.trim() ??
        '';
    if (title.isEmpty) throw StateError('Hentai18 did not return $animeId.');
    final taxonomy = <String, AnimeTaxonomyLink>{};
    for (final anchor in document.querySelectorAll(
      '.hx-vabout-genres a, .hx-pills a, .hx-vfacts a',
    )) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final kind = href.startsWith('/hentai-video-series/')
          ? AnimeTaxonomyKind.parody
          : href.startsWith('/hentai-video-brands/')
              ? AnimeTaxonomyKind.artist
              : AnimeTaxonomyKind.tag;
      taxonomy['${kind.name}:$href'] =
          AnimeTaxonomyLink(kind: kind, id: href, name: label);
    }
    final studios = taxonomy.values
        .where((item) => item.kind == AnimeTaxonomyKind.artist)
        .map((item) => item.name);
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: uri.path,
        title: title,
        coverUri: _image(document.querySelector('.hx-player-poster')),
        subtitle: document.querySelector('.hx-epnav-now')?.text.trim(),
      ),
      description:
          document.querySelector('.hx-synopsis-text')?.text.trim() ?? '',
      alternativeTitles: [
        if (document.querySelector('.hx-detail-alt')?.text.trim().isNotEmpty ==
            true)
          document
              .querySelector('.hx-detail-alt')!
              .text
              .replaceFirst('Also known as', '')
              .trim(),
      ],
      genres: taxonomy.values
          .where((item) => item.kind == AnimeTaxonomyKind.tag)
          .map((item) => item.name),
      taxonomyLinks: taxonomy.values,
      status: AnimeStatus.completed,
      studios: studios,
      externalIds: {'hentai18': uri.path},
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final uri = _baseUri.resolve(animeId);
    final document = await _document(uri);
    final episodes = <String, AnimeEpisode>{};
    for (final anchor
        in document.querySelectorAll('.hx-wside-list a.hx-wep[href]')) {
      final href = _baseUri.resolve(anchor.attributes['href'] ?? '').path;
      final title = anchor.attributes['title']?.trim() ??
          anchor.querySelector('.hx-wep-name')?.text.trim() ??
          '';
      if (href.isEmpty || title.isEmpty) continue;
      episodes[href] = AnimeEpisode(
        id: href,
        animeId: animeId,
        title: title,
        number: double.tryParse(
          RegExp(r'Episode\s+(\d+(?:\.\d+)?)', caseSensitive: false)
                  .firstMatch(title)
                  ?.group(1) ??
              '',
        ),
        thumbnailUri: _image(anchor.querySelector('img')),
      );
    }
    if (episodes.isEmpty) {
      final details = await getDetails(animeId);
      episodes[uri.path] = AnimeEpisode(
        id: uri.path,
        animeId: animeId,
        title: details.item.title,
        number: 1,
        thumbnailUri: details.item.coverUri,
      );
    }
    return episodes.values.toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final pageUri = _baseUri.resolve(episodeId);
    final document = await _document(pageUri);
    final iframe = document.querySelector('.hx-player iframe[src]');
    final iframeUri = _baseUri.resolve(iframe?.attributes['src'] ?? '');
    final token =
        iframeUri.pathSegments.isEmpty ? '' : iframeUri.pathSegments.last;
    Uri? stream;
    if (token.isNotEmpty) {
      try {
        final normalized = base64.normalize(token);
        final decoded = utf8.decode(base64.decode(normalized));
        for (final part in decoded.split(';')) {
          final candidate = Uri.tryParse(part.trim());
          if (candidate != null &&
              candidate.hasScheme &&
              (candidate.path.endsWith('.m3u8') ||
                  candidate.path.endsWith('.mp4'))) {
            stream = candidate;
            break;
          }
        }
      } catch (_) {
        // Fall through to inspecting the player document.
      }
    }
    if (stream == null && iframeUri.hasScheme) {
      final player = await _document(iframeUri);
      stream =
          _uri(player.querySelector('video source[src]')?.attributes['src']);
    }
    if (stream == null) {
      throw StateError('Hentai18 did not expose a playable video URL.');
    }
    final hls = stream.path.toLowerCase().endsWith('.m3u8');
    return AnimePlayback(streams: [
      AnimeVideoStream(
        uri: stream,
        protocol: hls ? VideoProtocol.hls : VideoProtocol.progressive,
        quality: 'Auto',
        language: 'ja',
        mimeType: hls ? 'application/vnd.apple.mpegurl' : 'video/mp4',
        headers: {
          'Referer': iframeUri.toString(),
          'Origin': '${iframeUri.scheme}://${iframeUri.host}',
          'User-Agent': _ua,
        },
      ),
    ]);
  }

  @override
  Future<AnimeCatalogPage> browseTaxonomy(
    AnimeTaxonomyKind kind,
    String taxonomyId, {
    String? cursor,
  }) =>
      _catalog(taxonomyId, cursor);

  Future<Document> _document(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Hentai18 returned HTTP ${response.statusCode}.');
    }
    return html_parser.parse(utf8.decode(response.bodyBytes));
  }

  Uri? _image(Element? image) {
    for (final key in const ['data-src', 'src']) {
      final value = image?.attributes[key]?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('data:')) {
        return _baseUri.resolve(value);
      }
    }
    return null;
  }

  Uri? _uri(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : _baseUri.resolve(normalized);
  }
}
