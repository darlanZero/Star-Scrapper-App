import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AnimeSourceSessionScreen extends StatefulWidget {
  final BrowserSessionAnimeSource source;

  const AnimeSourceSessionScreen({super.key, required this.source});

  @override
  State<AnimeSourceSessionScreen> createState() =>
      _AnimeSourceSessionScreenState();
}

class _AnimeSourceSessionScreenState extends State<AnimeSourceSessionScreen> {
  late final WebViewController _controller;
  static const _cookieChannel = MethodChannel('starslibrary/webview_cookies');
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            await _tryFinish();
          },
        ),
      )
      ..loadRequest(widget.source.sessionUri);
  }

  Future<void> _tryFinish() async {
    if (_saving) return;
    final ready = await _controller.runJavaScriptReturningResult(
      "Boolean(document.querySelector('article.bs, .bsx, .boxAN, .boxEP, "
      ".list-item, .streamer-content, .postbody'))",
    );
    if (ready != true && ready.toString() != 'true') return;
    _saving = true;
    try {
      final cookieHeader = await _cookieChannel.invokeMethod<String>(
            'getCookies',
            {'url': widget.source.sessionUri.toString()},
          ) ??
          '';
      final rawUserAgent = await _controller.runJavaScriptReturningResult(
        'navigator.userAgent',
      );
      await widget.source.updateBrowserSession(
        cookies: _parseCookies(cookieHeader),
        userAgent: _decodeJavaScriptString(rawUserAgent),
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            'Verify ${widget.source is AnimeSource ? (widget.source as AnimeSource).name : 'source'}',
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading || _saving)
              const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      );
}

class AnimePlaybackResolverScreen extends StatefulWidget {
  final BrowserPlaybackAnimeSource source;
  final AnimePlaybackResolutionRequired request;

  const AnimePlaybackResolverScreen({
    super.key,
    required this.source,
    required this.request,
  });

  @override
  State<AnimePlaybackResolverScreen> createState() =>
      _AnimePlaybackResolverScreenState();
}

