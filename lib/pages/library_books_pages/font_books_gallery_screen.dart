import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart' as wvw;
import 'package:star_scrapper_app/data/sources/manga/engine/auth_webview_screen.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/data/sources/manga/engine/base_html_manga_source.dart'
    show BaseHtmlMangaSource, ProfileAuthMangaSource;
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

class FontBooksGalleryScreen extends StatefulWidget {
  final String initialView;
  final Fonte selectedFont;
  const FontBooksGalleryScreen({
    super.key,
    required this.initialView,
    required this.selectedFont,
  });

  @override
  State<FontBooksGalleryScreen> createState() => _FontBooksGalleryScreenState();
}

class _FontBooksGalleryScreenState extends State<FontBooksGalleryScreen> {
  late MangaCatalogFilter _currentFilter;
  late Future<List<dynamic>> _bookFuture;
  late ScrollController _scrollController;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _authRequired = false;
  String? _nextCursor;
  String? _selectedGenreId;
  String? _selectedGenreName;
  MangaTaxonomyKind? _selectedTaxonomyKind;
  String? _selectedTaxonomyId;
  String? _selectedTaxonomyName;
  String? _selectedCatalogVariantId;
  String? _selectedCatalogVariantName;
  MangaSearchRequest? _catalogRequest;
  List<dynamic> allBooksData = [];

