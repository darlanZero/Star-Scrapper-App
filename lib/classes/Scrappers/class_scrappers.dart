import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';

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
  String getBookId(dynamic bookDetails);

  // ─── Autenticação (opcional — implementado por scrapers protegidos) ────────

  /// Perfil de configuração do scrapper (auth, seletores, URL builders).
  /// Retorna null para scrapers que não usam [ScrapperProfile].
  ScrapperProfile? get scrapperProfile => null;

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
