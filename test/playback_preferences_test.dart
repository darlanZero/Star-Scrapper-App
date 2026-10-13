import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/playback/playback_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('playback preferences have safe hardware-first defaults', () async {
    final preferences = PlaybackPreferences();

    await preferences.initialize();

    expect(preferences.decoderMode, VideoDecoderMode.automatic);
    expect(preferences.useHardwareAcceleration, isTrue);
    expect(preferences.gesturesEnabled, isTrue);
    expect(preferences.doubleTapSeconds, 10);
    expect(preferences.autoSkipIntro, isFalse);
    expect(preferences.subtitleLanguage, 'auto');
    expect(preferences.subtitleFontSize, 28);
    expect(preferences.subtitleTypeface, SubtitleTypeface.notoSans);
  });

  test('playback preferences persist compatibility and gesture settings',
      () async {
    final preferences = PlaybackPreferences();
    await preferences.initialize();

    await preferences.setDecoderMode(VideoDecoderMode.software);
    await preferences.setGesturesEnabled(false);
    await preferences.setDoubleTapSeconds(15);
    await preferences.setAutoSkipIntro(true);
    await preferences.setSubtitleLanguage('pt-BR');
    await preferences.setSubtitleFontSize(34);
    await preferences.setSubtitleTypeface(SubtitleTypeface.system);

    final restored = PlaybackPreferences();
    await restored.initialize();
    expect(restored.decoderMode, VideoDecoderMode.software);
    expect(restored.useHardwareAcceleration, isFalse);
    expect(restored.gesturesEnabled, isFalse);
    expect(restored.doubleTapSeconds, 15);
    expect(restored.autoSkipIntro, isTrue);
    expect(restored.subtitleLanguage, 'pt-BR');
    expect(restored.subtitleFontSize, 34);
    expect(restored.subtitleTypeface, SubtitleTypeface.system);
  });

  test('double-tap seek interval is constrained to a safe range', () async {
    final preferences = PlaybackPreferences();
    await preferences.initialize();

    await preferences.setDoubleTapSeconds(120);
    expect(preferences.doubleTapSeconds, 30);

    await preferences.setDoubleTapSeconds(1);
    expect(preferences.doubleTapSeconds, 5);
  });

  test('subtitle size is constrained to a readable range', () async {
    final preferences = PlaybackPreferences();
    await preferences.initialize();

    await preferences.setSubtitleFontSize(72);
    expect(preferences.subtitleFontSize, 48);

    await preferences.setSubtitleFontSize(8);
    expect(preferences.subtitleFontSize, 16);
  });
}
