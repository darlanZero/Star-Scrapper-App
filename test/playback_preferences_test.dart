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

    final restored = PlaybackPreferences();
    await restored.initialize();
    expect(restored.decoderMode, VideoDecoderMode.software);
    expect(restored.useHardwareAcceleration, isFalse);
    expect(restored.gesturesEnabled, isFalse);
    expect(restored.doubleTapSeconds, 15);
    expect(restored.autoSkipIntro, isTrue);
    expect(restored.subtitleLanguage, 'pt-BR');
  });

  test('double-tap seek interval is constrained to a safe range', () async {
    final preferences = PlaybackPreferences();
    await preferences.initialize();

    await preferences.setDoubleTapSeconds(120);
    expect(preferences.doubleTapSeconds, 30);

    await preferences.setDoubleTapSeconds(1);
    expect(preferences.doubleTapSeconds, 5);
  });
}
