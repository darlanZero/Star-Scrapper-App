import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/domain/library/reader_progress.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;
import 'package:webview_windows/webview_windows.dart' as webview_windows;
import 'reader_page_image.dart';

class ChapterBookScreen extends StatefulWidget {
  final String bookTitle;
  final String chapterId;
  final String? chapterTitle;
  final String? chapterNumber;
  final String mangaID;
  final String chapterWebViewUrl;
  final MangaSource? scrapper;
  final Future<void> Function(int chapter)? onChapterCompleted;

  const ChapterBookScreen({
    super.key,
    required this.bookTitle,
    required this.chapterId,
    this.chapterTitle,
    required this.mangaID,
    this.chapterNumber,
    this.chapterWebViewUrl = '',
    this.scrapper,
    this.onChapterCompleted,
  });

  @override
  State<ChapterBookScreen> createState() => _ChapterBookScreenState();
}

class _ChapterBookScreenState extends State<ChapterBookScreen>
    with WidgetsBindingObserver {
  static const int _preloadWindowSize = 4;
  static const MethodChannel _readerImageChannel =
      MethodChannel('starslibrary/reader_images');

  bool _showControls = false;
  int _currentPage = 0;
  bool _isPaginatedView = false;
  bool _reverseReading = false;
  final List<MangaReaderPage> _chapterImages = [];
  final List<GlobalKey> _imageItemKeys = [];
  final Map<int, double> _pageAspectRatios = {};
  final Set<int> _preloadedPageIndexes = <int>{};
  final Set<int> _preloadingPageIndexes = <int>{};
  StreamSubscription<MangaReaderPage>? _chapterImagesSubscription;
  bool _showWebView = false;
  bool _streamDone = false;
  bool _streamCompletedSuccessfully = false;
  String? _readerError;
  flutter_webview.WebViewController? _androidWebViewController;
  int _webViewProgress = 0;
  String? _webViewError;
  Timer? _webViewReadinessTimer;
  int _webViewReadinessAttempts = 0;
  ReaderProgressPosition? _pendingRestorePosition;
  double _currentPageFraction = 0;
  double _chapterProgress = 0;
  bool _restoringPosition = false;
  bool _recalcScheduled = false;
  bool _didRecordChapter = false;
  Timer? _controlsAutoHideTimer;
  Timer? _progressSaveTimer;

  PageController? _pageController;
  late ScrollController _scrollController;
  // ignore: unused_field
  late FontProvider _fontProvider;
  late MangaSource _activeScrapper;
  late String _chapterWebViewUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
          initialPage: _currentPage < _chapterImages.length ? _currentPage : 0,
          viewportFraction: _isPaginatedView ? 0.75 : 1.0);
      _pageController!.addListener(() {
        final page = _pageController!.page?.round() ?? 0;
        _updatePaginatedProgress(page);
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
        _scheduleScrollProgressRecalc();
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _streamDone = true;
            _readerError = error.toString();
          });
        }
        // Falha ao resolver páginas → cai para a WebView se houver URL.
        if (_chapterImages.isEmpty &&
            _chapterWebViewUrl.isNotEmpty &&
            _activeScrapper.id != 'luratoons' &&
            mounted) {
          _activateWebView();
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _streamDone = true;
            _streamCompletedSuccessfully = true;
          });
          _tryRestoreScrollPosition();
          _scheduleScrollProgressRecalc();
        }
        // Se a fonte não forneceu imagens (ex.: conteúdo protegido por DRM),
        // abre automaticamente a WebView com a URL do capítulo.
        if (_chapterImages.isEmpty &&
            _chapterWebViewUrl.isNotEmpty &&
            _activeScrapper.id != 'luratoons' &&
            mounted) {
          _activateWebView();
        } else if (_chapterImages.isEmpty &&
            _activeScrapper.id == 'luratoons' &&
            _readerError == null &&
            mounted) {
          setState(() {
            _readerError =
                'The protected reader finished without producing pages.';
          });
        }
      },
    );
  }

  void _recordChapterRead() {
    if (_didRecordChapter) return;
    _didRecordChapter = true;
    _chapterProgress = 1;
    _scheduleReadingProgressSave();
    unawaited(_fontProvider.saveSingleSelectedChapterId(
      widget.mangaID,
      widget.chapterId,
      widget.chapterNumber?.trim().isNotEmpty == true
          ? widget.chapterNumber!.trim()
          : (widget.chapterTitle?.trim().isNotEmpty == true
              ? widget.chapterTitle!.trim()
              : widget.chapterId),
      scrapper: _activeScrapper,
    ));
    final chapter = trackerChapterProgress(widget.chapterNumber);
    if (chapter != null && chapter > 0 && widget.onChapterCompleted != null) {
      unawaited(_syncCompletedChapter(chapter));
    }
  }

  Future<void> _syncCompletedChapter(int chapter) async {
    try {
      await widget.onChapterCompleted!(chapter);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Chapter saved locally. AniList sync failed: $error',
          ),
        ),
      );
    }
  }

  void _maybeRecordChapterRead() {
    if (_didRecordChapter || _chapterImages.isEmpty) return;
    final position =
        _scrollController.hasClients ? _scrollController.position : null;
    final completed = readerReachedCompletion(
      mode: _readerLayoutMode,
      streamDone: _streamCompletedSuccessfully,
      currentPage: _currentPage,
      pageCount: _chapterImages.length,
      extentAfter: position?.extentAfter ?? double.infinity,
      viewportDimension: position?.viewportDimension ?? 0,
    );
    if (completed) _recordChapterRead();
  }

  void _updatePaginatedProgress(int page) {
    if (!mounted || _chapterImages.isEmpty || !_isPaginatedView) return;
    final safePage = page.clamp(0, _chapterImages.length - 1);
    final progress = (safePage + 1) / _chapterImages.length;
    if (safePage != _currentPage || _chapterProgress != progress) {
      setState(() {
        _currentPage = safePage;
        _currentPageFraction = 0;
        _chapterProgress = progress;
      });
      _preloadPagesAround(safePage);
      _scheduleReadingProgressSave();
    }
    _maybeRecordChapterRead();
  }

  Future<void> _retryNativeReader() async {
    await _chapterImagesSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _chapterImages.clear();
      _imageItemKeys.clear();
      _pageAspectRatios.clear();
      _preloadedPageIndexes.clear();
      _preloadingPageIndexes.clear();
      _readerError = null;
      _streamDone = false;
      _streamCompletedSuccessfully = false;
    });
    await _loadChapterImages();
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
    final colors = Theme.of(context).colorScheme;
    final loaded = _chapterImages.length;
    final label = loaded == 0
        ? 'Loading pages…'
        : '$loaded ${loaded == 1 ? 'page ready' : 'pages ready'}';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            colors.surface,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Preparing the reader',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderError() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 52, color: colors.error),
            const SizedBox(height: 18),
            Text(
              'Could not prepare the native reader',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _readerError ?? 'No pages were returned.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _retryNativeReader,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageImage(MangaReaderPage page, {BoxFit fit = BoxFit.contain}) {
    return Image(
      image: _imageProvider(page),
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryRestoreScrollPosition();
            _scheduleScrollProgressRecalc();
          });
        }
        return child;
      },
    );
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
          onChapterCompleted: widget.onChapterCompleted,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsAutoHideTimer?.cancel();
    _progressSaveTimer?.cancel();
    _webViewReadinessTimer?.cancel();
    unawaited(_saveReadingProgress());
    _scrollController.dispose();
    _pageController?.dispose();
    _chapterImagesSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveReadingProgress());
    }
  }

  Future<void> _loadReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    ReaderProgressPosition? position;
    final encoded = prefs.getString(_readingProgressKey);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          position = ReaderProgressPosition.fromJson(decoded);
        }
      } catch (_) {
        // Fall through to the legacy page-only position.
      }
    }
    position ??= ReaderProgressPosition(
      pageIndex: prefs.getInt('reading_progress_${widget.chapterId}') ?? 0,
      pageFraction: 0,
      chapterFraction: 0,
      mode: ReaderLayoutMode.webtoon,
    );
    _pendingRestorePosition = position;
    setState(() {
      _currentPage = position!.pageIndex;
      _currentPageFraction = position.pageFraction;
      _chapterProgress = position.chapterFraction;
      _isPaginatedView = position.mode == ReaderLayoutMode.paginated;
      _didRecordChapter = position.completed;
    });
  }

  Future<void> _saveReadingProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final position = ReaderProgressPosition(
      pageIndex: _currentPage,
      pageFraction: _currentPageFraction,
      chapterFraction: _chapterProgress,
      mode: _readerLayoutMode,
      completed: _didRecordChapter,
    );
    await prefs.setString(_readingProgressKey, jsonEncode(position.toJson()));
  }

  String get _readingProgressKey => readerProgressStorageKey(
        sourceId: _activeScrapper.id,
        mangaId: widget.mangaID,
        chapterId: widget.chapterId,
      );

  ReaderLayoutMode get _readerLayoutMode =>
      _isPaginatedView ? ReaderLayoutMode.paginated : ReaderLayoutMode.webtoon;

  void _scheduleReadingProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_saveReadingProgress()),
    );
  }

  void _onScroll() {
    _scheduleScrollProgressRecalc();
    if (_showControls) _scheduleControlsAutoHide();
  }

  bool _handleReaderScrollNotification(ScrollNotification notification) {
    final isUserDrag = notification is ScrollStartNotification &&
        notification.dragDetails != null;
    if (isUserDrag && _pendingRestorePosition != null) {
      _pendingRestorePosition = null;
      _restoringPosition = false;
      _scheduleScrollProgressRecalc();
    }
    return false;
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
    if (!mounted ||
        _chapterImages.isEmpty ||
        _isPaginatedView ||
        _restoringPosition ||
        _pendingRestorePosition != null) {
      return;
    }

    final viewportHeight = MediaQuery.of(context).size.height;
    final probeY = viewportHeight * 0.35;
    int bestIndex = _currentPage.clamp(0, _chapterImages.length - 1).toInt();
    double bestFraction = _currentPageFraction;
    double bestDistance = double.infinity;

    for (var i = 0; i < _imageItemKeys.length; i++) {
      final ctx = _imageItemKeys[i].currentContext;
      if (ctx == null) continue;
      final render = ctx.findRenderObject();
      if (render is! RenderBox) continue;

      final top = render.localToGlobal(Offset.zero).dy;
      final height = render.size.height;
      if (height <= 0) continue;
      final bottom = top + height;
      if (probeY >= top && probeY <= bottom) {
        bestIndex = i;
        bestFraction = ((probeY - top) / height).clamp(0.0, 1.0);
        bestDistance = 0;
        break;
      }
      final center = top + (height / 2);
      final distance = (center - probeY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
        bestFraction = ((probeY - top) / height).clamp(0.0, 1.0);
      }
    }

    final scrollPosition =
        _scrollController.hasClients ? _scrollController.position : null;
    final chapterFraction = scrollPosition == null
        ? _chapterProgress
        : normalizedReaderScrollProgress(
            pixels: scrollPosition.pixels,
            maxScrollExtent: scrollPosition.maxScrollExtent,
          );
    if (bestIndex != _currentPage ||
        (bestFraction - _currentPageFraction).abs() >= 0.002 ||
        (chapterFraction - _chapterProgress).abs() >= 0.002) {
      setState(() {
        _currentPage = bestIndex;
        _currentPageFraction = bestFraction;
        _chapterProgress = chapterFraction;
      });
      _preloadPagesAround(bestIndex);
      _scheduleReadingProgressSave();
    }
    _maybeRecordChapterRead();
  }

  void _tryRestoreScrollPosition() {
    final saved = _pendingRestorePosition;
    if (saved == null || _chapterImages.isEmpty) return;
    if (saved.pageIndex >= _chapterImages.length && !_streamDone) {
      if (!_isPaginatedView && _scrollController.hasClients) {
        final position = _scrollController.position;
        _restoringPosition = true;
        _scrollController.jumpTo(
          (position.maxScrollExtent * saved.chapterFraction)
              .clamp(0.0, position.maxScrollExtent),
        );
        _restoringPosition = false;
      }
      return;
    }
    final target = saved.pageIndex.clamp(0, _chapterImages.length - 1);

    if (_isPaginatedView) {
      if (_pageController?.hasClients == true) {
        _pageController!.jumpToPage(target);
        _pendingRestorePosition = null;
      }
      return;
    }
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tryRestoreScrollPosition(),
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingRestorePosition == null) return;
      final targetContext = _imageItemKeys[target].currentContext;
      if (targetContext == null) {
        final position = _scrollController.position;
        final approximate = position.maxScrollExtent * saved.chapterFraction;
        _restoringPosition = true;
        _scrollController.jumpTo(
          approximate.clamp(0.0, position.maxScrollExtent),
        );
        _restoringPosition = false;
        return;
      }
      final render = targetContext.findRenderObject();
      if (render is! RenderBox || render.size.height <= 0) return;
      // Wait for real image geometry, not the temporary loading placeholder.
      if (!_pageAspectRatios.containsKey(target)) return;
      final probeY = MediaQuery.of(context).size.height * 0.35;
      final targetY = render.localToGlobal(Offset.zero).dy +
          render.size.height * saved.pageFraction;
      final position = _scrollController.position;
      final destination = (position.pixels + targetY - probeY)
          .clamp(0.0, position.maxScrollExtent);
      _restoringPosition = true;
      _scrollController.jumpTo(destination);
      _restoringPosition = false;
      setState(() {
        _currentPage = target;
        _currentPageFraction = saved.pageFraction;
        _chapterProgress = saved.chapterFraction;
      });
      _preloadPagesAround(target);
      _pendingRestorePosition = null;
    });
  }

  void _toggleView() {
    _setReaderMode(!_isPaginatedView);
  }

  void _setReaderMode(bool paginated) {
    if (_isPaginatedView == paginated) return;
    final resume = ReaderProgressPosition(
      pageIndex: _currentPage,
      pageFraction: _currentPageFraction,
      chapterFraction: _chapterProgress,
      mode: paginated ? ReaderLayoutMode.paginated : ReaderLayoutMode.webtoon,
      completed: _didRecordChapter,
    );
    setState(() {
      _isPaginatedView = paginated;
      _pendingRestorePosition = resume;
      _pageController?.dispose();
      _pageController =
          PageController(initialPage: _currentPage, viewportFraction: 1.0);
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tryRestoreScrollPosition(),
    );
    _scheduleReadingProgressSave();
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
    if (_isPaginatedView) {
      _updatePaginatedProgress(index);
    } else {
      setState(() {
        _currentPage = index;
        _currentPageFraction = 0;
      });
    }
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
        _scheduleScrollProgressRecalc();
      }
    }
  }

  void _jumpToChapterProgress(double value) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.maxScrollExtent * value.clamp(0.0, 1.0))
          .clamp(0.0, position.maxScrollExtent),
    );
    _scheduleScrollProgressRecalc();
  }

  void _showReaderPreferences() {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
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
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Reader preferences',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _isPaginatedView,
                      onChanged: (v) {
                        _setReaderMode(v);
                        setModalState(() {});
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text('Paginated mode',
                          style: TextStyle(color: colors.onSurface)),
                      activeThumbColor: colors.primary,
                    ),
                    SwitchListTile(
                      value: _reverseReading,
                      onChanged: (v) {
                        setModalState(() => _reverseReading = v);
                        setState(() => _reverseReading = v);
                        _preloadPagesAround(_currentPage);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text('Reverse reading direction',
                          style: TextStyle(color: colors.onSurface)),
                      activeThumbColor: colors.primary,
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
    try {
      final image = await _materializeReaderImage(page);
      if (defaultTargetPlatform == TargetPlatform.android) {
        final savedLocation = await _readerImageChannel.invokeMethod<String>(
          'saveImage',
          <String, Object>{
            'path': image.file.path,
            'fileName': image.fileName,
            'mimeType': image.mimeType,
          },
        );
        _showImageActionMessage(
          savedLocation == null
              ? 'Image saved.'
              : 'Image saved to $savedLocation',
        );
        return;
      }

      final downloads = await getDownloadsDirectory();
      if (downloads == null) {
        throw const FileSystemException('Downloads folder is unavailable.');
      }
      final destination = await _uniqueDestination(
        downloads,
        image.fileName,
      );
      await image.file.copy(destination.path);
      _showImageActionMessage('Image saved to ${destination.path}');
    } catch (error) {
      _showImageActionMessage('Could not save image: $error', isError: true);
    }
  }

  Future<void> _shareImage(MangaReaderPage page) async {
    try {
      final image = await _materializeReaderImage(page);
      if (defaultTargetPlatform != TargetPlatform.android) {
        throw UnsupportedError(
          'Image sharing is currently available on Android.',
        );
      }
      await _readerImageChannel.invokeMethod<void>(
        'shareImage',
        <String, Object>{
          'path': image.file.path,
          'fileName': image.fileName,
          'mimeType': image.mimeType,
          'text': '${widget.bookTitle} — ${widget.chapterTitle ?? 'Chapter'}',
        },
      );
    } catch (error) {
      _showImageActionMessage('Could not share image: $error', isError: true);
    }
  }

  Future<_MaterializedReaderImage> _materializeReaderImage(
    MangaReaderPage page,
  ) async {
    late final Uint8List bytes;
    String? contentType;
    String? sourceExtension;

    if (page.isLocal) {
      final source = File(page.filePath!);
      bytes = await source.readAsBytes();
      sourceExtension = path.extension(source.path);
    } else {
      final uri = page.uri!;
      final response = await http.get(uri, headers: page.headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      bytes = response.bodyBytes;
      contentType = response.headers['content-type']?.split(';').first.trim();
      sourceExtension = path.extension(uri.path);
    }

    if (bytes.isEmpty) throw const FormatException('The image is empty.');
    final format = _detectReaderImageFormat(
      bytes,
      contentType: contentType,
      extension: sourceExtension,
    );
    final pageNumber = _chapterImages.indexOf(page) + 1;
    final safeTitle = _safeFilePart(widget.bookTitle, fallback: 'manga');
    final safeChapter = _safeFilePart(
      widget.chapterNumber ?? widget.chapterTitle ?? widget.chapterId,
      fallback: 'chapter',
    );
    final fileName =
        '${safeTitle}_${safeChapter}_p${pageNumber.clamp(1, 99999)}'
        '.${format.extension}';
    final temp = await getTemporaryDirectory();
    final exportDirectory = Directory(path.join(temp.path, 'reader_exports'));
    await exportDirectory.create(recursive: true);
    final file = File(path.join(exportDirectory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return _MaterializedReaderImage(
      file: file,
      fileName: fileName,
      mimeType: format.mimeType,
    );
  }

  Future<File> _uniqueDestination(Directory directory, String fileName) async {
    final stem = path.basenameWithoutExtension(fileName);
    final extension = path.extension(fileName);
    var candidate = File(path.join(directory.path, fileName));
    for (var suffix = 2; await candidate.exists(); suffix++) {
      candidate = File(path.join(directory.path, '$stem ($suffix)$extension'));
    }
    return candidate;
  }

  void _showImageActionMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
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

  int _pageIndexAtGlobalPosition(Offset globalPosition) {
    if (_chapterImages.isEmpty) return 0;
    if (_isPaginatedView) {
      return _currentPage.clamp(0, _chapterImages.length - 1).toInt();
    }

    final y = globalPosition.dy;
    var nearestIndex = _currentPage.clamp(0, _chapterImages.length - 1).toInt();
    var nearestDistance = double.infinity;
    for (var index = 0; index < _imageItemKeys.length; index++) {
      final render = _imageItemKeys[index].currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached || render.size.height <= 0) {
        continue;
      }
      final top = render.localToGlobal(Offset.zero).dy;
      final bottom = top + render.size.height;
      if (y >= top && y <= bottom) return index;

      final distance = y < top ? top - y : y - bottom;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    return nearestIndex;
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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _showControls
          ? PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: AppBar(
                    title: Text(
                      '${widget.bookTitle} - $displayTitle',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    backgroundColor: colors.surface.withValues(alpha: 0.82),
                    foregroundColor: colors.onSurface,
                    elevation: 0,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.tune_rounded),
                        color: colors.onSurface,
                        onPressed: _showReaderPreferences,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          icon: const Icon(Icons.open_in_new_rounded),
                          tooltip: _showWebView
                              ? 'Open externally'
                              : 'Browser reader',
                          onPressed: () {
                            if (_showWebView) {
                              launchUrl(Uri.parse(_chapterWebViewUrl));
                            } else {
                              _activateWebView();
                            }
                          },
                          style: IconButton.styleFrom(
                            backgroundColor:
                                colors.primary.withValues(alpha: 0.18),
                            foregroundColor: colors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: _showWebView
          ? _buildWebView(context)
          : _isInitialBuffering
              ? _buildReaderLoader()
              : _chapterImages.isEmpty && _readerError != null
                  ? _buildReaderError()
                  : GestureDetector(
                      onTap: () {
                        _setControlsVisible(!_showControls);
                      },
                      onLongPressStart: (details) {
                        if (_chapterImages.isEmpty) return;
                        final touchedIndex =
                            _pageIndexAtGlobalPosition(details.globalPosition);
                        _showImageOptions(_chapterImages[touchedIndex]);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Theme.of(context).scaffoldBackgroundColor,
                              colors.surface,
                            ],
                          ),
                        ),
                        child: _isPaginatedView
                            ? PageView.builder(
                                onPageChanged: (index) {
                                  _updatePaginatedProgress(index);
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
                            : NotificationListener<ScrollNotification>(
                                onNotification: _handleReaderScrollNotification,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  reverse: _reverseReading,
                                  itemCount: _chapterImages.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      key: _imageItemKeys[index],
                                      child: ReaderPageImage(
                                        image: _imageProvider(
                                            _chapterImages[index]),
                                        pageIndex: index,
                                        aspectRatios: _pageAspectRatios,
                                        onImageReady: () {
                                          _tryRestoreScrollPosition();
                                          _scheduleScrollProgressRecalc();
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
      floatingActionButton: _showControls
          ? FloatingActionButton(
              onPressed: () async {
                await _saveReadingProgress();
                if (!context.mounted) return;
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
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((_isPaginatedView && _chapterImages.length > 1) ||
                              (!_isPaginatedView && _chapterImages.isNotEmpty))
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: colors.primary,
                                inactiveTrackColor: colors.onSurfaceVariant
                                    .withValues(alpha: 0.25),
                                thumbColor: colors.primary,
                                overlayColor:
                                    colors.primary.withValues(alpha: 0.15),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: _isPaginatedView
                                    ? _currentPage
                                        .clamp(0, _chapterImages.length - 1)
                                        .toDouble()
                                    : _chapterProgress.clamp(0.0, 1.0),
                                min: 0,
                                max: _isPaginatedView
                                    ? (_chapterImages.length - 1).toDouble()
                                    : 1,
                                onChanged: _isPaginatedView
                                    ? (v) => _jumpToPage(v.round())
                                    : _jumpToChapterProgress,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  color: colors.onSurface,
                                  onPressed: () => _openAdjacentChapter(false),
                                ),
                                Text(
                                  '${(_chapterProgress * 100).round()}% • ${_chapterImages.isEmpty ? 0 : _currentPage + 1}/${_chapterImages.length}',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(_isPaginatedView
                                      ? Icons.view_agenda_rounded
                                      : Icons.view_carousel_rounded),
                                  color: colors.onSurface,
                                  onPressed: _toggleView,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next_rounded),
                                  color: colors.onSurface,
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

class _MaterializedReaderImage {
  final File file;
  final String fileName;
  final String mimeType;

  const _MaterializedReaderImage({
    required this.file,
    required this.fileName,
    required this.mimeType,
  });
}

class _ReaderImageFormat {
  final String extension;
  final String mimeType;

  const _ReaderImageFormat(this.extension, this.mimeType);
}

_ReaderImageFormat _detectReaderImageFormat(
  Uint8List bytes, {
  String? contentType,
  String? extension,
}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return const _ReaderImageFormat('jpg', 'image/jpeg');
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return const _ReaderImageFormat('png', 'image/png');
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return const _ReaderImageFormat('webp', 'image/webp');
  }
  if (bytes.length >= 6) {
    final signature = String.fromCharCodes(bytes.sublist(0, 6));
    if (signature == 'GIF87a' || signature == 'GIF89a') {
      return const _ReaderImageFormat('gif', 'image/gif');
    }
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand.contains('avif') || brand.contains('avis')) {
      return const _ReaderImageFormat('avif', 'image/avif');
    }
    if (brand.contains('heic') || brand.contains('heif')) {
      return const _ReaderImageFormat('heic', 'image/heic');
    }
  }

  final normalizedType = contentType?.toLowerCase();
  const byMime = <String, _ReaderImageFormat>{
    'image/jpeg': _ReaderImageFormat('jpg', 'image/jpeg'),
    'image/png': _ReaderImageFormat('png', 'image/png'),
    'image/webp': _ReaderImageFormat('webp', 'image/webp'),
    'image/gif': _ReaderImageFormat('gif', 'image/gif'),
    'image/avif': _ReaderImageFormat('avif', 'image/avif'),
    'image/heic': _ReaderImageFormat('heic', 'image/heic'),
  };
  if (normalizedType != null && byMime.containsKey(normalizedType)) {
    return byMime[normalizedType]!;
  }

  switch (extension?.toLowerCase()) {
    case '.jpeg':
    case '.jpg':
      return const _ReaderImageFormat('jpg', 'image/jpeg');
    case '.png':
      return const _ReaderImageFormat('png', 'image/png');
    case '.webp':
      return const _ReaderImageFormat('webp', 'image/webp');
    case '.gif':
      return const _ReaderImageFormat('gif', 'image/gif');
    case '.avif':
      return const _ReaderImageFormat('avif', 'image/avif');
    case '.heic':
    case '.heif':
      return const _ReaderImageFormat('heic', 'image/heic');
  }
  return const _ReaderImageFormat('jpg', 'image/jpeg');
}

String _safeFilePart(String value, {required String fallback}) {
  final sanitized = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (sanitized.isEmpty) return fallback;
  return sanitized.length <= 60 ? sanitized : sanitized.substring(0, 60).trim();
}
