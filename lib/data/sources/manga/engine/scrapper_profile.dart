/// ─────────────────────────────────────────────────────────────────────────────
/// Scrapper Profile — configuração declarativa de uma fonte de mangá
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Como usar:
///   1. Defina um [ScrapperProfile] para o site com [AuthConfig] e [HtmlSelectorMap].
///   2. Passe-o para [BaseHtmlScrapper] (sites server-rendered) ou
///      [BaseWebViewScrapper] (sites SPA/Cloudflare).
///   3. Para fontes API puras (ex.: MangaDex), continue implementando [Scrapper]
///      diretamente — o perfil declarativo é opcional nesses casos.
///
/// Tipos de auth suportados:
///   [AuthType.none]         → acesso público, sem login.
///   [AuthType.djangoForm]   → Django-allauth: GET csrf → POST creds → sessionid.
///   [AuthType.genericForm]  → Formulário HTML genérico server-rendered.
///   [AuthType.webviewOAuth] → OAuth (Google, Discord, etc.) via WebView.
///   [AuthType.webviewForm]  → Formulário React/SPA que exige WebView (Cloudflare/Turnstile).
library;

// ─── Tipos de autenticação ───────────────────────────────────────────────────

enum AuthType {
  none,
  djangoForm,
  genericForm,
  webviewOAuth,
  webviewForm,
}

// ─── Tipos de conteúdo ───────────────────────────────────────────────────────

enum ContentType {
  /// HTML renderizado no servidor — HTTP + CSS selectors.
  serverRenderedHtml,

  /// SPA (React/Next.js) — conteúdo carregado via JS.
  /// Requer WebView + injeção de JS para extração de dados.
  spa,
}

// ─── Configuração de autenticação ────────────────────────────────────────────

class AuthConfig {
  /// URL da página de login.
  final String loginUrl;

  /// Tipo do fluxo de autenticação.
  final AuthType type;

  // ── Form-based (djangoForm / genericForm) ──

  /// Nome do campo de usuário/email no formulário HTML.
  final String? usernameFieldName;

  /// Nome do campo de senha no formulário HTML.
  final String? passwordFieldName;

  /// Nome do campo CSRF no formulário (ex.: 'csrfmiddlewaretoken' no Django).
  final String? csrfFieldName;

  /// Nome do cookie CSRF a extrair da resposta (ex.: 'csrftoken' no Django).
  final String? csrfCookieName;

  // ── WebView (webviewOAuth / webviewForm) ──

  /// Fragmento de URL que indica login bem-sucedido no WebView.
  /// Ex.: '/' significa que ao chegar na home, o login foi concluído.
  final String? successUrlFragment;

  // ── Session ──

  /// Nomes dos cookies que compõem a sessão autenticada.
  /// Ex.: ['sessionid', 'csrftoken'] para Django.
  final List<String> sessionCookieNames;

  /// URL de logout, para invalidar a sessão remotamente.
  final String? logoutUrl;

  const AuthConfig({
    required this.loginUrl,
    required this.type,
    this.usernameFieldName,
    this.passwordFieldName,
    this.csrfFieldName,
    this.csrfCookieName,
    this.successUrlFragment,
    required this.sessionCookieNames,
    this.logoutUrl,
  });
}

// ─── Mapa de seletores CSS ───────────────────────────────────────────────────

/// Define os CSS selectors para cada operação do contrato [Scrapper].
/// Todos os seletores devem funcionar com [querySelector] / [querySelectorAll]
/// do pacote `html`.
class HtmlSelectorMap {
  // ── getAll / loadMore — listagem de obras ──

  /// Container que envolve todos os cards de obras.
  final String listContainer;

  /// Seletor de cada card individual dentro de [listContainer].
  final String listItem;

  /// Seletor do título dentro de um card.
  final String itemTitle;

  /// Atributo que contém o texto do título (null = text content do elemento).
  final String? itemTitleAttr;

  /// Seletor da imagem de capa dentro de um card.
  final String itemCoverSelector;

  /// Atributo da imagem que contém a URL (ex.: 'src', 'data-src', 'data-lazy').
  final String itemCoverAttr;

