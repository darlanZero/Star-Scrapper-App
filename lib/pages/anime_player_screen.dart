import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:star_scrapper_app/application/playback/playback_preferences.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:volume_controller/volume_controller.dart';

class AnimePlayerScreen extends StatefulWidget {
  final AnimePlayback playback;
  final String title;
  final String? episodeTitle;

  const AnimePlayerScreen({
    super.key,
    required this.playback,
    required this.title,
    this.episodeTitle,
  });

  @override
  State<AnimePlayerScreen> createState() => _AnimePlayerScreenState();
}

enum _VerticalGestureMode { volume, brightness }

class _AnimePlayerScreenState extends State<AnimePlayerScreen> {
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<AnimeSkipSegment> _automaticallySkipped = {};
  Timer? _controlsTimer;
  Timer? _gestureTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _controlsVisible = true;
  int _streamIndex = 0;
  Tracks _tracks = const Tracks();
  Track _selectedTracks = const Track();
  String? _error;
  double? _doubleTapX;
  _VerticalGestureMode? _verticalMode;
  double _gestureStartValue = 0.5;
  double _gestureValue = 0.5;
  IconData? _gestureIcon;
  String? _gestureLabel;

  PlaybackPreferences get _preferences => context.read<PlaybackPreferences>();

  @override
  void initState() {
    super.initState();
    VolumeController.instance.showSystemUI = false;
    _enterPlayerMode();
    _createPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCurrentStream());
  }

  void _createPlayer() {
    final decoder = _preferences.decoderMode;
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'StarsLibrary',
        // Flutter-rendered subtitles are reliable on Android without bundling
        // a separate libass font asset.
        libass: false,
      ),
    );
    final videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: decoder != VideoDecoderMode.software,
        hwdec: switch (decoder) {
          VideoDecoderMode.automatic => null,
          VideoDecoderMode.hardware => 'auto-safe',
          VideoDecoderMode.software => 'no',
        },
      ),
    );
    _player = player;
    _videoController = videoController;
    _subscriptions.addAll([
      player.stream.position.listen(_onPosition),
      player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      }),
      player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      }),
      player.stream.buffering.listen((value) {
        if (mounted) setState(() => _buffering = value);
      }),
      player.stream.tracks.listen((value) {
        if (mounted) setState(() => _tracks = value);
      }),
      player.stream.track.listen((value) {
        if (mounted) setState(() => _selectedTracks = value);
      }),
      player.stream.error.listen((value) {
        if (mounted) setState(() => _error = value);
      }),
    ]);
  }

  Future<void> _openCurrentStream({
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    final stream = widget.playback.streams[_streamIndex];
    setState(() {
      _buffering = true;
      _error = null;
    });
    try {
      await _player!.open(
        Media(
          stream.uri.toString(),
          httpHeaders: stream.headers.isEmpty ? null : stream.headers,
          start: start == Duration.zero ? null : start,
        ),
        play: play,
      );
      await _selectPreferredSubtitle();
      _restartControlsTimer();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _selectPreferredSubtitle() async {
    if (widget.playback.subtitles.isEmpty) return;
    final preferred = _preferences.subtitleLanguage.toLowerCase();
    AnimeSubtitleTrack? track;
    if (preferred != 'off') {
      track = widget.playback.subtitles.cast<AnimeSubtitleTrack?>().firstWhere(
            (candidate) => candidate!.isDefault,
            orElse: () => null,
          );
      if (preferred != 'auto') {
        track =
            widget.playback.subtitles.cast<AnimeSubtitleTrack?>().firstWhere(
                  (candidate) => candidate!.language.toLowerCase() == preferred,
                  orElse: () => track,
                );
      }
      track ??= widget.playback.subtitles.first;
    }
    if (track == null) {
      await _player?.setSubtitleTrack(SubtitleTrack.no());
    } else {
      await _selectExternalSubtitle(track);
    }
  }

  Future<void> _selectExternalSubtitle(AnimeSubtitleTrack track) async {
    SubtitleTrack mediaTrack;
    if (track.uri.scheme == 'http' || track.uri.scheme == 'https') {
      final response = await http.get(track.uri, headers: track.headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Subtitle request failed (${response.statusCode}).',
        );
      }
      mediaTrack = SubtitleTrack.data(
        response.body,
        title: track.label,
        language: track.language,
      );
    } else {
      mediaTrack = SubtitleTrack.uri(
        track.uri.toString(),
        title: track.label,
        language: track.language,
      );
    }
    await _player?.setSubtitleTrack(mediaTrack);
  }

  void _onPosition(Duration value) {
    if (!mounted) return;
    setState(() => _position = value);
    if (!_preferences.autoSkipIntro) return;
    final segment = _activeSkipSegment;
    if (segment != null && _automaticallySkipped.add(segment)) {
      _player?.seek(segment.end);
      _showGestureFeedback(Icons.skip_next_rounded, segment.displayLabel);
    }
  }

  AnimeSkipSegment? get _activeSkipSegment {
    for (final segment in widget.playback.skipSegments) {
      if (segment.contains(_position)) return segment;
    }
    return null;
  }

  Future<void> _changeStream(int index) async {
    if (index == _streamIndex) return;
    final position = _position;
    final playing = _playing;
    setState(() => _streamIndex = index);
    await _openCurrentStream(start: position, play: playing);
  }

  Future<void> _changeDecoder(VideoDecoderMode mode) async {
    if (mode == _preferences.decoderMode) return;
    await _preferences.setDecoderMode(mode);
    final position = _position;
    final playing = _playing;
    await _disposePlayer();
    if (!mounted) return;
    setState(_createPlayer);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openCurrentStream(start: position, play: playing),
    );
  }

  Future<void> _seekRelative(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final bounded = target < Duration.zero
        ? Duration.zero
        : target > _duration && _duration > Duration.zero
            ? _duration
            : target;
    await _player?.seek(bounded);
    _showGestureFeedback(
      seconds < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded,
      '${seconds > 0 ? '+' : ''}$seconds seconds',
    );
  }

  void _handleDoubleTap(double width) {
    if (!_preferences.gesturesEnabled || _doubleTapX == null) return;
    final seconds = _preferences.doubleTapSeconds;
    _seekRelative(_doubleTapX! < width / 2 ? -seconds : seconds);
  }

  Future<void> _beginVerticalGesture(
    DragStartDetails details,
    double width,
  ) async {
    if (!_preferences.gesturesEnabled) return;
    _verticalMode = details.localPosition.dx < width / 2
        ? _VerticalGestureMode.volume
        : _VerticalGestureMode.brightness;
    try {
      _gestureStartValue = _verticalMode == _VerticalGestureMode.volume
          ? await VolumeController.instance.getVolume()
          : await ScreenBrightness.instance.application;
    } catch (_) {
      _gestureStartValue = 0.5;
    }
    _gestureValue = _gestureStartValue;
  }

  void _updateVerticalGesture(DragUpdateDetails details, double height) {
    if (!_preferences.gesturesEnabled || _verticalMode == null) return;
    final delta = -details.delta.dy / height;
    _gestureValue = (_gestureValue + delta * 1.8).clamp(0.0, 1.0);
    if (_verticalMode == _VerticalGestureMode.volume) {
      unawaited(VolumeController.instance.setVolume(_gestureValue));
      _showGestureFeedback(
        _gestureValue == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        'Volume ${(_gestureValue * 100).round()}%',
      );
    } else {
      unawaited(
        ScreenBrightness.instance.setApplicationScreenBrightness(_gestureValue),
      );
      _showGestureFeedback(
        Icons.brightness_6_rounded,
        'Brightness ${(_gestureValue * 100).round()}%',
      );
    }
  }

  void _endVerticalGesture(DragEndDetails _) => _verticalMode = null;

  void _showGestureFeedback(IconData icon, String label) {
    _gestureTimer?.cancel();
    if (mounted) {
      setState(() {
        _gestureIcon = icon;
        _gestureLabel = label;
      });
    }
    _gestureTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          _gestureIcon = null;
          _gestureLabel = null;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _restartControlsTimer();
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    if (!_playing) return;
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return PopScope(
      onPopInvokedWithResult: (_, __) => _leavePlayerMode(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (details) =>
                  _doubleTapX = details.localPosition.dx,
              onDoubleTap: () => _handleDoubleTap(constraints.maxWidth),
              onVerticalDragStart: (details) =>
                  _beginVerticalGesture(details, constraints.maxWidth),
              onVerticalDragUpdate: (details) =>
                  _updateVerticalGesture(details, constraints.maxHeight),
              onVerticalDragEnd: _endVerticalGesture,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null)
                    Video(
                      controller: controller,
                      controls: NoVideoControls,
                      fit: BoxFit.contain,
                      subtitleViewConfiguration:
                          const SubtitleViewConfiguration(
                        style: TextStyle(
                          height: 1.3,
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(blurRadius: 3, color: Colors.black),
                            Shadow(blurRadius: 6, color: Colors.black),
                          ],
                        ),
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 74),
                      ),
                    ),
                  if (_buffering)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null) _PlayerError(error: _error!),
                  _controlsOverlay(),
                  if (_activeSkipSegment case final segment?)
                    Positioned(
                      right: 24,
                      bottom: 104,
                      child: FilledButton.icon(
                        onPressed: () => _player?.seek(segment.end),
                        icon: const Icon(Icons.skip_next_rounded),
                        label: Text(segment.displayLabel),
                      ),
                    ),
                  if (_gestureIcon != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_gestureIcon, color: Colors.white, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              _gestureLabel ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _controlsOverlay() {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.78),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.82),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.maybePop(context),
                        color: Colors.white,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (widget.episodeTitle != null)
                              Text(
                                widget.episodeTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Playback settings',
                        onPressed: _showPlaybackMenu,
                        color: Colors.white,
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  iconSize: 38,
                  onPressed: () {
                    _player?.playOrPause();
                    _restartControlsTimer();
                  },
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: const TextStyle(color: Colors.white),
                          ),
                          Expanded(
                            child: Slider(
                              value: _duration.inMilliseconds <= 0
                                  ? 0
                                  : _position.inMilliseconds
                                      .clamp(0, _duration.inMilliseconds)
                                      .toDouble(),
                              max: _duration.inMilliseconds <= 0
                                  ? 1
                                  : _duration.inMilliseconds.toDouble(),
                              onChanged: (value) => _player
                                  ?.seek(Duration(milliseconds: value.round())),
                            ),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back ${_preferences.doubleTapSeconds}s',
                            onPressed: () => _seekRelative(
                              -_preferences.doubleTapSeconds,
                            ),
                            color: Colors.white,
                            icon: const Icon(Icons.replay_10_rounded),
                          ),
                          IconButton(
                            tooltip:
                                'Forward ${_preferences.doubleTapSeconds}s',
                            onPressed: () =>
                                _seekRelative(_preferences.doubleTapSeconds),
                            color: Colors.white,
                            icon: const Icon(Icons.forward_10_rounded),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showSubtitleMenu,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.subtitles_rounded),
                            label: Text(
                              _selectedTracks.subtitle.title ?? 'Subtitles',
                            ),
                          ),
                          if (widget.playback.streams.length > 1)
                            TextButton.icon(
                              onPressed: _showQualityMenu,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.hd_rounded),
                              label: Text(
                                widget.playback.streams[_streamIndex].quality,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSubtitleMenu() async {
    _controlsTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17151D),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Subtitles'),
              subtitle: Text('Embedded and source-provided tracks'),
            ),
            ListTile(
              leading: const Icon(Icons.subtitles_off_rounded),
              title: const Text('Off'),
              onTap: () {
                _player?.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(context);
              },
            ),
            for (final track in _tracks.subtitle.where(
              (track) => track.id != 'auto' && track.id != 'no',
            ))
              ListTile(
                leading: const Icon(Icons.closed_caption_rounded),
                title: Text(track.title ?? track.language ?? 'Embedded'),
                subtitle: track.codec == null ? null : Text(track.codec!),
                onTap: () {
                  _player?.setSubtitleTrack(track);
                  Navigator.pop(context);
                },
              ),
            for (final track in widget.playback.subtitles)
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(track.label),
                subtitle: Text([
                  track.language,
                  if (track.format != null) track.format!,
                ].join(' • ')),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _selectExternalSubtitle(track);
                  } catch (error) {
                    if (mounted) _showError(error);
                  }
                },
              ),
          ],
        ),
      ),
    );
    _restartControlsTimer();
  }

  Future<void> _showQualityMenu() async {
    _controlsTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17151D),
      builder: (context) => SafeArea(
        child: RadioGroup<int>(
          groupValue: _streamIndex,
          onChanged: (value) {
            Navigator.pop(context);
            if (value != null) _changeStream(value);
          },
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.playback.streams.length,
            itemBuilder: (context, index) {
              final stream = widget.playback.streams[index];
              return RadioListTile<int>(
                value: index,
                title: Text(stream.quality),
                subtitle: Text([
                  stream.language,
                  if (stream.codec != null) stream.codec!,
                ].join(' • ')),
              );
            },
          ),
        ),
      ),
    );
    _restartControlsTimer();
  }

  Future<void> _showPlaybackMenu() async {
    _controlsTimer?.cancel();
    final selected = await showModalBottomSheet<VideoDecoderMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17151D),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: RadioGroup<VideoDecoderMode>(
              groupValue: _preferences.decoderMode,
              onChanged: (value) => Navigator.pop(context, value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('Video decoder'),
                    subtitle: Text(
                      'Changing decoder reloads the current stream.',
                    ),
                  ),
                  for (final mode in VideoDecoderMode.values)
                    RadioListTile<VideoDecoderMode>(
                      value: mode,
                      title: Text(switch (mode) {
                        VideoDecoderMode.automatic => 'Automatic',
                        VideoDecoderMode.hardware => 'Hardware',
                        VideoDecoderMode.software => 'Software compatibility',
                      }),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) await _changeDecoder(selected);
    _restartControlsTimer();
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _enterPlayerMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _leavePlayerMode() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _disposePlayer() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _gestureTimer?.cancel();
    unawaited(_disposePlayer());
    unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    unawaited(_leavePlayerMode());
    super.dispose();
  }
}

class _PlayerError extends StatelessWidget {
  final String error;

  const _PlayerError({required this.error});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      );
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
