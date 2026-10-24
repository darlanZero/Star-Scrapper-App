import 'dart:convert';

import 'package:flutter/services.dart';

abstract final class BrowserHtmlLoader {
  static const _channel = MethodChannel('starslibrary/webview_cookies');
  static Future<void> _pending = Future.value();

  static Future<String> load(Uri uri, String userAgent) {
    final operation = _pending.then((_) => _loadNow(uri, userAgent));
    _pending = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  static Future<String> _loadNow(Uri uri, String userAgent) async {
    final encoded = await _channel.invokeMethod<String>('loadHtml', {
      'url': uri.toString(),
      'userAgent': userAgent,
      'readySelector':
          'article.bs, .bsx, .postbody, .listupd, .bixbox, .filter, main',
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
}
