import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

class TrackerOAuthWebViewScreen extends StatefulWidget {
  final String providerName;
  final Uri authorizationUri;
  final String redirectUri;

  const TrackerOAuthWebViewScreen({
    super.key,
    required this.providerName,
    required this.authorizationUri,
    required this.redirectUri,
  });

  @override
  State<TrackerOAuthWebViewScreen> createState() =>
      _TrackerOAuthWebViewScreenState();
}

class _TrackerOAuthWebViewScreenState extends State<TrackerOAuthWebViewScreen> {
  mobile.WebViewController? _mobileController;
  windows.WebviewController? _windowsController;
  bool _loading = true;
  bool _finished = false;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initializeWindows();
    } else {
      _initializeMobile();
    }
  }

  void _initializeMobile() {
    final controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onNavigationRequest: (request) {
            if (_completeIfRedirect(request.url)) {
              return mobile.NavigationDecision.prevent;
            }
            return mobile.NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            _completeIfRedirect(url);
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            _completeIfRedirect(url);
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(widget.authorizationUri);
    _mobileController = controller;
  }

  Future<void> _initializeWindows() async {
    final controller = windows.WebviewController();
    await controller.initialize();
    controller.url.listen(_completeIfRedirect);
    controller.loadingState.listen((state) {
      if (!mounted) return;
      setState(() => _loading = state == windows.LoadingState.loading);
    });
    await controller.loadUrl(widget.authorizationUri.toString());
    if (!mounted) return;
    setState(() => _windowsController = controller);
  }

  bool _completeIfRedirect(String url) {
    if (_finished || !_matchesRedirect(url)) return false;
    _finished = true;
    if (mounted) Navigator.of(context).pop(url);
    return true;
  }

  bool _matchesRedirect(String url) {
    final actual = Uri.tryParse(url);
    final expected = Uri.tryParse(widget.redirectUri);
    if (actual == null || expected == null) return false;
    return actual.scheme.toLowerCase() == expected.scheme.toLowerCase() &&
        actual.host.toLowerCase() == expected.host.toLowerCase() &&
        actual.path == expected.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect ${widget.providerName}'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          MaterialBanner(
            content: Text(
              'Sign in on ${widget.providerName}. StarsLibrary never sees or stores your password.',
            ),
            actions: const [SizedBox.shrink()],
          ),
          Expanded(child: _buildWebView()),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_isWindows) {
      final controller = _windowsController;
      return controller == null
          ? const Center(child: CircularProgressIndicator())
          : windows.Webview(controller);
    }
    final controller = _mobileController;
    return controller == null
        ? const Center(child: CircularProgressIndicator())
        : mobile.WebViewWidget(controller: controller);
  }

  @override
  void dispose() {
    _windowsController?.dispose();
    super.dispose();
  }
}
