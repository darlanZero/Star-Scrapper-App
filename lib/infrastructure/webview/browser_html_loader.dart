import 'dart:convert';

import 'package:flutter/services.dart';

abstract final class BrowserHtmlLoader {
  static const _channel = MethodChannel('starslibrary/webview_cookies');
  static Future<void> _pending = Future.value();
  static final Map<String, Future<Uint8List>> _imageCache = {};
  static const _defaultReadySelector =
      'article.bs, .bsx, .boxAN, .cardAN, .boxEP, .list-item, '
      '.streamer-content, .postbody, .listupd, .bixbox, .filter, main, pre';

  static Future<String> load(Uri uri, String userAgent) {
    final operation = _pending.then(
      (_) => _loadNow(uri, userAgent),
    );
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  static Future<String> _loadNow(
    Uri uri,
    String userAgent,
  ) async {
    final encoded = await _channel.invokeMethod<String>('loadHtml', {
      'url': uri.toString(),
      'userAgent': userAgent,
      'readySelector': _defaultReadySelector,
    });
    if (encoded == null || encoded.isEmpty) {
      throw StateError('The browser returned an empty page.');
    }
    try {
      final decoded = jsonDecode(encoded);
      return decoded is String ? decoded : encoded;
    } catch (_) {
      return encoded;
    }
  }

  static Future<Uint8List> loadImage(Uri uri, String userAgent) =>
      _imageCache.putIfAbsent(uri.toString(), () {
        final operation = _pending.then(
          (_) => _channel.invokeMethod<Uint8List>('loadImage', {
            'url': uri.toString(),
            'userAgent': userAgent,
          }),
        );
        _pending = operation.then<void>((_) {}, onError: (_) {});
        return operation.then((bytes) {
          if (bytes == null || bytes.isEmpty) {
            _imageCache.remove(uri.toString());
            throw StateError('The browser returned an empty image.');
          }
          return bytes;
        }, onError: (Object error, StackTrace stackTrace) {
          _imageCache.remove(uri.toString());
          Error.throwWithStackTrace(error, stackTrace);
        });
      });

  /// Drives a blob-based SPA reader inside the native WebView and returns the
  /// absolute paths of the extracted page images, in reading order.
  static Future<List<String>> loadReaderPages(
    Uri uri,
    String userAgent,
    int pageCount,
  ) {
    final operation = _pending.then(
      (_) => _channel.invokeMethod<List<dynamic>>('loadReaderPages', {
        'url': uri.toString(),
        'userAgent': userAgent,
        'pageCount': pageCount,
      }),
    );
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation.then((pages) {
      final paths = (pages ?? const [])
          .map((path) => path.toString())
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (paths.isEmpty) {
        throw StateError('The browser returned no reader pages.');
      }
      return paths;
    });
  }
}
