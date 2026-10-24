import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class ChapterBookScreen extends StatefulWidget {
  final String bookTitle;
  final String chapterId;
  final String? chapterTitle;
  final String? chapterNumber;
  final String mangaID;
  final String chapterWebViewUrl;
  final MangaSource? scrapper;

  const ChapterBookScreen({
    super.key,
    required this.bookTitle,
    required this.chapterId,
    this.chapterTitle,
    required this.mangaID,
    this.chapterNumber,
    this.chapterWebViewUrl = '',
    this.scrapper,
  });

  @override
  State<ChapterBookScreen> createState() => _ChapterBookScreenState();
}

class _ChapterBookScreenState extends State<ChapterBookScreen> {
  static const int _preloadWindowSize = 4;

  bool _showControls = false;
  int _currentPage = 0;
  bool _isPaginatedView = false;
  bool _reverseReading = false;
  final List<MangaReaderPage> _chapterImages = [];
  final List<GlobalKey> _imageItemKeys = [];
  final Set<int> _preloadedPageIndexes = <int>{};
  final Set<int> _preloadingPageIndexes = <int>{};
  StreamSubscription<MangaReaderPage>? _chapterImagesSubscription;
  bool _showWebView = false;
  bool _streamDone = false;
  flutter_webview.WebViewController? _androidWebViewController;
  int _webViewProgress = 0;
  String? _webViewError;
  Timer? _webViewReadinessTimer;
  int _webViewReadinessAttempts = 0;
  int? _pendingRestorePage;
  bool _recalcScheduled = false;
  Timer? _controlsAutoHideTimer;

  late PageController? _pageController;
  late ScrollController _scrollController;
  // ignore: unused_field
  late FontProvider _fontProvider;
  late MangaSource _activeScrapper;
  late String _chapterWebViewUrl;

