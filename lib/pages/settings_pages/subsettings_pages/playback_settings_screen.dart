import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/playback/playback_preferences.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/pages/anime_player_screen.dart';

class PlaybackSettingsScreen extends StatelessWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PlaybackPreferences>();
    return Scaffold(
      appBar: AppBar(title: const Text('Video playback')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          Text(
            'Decoder',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<VideoDecoderMode>(
              groupValue: preferences.decoderMode,
              onChanged: (value) {
                if (value != null) preferences.setDecoderMode(value);
              },
              child: const Column(
                children: [
                  RadioListTile<VideoDecoderMode>(
                    value: VideoDecoderMode.automatic,
                    title: Text('Automatic'),
                    subtitle: Text(
                      'Prefer hardware decoding and fall back when necessary.',
                    ),
                  ),
                  RadioListTile<VideoDecoderMode>(
                    value: VideoDecoderMode.hardware,
                    title: Text('Hardware'),
                    subtitle: Text(
                      'Use the device video decoder for lower battery usage.',
                    ),
                  ),
                  RadioListTile<VideoDecoderMode>(
                    value: VideoDecoderMode.software,
                    title: Text('Software compatibility'),
                    subtitle: Text(
                      'Use the CPU when a device codec produces visual errors.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Gestures', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: preferences.gesturesEnabled,
                  onChanged: preferences.setGesturesEnabled,
                  secondary: const Icon(Icons.touch_app_rounded),
                  title: const Text('Player gestures'),
                  subtitle: const Text(
                    'Double tap to seek; swipe left for volume and right for brightness.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.fast_forward_rounded),
                  title: const Text('Double-tap seek'),
                  subtitle: Text('${preferences.doubleTapSeconds} seconds'),
                  trailing: DropdownButton<int>(
                    value: preferences.doubleTapSeconds,
                    items: const [5, 10, 15, 20, 30]
                        .map(
                          (seconds) => DropdownMenuItem(
                            value: seconds,
                            child: Text('$seconds s'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        preferences.setDoubleTapSeconds(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Episodes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: preferences.autoSkipIntro,
                  onChanged: preferences.setAutoSkipIntro,
                  secondary: const Icon(Icons.skip_next_rounded),
                  title: const Text('Automatically skip intros'),
                  subtitle: const Text(
                    'Only applies when the source supplies a verified intro range.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Subtitles', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.subtitles_rounded),
                  title: const Text('Preferred subtitle language'),
                  subtitle: const Text(
                    'Use “auto” or a language code such as en, pt-BR or ja.',
                  ),
                  trailing: SizedBox(
                    width: 86,
                    child: TextFormField(
                      initialValue: preferences.subtitleLanguage,
                      textAlign: TextAlign.center,
                      onFieldSubmitted: preferences.setSubtitleLanguage,
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: const Text('Subtitle font'),
                  subtitle: const Text(
                    'Noto Sans includes Portuguese and other extended characters.',
                  ),
                  trailing: DropdownButton<SubtitleTypeface>(
                    value: preferences.subtitleTypeface,
                    items: SubtitleTypeface.values
                        .map(
                          (typeface) => DropdownMenuItem(
                            value: typeface,
                            child: Text(typeface.label),
                          ),
                        )
                        .toList(),
                    onChanged: (typeface) {
                      if (typeface != null) {
                        preferences.setSubtitleTypeface(typeface);
                      }
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.format_size_rounded),
                  title: Text(
                    'Subtitle size · ${preferences.subtitleFontSize.round()} px',
                  ),
                  subtitle: Slider(
                    min: 16,
                    max: 48,
                    divisions: 16,
                    value: preferences.subtitleFontSize,
                    label: '${preferences.subtitleFontSize.round()} px',
                    onChanged: preferences.setSubtitleFontSize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Hardware decoding is recommended. Software mode may use considerably more battery and make the device warmer.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openDiagnostics(context),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Test video player'),
          ),
        ],
      ),
    );
  }

  void _openDiagnostics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimePlayerScreen(
          title: 'StarsLibrary player diagnostics',
          episodeTitle: 'Public sample video',
          playback: AnimePlayback(
            streams: [
              AnimeVideoStream(
                uri: Uri.parse(
                  'https://media.w3.org/2010/05/sintel/trailer.mp4',
                ),
                protocol: VideoProtocol.progressive,
                quality: 'Sintel trailer sample',
                language: 'en',
                codec: 'H.264',
                mimeType: 'video/mp4',
              ),
            ],
            subtitles: [
              AnimeSubtitleTrack(
                uri: Uri.parse(
                  'https://raw.githubusercontent.com/andreyvit/subtitle-tools/master/sample.srt',
                ),
                label: 'English SRT sample',
                language: 'en',
                format: 'SRT',
                isDefault: true,
              ),
            ],
            skipSegments: [
              AnimeSkipSegment(
                start: const Duration(seconds: 5),
                end: const Duration(seconds: 15),
                label: 'Skip test intro',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