class _AnimePlaybackResolverScreenState
    extends State<AnimePlaybackResolverScreen> {
  late final WebViewController _controller;
  Timer? _probeTimer;
  String _status = 'Opening the video host…';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() => _status = 'Following secure redirects…');
            }
            _inspectUri(Uri.tryParse(url));
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(
                () => _status =
                    'Resolving ${widget.request.choices.single.label}…',
              );
            }
            _inspectUri(Uri.tryParse(url));
            _startProbing();
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (_isProbableMediaUri(uri)) {
              _finish(uri!);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _status = error.description);
            }
          },
        ),
      );
    unawaited(_loadEntryUri());
  }

  Future<void> _loadEntryUri() async {
    if (widget.source case final AnimeSource animeSource) {
      final userAgent = animeSource.requestHeaders.entries
          .where((entry) => entry.key.toLowerCase() == 'user-agent')
          .map((entry) => entry.value)
          .firstOrNull;
      if (userAgent != null && userAgent.isNotEmpty) {
        await _controller.setUserAgent(userAgent);
      }
    }
    await _controller.loadRequest(widget.request.entryUri);
  }

  void _startProbing() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _probePage(),
    );
  }

  Future<void> _probePage() async {
    if (_finished) return;
    try {
      final raw = await _controller.runJavaScriptReturningResult(r'''
        (() => {
          const documents = [];
          const collectDocuments = doc => {
            if (!doc || documents.includes(doc)) return;
            documents.push(doc);
            for (const frame of doc.querySelectorAll('iframe')) {
              try {
                collectDocuments(frame.contentDocument);
              } catch (_) {}
            }
          };
          collectDocuments(document);

          const videos = documents.map(doc =>
            doc.querySelector('video')?.currentSrc ||
            doc.querySelector('video')?.src ||
            doc.querySelector('video source')?.src || ''
          ).filter(Boolean);
          const resources = documents.flatMap(doc => {
            try {
              return [...doc.defaultView.performance.getEntriesByType('resource')]
                .map(entry => entry.name)
                .filter(value => value.includes('videoplayback') ||
                  /\.(m3u8|mpd|mp4|mkv|webm)(\?|$)/i.test(value));
            } catch (_) {
              return [];
            }
          });
          const links = documents.flatMap(doc =>
            [...doc.querySelectorAll('a[href]')]
              .filter(link => link.hasAttribute('download') ||
                /download/i.test(`${link.id} ${link.className}`) ||
                /\.(m3u8|mpd|mp4|mkv|webm)(\?|$)/i.test(link.href))
              .map(link => link.href)
          );
          const blogger = documents.flatMap(doc =>
            [...doc.querySelectorAll('[data-p]')].flatMap(element => {
              const data = (element.getAttribute('data-p') || '')
                .replace(/\\u003d/g, '=')
                .replace(/\\u0026/g, '&')
                .replace(/\\\//g, '/');
              return data.match(
                /https:\/\/[^\s"'\\]*googlevideo\.com\/videoplayback\?[^\s"'\\]+/g
              ) || [];
            })
          );
          const authorized = documents.map(doc => {
            try {
              return doc.defaultView?._pC?.result?.url || '';
            } catch (_) {
              return '';
            }
          }).filter(Boolean);
          return JSON.stringify({
            videos,
            text: documents.map(doc => doc.body?.innerText || '')
              .join('\n').slice(0, 4000),
            resources,
            links,
            blogger,
            authorized
          });
        })()
      ''');
      final decoded = jsonDecode(_decodeJavaScriptString(raw));
      if (decoded is! Map) return;
      final candidates = <String>[
        ...((decoded['videos'] as List?) ?? const []).map((e) => '$e'),
        ...((decoded['resources'] as List?) ?? const []).map((e) => '$e'),
        ...((decoded['links'] as List?) ?? const []).map((e) => '$e'),
        ...((decoded['blogger'] as List?) ?? const []).map((e) => '$e'),
        ...((decoded['authorized'] as List?) ?? const []).map((e) => '$e'),
      ];
      final pageText = (decoded['text']?.toString() ?? '').toLowerCase();
      if (widget.request.provider == 'SEND' &&
          (pageText.contains('security verification') ||
              pageText.contains('verify you are human') ||
              pageText.contains('needs to review the security'))) {
        if (mounted) {
          setState(
            () => _status =
                'Complete the SEND security verification below to continue.',
          );
        }
      } else if (widget.request.provider == 'NHPlayer' &&
          (pageText.contains('verifying that you are not a robot') ||
              pageText.contains('verify you are human'))) {
        if (mounted) {
          setState(
            () => _status =
                'Complete the NHPlayer verification below to continue.',
          );
        }
      } else if (widget.request.provider == 'NHPlayer' && mounted) {
        setState(
          () => _status =
              'Tap the NHPlayer play button below. The video will open natively once authorized.',
        );
      } else if (widget.request.provider == 'Google Drive' &&
          (pageText.contains('quota') ||
              pageText.contains('não foi possível carregar o vídeo') ||
              pageText.contains('unable to play this video'))) {
        if (mounted) {
          setState(
            () => _status =
                'Google Drive cannot play this file right now. Try another episode or try again later.',
          );
        }
        _probeTimer?.cancel();
        return;
      }
      for (final candidate in candidates) {
        final uri = Uri.tryParse(candidate);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          await _finish(uri);
          return;
        }
      }
    } catch (_) {}
  }

  void _inspectUri(Uri? uri) {
    if (uri == null || _finished) return;
    if (_isProbableMediaUri(uri)) {
      _finish(uri);
      return;
    }
  }

  bool _isProbableMediaUri(Uri? uri) {
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final lower = uri.toString().toLowerCase();
    return uri.host.contains('googlevideo.com') ||
        RegExp(r'\.(m3u8|mpd|mp4|mkv|webm)(\?|$)').hasMatch(lower);
  }

  Future<void> _finish(Uri uri) async {
    if (_finished || !mounted) return;
    _finished = true;
    _probeTimer?.cancel();
    try {
      final playback = await widget.source.playbackFromResolvedUri(
        uri,
        quality: widget.request.quality,
        provider: widget.request.provider,
      );
      if (mounted) Navigator.pop(context, playback);
    } catch (error) {
      _finished = false;
      if (mounted) setState(() => _status = 'Could not resolve video: $error');
    }
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.request.choices.single.label),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_status)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

String _decodeJavaScriptString(Object value) {
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      return decoded is String ? decoded : value;
    } catch (_) {
      return value;
    }
  }
  return value.toString();
}

Map<String, String> _parseCookies(String header) => {
      for (final pair in header.split(';'))
        if (pair.trim().contains('='))
          pair.trim().substring(0, pair.trim().indexOf('=')):
              pair.trim().substring(pair.trim().indexOf('=') + 1),
    };