  @override
  void initState() {
    super.initState();
    _chapterWebViewUrl = widget.chapterWebViewUrl;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _fontProvider = Provider.of<FontProvider>(context, listen: false);
    _activeScrapper = widget.scrapper ?? _fontProvider.selectedFontApi;
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadReadingProgress();
      await _loadChapterImages();
      _scrollController.addListener(() {
        _onScroll();
      });
      _pageController = PageController(
          initialPage: _currentPage,
          viewportFraction: _isPaginatedView ? 0.75 : 1.0);
      _pageController!.addListener(() {
        setState(() {
          _currentPage = _pageController!.page?.round() ?? 0;
        });
      });
      _setControlsVisible(true);
      setState(() {});
    });
  }

  Future<void> _loadChapterImages() async {
    _chapterImagesSubscription = _activeScrapper
        .readChapter(mangaId: widget.mangaID, chapterId: widget.chapterId)
        .listen(
      (page) {
        final pageIndex = _chapterImages.length;
        setState(() {
          _chapterImages.add(page);
          _imageItemKeys.add(GlobalKey());
        });
        if (pageIndex < _preloadWindowSize) {
          _preloadPagesAround(0);
        }
        _tryRestoreScrollPosition();
      },
      onError: (_) {
        if (mounted) setState(() => _streamDone = true);
        // Falha ao resolver páginas → cai para a WebView se houver URL.
        if (_chapterImages.isEmpty &&
            _chapterWebViewUrl.isNotEmpty &&
            mounted) {
          _activateWebView();
        }
      },
      onDone: () {
        if (mounted) setState(() => _streamDone = true);
        // Se a fonte não forneceu imagens (ex.: conteúdo protegido por DRM),
        // abre automaticamente a WebView com a URL do capítulo.
        if (_chapterImages.isEmpty &&
            _chapterWebViewUrl.isNotEmpty &&
            mounted) {
          _activateWebView();
        }
      },
    );
  }

  void _activateWebView() {
    _ensureAndroidWebViewController();
    setState(() => _showWebView = true);
  }

  void _ensureAndroidWebViewController() {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _androidWebViewController != null ||
        _chapterWebViewUrl.isEmpty) {
      return;
    }
    final controller = flutter_webview.WebViewController();
    controller
      ..setJavaScriptMode(flutter_webview.JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
    controller.setNavigationDelegate(flutter_webview.NavigationDelegate(
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _webViewProgress = progress);
      },
      onPageStarted: (_) {
        if (!mounted) return;
        _webViewReadinessTimer?.cancel();
        setState(() {
          _webViewProgress = 0;
          _webViewError = null;
        });
      },
      onPageFinished: (_) {
        if (!mounted) return;
        setState(() => _webViewProgress = 100);
        _startWebViewReadinessChecks(controller);
      },
      onWebResourceError: (error) {
        if (!mounted || error.isForMainFrame != true) return;
        setState(() => _webViewError = error.description);
      },
      onNavigationRequest: (_) => flutter_webview.NavigationDecision.navigate,
    ));
    _androidWebViewController = controller;
    unawaited(controller.loadRequest(Uri.parse(_chapterWebViewUrl)));
  }

  void _retryWebView() {
    _webViewReadinessTimer?.cancel();
    setState(() {
      _webViewError = null;
      _webViewProgress = 0;
    });
    final controller = _androidWebViewController;
    if (controller != null) unawaited(controller.reload());
  }

  void _startWebViewReadinessChecks(
    flutter_webview.WebViewController controller,
  ) {
    _webViewReadinessTimer?.cancel();
    _webViewReadinessAttempts = 0;
    _webViewReadinessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_checkWebViewReadiness(controller));
    });
  }

  Future<void> _checkWebViewReadiness(
    flutter_webview.WebViewController controller,
  ) async {
    if (!mounted || !_showWebView) return;
    _webViewReadinessAttempts++;
    try {
      final result = await controller.runJavaScriptReturningResult('''
        (() => document.querySelectorAll(
          'img[src^="blob:"], img[src^="http"], canvas, video'
        ).length)()
      ''');
      final mediaCount = int.tryParse(
            result.toString().replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;
      if (mediaCount > 0) {
        _webViewReadinessTimer?.cancel();
        return;
      }
    } catch (_) {
      // Cross-origin pages can reject inspection. The main-frame timeout below
      // still provides a recoverable state instead of an endless spinner.
    }
    if (_webViewReadinessAttempts < 15 || !mounted) return;
    _webViewReadinessTimer?.cancel();
    setState(() {
      _webViewError =
          'The site finished loading but did not expose any reader pages. '
          'It may require browser verification.';
    });
  }

  bool get _isInitialBuffering =>
      !_showWebView &&
      !_streamDone &&
      _chapterImages.length < _preloadWindowSize;

  Widget _buildReaderLoader() {
    final loaded = _chapterImages.length;
    final label = loaded == 0
        ? 'Loading pages…'
        : '$loaded ${loaded == 1 ? 'page ready' : 'pages ready'}';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Color(0xFF14101E)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Preparing the reader',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageImage(MangaReaderPage page, {BoxFit fit = BoxFit.contain}) {
    return Image(image: _imageProvider(page), fit: fit);
  }

  ImageProvider<Object> _imageProvider(MangaReaderPage page) {
    if (page.isLocal) return FileImage(File(page.filePath!));
    return NetworkImage(
      page.uri.toString(),
      headers: page.headers.isEmpty ? null : page.headers,
    );
  }

  void _preloadPagesAround(int anchor) {
    if (!mounted || _chapterImages.isEmpty) return;
    final indexes = mangaReaderPreloadIndexes(
      currentPage: anchor,
      pageCount: _chapterImages.length,
      windowSize: _preloadWindowSize,
      reverse: _reverseReading,
    );
    for (final index in indexes) {
      if (_preloadedPageIndexes.contains(index) ||
          !_preloadingPageIndexes.add(index)) {
        continue;
      }
      unawaited(
        precacheImage(_imageProvider(_chapterImages[index]), context).then((_) {
          _preloadingPageIndexes.remove(index);
          _preloadedPageIndexes.add(index);
        }).catchError((_) {
          _preloadingPageIndexes.remove(index);
        }),
      );
    }
  }

  Future<void> _openAdjacentChapter(bool next) async {
    final api = _activeScrapper;
    if (api is! ChapterNavigationMangaSource) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Navegação entre capítulos não é suportada nesta fonte.'),
        ),
      );
      return;
    }
    final nav = api as ChapterNavigationMangaSource;
    final targetId = next
        ? await nav.nextChapterId(widget.mangaID, widget.chapterId)
        : await nav.previousChapterId(widget.mangaID, widget.chapterId);
    if (!mounted) return;
    if (targetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next ? 'Não há próximo capítulo.' : 'Não há capítulo anterior.',
          ),
        ),
      );
      return;
    }
    final webViewUrl = api is WebViewChapterMangaSource
        ? (api as WebViewChapterMangaSource)
            .chapterWebUri(mangaId: widget.mangaID, chapterId: targetId)
            .toString()
        : '';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChapterBookScreen(
          bookTitle: widget.bookTitle,
          chapterId: targetId,
          mangaID: widget.mangaID,
          chapterWebViewUrl: webViewUrl,
          scrapper: _activeScrapper,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controlsAutoHideTimer?.cancel();
    _webViewReadinessTimer?.cancel();
    _saveReadingProgress();
    _scrollController.dispose();
    _pageController?.dispose();
    _chapterImagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getInt('reading_progress_${widget.chapterId}') ?? 0;
    _pendingRestorePage = savedPage;
    setState(() {
      _currentPage = savedPage;
    });
  }

  Future<void> _saveReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('reading_progress_${widget.chapterId}', _currentPage);
  }

  void _onScroll() {
    _scheduleScrollProgressRecalc();
    if (_showControls) _scheduleControlsAutoHide();
  }

  void _scheduleScrollProgressRecalc() {
    if (_isPaginatedView || _recalcScheduled) return;
    _recalcScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcScheduled = false;
      _recalculateCurrentPageFromViewport();
    });
  }

  void _recalculateCurrentPageFromViewport() {
    if (!mounted || _chapterImages.isEmpty || _isPaginatedView) return;

    final viewportHeight = MediaQuery.of(context).size.height;
    final probeY = viewportHeight * 0.35;
    int bestIndex = _currentPage.clamp(0, _chapterImages.length - 1).toInt();
    double bestDistance = double.infinity;

    for (var i = 0; i < _imageItemKeys.length; i++) {
      final ctx = _imageItemKeys[i].currentContext;
      if (ctx == null) continue;
      final render = ctx.findRenderObject();
      if (render is! RenderBox) continue;

      final top = render.localToGlobal(Offset.zero).dy;
      final center = top + (render.size.height / 2);
      final distance = (center - probeY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex != _currentPage) {
      setState(() {
        _currentPage = bestIndex;
      });
      _preloadPagesAround(bestIndex);
    }
  }

  void _tryRestoreScrollPosition() {
    if (_isPaginatedView || _pendingRestorePage == null) return;
    final target = _pendingRestorePage!;
    if (target < 0 || target >= _imageItemKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingRestorePage == null) return;
      final targetContext = _imageItemKeys[target].currentContext;
      if (targetContext == null) return;

      Scrollable.ensureVisible(
        targetContext,
        duration: Duration.zero,
        alignment: 0,
      );
      _preloadPagesAround(target);
      _pendingRestorePage = null;
    });
  }

  void _toggleView() {
    setState(() {
      _isPaginatedView = !_isPaginatedView;
      _pageController?.dispose();
      _pageController =
          PageController(initialPage: _currentPage, viewportFraction: 1.0);
    });
    _scheduleControlsAutoHide();
  }

  void _setControlsVisible(bool visible) {
    if (!mounted) return;
    setState(() => _showControls = visible);
    if (visible) {
      _scheduleControlsAutoHide();
    } else {
      _controlsAutoHideTimer?.cancel();
    }
  }

  void _scheduleControlsAutoHide() {
    _controlsAutoHideTimer?.cancel();
    _controlsAutoHideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _showWebView) return;
      setState(() => _showControls = false);
    });
  }

  Future<void> _jumpToPage(int target) async {
    if (_chapterImages.isEmpty) return;
    final index = target.clamp(0, _chapterImages.length - 1);
    setState(() => _currentPage = index);
    _preloadPagesAround(index);

    if (_isPaginatedView) {
      _pageController?.jumpToPage(index);
      return;
    }
    if (index < _imageItemKeys.length) {
      final ctx = _imageItemKeys[index].currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: 0,
        );
      }
    }
  }

  void _showReaderPreferences() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151026),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reader preferences',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _isPaginatedView,
                      onChanged: (v) {
                        setModalState(() => _isPaginatedView = v);
                        setState(() {
                          _isPaginatedView = v;
                          _pageController?.dispose();
                          _pageController = PageController(
                              initialPage: _currentPage, viewportFraction: 1.0);
                        });
                      },
                      title: const Text('Paginated mode',
                          style: TextStyle(color: Colors.white)),
                      activeThumbColor: Colors.deepPurpleAccent,
                    ),
                    SwitchListTile(
                      value: _reverseReading,
                      onChanged: (v) {
                        setModalState(() => _reverseReading = v);
                        setState(() => _reverseReading = v);
                        _preloadPagesAround(_currentPage);
                      },
                      title: const Text('Reverse reading direction',
                          style: TextStyle(color: Colors.white)),
                      activeThumbColor: Colors.deepPurpleAccent,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadImage(MangaReaderPage page) async {
    // TODO: Implement image download logic
  }

  Future<void> _shareImage(MangaReaderPage page) async {
    // TODO: Implement image sharing logic
  }

  void _showImageOptions(MangaReaderPage page) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Image Options'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.save_alt),
                  title: const Text('Save Image'),
                  onTap: () {
                    _downloadImage(page);
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.share),
                  title: const Text('Share Image'),
                  onTap: () {
                    _shareImage(page);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
        });
  }

  Widget _buildWebView(BuildContext context) {
    final String url = _chapterWebViewUrl.isNotEmpty
        ? _chapterWebViewUrl
        : 'https://www.google.com';

    Widget webViewContent;

    if (kIsWeb) {
      return Center(
        child: Text('Web view not supported on this platform.'),
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      _ensureAndroidWebViewController();
      final controller = _androidWebViewController;
      if (controller == null) {
        webViewContent = const Center(child: CircularProgressIndicator());
      } else {
        webViewContent = Stack(
          children: [
            flutter_webview.WebViewWidget(controller: controller),
            if (_webViewProgress < 100)
              LinearProgressIndicator(value: _webViewProgress / 100),
            if (_webViewError != null)
              ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 52),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load the browser reader.\n$_webViewError',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _retryWebView,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try again'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse(url)),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Open externally'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      }
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      webViewContent = FutureBuilder<webview_windows.WebviewController>(
          future: _initializeWebviewController(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final controller = snapshot.data!;
              controller.loadUrl(url);
              return webview_windows.Webview(controller);
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              return const CircularProgressIndicator();
            }
          });
    } else {
      webViewContent = const Text('Unsupported platform');
    }

    return webViewContent;
  }

  Future<webview_windows.WebviewController>
      _initializeWebviewController() async {
    final controller = webview_windows.WebviewController();
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle =
        widget.chapterTitle ?? widget.chapterNumber ?? 'Chapter';

    return Scaffold(
      appBar: _showControls
          ? AppBar(
              title: Text('${widget.bookTitle} - $displayTitle',
                  style: const TextStyle(
                      color: Color.fromARGB(255, 224, 224, 224),
                      fontWeight: FontWeight.bold)),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              backgroundColor: Color.fromARGB(158, 60, 16, 180),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _showReaderPreferences,
                ),
                IconButton(
                  icon: Icon(Icons.open_in_new_rounded),
                  tooltip: _showWebView ? 'Open externally' : 'Browser reader',
                  onPressed: () {
                    if (_showWebView) {
                      launchUrl(Uri.parse(_chapterWebViewUrl));
                    } else {
                      _activateWebView();
                    }
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.deepPurple.withValues(alpha: 0.5),
                    highlightColor: Colors.white,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                )
              ],
            )
          : null,
      body: _showWebView
          ? _buildWebView(context)
          : _isInitialBuffering
              ? _buildReaderLoader()
              : GestureDetector(
              onTap: () {
                _setControlsVisible(!_showControls);
              },
              onLongPress: () {
                if (_chapterImages.isEmpty) return;
                final safeIndex =
                    _currentPage.clamp(0, _chapterImages.length - 1).toInt();
                _showImageOptions(_chapterImages[safeIndex]);
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black,
                      Colors.grey[900]!,
                    ],
                  ),
                ),
                child: _isPaginatedView
                    ? PageView.builder(
                        onPageChanged: (index) {
                          setState(() {
                            _currentPage = index;
                          });
                          _preloadPagesAround(index);
                          _scheduleControlsAutoHide();
                        },
                        reverse: _reverseReading,
                        scrollBehavior: ScrollBehavior().copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                          },
                        ),
                        controller: _pageController,
                        itemCount: _chapterImages.length,
                        itemBuilder: (context, index) {
                          return _buildPageImage(_chapterImages[index]);
                        },
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: _reverseReading,
                        itemCount: _chapterImages.length,
                        itemBuilder: (context, index) {
                          return Container(
                            key: _imageItemKeys[index],
                            child: _buildPageImage(_chapterImages[index]),
                          );
                        },
                      ),
              ),
            ),
      floatingActionButton: _showControls
          ? FloatingActionButton(
              onPressed: () async {
                await _saveReadingProgress();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reading progress saved'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Icon(Icons.save),
            )
          : null,
      bottomNavigationBar: _showControls
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(185, 42, 19, 107),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_chapterImages.length > 1)
                            Slider(
                              value: _currentPage
                                  .clamp(0, _chapterImages.length - 1)
                                  .toDouble(),
                              min: 0,
                              max: (_chapterImages.length - 1).toDouble(),
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                              onChanged: (v) => _jumpToPage(v.round()),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  onPressed: () => _openAdjacentChapter(false),
                                ),
                                Text(
                                  '${_chapterImages.isEmpty ? 0 : _currentPage + 1}/${_chapterImages.length} • ${_chapterImages.isEmpty ? 0 : (((_currentPage + 1) / _chapterImages.length) * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(_isPaginatedView
                                      ? Icons.view_agenda_rounded
                                      : Icons.view_carousel_rounded),
                                  onPressed: _toggleView,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next_rounded),
                                  onPressed: () => _openAdjacentChapter(true),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