  /// Referência ao WebviewController após login WebView no Windows.
  /// Usado para limpar cookies do WebView2 e como backend do proxy HTTP.
  wvw.WebviewController? _proxyController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final filters = widget.selectedFont.api.catalogFilters;
    final requestedFilter = _filterFor(widget.initialView);
    final initialFilter = filters.contains(requestedFilter)
        ? requestedFilter
        : requestedFilter == MangaCatalogFilter.recent &&
                filters.contains(MangaCatalogFilter.updated)
            ? MangaCatalogFilter.updated
            : filters.firstOrNull ?? MangaCatalogFilter.popular;
    _currentFilter = initialFilter;
    final api = widget.selectedFont.api;
    if (api is VariantCatalogMangaSource) {
      final variants =
          (api as VariantCatalogMangaSource).catalogVariants(initialFilter);
      if (variants.isNotEmpty) {
        _selectedCatalogVariantId = variants.first.id;
        _selectedCatalogVariantName = variants.first.label;
      }
    }
    _loadBooks();
  }

  void _loadBooks() {
    setState(() {
      _authRequired = false;
      _hasMore = true;
      _isLoadingMore = false;
      _nextCursor = null;
      allBooksData = [];
      _bookFuture = _fetchBooks();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _proxyController?.dispose();
    super.dispose();
  }

  MangaCatalogFilter _filterFor(String view) {
    final normalized = view.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return switch (normalized) {
      'recent' => MangaCatalogFilter.recent,
      'latest' || 'updated' => MangaCatalogFilter.updated,
      'recentlyadded' || 'added' => MangaCatalogFilter.added,
      'trending' => MangaCatalogFilter.trending,
      'alphabetical' => MangaCatalogFilter.alphabetical,
      _ => MangaCatalogFilter.popular,
    };
  }

  String _labelFor(MangaCatalogFilter filter) =>
      widget.selectedFont.api.catalogFilterLabel(filter);

  String get _activeFilterLabel {
    final count = _catalogRequest?.activeFilterCount ?? 0;
    if (count > 0) return 'Filters ($count)';
    return _selectedTaxonomyName ?? _selectedGenreName ?? 'Filter';
  }

  IconData _iconFor(MangaCatalogFilter filter) => switch (filter) {
        MangaCatalogFilter.updated => Icons.update_rounded,
        MangaCatalogFilter.added => Icons.new_releases_outlined,
        MangaCatalogFilter.recent => Icons.schedule_rounded,
        MangaCatalogFilter.trending => Icons.trending_up_outlined,
        MangaCatalogFilter.alphabetical => Icons.sort_by_alpha_rounded,
        MangaCatalogFilter.popular => Icons.local_fire_department_outlined,
      };

  Future<List<dynamic>> _fetchBooks() async {
    final api = widget.selectedFont.api;
    // Restaura sessão persistida (cookies/tokens do SessionManager) antes de qualquer
    // request. Só para fontes com sessão de browser (ex.: MediocreScan/LuraToons).
    if (api is BrowserSessionMangaSource) {
      await (api as BrowserSessionMangaSource).restoreSession();
    }
    final page = await _browsePage(api);
    _nextCursor = page.nextCursor;
    final booksData = page.items.map((item) => item.toJson()).toList();
    setState(() => allBooksData = booksData);
    return booksData;
  }

  Future<void> _loadMoreBooks() async {
    if (_isLoadingMore || !_hasMore) return;
    if (_nextCursor == null) {
      setState(() => _hasMore = false);
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final api = widget.selectedFont.api;
      final page = await _browsePage(api, cursor: _nextCursor);
      _nextCursor = page.nextCursor;
      final moreBooksData = page.items.map((item) => item.toJson()).toList();
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        if (moreBooksData.isEmpty || _nextCursor == null) {
          _hasMore = false;
        }
        if (moreBooksData.isNotEmpty) {
          allBooksData = List.from(allBooksData)..addAll(moreBooksData);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      if (_isAuthError(e)) {
        // Sessão expirou durante paginação → redireciona para tela de login
        _loadBooks();
      }
    }
  }

  Future<MangaCatalogPage> _browsePage(
    MangaSource api, {
    String? cursor,
  }) {
    final catalogRequest = _catalogRequest;
    if (catalogRequest != null && api is FilterableMangaSource) {
      return (api as FilterableMangaSource).filterCatalog(
        catalogRequest,
        cursor: cursor,
      );
    }
    final taxonomyKind = _selectedTaxonomyKind;
    final taxonomyId = _selectedTaxonomyId;
    if (taxonomyKind != null &&
        taxonomyId != null &&
        api is TaxonomyBrowsableMangaSource) {
      return (api as TaxonomyBrowsableMangaSource).browseTaxonomy(
        taxonomyKind,
        taxonomyId,
        cursor: cursor,
      );
    }
    final genreId = _selectedGenreId;
    if (genreId != null && api is GenreBrowsableMangaSource) {
      return (api as GenreBrowsableMangaSource).browseGenre(
        genreId,
        filter: _currentFilter,
        cursor: cursor,
      );
    }
    final variantId = _selectedCatalogVariantId;
    if (variantId != null && api is VariantCatalogMangaSource) {
      return (api as VariantCatalogMangaSource).browseVariant(
        _currentFilter,
        variantId,
        cursor: cursor,
      );
    }
    return api.browse(filter: _currentFilter, cursor: cursor);
  }

  // ─── Auth helpers ──────────────────────────────────────────────────────────

  /// Detecta se um erro é de autenticação expirada/ausente.
  bool _isAuthError(Object? error) =>
      error?.toString().contains('authentication_required') ?? false;

  /// Inicia o fluxo de login adequado para o scrapper selecionado.
  void _handleLogin() {
    final api = widget.selectedFont.api;
    if (api is! ProfileAuthMangaSource) return;
    final profile = (api as ProfileAuthMangaSource).authProfile;

    final authType = profile.auth.type;

    if (authType == AuthType.djangoForm || authType == AuthType.genericForm) {
      // Oferece: formulário de credenciais OU login via WebView
      _showLoginOptions(api, profile);
    } else {
      // WebView apenas (ex.: Cloudflare Turnstile, OAuth)
      _openWebViewLogin(api, profile);
    }
  }

  /// Exibe um bottom sheet com as opções de login disponíveis para o scrapper.
  void _showLoginOptions(MangaSource api, ScrapperProfile profile) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter in ${widget.selectedFont.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to authenticate:',
                style: TextStyle(color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.email_outlined),
                label: const Text('Login with email and password'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCredentialsDialog(api);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_browser_outlined),
                label: const Text('Login via browser'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openWebViewLogin(api, profile);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Abre [AuthWebViewScreen] para login visual (form SPA, OAuth, etc.).
  Future<void> _openWebViewLogin(
      MangaSource api, ScrapperProfile profile) async {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final cookies = await showAuthWebView(
      context: context,
      profile: profile,
      onSuccess: (cookies) => api is BrowserSessionMangaSource
          ? (api as BrowserSessionMangaSource).updateBrowserSession(cookies)
          : Future.value(),
      onSuccessWithController: (cookies, controller) async {
        // Guarda referência para poder limpar cookies do WebView2 mais tarde (ex.: debug logout).
        _proxyController?.dispose();
        _proxyController = controller;

        // On Windows: se algum cookie de sessão está faltando (HttpOnly, ex.: sessionid),
        // configura proxy via WebView para manter a sessão autenticada.
        final missing = profile.auth.sessionCookieNames.any(
          (n) => !cookies.containsKey(n),
        );
        if (missing && api is BaseHtmlMangaSource) {
          final BaseHtmlMangaSource htmlApi = api;
          htmlApi.setHttpGetProxy(
            _buildWebViewProxy(
              controller,
              onDisconnect: () => htmlApi.setHttpGetProxy(null),
            ),
          );
        }
      },
    );
    if (cookies != null && cookies.isNotEmpty) {
      await fontProvider.syncReadingHistory(source: api);
      _loadBooks();
    }
  }

  /// Exibe diálogo de email + senha para form login via HTTP.
  void _showCredentialsDialog(MangaSource api) {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var loading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final email = emailCtrl.text.trim();
            final pass = passCtrl.text;
            if (email.isEmpty || pass.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Please fill in both email and password.')),
              );
              return;
            }
            setDialogState(() => loading = true);
            try {
              await (api as CredentialAuthMangaSource)
                  .authenticateWithCredentials(email, pass);
              if (mounted && ctx.mounted) {
                await Provider.of<FontProvider>(context, listen: false)
                    .syncReadingHistory(source: api);
                if (!mounted || !ctx.mounted) return;
                Navigator.pop(ctx);
                _loadBooks();
              }
            } catch (e) {
              if (!mounted || !ctx.mounted) return;
              setDialogState(() => loading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Login failed: ${e.toString().replaceAll('Exception: ', '')}'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          }

          return AlertDialog(
            title: Text('Login — ${widget.selectedFont.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !loading,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  enabled: !loading,
                  onSubmitted: (_) => loading ? null : submit(),
                ),
                if (loading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: loading ? null : submit,
                child: const Text('Login'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      emailCtrl.dispose();
      passCtrl.dispose();
    });
  }

  // ─── Debug helpers ─────────────────────────────────────────────────────────

  /// Limpa a sessão HTTP **e** o cookie store do WebView2.
  /// Usado no modo debug para testar o fluxo de login do zero.
  Future<void> _debugClearSession() async {
    final api = widget.selectedFont.api;

    // 1. Zera sessão no SharedPreferences e remove proxy HTTP.
    if (api is BrowserSessionMangaSource) {
      await (api as BrowserSessionMangaSource).logout();
    }
    if (api is BaseHtmlMangaSource) api.setHttpGetProxy(null);

    // 2. Limpa o cookie store persistente do WebView2 (Windows).
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _clearWebViewCookies();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão + cookies WebView limpos.'),
          duration: Duration(seconds: 3),
        ),
      );
      _loadBooks();
    }
  }

  /// Limpa o cookie store do WebView2.
  ///
  /// Usa [_proxyController] se disponível (já inicializado); caso contrário
  /// cria um controller temporário só para a chamada de limpeza.
  Future<void> _clearWebViewCookies() async {
    if (_proxyController != null) {
      try {
        await _proxyController!.clearCookies();
      } catch (_) {}
      _proxyController!.dispose();
      _proxyController = null;
      return;
    }

    // Nenhum controller ativo — cria um temporário.
    final ctrl = wvw.WebviewController();
    try {
      await ctrl.initialize();
      await ctrl.clearCookies();
    } catch (_) {}
    await ctrl.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          widget.selectedFont.name,
          style: TextStyle(
            color: theme.selectedTheme.textTheme.titleMedium?.color,
            fontWeight: FontWeight.bold,
            shadows: const <Shadow>[
              Shadow(color: Colors.black, blurRadius: 10.0)
            ],
          ),
        ),
        iconTheme:
            const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              tooltip: 'Limpar sessão + cookies WebView (debug)',
              onPressed: _debugClearSession,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final filter
                    in widget.selectedFont.api.catalogFilters) ...[
                  _buildButton(filter, _iconFor(filter), theme),
                  const SizedBox(width: 8),
                ],
                OutlinedButton(
                  onPressed: _showFilterPopup,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list,
                          color: theme
                              .selectedTheme.textTheme.displayMedium?.color),
                      Text(_activeFilterLabel,
                          style: TextStyle(
                              color: theme.selectedTheme.textTheme.displayMedium
                                  ?.color)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _dynamicBooksGrid(theme),
    );
  }

  Widget _buildButton(
    MangaCatalogFilter filter,
    IconData icon,
    ThemeProvider theme,
  ) {
    final api = widget.selectedFont.api;
    final variants = api is VariantCatalogMangaSource
        ? (api as VariantCatalogMangaSource).catalogVariants(filter)
        : const <MangaCatalogVariant>[];
    final baseText = _labelFor(filter);
    final text = variants.isNotEmpty &&
            _currentFilter == filter &&
            _selectedCatalogVariantName != null
        ? '$baseText · $_selectedCatalogVariantName'
        : baseText;
    final isSelected = _catalogRequest == null && _currentFilter == filter;
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: theme.selectedTheme.textTheme.displayMedium?.color),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(
              color: theme.selectedTheme.textTheme.displayMedium?.color)),
      if (variants.isNotEmpty) ...[
        const SizedBox(width: 2),
        Icon(
          Icons.arrow_drop_down_rounded,
          color: theme.selectedTheme.textTheme.displayMedium?.color,
        ),
      ],
    ]);
    final style = OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      backgroundColor: isSelected
          ? Colors.deepPurple.withValues(alpha: 0.3)
          : Colors.transparent,
    );
    if (variants.isNotEmpty) {
      return PopupMenuButton<String>(
        tooltip: 'Choose $baseText type',
        initialValue: _currentFilter == filter
            ? _selectedCatalogVariantId
            : variants.first.id,
        onSelected: (variantId) {
          final variant = variants.firstWhere((item) => item.id == variantId);
          setState(() {
            _currentFilter = filter;
            _selectedCatalogVariantId = variant.id;
            _selectedCatalogVariantName = variant.label;
            _catalogRequest = null;
            _selectedGenreId = null;
            _selectedGenreName = null;
            _selectedTaxonomyKind = null;
            _selectedTaxonomyId = null;
            _selectedTaxonomyName = null;
          });
          _loadBooks();
        },
        itemBuilder: (_) => [
          for (final variant in variants)
            PopupMenuItem(value: variant.id, child: Text(variant.label)),
        ],
        child: AbsorbPointer(
          child: OutlinedButton(
            onPressed: () {},
            style: style,
            child: content,
          ),
        ),
      );
    }
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _currentFilter = filter;
          _selectedCatalogVariantId = null;
          _selectedCatalogVariantName = null;
          _catalogRequest = null;
          _selectedGenreId = null;
          _selectedGenreName = null;
          _selectedTaxonomyKind = null;
          _selectedTaxonomyId = null;
          _selectedTaxonomyName = null;
        });
        _loadBooks();
      },
      style: style,
      child: content,
    );
  }

  Widget _dynamicBooksGrid(ThemeProvider theme) {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    return FutureBuilder<List<dynamic>>(
      future: _bookFuture,
      builder: (context, snapshot) {
        // ── Carregando ───────────────────────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // ── Erro de autenticação ─────────────────────────────────────────────
        if (snapshot.hasError && _isAuthError(snapshot.error)) {
          return _buildAuthRequiredWidget();
        }

        // ── Outros erros ────────────────────────────────────────────────────
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed: _loadBooks,
                  ),
                ],
              ),
            ),
          );
        }

        // ── Sem dados ────────────────────────────────────────────────────────
        if (!snapshot.hasData || allBooksData.isEmpty) {
          return const Center(child: Text('No data available'));
        }

        // ── Grid de livros ───────────────────────────────────────────────────
        // allBooksData é a fonte de verdade: contém página 1 (via _fetchBooks)
        // + todas as páginas adicionais (via _loadMoreBooks). Não usar snapshot.data!
        // pois o Future já completou e nunca reflete as páginas seguintes.
        final books = allBooksData;
        return Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  // Dispara loadMore quando estiver a 200px do fim (antes de bater no fundo)
                  final nearEnd = scrollInfo.metrics.pixels >=
                      scrollInfo.metrics.maxScrollExtent - 200;
                  if (nearEnd && !_isLoadingMore && _hasMore) {
                    _loadMoreBooks();
                  }
                  return false;
                },
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8.0),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                    mainAxisSpacing: 8.0,
                    crossAxisSpacing: 8.0,
                    childAspectRatio:
                        MediaQuery.of(context).size.width >= 600 ? 0.72 : 0.68,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final isFavorited = fontProvider.isFavorited(books[index]);
                    return _buildBookTile(books[index], theme, isFavorited);
                  },
                ),
              ),
            ),

            // ── Footer de paginação ──────────────────────────────────────────
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Carregando mais...',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else if (!_hasMore && books.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '— fim da lista —',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Widget exibido quando o scrapper exige login para acessar o conteúdo.
  Widget _buildAuthRequiredWidget() {
    final api = widget.selectedFont.api;
    final hasProfile = api is ProfileAuthMangaSource;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Login necessário',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Please log in to ${widget.selectedFont.name} to access the content.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 28),
            if (hasProfile)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text('Login to ${widget.selectedFont.name}'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _handleLogin,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookTile(
      dynamic bookDetails, ThemeProvider theme, bool isFavorited) {
    final api = widget.selectedFont.api;
    final book = bookDetails as Map<String, dynamic>;
    final String title = (book['title'] ?? '').toString();
    final String metadata =
        (book['latestChapter'] ?? book['subtitle'] ?? '').toString().trim();
    final String imageUrl =
        (book['coverImageUrl'] ?? book['imageurl'] ?? '').toString();
    final imageHeaders = api.coverImageHeaders;
    final String mangaId = (book['id'] ?? '').toString();
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final bool isBookFavorited = fontProvider.isFavorited(bookDetails);

    if (kDebugMode) print('image URL: $imageUrl');

    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBookFavorited
            ? BorderSide(
                color: theme.selectedTheme.primaryColor.withAlpha(190),
                width: 2,
              )
            : BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _navigateToBookDetails(mangaId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    httpHeaders: imageHeaders,
                    fit: BoxFit.cover,
                    color: isBookFavorited
                        ? Colors.black.withValues(alpha: 0.32)
                        : null,
                    colorBlendMode:
                        isBookFavorited ? BlendMode.srcOver : BlendMode.dstATop,
                    placeholder: (context, _) => ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, _, __) => ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  if (isBookFavorited)
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: Icon(Icons.favorite, color: Colors.red, size: 24),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToBookDetails(String bookId) async {
    final loadingSnackBar = SnackBar(
      content: const Row(children: [
        Text('Loading book details...'),
        SizedBox(width: 10),
        CircularProgressIndicator(),
      ]),
      duration: const Duration(minutes: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
    );

    ScaffoldMessenger.of(context).showSnackBar(loadingSnackBar);

    try {
      final bookDetails =
          (await widget.selectedFont.api.getDetails(bookId)).toJson();
      if (kDebugMode) print(bookDetails);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookDetailsScreen(
            bookDetails: bookDetails,
            scrapper: widget.selectedFont.api,
          ),
        ),
      ).then((_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Sessão expirou durante a navegação → redireciona para tela de login
      if (_isAuthError(e)) {
        setState(() => _authRequired = true);
        _loadBooks(); // re-dispara o future que vai falhar com auth_required → mostra UI
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load book details: $e'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showFilterPopup() async {
    final api = widget.selectedFont.api;
    if (api is FilterableMangaSource) {
      try {
        final options = await (api as FilterableMangaSource).getSearchOptions();
        if (!mounted) return;
        final request = await showModalBottomSheet<MangaSearchRequest>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _MangaAdvancedFilterSheet(
            options: options,
            initial: _catalogRequest,
          ),
        );
        if (!mounted || request == null) return;
        setState(() {
          _catalogRequest = request.hasFilters ? request : null;
          _selectedGenreId = null;
          _selectedGenreName = null;
          _selectedTaxonomyKind = null;
          _selectedTaxonomyId = null;
          _selectedTaxonomyName = null;
        });
        _loadBooks();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load filters: $error')),
        );
      }
      return;
    }
    if (api is TaxonomyBrowsableMangaSource) {
      final selection = await showDialog<_MangaTaxonomySelection>(
        context: context,
        builder: (_) => _MangaTaxonomyDialog(
          source: api as TaxonomyBrowsableMangaSource,
          initialKind: _selectedTaxonomyKind,
          initialId: _selectedTaxonomyId,
          initialName: _selectedTaxonomyName,
        ),
      );
      if (!mounted || selection == null) return;
      setState(() {
        _selectedTaxonomyKind = selection.id.isEmpty ? null : selection.kind;
        _selectedTaxonomyId = selection.id.isEmpty ? null : selection.id;
        _selectedTaxonomyName = selection.id.isEmpty ? null : selection.name;
        _selectedGenreId = null;
        _selectedGenreName = null;
      });
      _loadBooks();
      return;
    }
    if (api is GenreBrowsableMangaSource) {
      try {
        final genres = await (api as GenreBrowsableMangaSource).getGenres();
        if (!mounted) return;
        await _showGenreFilterPopup(genres);
        return;
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load genres: $error')),
        );
        return;
      }
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter'),
          content: SingleChildScrollView(
            child: Column(
              children: const [
                Text('Filter by:'),
                Divider(),
                Text('Genre'),
                Divider(),
                Text('Author'),
                Divider(),
                Text('Year'),
                Divider(),
                Text('Rating'),
                Divider(),
              ],
            ),
          ),
          scrollable: true,
          titleTextStyle:
              const TextStyle(color: Color.fromARGB(255, 224, 224, 224)),
          contentTextStyle:
              const TextStyle(color: Color.fromARGB(255, 224, 224, 224)),
          backgroundColor: const Color.fromARGB(255, 26, 17, 51),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10.0)),
          ),
          actionsPadding: const EdgeInsets.all(16.0),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Apply'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showGenreFilterPopup(List<MangaGenre> genres) async {
    var selectedId = _selectedGenreId;
    var selectedName = _selectedGenreName;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filter by genre'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: selectedId == null,
                    onSelected: (_) => setDialogState(() {
                      selectedId = null;
                      selectedName = null;
                    }),
                  ),
                  for (final genre in genres)
                    ChoiceChip(
                      label: Text(genre.name),
                      selected: selectedId == genre.id,
                      onSelected: (_) => setDialogState(() {
                        selectedId = genre.id;
                        selectedName = genre.name;
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() {
                  _selectedGenreId = selectedId;
                  _selectedGenreName = selectedName;
                });
                _loadBooks();
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MangaAdvancedFilterSheet extends StatefulWidget {
  final MangaSearchOptions options;
  final MangaSearchRequest? initial;

  const _MangaAdvancedFilterSheet({required this.options, this.initial});

  @override
  State<_MangaAdvancedFilterSheet> createState() =>
      _MangaAdvancedFilterSheetState();
}

class _MangaAdvancedFilterSheetState extends State<_MangaAdvancedFilterSheet> {
  late Set<String> _formats;
  late Set<String> _statuses;
  late Set<String> _tags;
  late MangaSearchSort _sort;
  late final TextEditingController _minimumController;
  late final TextEditingController _maximumController;
  final TextEditingController _tagSearchController = TextEditingController();
  String _tagQuery = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _formats = {...?initial?.formats};
    _statuses = {...?initial?.statuses};
    _tags = {...?initial?.tags};
    _sort = initial?.sort ?? MangaSearchSort.recentlyAdded;
    _minimumController = TextEditingController(
      text: initial?.minimumChapters?.toString() ?? '',
    );
    _maximumController = TextEditingController(
      text: initial?.maximumChapters?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _minimumController.dispose();
    _maximumController.dispose();
    _tagSearchController.dispose();
    super.dispose();
  }

  int? _number(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value < 0 ? null : value;
  }

  void _setChapterRange(int? minimum, int? maximum) {
    setState(() {
      _minimumController.text = minimum?.toString() ?? '';
      _maximumController.text = maximum?.toString() ?? '';
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      MangaSearchRequest(
        formats: _formats,
        statuses: _statuses,
        tags: _tags,
        minimumChapters: _number(_minimumController),
        maximumChapters: _number(_maximumController),
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTags = widget.options.tags.where((tag) {
      return _tagQuery.isEmpty ||
          tag.label.toLowerCase().contains(_tagQuery.toLowerCase());
    }).toList(growable: false);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      minChildSize: .55,
      maxChildSize: .96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Catalog filters',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, MangaSearchRequest()),
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Format', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final option in widget.options.formats)
                FilterChip(
                  label: Text(option.label),
                  selected: _formats.contains(option.value),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _formats.add(option.value)
                        : _formats.remove(option.value);
                    _tags.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Chapters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('< 50'),
                onPressed: () => _setChapterRange(null, 49),
              ),
              ActionChip(
                label: const Text('50–150'),
                onPressed: () => _setChapterRange(50, 150),
              ),
              ActionChip(
                label: const Text('150+'),
                onPressed: () => _setChapterRange(150, null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minimumController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minimum'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maximumController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Maximum'),
                ),
              ),
            ],
          ),
          if (widget.options.statuses.isNotEmpty) ...[
            const SizedBox(height: 14),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Status'),
              subtitle: Text(
                _statuses.isEmpty
                    ? 'Any status'
                    : '${_statuses.length} selected',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final option in widget.options.statuses)
                        FilterChip(
                          label: Text(option.label),
                          selected: _statuses.contains(option.value),
                          onSelected: (selected) => setState(() {
                            selected
                                ? _statuses.add(option.value)
                                : _statuses.remove(option.value);
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (widget.options.tags.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Tags'),
              subtitle: Text(
                _tags.isEmpty ? 'Any tag' : '${_tags.length} selected',
              ),
              children: [
                TextField(
                  controller: _tagSearchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Find a tag',
                  ),
                  onChanged: (value) => setState(() => _tagQuery = value),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final option in visibleTags)
                        FilterChip(
                          label: Text(option.label),
                          selected: _tags.contains(option.value),
                          onSelected: (selected) => setState(() {
                            selected
                                ? _tags.add(option.value)
                                : _tags.remove(option.value);
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          DropdownButtonFormField<MangaSearchSort>(
            initialValue: _sort,
            decoration: const InputDecoration(labelText: 'Order by'),
            items: [
              for (final sort in widget.options.sorts)
                DropdownMenuItem(
                    value: sort, child: Text(_mangaSortLabel(sort))),
            ],
            onChanged: (value) => setState(
              () => _sort = value ?? MangaSearchSort.recentlyAdded,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.filter_alt_rounded),
            label: const Text('Apply filters'),
          ),
        ],
      ),
    );
  }
}

String _mangaSortLabel(MangaSearchSort sort) => switch (sort) {
      MangaSearchSort.recentlyAdded => 'Most recent',
      MangaSearchSort.popular => 'Popular',
      MangaSearchSort.rating => 'Best rated',
      MangaSearchSort.titleAscending => 'A-Z',
      MangaSearchSort.titleDescending => 'Z-A',
      MangaSearchSort.chapterCount => 'Most chapters',
    };

class _MangaTaxonomySelection {
  final MangaTaxonomyKind kind;
  final String id;
  final String name;

  const _MangaTaxonomySelection(this.kind, this.id, this.name);
}

class _MangaTaxonomyDialog extends StatefulWidget {
  final TaxonomyBrowsableMangaSource source;
  final MangaTaxonomyKind? initialKind;
  final String? initialId;
  final String? initialName;

  const _MangaTaxonomyDialog({
    required this.source,
    this.initialKind,
    this.initialId,
    this.initialName,
  });

  @override
  State<_MangaTaxonomyDialog> createState() => _MangaTaxonomyDialogState();
}

class _MangaTaxonomyDialogState extends State<_MangaTaxonomyDialog> {
  late MangaTaxonomyKind _kind;
  late final TextEditingController _queryController;
  List<MangaTaxonomyOption> _options = const [];
  String? _selectedId;
  String? _selectedName;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? widget.source.taxonomyKinds.first;
    _selectedId = widget.initialId;
    _selectedName = widget.initialName;
    _queryController = TextEditingController();
    if (_kind == MangaTaxonomyKind.tag) _loadOptions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  String _kindLabel(MangaTaxonomyKind kind) => switch (kind) {
        MangaTaxonomyKind.tag => 'Tags',
        MangaTaxonomyKind.artist => 'Artists',
        MangaTaxonomyKind.circle => 'Circles',
      };

  void _onKindChanged(MangaTaxonomyKind? value) {
    if (value == null || value == _kind) return;
    _debounce?.cancel();
    setState(() {
      _kind = value;
      _selectedId = null;
      _selectedName = null;
      _options = const [];
      _error = null;
      _queryController.clear();
    });
    if (value == MangaTaxonomyKind.tag) _loadOptions();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    setState(() {
      _selectedId = null;
      _selectedName = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), _loadOptions);
  }

  Future<void> _loadOptions() async {
    final query = _queryController.text.trim();
    if (_kind != MangaTaxonomyKind.tag && query.length < 2) {
      setState(() {
        _options = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final options = await widget.source.getTaxonomy(_kind, query: query);
      if (!mounted || generation != _generation) return;
      setState(() => _options = options);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsQuery = _kind != MangaTaxonomyKind.tag;
    return AlertDialog(
      title: const Text('Filter HDoujin'),
      content: SizedBox(
        width: 460,
        height: 520,
        child: Column(
          children: [
            DropdownButtonFormField<MangaTaxonomyKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Filter type'),
              items: [
                for (final kind in widget.source.taxonomyKinds)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(_kindLabel(kind)),
                  ),
              ],
              onChanged: _onKindChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                labelText:
                    needsQuery ? 'Type at least 2 characters' : 'Find a tag',
                helperText: needsQuery
                    ? 'Suggestions appear as you type.'
                    : 'Tags are listed alphabetically.',
              ),
              onChanged: _onQueryChanged,
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildResults(needsQuery)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _MangaTaxonomySelection(_kind, '', ''),
          ),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.of(context).pop(
                    _MangaTaxonomySelection(
                      _kind,
                      _selectedId!,
                      _selectedName!,
                    ),
                  ),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildResults(bool needsQuery) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Could not load filters: $_error'));
    }
    if (needsQuery && _queryController.text.trim().length < 2) {
      return const Center(
        child: Text('Start typing to search this large index.'),
      );
    }
    if (_options.isEmpty) {
      return const Center(child: Text('No matching filters.'));
    }
    return ListView.builder(
      itemCount: _options.length,
      itemBuilder: (context, index) {
        final option = _options[index];
        final selected = option.id == _selectedId;
        return ListTile(
          selected: selected,
          title: Text(option.name),
          subtitle: option.titleCount == null
              ? null
              : Text('${option.titleCount} titles'),
          trailing: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
          ),
          onTap: () => setState(() {
            _selectedId = option.id;
            _selectedName = option.name;
          }),
        );
      },
    );
  }
}

/// Cria uma função de proxy HTTP que roteia requests GET através da sessão
/// autenticada do WebView (inclui cookies HttpOnly como sessionid automaticamente).
///
/// Usado no Windows após Google OAuth quando sessionid é HttpOnly e não pode
/// ser lido via document.cookie. O WebView tem a sessão válida; o fetch()
/// executado via executeScript inclui os cookies automaticamente.
Future<http.Response> Function(String url) _buildWebViewProxy(
  wvw.WebviewController controller, {
  VoidCallback? onDisconnect,
}) {
  return (String url) async {
    final encodedUrl = jsonEncode(url);
    dynamic result;
    try {
      // Usa XMLHttpRequest síncrono — executeScript não aguarda Promises,
      // portanto async/await ou fetch() retornariam {} sem o resultado real.
      result = await controller.executeScript('''
        (function() {
          try {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", $encodedUrl, false);
            xhr.withCredentials = true;
            xhr.setRequestHeader("Accept", "text/html,application/xhtml+xml,*/*;q=0.8");
            xhr.send(null);
            var finalUrl = xhr.responseURL || "";
            if (finalUrl.indexOf("/login") !== -1 || finalUrl.indexOf("/entrar") !== -1) {
              return JSON.stringify({ status: 302, location: finalUrl, body: "" });
            }
            return JSON.stringify({ status: xhr.status, location: "", body: xhr.responseText });
          } catch(e) {
            return JSON.stringify({ status: 0, location: "", body: "" });
          }
        })()
      ''');
    } catch (_) {
      // executeScript lançou (controller morto/disposed) → limpa proxy e sinaliza login
      onDisconnect?.call();
      return http.Response('', 302, headers: {'location': '/accounts/login/'});
    }

    String raw =
        result?.toString().trim() ?? '{"status":0,"location":"","body":""}';
    // webview_windows envolve strings JS em aspas externas: "\"...\""
    if (raw.startsWith('"') && raw.endsWith('"')) {
      raw = jsonDecode(raw) as String;
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final status = (data['status'] as num? ?? 0).toInt();
    final body = data['body'] as String? ?? '';
    final location = data['location'] as String? ?? '';

    if (status == 0) {
      // XHR falhou (WebView desconectado ou bloqueado) → limpa proxy e exibe login UI
      onDisconnect?.call();
      return http.Response('', 302, headers: {'location': '/accounts/login/'});
    }
    if (location.isNotEmpty) {
      return http.Response(body, status, headers: {'location': location});
    }
    return http.Response(body, status);
  };
}
