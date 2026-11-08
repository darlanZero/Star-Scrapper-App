import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Loopback-only proxy for HLS providers that disguise playlists and media
/// fragments with image extensions.
///
/// FFmpeg rejects those fragments before probing their contents. This proxy
/// keeps the upstream bytes untouched and exposes local URLs with extensions
/// accepted by the native HLS demuxer.
class HlsExtensionProxy {
  final Map<String, String> _headers;
  final HttpClient _client = HttpClient();
  final Map<int, _ProxyEntry> _entries = {};
  final Map<String, int> _entryIds = {};
  late final HttpServer _server;
  late final Uri entryUri;
  int _nextId = 0;
  bool _closed = false;

  HlsExtensionProxy._(this._headers);

  static Future<HlsExtensionProxy> start({
    required Uri manifestUri,
    Map<String, String> headers = const {},
  }) async {
    final proxy = HlsExtensionProxy._(Map.unmodifiable(headers));
    proxy._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy.entryUri = proxy._register(manifestUri, _ProxyKind.playlist);
    unawaited(proxy._serve());
    return proxy;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final fileName = request.uri.pathSegments.firstOrNull ?? '';
      final id = int.tryParse(fileName.split('.').first);
      final entry = id == null ? null : _entries[id];
      if (request.method != 'GET' || entry == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final upstreamRequest = await _client.getUrl(entry.uri);
      _headers.forEach(upstreamRequest.headers.set);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upstream = await upstreamRequest.close();
      request.response.statusCode = upstream.statusCode;
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-store',
      );

      if (entry.kind == _ProxyKind.playlist &&
          upstream.statusCode >= 200 &&
          upstream.statusCode < 300) {
        final bytes = await _readBytes(upstream);
        final text = utf8.decode(bytes, allowMalformed: true);
        final rewritten = _rewritePlaylist(text, entry.uri);
        final output = utf8.encode(rewritten);
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.contentLength = output.length;
        request.response.add(output);
      } else {
        _copyHeader(
          upstream.headers,
          request.response.headers,
          HttpHeaders.contentTypeHeader,
        );
        _copyHeader(
          upstream.headers,
          request.response.headers,
          HttpHeaders.contentRangeHeader,
        );
        _copyHeader(
          upstream.headers,
          request.response.headers,
          HttpHeaders.acceptRangesHeader,
        );
        final contentLength = upstream.contentLength;
        if (contentLength >= 0) {
          request.response.contentLength = contentLength;
        }
        await request.response.addStream(upstream);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  String _rewritePlaylist(String text, Uri baseUri) {
    final lines = const LineSplitter().convert(text);
    final output = <String>[];
    var nextLineIsPlaylist = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        output.add(line);
        continue;
      }
      if (!trimmed.startsWith('#')) {
        final kind =
            nextLineIsPlaylist ? _ProxyKind.playlist : _ProxyKind.segment;
        output.add(_register(baseUri.resolve(trimmed), kind).toString());
        nextLineIsPlaylist = false;
        continue;
      }

      final upper = trimmed.toUpperCase();
      nextLineIsPlaylist = upper.startsWith('#EXT-X-STREAM-INF:');
      final uriKind = upper.startsWith('#EXT-X-MEDIA:') ||
              upper.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
              upper.startsWith('#EXT-X-IMAGE-STREAM-INF:') ||
              upper.startsWith('#EXT-X-RENDITION-REPORT:')
          ? _ProxyKind.playlist
          : _ProxyKind.binary;
      output.add(line.replaceAllMapped(
        RegExp(r'URI="([^"]+)"', caseSensitive: false),
        (match) {
          final uri = baseUri.resolve(match.group(1)!);
          return 'URI="${_register(uri, uriKind)}"';
        },
      ));
    }
    return '${output.join('\n')}\n';
  }

  Uri _register(Uri uri, _ProxyKind kind) {
    final key = '${kind.name}:$uri';
    final existing = _entryIds[key];
    final id = existing ?? ++_nextId;
    if (existing == null) {
      _entryIds[key] = id;
      _entries[id] = _ProxyEntry(uri, kind);
    }
    final extension = switch (kind) {
      _ProxyKind.playlist => 'm3u8',
      _ProxyKind.segment => 'm4s',
      _ProxyKind.binary => 'bin',
    };
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server.port,
      path: '/$id.$extension',
    );
  }

  static Future<Uint8List> _readBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static void _copyHeader(
    HttpHeaders source,
    HttpHeaders target,
    String name,
  ) {
    final value = source.value(name);
    if (value != null) target.set(name, value);
  }
}

enum _ProxyKind { playlist, segment, binary }

class _ProxyEntry {
  final Uri uri;
  final _ProxyKind kind;

  const _ProxyEntry(this.uri, this.kind);
}
