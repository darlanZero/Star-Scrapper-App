import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/session_manager.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// BaseHtmlScrapper
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Base para scrapers de sites **server-rendered** (HTML estático).
/// Implementa o contrato [Scrapper] lendo CSS selectors de [ScrapperProfile].
///
/// Fluxo de autenticação suportado:
///   • [AuthType.djangoForm]:   GET página de login → extrai CSRF token →
///                              POST credenciais → extrai sessionid do Set-Cookie.
///   • [AuthType.genericForm]:  Mesmo fluxo, com nomes de campos configuráveis.
///   • [AuthType.webviewOAuth]: Não implementado aqui — use [AuthWebViewScreen]
///                              para obter os cookies e chame [updateSession].
///
/// Exceções lançadas:
///   'authentication_required'  → sessão expirada ou ausente.
///   'selector_not_configured'  → seletor é placeholder (TODO).
///
/// Como integrar:
///   1. Crie uma subclasse e injete o [ScrapperProfile] no construtor.
///   2. Lide com 'authentication_required' no widget/provider e navegue para
///      [AuthWebViewScreen] ou chame [authenticateWithCredentials].
///   3. Após auth via WebView, chame [updateSession(cookies)].
abstract class BaseHtmlScrapper extends Scrapper {
  final ScrapperProfile profile;

  Map<String, String> _cookies = {};
  int _currentPage = 0;
  Future<http.Response> Function(String url)? _httpGetProxy;

  BaseHtmlScrapper(this.profile);

  // ─── Identificação ────────────────────────────────────────────────────────

  String get siteKey => profile.name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  HtmlSelectorMap get _sel {
    assert(profile.selectors != null,
        'ScrapperProfile para ${profile.name} não tem HtmlSelectorMap.');
    return profile.selectors!;
  }

  // ─── Sessão ───────────────────────────────────────────────────────────────

  bool get isAuthenticated => _cookies.isNotEmpty;

  Future<void> _ensureSession() async {
    if (_cookies.isEmpty) {
      _cookies = await SessionManager.loadCookies(siteKey);
    }
  }

  /// Atualiza a sessão com cookies externos (ex.: vindos de [AuthWebViewScreen]).
  Future<void> updateSession(Map<String, String> cookies) async {
    _cookies = Map.from(cookies);
    await SessionManager.saveCookies(siteKey, _cookies);
  }

  /// Configura (ou remove, passando null) um proxy para todos os _get().
  /// Usado no Windows após OAuth via WebView quando sessionid é HttpOnly.
  void setHttpGetProxy(Future<http.Response> Function(String url)? proxy) {
    _httpGetProxy = proxy;
  }

  // ─── Protected HTTP helpers (para subclasses) ─────────────────────────────

  /// Executa GET autenticado. Usa o proxy se configurado.
  /// Destinado a subclasses que precisam fazer requisições HTTP.
  @protected
  Future<http.Response> httpGet(String url) => _get(url);

  /// Lança exceção se a resposta indicar erro de auth ou status != 200.
  @protected
  void assertAuthResponse(http.Response res) => _assertAuth(res);

  /// Efetua logout: limpa cookies locais e, opcionalmente, chama a URL de logout.
  Future<void> logout() async {
    _cookies = {};
    await SessionManager.clearSession(siteKey);
    if (profile.auth.logoutUrl != null) {
      try {
        await _get(profile.auth.logoutUrl!);
      } catch (_) {}
    }
  }

  // ─── HTTP ─────────────────────────────────────────────────────────────────

