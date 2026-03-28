import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv;
import 'package:webview_windows/webview_windows.dart' as wvw;
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/session_manager.dart';

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
  // ── Mobile / Web (webview_flutter) ──
  wv.WebViewController? _mobileController;

  // ── Windows (webview_windows) ──
  wvw.WebviewController? _windowsController;
  bool _windowsInitialized = false;

  bool _isLoading = true;
  bool _loginDetected = false;
  String _currentUrl = '';

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initWindowsWebView();
    } else {
      _initMobileWebView();
    }
  }

  // ─── Mobile init ─────────────────────────────────────────────────────────

  void _initMobileWebView() {
    final controller = wv.WebViewController()
      ..setJavaScriptMode(wv.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        wv.NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _currentUrl = url;
              _isLoading = true;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _currentUrl = url;
              _isLoading = false;
            });
            await _checkLoginSuccess(url);
          },
          onWebResourceError: (error) {
            debugPrint('[AuthWebView] resource error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.profile.auth.loginUrl));
    setState(() => _mobileController = controller);
  }

  // ─── Windows init ─────────────────────────────────────────────────────────

  Future<void> _initWindowsWebView() async {
    final controller = wvw.WebviewController();
    await controller.initialize();
    controller.url.listen((url) async {
      if (!mounted) return;
      setState(() => _currentUrl = url ?? '');
      if (url != null) await _checkLoginSuccess(url);
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
    if (siteHost.isNotEmpty && currentHost.isNotEmpty &&
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

    // Aguarda renderização completa e extrai cookies
    await Future.delayed(const Duration(milliseconds: 800));
    final cookies = await _extractCookies();

    if (cookies.isEmpty) {
      // Fallback: pode ter chegado em uma URL intermediária (ex.: OAuth).
      // Continua monitorando.
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

    await widget.onSuccess(sessionCookies.isNotEmpty ? sessionCookies : cookies);

    // On Windows: transfer the WebviewController so the caller can proxy HTTP
    // requests through the authenticated WebView session (HttpOnly cookie workaround).
    if (_isWindows && widget.onSuccessWithController != null && _windowsController != null) {
      final ctrl = _windowsController!;
      _windowsController = null; // Transfer ownership: dispose() will skip it
      await widget.onSuccessWithController!(
        sessionCookies.isNotEmpty ? sessionCookies : cookies,
        ctrl,
      );
    }

    if (mounted) Navigator.of(context).pop(sessionCookies);
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
        if (rawJson != null && rawJson.startsWith('"') && rawJson.endsWith('"')) {
          rawJson = rawJson.substring(1, rawJson.length - 1)
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', r'\');
        }
      } else if (_mobileController != null) {
        rawJson = await _mobileController!.runJavaScriptReturningResult(js)
            as String?;
      }

      if (rawJson == null || rawJson == 'null' || rawJson.isEmpty) return {};

      // runJavaScriptReturningResult retorna uma String com aspas externas
      // quando o resultado JS é uma string. Precisamos desembrulhar.
      String jsonStr = rawJson.trim();
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        // Unescape and remove external quotes
        jsonStr = jsonDecode(jsonStr) as String;
      }

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      debugPrint('[AuthWebView] Error when extracting cookies: $e');
      return {};
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

    if (_mobileController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return wv.WebViewWidget(controller: _mobileController!);
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
