import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart' as wvw;
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/auth_webview_screen.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/base_html_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';
import 'package:star_scrapper_app/pages/library_books_pages/book_details_screen.dart';

class FontBooksGalleryScreen extends StatefulWidget {
  final String initialView;
  final Fonte selectedFont;
  const FontBooksGalleryScreen({
    Key? key,
    required this.initialView,
    required this.selectedFont,
  }) : super(key: key);

  @override
  State<FontBooksGalleryScreen> createState() => _FontBooksGalleryScreenState();
}

class _FontBooksGalleryScreenState extends State<FontBooksGalleryScreen> {
  late String currentView;
  late Future<List<dynamic>> _bookFuture;
  late ScrollController _scrollController;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _authRequired = false;
  List<dynamic> allBooksData = [];

  /// Referência ao WebviewController após login WebView no Windows.
  /// Usado para limpar cookies do WebView2 e como backend do proxy HTTP.
  wvw.WebviewController? _proxyController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    currentView = widget.initialView;
    _loadBooks();
  }

  void _loadBooks() {
    setState(() {
      _authRequired = false;
      _hasMore = true;
      _bookFuture = _fetchBooks();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _proxyController?.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetchBooks() async {
    final api = widget.selectedFont.api;
    // Restaura sessão persistida (cookies/tokens do SessionManager) antes de qualquer
    // request. No-op para scrapers que não usam SessionManager (ex.: Luratoons via WebView).
    await api.restoreSession();
    final booksData = await api.getAll(currentView);
    setState(() => allBooksData = booksData);
    return booksData;
  }

  Future<void> _loadMoreBooks() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final api = widget.selectedFont.api;
      final moreBooksData = await api.loadMore(currentView);
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        if (moreBooksData.isEmpty) {
          // Scrapper retornou lista vazia → chegamos na última página
          _hasMore = false;
        } else {
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

  // ─── Auth helpers ──────────────────────────────────────────────────────────

  /// Detecta se um erro é de autenticação expirada/ausente.
  bool _isAuthError(Object? error) =>
      error?.toString().contains('authentication_required') ?? false;

  /// Inicia o fluxo de login adequado para o scrapper selecionado.
  void _handleLogin() {
    final api = widget.selectedFont.api;
    final profile = api.scrapperProfile;
    if (profile == null) return;

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
  void _showLoginOptions(Scrapper api, ScrapperProfile profile) {
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
  Future<void> _openWebViewLogin(Scrapper api, ScrapperProfile profile) async {
    final cookies = await showAuthWebView(
      context: context,
      profile: profile,
      onSuccess: (cookies) => api.updateSession(cookies),
      onSuccessWithController: (cookies, controller) async {
        // Guarda referência para poder limpar cookies do WebView2 mais tarde (ex.: debug logout).
        _proxyController?.dispose();
        _proxyController = controller;

        // On Windows: se algum cookie de sessão está faltando (HttpOnly, ex.: sessionid),
        // configura proxy via WebView para manter a sessão autenticada.
        final missing = profile.auth.sessionCookieNames.any(
          (n) => !cookies.containsKey(n),
        );
        if (missing && api is BaseHtmlScrapper) {
          api.setHttpGetProxy(
            _buildWebViewProxy(
              controller,
              onDisconnect: () => api.setHttpGetProxy(null),
            ),
          );
        }
      },
    );
    if (cookies != null && cookies.isNotEmpty) {
      _loadBooks();
    }
  }

  /// Exibe diálogo de email + senha para form login via HTTP.
  void _showCredentialsDialog(Scrapper api) {
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
                const SnackBar(content: Text('Please fill in both email and password.')),
              );
              return;
            }
            setDialogState(() => loading = true);
            try {
              await api.authenticateWithCredentials(email, pass);
              if (mounted) {
                Navigator.pop(ctx);
                _loadBooks();
              }
            } catch (e) {
              setDialogState(() => loading = false);
              if (mounted) {
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
    await api.logout();
    if (api is BaseHtmlScrapper) api.setHttpGetProxy(null);

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
            shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 10.0)],
          ),
        ),
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),
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
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildButton('Popular', Icons.trending_up_outlined, theme),
                _buildButton('Recent', Icons.new_releases_outlined, theme),
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
                          color: theme.selectedTheme.textTheme.displayMedium?.color),
                      Text('Filter',
                          style: TextStyle(
                              color: theme.selectedTheme.textTheme.displayMedium?.color)),
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

  Widget _buildButton(String text, IconData icon, ThemeProvider theme) {
    bool isSelected = currentView.toLowerCase() == text.toLowerCase();
    return OutlinedButton(
      onPressed: () {
        setState(() {
          currentView = text;
          _loadBooks();
        });
      },
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        backgroundColor:
            isSelected ? Colors.deepPurple.withOpacity(0.3) : Colors.transparent,
      ),
      child: Row(children: [
        Icon(icon, color: theme.selectedTheme.textTheme.displayMedium?.color),
        Text(text,
            style: TextStyle(
                color: theme.selectedTheme.textTheme.displayMedium?.color)),
      ]),
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
                    crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                    mainAxisSpacing: 8.0,
                    crossAxisSpacing: 8.0,
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
                    Text('Carregando mais...', style: TextStyle(color: Colors.grey)),
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
    final hasProfile = api.scrapperProfile != null;

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

  Widget _buildBookTile(dynamic bookDetails, ThemeProvider theme, bool isFavorited) {
    final api = widget.selectedFont.api;
    final String title = api.getTitle(bookDetails);
    final String imageUrl = api.getCoverImageUrl(bookDetails);
    final String mangaId = api.getBookId(bookDetails);
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final bool isBookFavorited = fontProvider.isFavorited(bookDetails);

    if (kDebugMode) print('image URL: $imageUrl');

    return InkWell(
      onTap: () => _navigateToBookDetails(mangaId),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.0),
          border: isBookFavorited
              ? Border.all(
                  color: theme.selectedTheme.primaryColor.withAlpha(150),
                  width: 2.0,
                )
              : null,
        ),
        child: GridTile(
          footer: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8.0),
              bottomRight: Radius.circular(8.0),
            ),
            child: Container(
              color: Colors.black.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Image.network(
                  imageUrl,
                  color: isBookFavorited ? Colors.black.withOpacity(0.5) : null,
                  colorBlendMode:
                      isBookFavorited ? BlendMode.srcOver : BlendMode.dstATop,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.network(
                      'https://via.placeholder.com/150',
                      fit: BoxFit.cover,
                    );
                  },
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width,
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
      final bookDetails = await widget.selectedFont.api.getBookDetails(bookId);
      if (kDebugMode) print(bookDetails);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookDetailsScreen(
            bookDetails: bookDetails,
            scrapper: widget.selectedFont.api,
          ),
        ),
      ).then((_) => setState(() {}));
    } catch (e) {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showFilterPopup() {
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
          titleTextStyle: const TextStyle(color: Color.fromARGB(255, 224, 224, 224)),
          contentTextStyle: const TextStyle(color: Color.fromARGB(255, 224, 224, 224)),
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

    String raw = result?.toString().trim() ?? '{"status":0,"location":"","body":""}';
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
