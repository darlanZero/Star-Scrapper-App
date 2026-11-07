import 'dart:convert';

import 'package:flutter/services.dart';

abstract final class BrowserHtmlLoader {
  static const _channel = MethodChannel('starslibrary/webview_cookies');
  static const _readerPagesChannel = EventChannel('starslibrary/reader_pages');
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

  /// Loads a rendered page only after [readySelector] is present.
  static Future<String> loadWhen(
    Uri uri,
    String userAgent,
    String readySelector,
  ) {
    final operation = _pending.then(
      (_) => _loadNow(
        uri,
        userAgent,
        readySelector: readySelector,
        renderedViewport: true,
        sanitizeHtml: true,
      ),
    );
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  /// Loads the complete rendered DOM as soon as [readySelector] is present.
  ///
  /// Unlike [loadWhen], this keeps the original HTML instead of reducing it to
  /// manga cards. It is intended for protected video pages whose media or
  /// metadata lives in source-specific attributes.
  static Future<String> loadRawWhen(
    Uri uri,
    String userAgent,
    String readySelector,
  ) {
    final operation = _pending.then(
      (_) => _loadNow(
        uri,
        userAgent,
        readySelector: readySelector,
      ),
    );
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  /// Loads a JavaScript-rendered page after walking through its lazy content.
  ///
  /// Readers such as Yomu only attach page image URLs when each page slot
  /// approaches the viewport. A regular DOM snapshot therefore contains just
  /// the first few pages. This variant asks the Android WebView driver to visit
  /// every direct reader slot before returning the final HTML.
  static Future<String> loadScrolled(Uri uri, String userAgent) {
    final operation = _pending.then(
      (_) => _loadNow(uri, userAgent, autoScroll: true),
    );
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  /// Loads a rendered page and clicks a matching control before snapshotting.
  ///
  /// This is used for progressive server-rendered lists such as a chapter
  /// panel whose "load more" button is backed by Livewire. [maxClicks] is a
  /// safety bound; processing also stops as soon as the control disappears.
  static Future<String> loadInteracted(
    Uri uri,
    String userAgent,
    String clickSelector, {
    int maxClicks = 1,
  }) {
    final operation = _pending.then(
      (_) => _loadNow(
        uri,
        userAgent,
        clickSelector: clickSelector,
        maxClicks: maxClicks,
      ),
    );
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  static Future<String> _loadNow(
    Uri uri,
    String userAgent, {
    bool autoScroll = false,
    bool renderedViewport = false,
    bool sanitizeHtml = false,
    String? readySelector,
    String? clickSelector,
    int maxClicks = 0,
  }) async {
    final encoded = await _channel.invokeMethod<String>('loadHtml', {
      'url': uri.toString(),
      'userAgent': userAgent,
      'readySelector': readySelector ?? _defaultReadySelector,
      'autoScroll': autoScroll,
      'renderedViewport': renderedViewport,
      'sanitizeHtml': sanitizeHtml,
      if (clickSelector != null && clickSelector.isNotEmpty)
        'clickSelector': clickSelector,
      if (maxClicks > 0) 'maxClicks': maxClicks,
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

  /// Loads protected binary data with Android's network stack and the cookies
  /// already held by the authenticated WebView.
  static Future<({int statusCode, Uint8List body, Map<String, String> headers})>
      loadBytes(
    Uri uri,
    Map<String, String> headers,
  ) {
    return requestBytes(uri, headers);
  }

  /// Performs a same-origin browser request using the authenticated WebView
  /// cookie jar. Non-GET requests also receive the page's CSRF cookie on
  /// Android, matching requests issued by the site's own frontend.
  static Future<({int statusCode, Uint8List body, Map<String, String> headers})>
      requestBytes(
    Uri uri,
    Map<String, String> headers, {
    String method = 'GET',
    String? body,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('loadBytes', {
      'url': uri.toString(),
      'headers': headers,
      'method': method,
      if (body != null) 'body': body,
    });
    if (raw == null) {
      throw StateError('The native client returned no response.');
    }
    final responseHeaders = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        responseHeaders[entry.key.toString().toLowerCase()] =
            entry.value.toString();
      }
    }
    return (
      statusCode: raw['statusCode'] as int? ?? 0,
      body: raw['body'] as Uint8List? ?? Uint8List(0),
      headers: responseHeaders,
    );
  }

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
          'mode': 'blobFiles',
          'url': uri.toString(),
          'userAgent': userAgent,
          'pageCount': pageCount,
        })
        .map((event) => event?.toString() ?? '')
        .where((path) => path.isNotEmpty);
  }

  /// Streams lazy reader image URLs as soon as their slots are materialized.
  ///
  /// Unlike [loadScrolled], this does not wait for the complete DOM snapshot.
  /// The native reader can start rendering the first pages while the offscreen
  /// WebView continues walking the remaining placeholders.
  static Stream<String> lazyReaderUrls(Uri uri, String userAgent) {
    return _readerPagesChannel
        .receiveBroadcastStream(<String, dynamic>{
          'mode': 'lazyUrls',
          'url': uri.toString(),
          'userAgent': userAgent,
        })
        .map((event) => event?.toString() ?? '')
        .where((url) => url.isNotEmpty);
  }
}
