import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart' as wvw;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AuthWebViewScreen
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Tela de autenticação via WebView real.
///
/// Responsabilidade única: mostrar a página de login do site para o usuário
/// completar manualmente (ou via OAuth), detectar o sucesso e extrair os
/// cookies de sessão da resposta.
///
/// Funciona para:
///   • Login por formulário com CSRF / Cloudflare Turnstile (MediocreScan)
///   • OAuth (Google, Discord) — o WebView segue o redirect completo
///   • Django-allauth via Google (LuraToons)
///
/// Uso:
/// ```dart
/// final cookies = await Navigator.push<Map<String, String>>(
///   context,
///   MaterialPageRoute(
///     builder: (_) => AuthWebViewScreen(
///       profile: luratoonsScrapper.profile,
///       onSuccess: (cookies) async {
///         await luratoonsScrapper.updateSession(cookies);
///       },
///     ),
///   ),
/// );
/// ```
///
/// Detecção de sucesso:
///   A tela monitora cada navegação. Quando a URL não contém mais o padrão
///   da página de login ([AuthConfig.loginUrl] ou [AuthConfig.successUrlFragment]),
///   considera o login bem-sucedido, extrai cookies via JavaScript e fecha.
///
/// Extração de cookies:
///   • Cookies não-HttpOnly: via `document.cookie` injetado por JS.
///   • Cookies HttpOnly (ex.: Django sessionid): extraídos via
///     `_extractCookiesFromWebView` que usa uma requisição fetch() dentro
///     do contexto do WebView, capturando o header `cookie` ativo.
///   • No Windows: usa [webview_windows] com execScript.

class AuthWebViewScreen extends StatefulWidget {
  final ScrapperProfile profile;

  /// Chamado com os cookies extraídos após login bem-sucedido.
  final Future<void> Function(Map<String, String> cookies) onSuccess;

  /// (Windows only) Chamado após login com o [wvw.WebviewController], cujo
  /// ownership é transferido ao caller (não será disposed pela tela de auth).
  /// Usar para contornar cookies HttpOnly inacessíveis via JS (ex.: sessionid do Django).
  final Future<void> Function(
    Map<String, String> cookies,
    wvw.WebviewController controller,
  )? onSuccessWithController;

  const AuthWebViewScreen({
    super.key,
    required this.profile,
    required this.onSuccess,
    this.onSuccessWithController,
  });

  @override
  State<AuthWebViewScreen> createState() => _AuthWebViewScreenState();
}

class _AuthWebViewScreenState extends State<AuthWebViewScreen> {
  static const _cookieChannel = MethodChannel('starslibrary/webview_cookies');

  // ── Mobile / Web (flutter_inappwebview) ──
  iaw.InAppWebViewController? _mobileController;

  // ── Windows (webview_windows) ──
  wvw.WebviewController? _windowsController;
  bool _windowsInitialized = false;

