import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';

export 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';

/// Capability for sources that expose a [ScrapperProfile] so the auth WebView UI
/// and the logins settings screen can drive a login flow generically.
abstract interface class ProfileAuthMangaSource {
  ScrapperProfile get authProfile;

  /// Stable key under which the session is persisted (snake_case).
  String get sessionKey;
}

/// Base for manga sources served over authenticated HTTP (Django/generic form
/// login, cookie session). It provides the session plumbing and HTTP helpers so
/// concrete sources only implement their catalog/detail/reading logic.
///
/// It implements the auth capabilities ([CredentialAuthMangaSource],
/// [BrowserSessionMangaSource]); the content methods of [MangaSource] stay
/// abstract. Ported from the legacy `BaseHtmlScrapper`.
abstract class BaseHtmlMangaSource
    implements
        MangaSource,
        CredentialAuthMangaSource,
        BrowserSessionMangaSource,
        ProfileAuthMangaSource {
  final ScrapperProfile profile;
  final http.Client _client;

  Map<String, String> _cookies = {};
  Future<http.Response> Function(String url)? _httpGetProxy;

  BaseHtmlMangaSource(this.profile, {http.Client? client})
      : _client = client ?? http.Client();

  /// Storage key for the persisted session (snake_case).
  String get siteKey =>
      profile.name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  /// Exposes the profile so the auth WebView UI can drive a login flow.
  @override
  ScrapperProfile get authProfile => profile;

  @override
  String get sessionKey => siteKey;

  @override
  Uri get loginUri => Uri.parse(profile.auth.loginUrl);

  @override
  bool get isAuthenticated => _cookies.isNotEmpty;

  @override
  Future<void> restoreSession() => _ensureSession();

  Future<void> _ensureSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(siteKey);
    }
  }

  @override
  Future<void> updateBrowserSession(Map<String, String> cookies) async {
    _cookies = Map.from(cookies);
    await SessionManager.saveCookies(siteKey, _cookies);
  }

  @override
  Future<void> logout() async {
    _cookies = {};
    await SessionManager.clearSession(siteKey);
    if (profile.auth.logoutUrl != null) {
      try {
        await _get(profile.auth.logoutUrl!);
      } catch (_) {}
    }
  }

  /// Configures (or clears, passing null) a proxy for all authenticated GETs.
  /// Used on Windows after WebView OAuth when `sessionid` is HttpOnly.
  void setHttpGetProxy(Future<http.Response> Function(String url)? proxy) {
    _httpGetProxy = proxy;
  }

  // ─── Protected HTTP helpers ────────────────────────────────────────────────

  @protected
  Future<http.Response> httpGet(String url) => _get(url);

  @protected
  void assertAuthResponse(http.Response res) => _assertAuth(res);

  Map<String, String> get _baseHeaders => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
        'Referer': profile.baseUrl,
      };

  Map<String, String> get _authHeaders => {
        ..._baseHeaders,
        if (_cookies.isNotEmpty)
          'Cookie': SessionManager.buildCookieHeader(_cookies),
      };

  Future<http.Response> _get(String url, {int maxRedirects = 5}) async {
    if (_httpGetProxy != null) return _httpGetProxy!(url);
    await _ensureSession();
    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(_authHeaders);
    request.followRedirects = false;
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (maxRedirects > 0 &&
        (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303)) {
      final location = response.headers['location'] ?? '';
      if (location.isEmpty) return response;
      if (location.contains('login') || location.contains('entrar')) {
        return response;
      }
      return _get(_absoluteUrl(location), maxRedirects: maxRedirects - 1);
    }
    return response;
  }

  Future<http.Response> _post(
    String url, {
    required Map<String, String> fields,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = {
      ..._baseHeaders,
      'Content-Type': 'application/x-www-form-urlencoded',
      if (_cookies.isNotEmpty)
        'Cookie': SessionManager.buildCookieHeader(_cookies),
      ...?extraHeaders,
    };
    final request = http.Request('POST', Uri.parse(url));
    request.headers.addAll(headers);
    request.body = Uri(queryParameters: fields).query;
    request.followRedirects = false;
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  bool _isAuthError(http.Response res) {
    if (res.statusCode == 403) return true;
    if (res.statusCode == 302 || res.statusCode == 301) {
      final location = res.headers['location'] ?? '';
      return location.contains('login') || location.contains('entrar');
    }
    if (res.statusCode == 200) {
      return res.body.contains(profile.auth.loginUrl) && res.body.length < 20000;
    }
    return false;
  }

  void _assertAuth(http.Response res) {
    if (_isAuthError(res)) {
      throw const MangaSourceSessionRequired('authentication_required');
    }
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} ao acessar ${res.request?.url}');
    }
  }

  String _absoluteUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    final base = profile.baseUrl.endsWith('/')
        ? profile.baseUrl.substring(0, profile.baseUrl.length - 1)
        : profile.baseUrl;
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  // ─── Credential (Django / generic form) login ─────────────────────────────

  @override
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    final auth = profile.auth;
    if (auth.type != AuthType.djangoForm && auth.type != AuthType.genericForm) {
      throw Exception(
        '${profile.name} usa ${auth.type} — use a WebView para autenticar.',
      );
    }

    final loginPageRes =
        await _client.get(Uri.parse(auth.loginUrl), headers: _baseHeaders);
    if (loginPageRes.statusCode != 200) {
      throw Exception(
          'Falha ao acessar página de login: ${loginPageRes.statusCode}');
    }

    final setCookies = _parseSetCookieList(loginPageRes);
    final csrfFromCookie =
        auth.csrfCookieName != null ? setCookies[auth.csrfCookieName!] : null;

    String? csrfFromHtml;
    if (auth.csrfFieldName != null) {
      final doc = html_parser.parse(loginPageRes.body);
      csrfFromHtml = doc
          .querySelector('input[name="${auth.csrfFieldName}"]')
          ?.attributes['value'];
    }

    final csrfValue = csrfFromHtml ?? csrfFromCookie ?? '';

    final fields = <String, String>{
      if (auth.usernameFieldName != null) auth.usernameFieldName!: username,
      if (auth.passwordFieldName != null) auth.passwordFieldName!: password,
      if (auth.csrfFieldName != null && csrfValue.isNotEmpty)
        auth.csrfFieldName!: csrfValue,
    };

    final extraHeaders = <String, String>{};
    if (auth.csrfCookieName != null && csrfFromCookie != null) {
      extraHeaders['Cookie'] = '${auth.csrfCookieName!}=$csrfFromCookie';
    }

    final loginRes =
        await _post(auth.loginUrl, fields: fields, extraHeaders: extraHeaders);

    if (loginRes.statusCode == 302) {
      final location = loginRes.headers['location'] ?? '';
      if (location.contains('login') || location.contains('entrar')) {
        throw Exception('Credenciais inválidas para ${profile.name}');
      }
    } else if (loginRes.statusCode == 200) {
      throw Exception('Credenciais inválidas para ${profile.name}');
    } else {
      throw Exception('Login falhou: HTTP ${loginRes.statusCode}');
    }

    final sessionCookies = <String, String>{};
    if (auth.csrfCookieName != null && csrfFromCookie != null) {
      sessionCookies[auth.csrfCookieName!] = csrfFromCookie;
    }
    final loginCookies = _parseSetCookieList(loginRes);
    for (final cookieName in auth.sessionCookieNames) {
      if (loginCookies.containsKey(cookieName)) {
        sessionCookies[cookieName] = loginCookies[cookieName]!;
      }
    }

    if (sessionCookies.isEmpty) {
      throw Exception(
        'Login de ${profile.name} não retornou cookies de sessão esperados.',
      );
    }

    await updateBrowserSession(sessionCookies);
  }

  Map<String, String> _parseSetCookieList(http.Response res) {
    final raw = res.headers['set-cookie'] ?? '';
    if (raw.isEmpty) return {};
    final cookies = <String, String>{};
    for (final cookie in _splitSetCookieHeader(raw)) {
      cookies.addAll(SessionManager.parseCookieString(cookie.split(';').first));
    }
    return cookies;
  }

  List<String> _splitSetCookieHeader(String raw) {
    final result = <String>[];
    var current = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      if (raw[i] == ',') {
        final nextNonSpace = raw.indexOf(RegExp(r'\S'), i + 1);
        final next = nextNonSpace >= 0
            ? raw.substring(nextNonSpace, nextNonSpace + 3)
            : '';
        final isDateComma = RegExp(r'^\d{2}\s').hasMatch(next);
        if (!isDateComma) {
          result.add(current.toString().trim());
          current = StringBuffer();
          i++;
          continue;
        }
      }
      current.write(raw[i]);
      i++;
    }
    if (current.isNotEmpty) result.add(current.toString().trim());
    return result;
  }
}
