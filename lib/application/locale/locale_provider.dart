import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes the user-selected application locale.
///
/// A `null` [locale] means the app follows the system locale (falling back to
/// English when the system language is unsupported).
class LocaleProvider extends ChangeNotifier {
  static const _storageKey = 'appLocale';

  Locale? _locale;

  LocaleProvider() {
    _loadLocale();
  }

  Locale? get locale => _locale;

  /// Canonical storage/UI tag: `'system'`, `'en'`, `'pt_BR'`, or `'es'`.
  String get localeTag {
    final current = _locale;
    if (current == null) return 'system';
    if (current.languageCode == 'pt') return 'pt_BR';
    return current.languageCode;
  }

  Future<void> setLocaleTag(String tag) async {
    final next = _parseTag(tag);
    if (_locale == next) return;
    _locale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, tag);
    }
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved == null || saved.isEmpty) return;
    final parsed = _parseTag(saved);
    if (parsed != _locale) {
      _locale = parsed;
      notifyListeners();
    }
  }

  static Locale? _parseTag(String tag) {
    switch (tag) {
      case 'en':
        return const Locale('en');
      case 'pt_BR':
      case 'pt-BR':
      case 'pt':
        return const Locale('pt', 'BR');
      case 'es':
        return const Locale('es');
      case 'system':
      default:
        return null;
    }
  }
}