  /// Seletor do link do card (elemento <a>).
  final String itemLinkSelector;

  /// Atributo do link com a URL (geralmente 'href').
  final String itemLinkAttr;

  /// Seletor do último capítulo dentro de um card (opcional).
  final String? itemLatestChapterSelector;

  // ── getBookDetails — detalhes de uma obra ──

  final String detailTitleSelector;
  final String? detailTitleAttr;
  final String detailCoverSelector;
  final String detailCoverAttr;
  final String? detailDescriptionSelector;

  /// Container da lista de capítulos na página de detalhes.
  final String chapterListContainer;

  /// Seletor de cada item de capítulo dentro de [chapterListContainer].
  final String chapterItem;

  /// Seletor do título do capítulo dentro de um item.
  final String chapterTitleSelector;

  /// Seletor do link do capítulo (elemento <a>).
  final String chapterLinkSelector;

  /// Atributo do link com a URL do capítulo (geralmente 'href').
  final String chapterLinkAttr;

  // ── searchTitle — busca ──

  /// Função que recebe a query e retorna a URL de busca completa.
  /// Ex.: (q) => 'https://site.com/search?q=${Uri.encodeComponent(q)}'
  final String Function(String query) buildSearchUrl;

  /// Container dos resultados de busca.
  final String searchContainer;

  /// Seletor de cada resultado de busca dentro de [searchContainer].
  /// null = usa [listItem] como fallback.
  final String? searchItem;

  // ── getChapter — leitura de capítulo ──

  /// Container das imagens do capítulo.
  final String chapterImagesContainer;

  /// Seletor de cada imagem dentro de [chapterImagesContainer].
  final String chapterImageItem;

  /// Atributo com a URL da imagem (ex.: 'src', 'data-src').
  final String chapterImageAttr;

  const HtmlSelectorMap({
    required this.listContainer,
    required this.listItem,
    required this.itemTitle,
    this.itemTitleAttr,
    required this.itemCoverSelector,
    required this.itemCoverAttr,
    required this.itemLinkSelector,
    required this.itemLinkAttr,
    this.itemLatestChapterSelector,
    required this.detailTitleSelector,
    this.detailTitleAttr,
    required this.detailCoverSelector,
    required this.detailCoverAttr,
    this.detailDescriptionSelector,
    required this.chapterListContainer,
    required this.chapterItem,
    required this.chapterTitleSelector,
    required this.chapterLinkSelector,
    required this.chapterLinkAttr,
    required this.buildSearchUrl,
    required this.searchContainer,
    this.searchItem,
    required this.chapterImagesContainer,
    required this.chapterImageItem,
    required this.chapterImageAttr,
  });
}

// ─── Perfil completo de um scrapper ─────────────────────────────────────────

class ScrapperProfile {
  /// Nome legível da fonte (ex.: 'LuraToons').
  final String name;

  /// URL base do site (ex.: 'https://luratoons.net').
  final String baseUrl;

  /// Tipo de conteúdo do site.
  final ContentType contentType;

  /// Configuração de autenticação.
  final AuthConfig auth;

  /// Mapa de seletores HTML (null para fontes API puras ou SPA).
  final HtmlSelectorMap? selectors;

  /// Constrói a URL de detalhes de uma obra a partir do seu ID.
  /// Ex.: (id, base) => '$base/obra/$id/'
  final String Function(String id, String baseUrl) buildDetailUrl;

  /// Constrói a URL de um capítulo a partir do seu ID.
  final String Function(String id, String baseUrl) buildChapterUrl;

  /// Constrói a URL de listagem paginada.
  /// [page] começa em 0 (primeira página).
  final String Function(String filter, int page, String baseUrl) buildListUrl;

  /// Extrai o ID de uma URL completa.
  /// Ex.: 'https://site.com/obra/my-hero-academia/' → 'my-hero-academia'
  final String Function(String url) extractId;

  const ScrapperProfile({
    required this.name,
    required this.baseUrl,
    required this.contentType,
    required this.auth,
    this.selectors,
    required this.buildDetailUrl,
    required this.buildChapterUrl,
    required this.buildListUrl,
    required this.extractId,
  });
}
