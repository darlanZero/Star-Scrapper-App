import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VideoDecoderMode { automatic, hardware, software }

enum SubtitleTypeface { system, notoSans }

extension SubtitleTypefaceDetails on SubtitleTypeface {
  String get label => switch (this) {
        SubtitleTypeface.system => 'System',
        SubtitleTypeface.notoSans => 'Noto Sans',
      };

  String? get fontFamily => switch (this) {
        SubtitleTypeface.system => null,
        SubtitleTypeface.notoSans => 'StarsNotoSans',
      };
}

class PlaybackPreferences extends ChangeNotifier {
  static const _decoderKey = 'playback_decoder_mode';
  static const _gesturesKey = 'playback_gestures_enabled';
  static const _seekSecondsKey = 'playback_double_tap_seconds';
  static const _autoSkipIntroKey = 'playback_auto_skip_intro';
  static const _subtitleLanguageKey = 'playback_subtitle_language';
  static const _subtitleFontSizeKey = 'playback_subtitle_font_size';
  static const _subtitleTypefaceKey = 'playback_subtitle_typeface';

  VideoDecoderMode _decoderMode = VideoDecoderMode.automatic;
  bool _gesturesEnabled = true;
  int _doubleTapSeconds = 10;
  bool _autoSkipIntro = false;
  String _subtitleLanguage = 'auto';
  double _subtitleFontSize = 28;
  SubtitleTypeface _subtitleTypeface = SubtitleTypeface.notoSans;
  bool _initialized = false;

  VideoDecoderMode get decoderMode => _decoderMode;
  bool get gesturesEnabled => _gesturesEnabled;
  int get doubleTapSeconds => _doubleTapSeconds;
  bool get autoSkipIntro => _autoSkipIntro;
  String get subtitleLanguage => _subtitleLanguage;
  double get subtitleFontSize => _subtitleFontSize;
  SubtitleTypeface get subtitleTypeface => _subtitleTypeface;
  bool get initialized => _initialized;

  bool get useHardwareAcceleration => _decoderMode != VideoDecoderMode.software;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _decoderMode = VideoDecoderMode.values.firstWhere(
      (mode) => mode.name == prefs.getString(_decoderKey),
      orElse: () => VideoDecoderMode.automatic,
    );
    _gesturesEnabled = prefs.getBool(_gesturesKey) ?? true;
    _doubleTapSeconds = (prefs.getInt(_seekSecondsKey) ?? 10).clamp(5, 30);
    _autoSkipIntro = prefs.getBool(_autoSkipIntroKey) ?? false;
    _subtitleLanguage = prefs.getString(_subtitleLanguageKey) ?? 'auto';
    _subtitleFontSize =
        (prefs.getDouble(_subtitleFontSizeKey) ?? 28).clamp(16, 48);
    _subtitleTypeface = SubtitleTypeface.values.firstWhere(
      (typeface) => typeface.name == prefs.getString(_subtitleTypefaceKey),
      orElse: () => SubtitleTypeface.notoSans,
    );
    _initialized = true;
    notifyListeners();
  }

  Future<void> setDecoderMode(VideoDecoderMode mode) async {
    _decoderMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decoderKey, mode.name);
    notifyListeners();
  }

  Future<void> setGesturesEnabled(bool enabled) async {
    _gesturesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gesturesKey, enabled);
    notifyListeners();
  }

  Future<void> setDoubleTapSeconds(int seconds) async {
    _doubleTapSeconds = seconds.clamp(5, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seekSecondsKey, _doubleTapSeconds);
    notifyListeners();
  }

  Future<void> setAutoSkipIntro(bool enabled) async {
    _autoSkipIntro = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSkipIntroKey, enabled);
    notifyListeners();
  }

  Future<void> setSubtitleLanguage(String language) async {
    _subtitleLanguage = language.trim().isEmpty ? 'auto' : language.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleLanguageKey, _subtitleLanguage);
    notifyListeners();
  }

  Future<void> setSubtitleFontSize(double size) async {
    _subtitleFontSize = size.clamp(16, 48);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleFontSizeKey, _subtitleFontSize);
    notifyListeners();
  }

  Future<void> setSubtitleTypeface(SubtitleTypeface typeface) async {
    _subtitleTypeface = typeface;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleTypefaceKey, typeface.name);
    notifyListeners();
  }
}
