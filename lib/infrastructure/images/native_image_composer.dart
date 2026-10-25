import 'package:flutter/services.dart';

/// Joins the vertical image slices used by protected manga readers.
///
/// Android performs the decode so formats supported by the platform (including
/// AVIF on recent devices) work without duplicating an image codec in Dart.
abstract final class NativeImageComposer {
  static const _channel = MethodChannel('starslibrary/webview_cookies');

  static Future<void> composeVertical(
    List<Uint8List> slices,
    String outputPath,
  ) async {
    if (slices.isEmpty) {
      throw const FormatException(
          'The page archive contained no image slices.');
    }
    await _channel.invokeMethod<void>('composeReaderImage', {
      'slices': slices,
      'outputPath': outputPath,
    });
  }
}