  Map<String, String> get _baseHeaders => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
    final client = http.Client();
    try {
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (maxRedirects > 0 &&
          (response.statusCode == 301 ||
           response.statusCode == 302 ||
           response.statusCode == 303)) {
        final location = response.headers['location'] ?? '';
        if (location.isEmpty) return response;
        // Auth redirect — return as-is so _assertAuth can detect it
        if (location.contains('login') || location.contains('entrar')) {
          return response;
        }
        return _get(_absoluteUrl(location), maxRedirects: maxRedirects - 1);
      }
      return response;
    } finally {
      client.close();
    }
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
    final client = http.Client();
    try {
      final streamed = await client.send(request);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  /// Retorna true se a resposta indica sessão inválida (redirect para login).
  bool _isAuthError(http.Response res) {
    if (res.statusCode == 403) return true;
    if (res.statusCode == 302 || res.statusCode == 301) {
      final location = res.headers['location'] ?? '';
      return location.contains('login') || location.contains('entrar');
    }
    if (res.statusCode == 200) {
      // Alguns sites retornam 200 com conteúdo da página de login
      return res.body.contains(profile.auth.loginUrl) &&
          res.body.length < 20000;
    }
    return false;
  }

  void _assertAuth(http.Response res) {
    if (_isAuthError(res)) throw Exception('authentication_required');
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} ao acessar ${res.request?.url}');
    }
  }

  // ─── Autenticação via HTTP (Django / form server-rendered) ────────────────

  /// Autentica usando credenciais diretamente via HTTP.
  ///
  /// Funciona para [AuthType.djangoForm] e [AuthType.genericForm]:
  ///   1. GET na página de login → extrai token CSRF do HTML.
  ///   2. POST com os campos configurados → extrai cookies de sessão.
  ///
  /// Throws [Exception] se as credenciais forem inválidas.
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    final auth = profile.auth;
    if (auth.type != AuthType.djangoForm && auth.type != AuthType.genericForm) {
      throw Exception(
        '${profile.name} usa ${auth.type} — use AuthWebViewScreen para autenticar.',
      );
    }

    // 1. GET login page → pega CSRF
    final loginPageRes = await http.get(
      Uri.parse(auth.loginUrl),
      headers: _baseHeaders,
    );
    if (loginPageRes.statusCode != 200) {
      throw Exception('Falha ao acessar página de login: ${loginPageRes.statusCode}');
    }

    // Extrai CSRF do Set-Cookie da página de login
    final setCookies = _parseSetCookieList(loginPageRes);
    final csrfFromCookie = auth.csrfCookieName != null
        ? setCookies[auth.csrfCookieName!]
        : null;

    // Extrai CSRF do HTML (campo hidden)
    String? csrfFromHtml;
    if (auth.csrfFieldName != null) {
      final doc = html_parser.parse(loginPageRes.body);
      csrfFromHtml = doc
          .querySelector('input[name="${auth.csrfFieldName}"]')
          ?.attributes['value'];
    }

    final csrfValue = csrfFromHtml ?? csrfFromCookie ?? '';

    // 2. POST credenciais
    final fields = <String, String>{
      if (auth.usernameFieldName != null) auth.usernameFieldName!: username,
      if (auth.passwordFieldName != null) auth.passwordFieldName!: password,
      if (auth.csrfFieldName != null && csrfValue.isNotEmpty)
        auth.csrfFieldName!: csrfValue,
    };

    // Django allauth exige o csrftoken no Cookie também
    final extraHeaders = <String, String>{};
    if (auth.csrfCookieName != null && csrfFromCookie != null) {
      extraHeaders['Cookie'] = '${auth.csrfCookieName!}=$csrfFromCookie';
    }

    final loginRes = await _post(
      auth.loginUrl,
      fields: fields,
      extraHeaders: extraHeaders,
    );

    // Verifica sucesso: 302 redirect para home (não para /login novamente)
    // Com followRedirects=false no _post, 200 significa que o servidor
    // devolveu a página de login novamente → credenciais inválidas.
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

    // Extrai cookies de sessão da resposta
    final sessionCookies = <String, String>{};

    // Inclui CSRF já obtido (necessário para requests subsequentes)
    if (auth.csrfCookieName != null && csrfFromCookie != null) {
      sessionCookies[auth.csrfCookieName!] = csrfFromCookie;
    }

    // Extrai cookies da resposta de login
    final loginCookies = _parseSetCookieList(loginRes);
    for (final name in auth.sessionCookieNames) {
      if (loginCookies.containsKey(name)) {
        sessionCookies[name] = loginCookies[name]!;
      }
    }

    if (sessionCookies.isEmpty) {
      throw Exception(
        'Login de ${profile.name} não retornou cookies de sessão esperados. '
        'Verifique as credenciais ou se o site mudou.',
      );
    }

    await updateSession(sessionCookies);
  }

  /// Extrai todos os valores de Set-Cookie de uma resposta HTTP.
  Map<String, String> _parseSetCookieList(http.Response res) {
    // O pacote `http` não desdobra Set-Cookie automaticamente em lista,
    // mas o header 'set-cookie' pode conter múltiplos valores separados por vírgula.
    final raw = res.headers['set-cookie'] ?? '';
    if (raw.isEmpty) return {};
    // Split cuidadoso: datas em cookies usam vírgulas (ex.: "expires=Mon, 01 Jan...")
    // então apenas splitar em '; ' e depois em ',' quando o próximo token não é espaço+número.
    final cookies = <String, String>{};
    // Tenta parsear cada cookie individualmente
    _splitSetCookieHeader(raw).forEach((cookie) {
      final parsed = SessionManager.parseCookieString(cookie.split(';').first);
      cookies.addAll(parsed);
    });
    return cookies;
  }

  List<String> _splitSetCookieHeader(String raw) {
    // Separa múltiplos Set-Cookie respeitando datas no formato "Day, DD Mon YYYY"
    final result = <String>[];
    var current = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      if (raw[i] == ',') {
        // Verifica se é início de novo cookie (próximo char não é espaço+dígito)
        final nextNonSpace = raw.indexOf(RegExp(r'\S'), i + 1);
        final next = nextNonSpace >= 0 ? raw.substring(nextNonSpace, nextNonSpace + 3) : '';
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

  // ─── HTML Parsing helpers ─────────────────────────────────────────────────

  String _text(dom.Element? el, [String? attr]) {
    if (el == null) return '';
    if (attr != null) return el.attributes[attr]?.trim() ?? '';
    return el.text.trim();
  }

  String _attr(dom.Element? el, String attr) {
    if (el == null) return '';
    return el.attributes[attr]?.trim() ?? '';
  }

  String _extractId(String url) => profile.extractId(url);

  /// Normaliza uma URL relativa para absoluta usando [profile.baseUrl].
  String _absoluteUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    final base = profile.baseUrl.endsWith('/')
        ? profile.baseUrl.substring(0, profile.baseUrl.length - 1)
        : profile.baseUrl;
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  // ─── Book list parsing ────────────────────────────────────────────────────

  List<Map<String, dynamic>> _parseBookList(dom.Document doc) {
    final s = _sel;
    final container = doc.querySelector(s.listContainer);
    if (container == null) return [];
    final items = container.querySelectorAll(s.listItem);
    return items.map((el) {
      // Fallback: se o seletor falhar (ex.: o próprio elemento é o link),
      // usa o elemento em si para extrair o atributo.
      final linkEl = el.querySelector(s.itemLinkSelector) ?? el;
      final link = _absoluteUrl(_attr(linkEl, s.itemLinkAttr));
      final id = _extractId(link);
      final coverRaw = _attr(el.querySelector(s.itemCoverSelector), s.itemCoverAttr);
      return {
        'id': id,
        'title': _text(el.querySelector(s.itemTitle), s.itemTitleAttr),
        'coverImageUrl': _absoluteUrl(coverRaw),
        'link': link,
        'latestChapter': s.itemLatestChapterSelector != null
            ? _text(el.querySelector(s.itemLatestChapterSelector!))
            : '',
        'type': 'manga',
      };
    }).where((b) => (b['id'] as String).isNotEmpty).toList();
  }

  // ─── Scrapper contract implementation ────────────────────────────────────

  @override
  Future<List<dynamic>> getAll(String filter) async {
    _currentPage = 0;
    final url = profile.buildListUrl(filter, _currentPage, profile.baseUrl);
    final res = await _get(url);
    _assertAuth(res);
    return _parseBookList(html_parser.parse(res.body));
  }

  @override
  Future<List<dynamic>> loadMore(String filter) async {
    _currentPage++;
    final url = profile.buildListUrl(filter, _currentPage, profile.baseUrl);
    final res = await _get(url);
    _assertAuth(res);
    return _parseBookList(html_parser.parse(res.body));
  }

  @override
  Future<List<dynamic>> searchTitle(String title) async {
    final url = _sel.buildSearchUrl(title);
    final res = await _get(url);
    _assertAuth(res);
    final doc = html_parser.parse(res.body);
    final s = _sel;
    final container = doc.querySelector(s.searchContainer);
    if (container == null) return [];
    final itemSel = s.searchItem ?? s.listItem;
    return container.querySelectorAll(itemSel).map((el) {
      final linkEl = el.querySelector(s.itemLinkSelector) ?? el;
      final link = _absoluteUrl(_attr(linkEl, s.itemLinkAttr));
      final coverRaw = _attr(el.querySelector(s.itemCoverSelector), s.itemCoverAttr);
      return {
        'id': _extractId(link),
        'title': _text(el.querySelector(s.itemTitle), s.itemTitleAttr),
        'coverImageUrl': _absoluteUrl(coverRaw),
        'link': link,
        'type': 'manga',
      };
    }).where((b) => (b['id'] as String).isNotEmpty).toList();
  }

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    final url = profile.buildDetailUrl(mangaID, profile.baseUrl);
    final res = await _get(url);
    _assertAuth(res);
    final doc = html_parser.parse(res.body);
    final s = _sel;

    final title = _text(doc.querySelector(s.detailTitleSelector), s.detailTitleAttr);
    final coverRaw = _attr(doc.querySelector(s.detailCoverSelector), s.detailCoverAttr);
    final description = s.detailDescriptionSelector != null
        ? _text(doc.querySelector(s.detailDescriptionSelector!))
        : '';

    final chapterContainer = doc.querySelector(s.chapterListContainer);
    final chapters = chapterContainer
            ?.querySelectorAll(s.chapterItem)
            .map((el) {
              // Fallback: caso o item seja o próprio link (ex.: <a> como chapterItem)
              final chLinkEl = el.querySelector(s.chapterLinkSelector) ?? el;
              final link = _absoluteUrl(_attr(chLinkEl, s.chapterLinkAttr));
              return {
                'id': _extractId(link),
                'title': _text(el.querySelector(s.chapterTitleSelector)),
                'link': link,
                'translatedLanguage': 'pt-br',
              };
            })
            .where((c) => (c['id'] as String).isNotEmpty)
            .toList() ??
        [];

    return {
      'id': mangaID,
      'title': title,
      'coverImageUrl': _absoluteUrl(coverRaw),
      'description': description,
      'chapters': chapters,
    };
  }

  @override
  Stream<Map<String, dynamic>> getChapter(
    String chapterID,
    String mangaID,
  ) async* {
    final url = profile.buildChapterUrl(chapterID, profile.baseUrl);
    final res = await _get(url);
    _assertAuth(res);
    final doc = html_parser.parse(res.body);
    final s = _sel;

    final container = doc.querySelector(s.chapterImagesContainer);
    final images = container
            ?.querySelectorAll(s.chapterImageItem)
            .map((el) => _absoluteUrl(_attr(el, s.chapterImageAttr)))
            .where((u) => u.isNotEmpty)
            .toList() ??
        [];

    yield {
      'chapterID': chapterID,
      // Fallback para WebView caso as imagens não sejam extraíveis via HTML
      'chapterWebviewUrl': url,
      'images': images,
    };
  }

  @override
  Stream<Map<String, dynamic>> retrieveLastChapter(
    String currentChapterId,
    String mangaId,
  ) async* {
    // Implementação padrão: reutiliza a URL do capítulo atual.
    // Override na subclasse se o site tiver link de "capítulo anterior".
    yield {
      'chapterID': currentChapterId,
      'chapterWebviewUrl': profile.buildChapterUrl(currentChapterId, profile.baseUrl),
    };
  }

  @override
  Stream<Map<String, dynamic>> retrieveNextChapter(
    String currentChapterId,
    String mangaId,
  ) async* {
    yield {
      'chapterID': currentChapterId,
      'chapterWebviewUrl': profile.buildChapterUrl(currentChapterId, profile.baseUrl),
    };
  }

  @override
  String getTitle(dynamic bookDetails) =>
      (bookDetails['title'] ?? '').toString();

  @override
  String getCoverImageUrl(dynamic bookDetails) =>
      (bookDetails['coverImageUrl'] ?? '').toString();

  @override
  String getBookId(dynamic bookDetails) =>
      (bookDetails['id'] ?? '').toString();
}
