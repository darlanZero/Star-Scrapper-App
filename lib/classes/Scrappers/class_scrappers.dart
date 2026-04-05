import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/session_manager.dart';

abstract class Scrapper {
  // ─── Contrato de conteúdo ─────────────────────────────────────────────────
  Future<List<dynamic>> getAll(String filter);
  Future<List<dynamic>> loadMore(String filter);
  Future<dynamic> getBookDetails(String mangaID);
  Stream<Map<String, dynamic>> getChapter(String chapterID, String mangaID);
  Stream<Map<String, dynamic>> retrieveLastChapter(String currentChapterId, String mangaId);
  Stream<Map<String, dynamic>> retrieveNextChapter(String currentChapterId, String mangaId);
  Future<List<dynamic>> searchTitle(String title);
  String getTitle(dynamic bookDetails);
  String getCoverImageUrl(dynamic bookDetails);
  Map<String, String> get imageHeaders => const {};
  String getBookId(dynamic bookDetails);

  // ─── Autenticação (opcional — implementado por scrapers protegidos) ────────

  /// Perfil de configuração do scrapper (auth, seletores, URL builders).
  /// Retorna null para scrapers que não usam [ScrapperProfile].
  ScrapperProfile? get scrapperProfile => null;

  /// Chave única de armazenamento de sessão (snake_case).
  /// Derivada automaticamente do nome do [scrapperProfile].
  /// Scrapers que precisam de chave customizada devem fazer override.
  String get siteKey =>
      scrapperProfile?.name.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_') ?? '';

  /// Indica se há uma sessão/token ativa em memória.
  /// Override nos scrapers que mantêm token em memória.
  bool get isAuthenticated => false;

  /// Verifica se há sessão persistida no disco para este scrapper.
  Future<bool> hasStoredSession() async {
    if (siteKey.isEmpty) return false;
    return SessionManager.hasSession(siteKey);
  }

  /// Restaura a sessão persistida para a memória do scrapper (se ainda não carregada).
  ///
  /// Deve ser chamado ao entrar na biblioteca do scrapper, antes de qualquer request,
  /// para garantir que tokens/cookies armazenados em [SessionManager] sejam carregados
  /// e usados nas chamadas subsequentes sem precisar de um round-trip de autenticação.
  ///
  /// Implementação padrão: no-op.
  /// Scrapers que mantêm sessão em memória (ex.: MediocreScan) devem fazer override.
  Future<void> restoreSession() async {}

  /// Autentica com credenciais diretas (email/senha) via HTTP form.
  ///
  /// Lança [UnimplementedError] para scrapers que não suportam form login.
  /// Use [showAuthWebView] quando [scrapperProfile.auth.type] for WebView.
  Future<void> authenticateWithCredentials(
    String username,
    String password,
  ) async {
    throw UnimplementedError(
      'Este scrapper não suporta login por credenciais. '
      'Use AuthWebViewScreen para autenticar.',
    );
  }

  /// Atualiza a sessão com cookies externos (ex.: extraídos de AuthWebViewScreen).
  Future<void> updateSession(Map<String, String> cookies) async {}

  /// Remove a sessão persistida e efetua logout.
  Future<void> logout() async {}
}
