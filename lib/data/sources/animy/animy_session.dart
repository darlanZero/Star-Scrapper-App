import 'package:star_scrapper_app/data/sources/manga/engine/session_manager.dart';

/// Shared authentication state used by both Animy's manga and anime sources.
///
/// Animy stores a single bearer token for the whole site (`aniume.token` in
/// the web client), so the two typed providers intentionally share one secure
/// storage entry.
class AnimySession {
  static const key = 'animy';

  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<String?> restore() async {
    if (isAuthenticated) return _token;
    final values = await SessionManager.loadCookies(key);
    _token =
        values['token'] ?? values['aniume.token'] ?? values['access_token'];
    return _token;
  }

  Future<void> save(String token) async {
    _token = token;
    await SessionManager.saveCookies(key, {'token': token});
  }

  Future<void> update(Map<String, String> values) async {
    final token = values['token'] ??
        values['aniume.token'] ??
        values['access_token'] ??
        values['Authorization']?.replaceFirst(RegExp(r'^Bearer\s+'), '');
    if (token == null || token.isEmpty) return;
    await save(token);
  }

  Future<void> clear() async {
    _token = null;
    await SessionManager.clearSession(key);
  }
}
