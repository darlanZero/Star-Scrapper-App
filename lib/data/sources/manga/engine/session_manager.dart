import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gerencia o armazenamento e recuperação de sessões (cookies/tokens) por site.
///
/// Cada site é identificado por uma [siteKey] — string única em snake_case
/// (ex.: 'luratoons', 'mediocrescan').
///
/// Cookies e tokens são persistidos no armazenamento seguro da plataforma e
/// usados nos headers HTTP de cada request autenticado. Sessões gravadas por
/// versões antigas em [SharedPreferences] são migradas na primeira leitura.
class SessionManager {
  static const String _prefix = 'scrapper_session_';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ─── Persistência ─────────────────────────────────────────────────────────

  /// Salva o mapa de cookies para [siteKey].
  static Future<void> saveCookies(
    String siteKey,
    Map<String, String> cookies,
  ) async {
    final key = '$_prefix$siteKey';
    final encoded = jsonEncode(cookies);
    try {
      await _secureStorage.write(key: key, value: encoded);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // Keeps desktop/test environments without a secure-storage backend
      // functional. Supported mobile builds always use the secure store.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encoded);
    }
  }

  /// Carrega os cookies persistidos para [siteKey].
  /// Retorna mapa vazio se não houver sessão.
  static Future<Map<String, String>> loadCookies(String siteKey) async {
    final key = '$_prefix$siteKey';
    String? raw;
    try {
      raw = await _secureStorage.read(key: key);
    } catch (_) {
      // Fall through to the legacy store below.
    }

    final prefs = await SharedPreferences.getInstance();
    raw ??= prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final session = decoded.map((k, v) => MapEntry(k, v.toString()));
      if (prefs.containsKey(key)) {
        await saveCookies(siteKey, session);
      }
      return session;
    } catch (_) {
      return {};
    }
  }

  /// Remove a sessão de [siteKey] (equivale a logout).
  static Future<void> clearSession(String siteKey) async {
    final key = '$_prefix$siteKey';
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // The legacy entry is still removed below.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Retorna true se houver sessão salva para [siteKey].
  static Future<bool> hasSession(String siteKey) async {
    final cookies = await loadCookies(siteKey);
    return cookies.isNotEmpty;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Monta o valor do header `Cookie` a partir de um mapa de cookies.
  /// Ex.: {'sessionid': 'abc', 'csrftoken': 'xyz'} → 'sessionid=abc; csrftoken=xyz'
  static String buildCookieHeader(Map<String, String> cookies) {
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Extrai cookies relevantes dos headers `Set-Cookie` de uma resposta HTTP.
  ///
  /// [setCookieHeaders] = lista de valores do header 'set-cookie'.
  /// [cookieNames] = lista de nomes de cookies que devem ser extraídos
  ///                (ex.: ['sessionid', 'csrftoken']).
  ///
  /// Retorna mapa com apenas os cookies cujos nomes estão em [cookieNames].
  static Map<String, String> parseSetCookieHeaders(
    List<String> setCookieHeaders,
    List<String> cookieNames,
  ) {
    final result = <String, String>{};
    for (final header in setCookieHeaders) {
      // Cada header 'set-cookie' tem formato:
      // name=value; Path=/; HttpOnly; SameSite=Lax; ...
      final parts = header.split(';');
      if (parts.isEmpty) continue;
      final firstPart = parts.first.trim();
      final eqIndex = firstPart.indexOf('=');
      if (eqIndex == -1) continue;
      final name = firstPart.substring(0, eqIndex).trim();
      final value = firstPart.substring(eqIndex + 1).trim();
      if (cookieNames.contains(name)) {
        result[name] = value;
      }
    }
    return result;
  }

  /// Extrai todos os cookies de um header `Cookie` (ou de múltiplos `Set-Cookie`).
  static Map<String, String> parseCookieString(String cookieString) {
    final result = <String, String>{};
    for (final pair in cookieString.split(';')) {
      final trimmed = pair.trim();
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex == -1) continue;
      final name = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      if (name.isNotEmpty) result[name] = value;
    }
    return result;
  }
}
