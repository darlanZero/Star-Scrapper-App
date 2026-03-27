import 'package:star_scrapper_app/classes/Scrappers/engine/base_html_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// LuraToonsScrapper
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Scrapper para https://luratoons.net
///
/// Stack: Vue.js (custom) com CSS scoped (classes hasheadas ex.: .nEjte, .V7SZP).
///
/// Autenticação:
///   1. Form HTTP (recomendado):
///      ```dart
///      await scrapper.authenticateWithCredentials(email, senha);
///      ```
///      Fluxo: GET /accounts/login/ → extrai csrfmiddlewaretoken →
///             POST email+senha+csrf → extrai sessionid do Set-Cookie.
///
///   2. WebView (Google OAuth ou login visual):
///      ```dart
///      await showAuthWebView(context: ctx, profile: scrapper.scrapperProfile!, onSuccess: ...);
///      ```
///
/// Seletores confirmados por inspeção (Chrome DevTools — março 2026):
///   • Lista de obras  : a.nEjte  (o card inteiro é um <a>)
///   • Capa na lista   : img dentro de a.nEjte  (attr src; pode ser data-src em lazy)
///   • Título na lista : p dentro de a.nEjte
///   • Capa no detalhe : img.container__img
///   • Lista capítulos : div.XXfRC → a.V7SZP  (o item é um <a>)
///   • Título capítulo : .BrZpP dentro de a.V7SZP
///   • Leitor          : div.iAyij → img (src attr; 162 imgs lazy-loaded)
///
/// URLs confirmadas:
///   • Login          : /accounts/login/
///   • Google OAuth   : /accounts/google/login/?process=login
///   • Lista obras    : /todas-as-obras/
///   • Detalhe obra   : /{manga-slug}/
///   • Capítulo       : /{manga-slug}/{numero-capitulo}/
///   • Busca          : /todas-as-obras/?search={q}

class LuraToonsScrapper extends BaseHtmlScrapper {
  LuraToonsScrapper() : super(_profile);

  static const String _base = 'https://luratoons.net';

  static final ScrapperProfile _profile = ScrapperProfile(
    name: 'LuraToons',
    baseUrl: _base,
    contentType: ContentType.serverRenderedHtml,

    // ── Autenticação ──────────────────────────────────────────────────────────
    auth: AuthConfig(
      loginUrl: '$_base/accounts/login/',
      type: AuthType.djangoForm,

      // Campos do formulário django-allauth
      usernameFieldName: 'login',
      passwordFieldName: 'password',
      csrfFieldName: 'csrfmiddlewaretoken',
      csrfCookieName: 'csrftoken',

      // Sucesso quando a URL não contém mais 'login'
      successUrlFragment: '/',

      // Cookies de sessão Django
      sessionCookieNames: ['sessionid', 'csrftoken'],

      logoutUrl: '$_base/accounts/logout/',
    ),

    // ── Seletores HTML (confirmados por inspeção — março 2026) ────────────────
    //
    // Nota: LuraToons usa Vue.js com CSS scoped — as classes hasheadas
    // (.nEjte, .V7SZP, .XXfRC, .iAyij) são estáveis pois o site é custom.
    //
    // Padrão de link: o card/item INTEIRO é o elemento <a> (itemLinkSelector
    // aponta para si mesmo; o BaseHtmlScrapper faz fallback para o elemento).
    selectors: HtmlSelectorMap(
      // ── Lista de obras (/todas-as-obras/) ──
      // body como container garante que todos os cards a.nEjte sejam encontrados.
      listContainer: 'body',
      listItem: 'a.nEjte',           // o card <a> em si
      itemTitle: 'p',                 // <p> filho do card com o título
      itemTitleAttr: null,            // usa text content
      itemCoverSelector: 'img',       // <img> filho do card
      itemCoverAttr: 'src',           // atributo de URL; lazy-load pode usar data-src
      itemLinkSelector: 'a.nEjte',   // self-reference → BaseHtmlScrapper usa fallback
      itemLinkAttr: 'href',
      itemLatestChapterSelector: null, // não exibido na listagem

      // ── Detalhe de uma obra ──
      detailTitleSelector: 'h1',          // título na página de detalhe
      detailTitleAttr: null,
      detailCoverSelector: 'img.container__img', // capa principal
      detailCoverAttr: 'src',
      detailDescriptionSelector: null,    // sinopse: verificar se existe selector

      // ── Lista de capítulos (div.XXfRC → a.V7SZP) ──
      chapterListContainer: 'div.XXfRC',
      chapterItem: 'a.V7SZP',            // o item é o próprio link
      chapterTitleSelector: '.BrZpP',    // título/número do capítulo
      chapterLinkSelector: 'a.V7SZP',   // self-reference → fallback para el
      chapterLinkAttr: 'href',

      // ── Busca ──
      // URL: /todas-as-obras/?search={q}  (mesmo container da listagem)
      buildSearchUrl: (q) =>
          '$_base/todas-as-obras/?search=${Uri.encodeComponent(q)}',
      searchContainer: 'body',
      searchItem: null,               // usa listItem (a.nEjte) como fallback

      // ── Leitura de capítulo ──
      // div.iAyij contém 162 <img> lazy-loaded (src pode precisar de data-src)
      chapterImagesContainer: 'div.iAyij',
      chapterImageItem: 'img',
      chapterImageAttr: 'src',
    ),

    // ── URL builders ──────────────────────────────────────────────────────────
    //
    // LuraToons usa /{slug}/ para obras e /{manga-slug}/{cap-num}/ para capítulos.
    // extractId retorna o path completo (ex.: "deus-do-campo-de-batalha/311")
    // para que buildChapterUrl possa reconstruir a URL corretamente.
    buildDetailUrl: (id, base) => '$base/$id/',
    buildChapterUrl: (id, base) => '$base/$id/',

    // Paginação: /todas-as-obras/?page=2
    buildListUrl: (filter, page, base) {
      final pageParam = page > 0 ? '?page=${page + 1}' : '';
      return '$base/todas-as-obras/$pageParam';
    },

    // Extrai o path completo sem a trailing slash.
    // Ex.: 'https://luratoons.net/deus-do-campo-de-batalha/'
    //       → 'deus-do-campo-de-batalha'
    // Ex.: 'https://luratoons.net/deus-do-campo-de-batalha/311/'
    //       → 'deus-do-campo-de-batalha/311'
    extractId: (url) {
      try {
        final uri = Uri.parse(url);
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        return segments.join('/');
      } catch (_) {
        return url;
      }
    },
  );

  // ─── Getters públicos ─────────────────────────────────────────────────────

  /// URL para iniciar login via Google OAuth (para uso em AuthWebViewScreen).
  static const String googleLoginUrl =
      '$_base/accounts/google/login/?process=login';

  /// Retorna o [ScrapperProfile] para uso externo (ex.: AuthWebViewScreen, gallery).
  @override
  ScrapperProfile get scrapperProfile => _profile;
}
