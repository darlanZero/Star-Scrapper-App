import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/playback/playback_preferences.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';
import 'package:star_scrapper_app/pages/anime_player_screen.dart';

class PlaybackSettingsScreen extends StatelessWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preferences = context.watch<PlaybackPreferences>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generalPlaybackTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          Text(
            l10n.decoderTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<VideoDecoderMode>(
              groupValue: preferences.decoderMode,
              onChanged: (value) {
                if (value != null) preferences.setDecoderMode(value);
              },
              child: Column(
                children: [
                  RadioListTile<VideoDecoderMode>(
                    value: VideoDecoderMode.automatic,
                    title: Text(l10n.decoderAutoTitle),
                    subtitle: Text(l10n.decoderAutoDesc),
                  ),
                  RadioListTile<VideoDecoderMode>(
                    value: VideoDecoderMode.hardware,
                    title: Text(l10n.decoderHardwareTitle),
                    subtitle: Text(l10n.decoderHardwareDesc),
                  ),
                  RadioListTile<VideoDecoderMode>(
                    value: VideoDecoderMode.software,
                    title: Text(l10n.decoderSoftwareTitle),
                    subtitle: Text(l10n.decoderSoftwareDesc),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.gesturesTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: preferences.gesturesEnabled,
                  onChanged: preferences.setGesturesEnabled,
                  secondary: const Icon(Icons.touch_app_rounded),
                  title: Text(l10n.playerGesturesTitle),
                  subtitle: Text(l10n.playerGesturesDesc),
                ),
                ListTile(
                  leading: const Icon(Icons.fast_forward_rounded),
                  title: Text(l10n.doubleTapSeekTitle),
                  subtitle: Text(l10n.secondsCount(preferences.doubleTapSeconds)),
                  trailing: DropdownButton<int>(
                    value: preferences.doubleTapSeconds,
                    items: const [5, 10, 15, 20, 30]
                        .map(
                          (seconds) => DropdownMenuItem(
                            value: seconds,
                            child: Text(l10n.secondsShort(seconds)),
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
          Text(l10n.episodesTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: preferences.autoSkipIntro,
                  onChanged: preferences.setAutoSkipIntro,
                  secondary: const Icon(Icons.skip_next_rounded),
                  title: Text(l10n.autoSkipIntroTitle),
                  subtitle: Text(l10n.autoSkipIntroDesc),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.subtitlesTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.subtitles_rounded),
                  title: Text(l10n.preferredSubtitleLanguageTitle),
                  subtitle: Text(l10n.preferredSubtitleLanguageDesc),
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
                  title: Text(l10n.subtitleFontTitle),
                  subtitle: Text(l10n.subtitleFontDesc),
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
                    l10n.subtitleSizeLabel(preferences.subtitleFontSize.round()),
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
                l10n.playbackHardwareWarning,
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
            label: Text(l10n.testVideoPlayer),
          ),
        ],
      ),
    );
  }

  void _openDiagnostics(BuildContext context) {
    final l10n = context.l10n;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimePlayerScreen(
          title: l10n.playerDiagnosticsTitle,
          episodeTitle: l10n.publicSampleVideo,
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