  bool _isLoading = true;
  bool _loginDetected = false;
  bool _popupOpen = false;
  String _currentUrl = '';

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initWindowsWebView();
    }
  }

  iaw.InAppWebViewSettings get _mobileSettings => iaw.InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useHybridComposition: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 14; Mobile) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/131.0.0.0 Mobile Safari/537.36',
      );

  Future<void> _showOAuthPopup(int windowId) async {
    if (!mounted || _popupOpen) return;
    _popupOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (popupContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Continue login'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(popupContext),
            ),
          ),
          body: iaw.InAppWebView(
            windowId: windowId,
            initialSettings: _mobileSettings,
            onCloseWindow: (_) {
              if (popupContext.mounted && Navigator.canPop(popupContext)) {
                Navigator.pop(popupContext);
              }
            },
            onReceivedError: (_, request, error) {
              if (request.isForMainFrame == true) {
                debugPrint(
                  '[AuthWebView] OAuth popup error: ${error.description}',
                );
              }
            },
          ),
        ),
      ),
    );
    _popupOpen = false;
  }

  // ─── Windows init ─────────────────────────────────────────────────────────

  Future<void> _initWindowsWebView() async {
    final controller = wvw.WebviewController();
    await controller.initialize();
    controller.url.listen((url) async {
      if (!mounted) return;
      setState(() => _currentUrl = url);
      await _checkLoginSuccess(url);
    });
    controller.loadingState.listen((state) {
      if (!mounted) return;
      setState(() => _isLoading = state == wvw.LoadingState.loading);
    });
    await controller.loadUrl(widget.profile.auth.loginUrl);
    if (mounted) {
      setState(() {
        _windowsController = controller;
        _windowsInitialized = true;
      });
    }
  }

  // ─── Detecção de sucesso ──────────────────────────────────────────────────

  Future<void> _checkLoginSuccess(String url) async {
    if (_loginDetected) return;

    final loginUrl = widget.profile.auth.loginUrl;
    final successFragment = widget.profile.auth.successUrlFragment;

    // Deve estar no domínio do próprio site (não em Google/Discord/OAuth provider)
    final siteHost = Uri.tryParse(loginUrl)?.host ?? '';
    final currentHost = Uri.tryParse(url)?.host ?? '';
    if (siteHost.isNotEmpty &&
        currentHost.isNotEmpty &&
        !currentHost.endsWith(siteHost)) {
      return; // Ainda em provider externo (ex.: accounts.google.com)
    }

    // Ainda na página de login → aguarda
    if (url.contains(loginUrl) ||
        url.contains('/login') ||
        url.contains('/entrar') ||
        url.contains('accounts/login')) {
      return;
    }

    // Se successUrlFragment definido, verifica que a URL o contém
    if (successFragment != null && !url.contains(successFragment)) {
      return;
    }

    _loginDetected = true;

    // OAuth providers can finish the navigation before the SPA has written its
    // own token cookies. Poll briefly instead of leaving an authenticated page
    // open forever when the first read races that write.
    final cookies = await _waitForSessionCookies();
    if (cookies.isEmpty) {
      _loginDetected = false;
      return;
    }

    if (!await _validateCapturedSession(cookies)) {
      _loginDetected = false;
      return;
    }

    // Filtra apenas os cookies de sessão esperados
    final sessionCookieNames = widget.profile.auth.sessionCookieNames;
    final sessionCookies = sessionCookieNames.isNotEmpty
        ? Map.fromEntries(
            cookies.entries.where((e) => sessionCookieNames.contains(e.key)),
          )
        : cookies;

    // Persiste e notifica
    await SessionManager.saveCookies(
      widget.profile.name.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      sessionCookies.isNotEmpty ? sessionCookies : cookies,
    );

    await widget
        .onSuccess(sessionCookies.isNotEmpty ? sessionCookies : cookies);

    // On Windows: transfer the WebviewController so the caller can proxy HTTP
    // requests through the authenticated WebView session (HttpOnly cookie workaround).
    if (_isWindows &&
        widget.onSuccessWithController != null &&
        _windowsController != null) {
      final ctrl = _windowsController!;
      _windowsController = null; // Transfer ownership: dispose() will skip it
      await widget.onSuccessWithController!(
        sessionCookies.isNotEmpty ? sessionCookies : cookies,
        ctrl,
      );
    }

    if (mounted) Navigator.of(context).pop(sessionCookies);
  }

  Future<Map<String, String>> _waitForSessionCookies() async {
    final expected = widget.profile.auth.sessionCookieNames;
    Map<String, String> latest = const {};
    for (var attempt = 0; attempt < 20; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      latest = await _extractCookies();
      if (latest.isEmpty) continue;
      if (expected.isEmpty || latest.containsKey(expected.first)) return latest;
    }
    debugPrint(
      '[AuthWebView] Login page completed without the expected session cookies.',
    );
    return const {};
  }

  // ─── Extração de cookies ──────────────────────────────────────────────────

  /// Extrai cookies do WebView atual.
  ///
  /// Estratégia:
  ///   1. `document.cookie` → cookies não-HttpOnly.
  ///   2. fetch() do próprio domínio → o WebView envia todos os cookies
  ///      (incluindo HttpOnly) e podemos capturá-los via cabeçalho enviado.
  ///
  /// NOTA: Cookies HttpOnly não são acessíveis via JS por design de segurança.
  /// Para recuperá-los totalmente em Android, usaríamos `CookieManager` nativo.
  /// Para fins desta implementação, os cookies não-HttpOnly (csrftoken, etc.)
  /// são suficientes para sites que os utilizam. Para Django sessionid (HttpOnly),
  /// a alternativa é usar [BaseHtmlScrapper.authenticateWithCredentials] que
  /// captura o cookie direto do header Set-Cookie da resposta HTTP.
  Future<Map<String, String>> _extractCookies() async {
    final nativeCookies = await _extractNativeMobileCookies();
    try {
      const js = r'''
        (function() {
          const cookieStr = document.cookie;
          const result = {};
          if (cookieStr) {
            cookieStr.split(';').forEach(pair => {
              const idx = pair.indexOf('=');
              if (idx > 0) {
                const k = pair.substring(0, idx).trim();
                const v = pair.substring(idx + 1).trim();
                if (k) result[k] = v;
              }
            });
          }
          return JSON.stringify(result);
        })()
      ''';

      String? rawJson;

      if (_isWindows && _windowsController != null) {
        // executeScript retorna Future (dynamic) — converte para String
        final result = await _windowsController!.executeScript(js);
        rawJson = result?.toString().trim();
        if (rawJson != null &&
            rawJson.startsWith('"') &&
            rawJson.endsWith('"')) {
          rawJson = rawJson
              .substring(1, rawJson.length - 1)
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', r'\');
        }
      } else if (_mobileController != null) {
        const mobileJs = r'''
          (function() {
            const result = {};
            if (document.cookie) {
              document.cookie.split(';').forEach(pair => {
                const idx = pair.indexOf('=');
                if (idx > 0) {
                  const key = pair.substring(0, idx).trim();
                  const value = pair.substring(idx + 1).trim();
                  if (key) result[key] = value;
                }
              });
            }
            return result;
          })()
        ''';
        final result =
            await _mobileController!.evaluateJavascript(source: mobileJs);
        if (result is Map) {
          return {
            ...result.map((key, value) => MapEntry(
                  key.toString(),
                  value.toString(),
                )),
            ...nativeCookies,
          };
        }
        rawJson = result?.toString().trim();
      }

      if (rawJson == null || rawJson == 'null' || rawJson.isEmpty) {
        return nativeCookies;
      }

      // runJavaScriptReturningResult retorna uma String com aspas externas
      // quando o resultado JS é uma string. Precisamos desembrulhar.
      String jsonStr = rawJson.trim();
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        // Unescape and remove external quotes
        jsonStr = jsonDecode(jsonStr) as String;
      }

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return {
        ...decoded.map((k, v) => MapEntry(k, v.toString())),
        ...nativeCookies,
      };
    } catch (e) {
      debugPrint('[AuthWebView] Error when extracting cookies: $e');
      return nativeCookies;
    }
  }

  Future<bool> _validateCapturedSession(Map<String, String> cookies) async {
    final url = widget.profile.auth.sessionValidationUrl;
    final field = widget.profile.auth.sessionValidationJsonField;
    if (url == null || field == null) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final raw = await _cookieChannel.invokeMapMethod<String, dynamic>(
        'loadBytes',
        {
          'url': url,
          'headers': {
            'Accept': 'application/json, text/plain, */*',
            'Cookie': SessionManager.buildCookieHeader(cookies),
          },
        },
      );
      if (raw?['statusCode'] != 200 || raw?['body'] is! Uint8List) {
        return false;
      }
      final body = utf8.decode(raw!['body'] as Uint8List);
      final decoded = jsonDecode(body);
      return decoded is Map && decoded[field] == true;
    } catch (error) {
      debugPrint('[AuthWebView] Session validation failed: $error');
      return false;
    }
  }

  /// Android's CookieManager can read the complete cookie header, including
  /// HttpOnly cookies such as Django's `sessionid`. JavaScript's
  /// `document.cookie` intentionally cannot expose those cookies.
  Future<Map<String, String>> _extractNativeMobileCookies() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const {};
    }
    final currentUri = Uri.tryParse(_currentUrl);
    final baseUri = Uri.parse(widget.profile.baseUrl);
    final cookieUrls = <String>{
      if (currentUri?.hasScheme == true) _currentUrl,
      widget.profile.baseUrl,
      '${baseUri.scheme}://${baseUri.host}/',
    };
    try {
      final result = <String, String>{};
      for (final url in cookieUrls) {
        final cookies = await iaw.CookieManager.instance().getCookies(
          url: iaw.WebUri(url),
        );
        for (final cookie in cookies) {
          if (cookie.name.isNotEmpty) result[cookie.name] = cookie.value;
        }
      }
      if (result.isNotEmpty) return result;
    } catch (error) {
      debugPrint('[AuthWebView] InAppWebView cookie extraction failed: $error');
    }
    try {
      final header = await _cookieChannel.invokeMethod<String>(
            'getCookies',
            {'url': widget.profile.baseUrl},
          ) ??
          '';
      return SessionManager.parseCookieString(header);
    } on MissingPluginException {
      return const {};
    } catch (error) {
      debugPrint('[AuthWebView] Native cookie extraction failed: $error');
      return const {};
    }
  }

  // ─── Limpeza ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _windowsController?.dispose();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Entrar — ${widget.profile.name}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Banner informativo
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Enter with your ${widget.profile.name} account. '
              'After login, the session will be saved automatically.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(child: _buildWebView()),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_isWindows) {
      if (!_windowsInitialized || _windowsController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return wvw.Webview(_windowsController!);
    }

    return iaw.InAppWebView(
      initialUrlRequest: iaw.URLRequest(
        url: iaw.WebUri(widget.profile.auth.loginUrl),
      ),
      initialSettings: _mobileSettings,
      onWebViewCreated: (controller) => _mobileController = controller,
      onLoadStart: (_, url) {
        if (!mounted) return;
        setState(() {
          _currentUrl = url?.toString() ?? _currentUrl;
          _isLoading = true;
        });
      },
      onLoadStop: (_, url) async {
        final loadedUrl = url?.toString() ?? _currentUrl;
        if (mounted) {
          setState(() {
            _currentUrl = loadedUrl;
            _isLoading = false;
          });
        }
        await _checkLoginSuccess(loadedUrl);
      },
      // MediocreScan completes OAuth with React Router's history.pushState.
      // That changes /entrar to /inicio without a document load, so onLoadStop
      // is never called for the authenticated route.
      onUpdateVisitedHistory: (_, url, __) async {
        final visitedUrl = url?.toString() ?? _currentUrl;
        if (mounted) {
          setState(() {
            _currentUrl = visitedUrl;
            _isLoading = false;
          });
        }
        await _checkLoginSuccess(visitedUrl);
      },
      onCreateWindow: (_, action) async {
        unawaited(_showOAuthPopup(action.windowId));
        return true;
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true) {
          debugPrint('[AuthWebView] resource error: ${error.description}');
        }
      },
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Helper: navega para [AuthWebViewScreen] e retorna os cookies extraídos.
/// ─────────────────────────────────────────────────────────────────────────────
Future<Map<String, String>?> showAuthWebView({
  required BuildContext context,
  required ScrapperProfile profile,
  required Future<void> Function(Map<String, String> cookies) onSuccess,
  Future<void> Function(
    Map<String, String> cookies,
    wvw.WebviewController controller,
  )? onSuccessWithController,
}) {
  return Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => AuthWebViewScreen(
        profile: profile,
        onSuccess: onSuccess,
        onSuccessWithController: onSuccessWithController,
      ),
    ),
  );
}
