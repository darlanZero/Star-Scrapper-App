import 'dart:convert';

import 'package:flutter/services.dart';

abstract final class BrowserHtmlLoader {
  static const _channel = MethodChannel('starslibrary/webview_cookies');
  static const _readerPagesChannel =
      EventChannel('starslibrary/reader_pages');
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

  /// Streams the absolute file path of each extracted reader page, in reading
  /// order, as the native driver pulls them out of the blob-based SPA reader.
  ///
  /// Cancelling the subscription tears down the underlying WebView.
  static Stream<String> readerPages(
    Uri uri,
    String userAgent,
    int pageCount,
  ) {
    return _readerPagesChannel
        .receiveBroadcastStream(<String, dynamic>{
          'url': uri.toString(),
          'userAgent': userAgent,
          'pageCount': pageCount,
        })
        .map((event) => event?.toString() ?? '')
        .where((path) => path.isNotEmpty);
  }
}
