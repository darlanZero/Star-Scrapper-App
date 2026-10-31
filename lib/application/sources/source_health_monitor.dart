import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';

enum FontHostStatus { unknown, checking, online, outdated }

typedef SourceReachabilityCheck = Future<bool> Function(Uri uri);

class SourceHealthEntry {
  final String id;
  final String name;
  final SourceContentType contentType;
  final Uri healthUri;
  final Uri? imageUri;

  const SourceHealthEntry({
    required this.id,
    required this.name,
    required this.contentType,
    required this.healthUri,
    required this.imageUri,
  });
}

/// Owns source availability checks, scheduling, and persisted health state.
class SourceHealthMonitor {
  static const _statusByIdKey = 'sourceHostStatusById';
  static const _legacyStatusByNameKey = 'fontHostStatusByName';

  final List<Fonte> sources;
  final List<AnimeSource> animeSources;
  final void Function() onChanged;
  final SourceReachabilityCheck _isReachable;

  Map<String, FontHostStatus> _statusById = {};
  bool _autoCheckEnabled = true;
  Duration _checkInterval = const Duration(hours: 6);
  int _lastCheckedAtMs = 0;
  Timer? _timer;
  bool _disposed = false;

  SourceHealthMonitor({
    required this.sources,
    this.animeSources = const [],
    required this.onChanged,
    SourceReachabilityCheck? isReachable,
  }) : _isReachable = isReachable ?? _defaultReachabilityCheck;

  bool get autoCheckEnabled => _autoCheckEnabled;
  Duration get checkInterval => _checkInterval;
  DateTime? get lastCheckedAt => _lastCheckedAtMs == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_lastCheckedAtMs);

  List<SourceHealthEntry> get entries => [
        for (final source in sources)
          SourceHealthEntry(
            id: source.id,
            name: source.name,
            contentType: SourceContentType.manga,
            healthUri: _resolveMangaHealthUri(source) ?? source.api.baseUri,
            imageUri: Uri.tryParse(source.image),
          ),
        for (final source in animeSources)
          SourceHealthEntry(
            id: source.id,
            name: source.name,
            contentType: SourceContentType.anime,
            healthUri: source.baseUri,
            imageUri: source.iconUri,
          ),
      ];

  Map<String, FontHostStatus> get statusesByName => {
        for (final source in entries)
          source.name: _statusById[source.id] ?? FontHostStatus.unknown,
      };

  Map<String, FontHostStatus> get statusesById => {
        for (final source in entries)
          source.id: _statusById[source.id] ?? FontHostStatus.unknown,
      };

  FontHostStatus statusForId(String sourceId) =>
      _statusById[sourceId] ?? FontHostStatus.unknown;

  FontHostStatus statusForName(String sourceName) {
    for (final source in entries) {
      if (source.name == sourceName) {
        return _statusById[source.id] ?? FontHostStatus.unknown;
      }
    }
    return FontHostStatus.unknown;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _autoCheckEnabled = prefs.getBool('fontHostAutoCheckEnabled') ?? true;
    _checkInterval = Duration(
      minutes: prefs.getInt('fontHostCheckIntervalMinutes') ?? 360,
    );
    _lastCheckedAtMs = prefs.getInt('fontHostLastCheckedAtMs') ?? 0;
    _statusById = _decodeStatuses(prefs.getString(_statusByIdKey));

    if (_statusById.isEmpty) {
      final legacyStatuses =
          _decodeStatuses(prefs.getString(_legacyStatusByNameKey));
      for (final source in entries) {
        final legacyStatus = legacyStatuses[source.name];
        if (legacyStatus != null) {
          _statusById[source.id] = legacyStatus;
        }
      }
      if (_statusById.isNotEmpty) {
        await _saveSettings();
      }
    }

    _applyStatusesToSources();
    _scheduleChecks();
    final hasUncheckedSource =
        entries.any((source) => !_statusById.containsKey(source.id));
    if (_autoCheckEnabled && hasUncheckedSource) {
      unawaited(checkAllNow());
    }
    _notifyChanged();
  }

  void setAutoCheckEnabled(bool value) {
    _autoCheckEnabled = value;
    _scheduleChecks();
    unawaited(_saveSettings());
    _notifyChanged();
  }

  void setCheckInterval(Duration interval) {
    if (interval <= Duration.zero) return;
    _checkInterval = interval;
    _scheduleChecks();
    unawaited(_saveSettings());
    _notifyChanged();
  }

  Future<void> checkAllNow() async {
    for (final source in entries) {
      _statusById[source.id] = FontHostStatus.checking;
    }
    _notifyChanged();

    for (final source in entries) {
      final isOnline = await _isReachable(source.healthUri);
      _statusById[source.id] =
          isOnline ? FontHostStatus.online : FontHostStatus.outdated;
      for (final mangaSource in sources) {
        if (mangaSource.id == source.id) mangaSource.isOutdated = !isOnline;
      }
    }

    _lastCheckedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _saveSettings();
    _notifyChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  void _scheduleChecks() {
    _timer?.cancel();
    if (!_autoCheckEnabled || _disposed) return;
    _timer = Timer.periodic(
      _checkInterval,
      (_) => unawaited(checkAllNow()),
    );
  }

  void _applyStatusesToSources() {
    for (final source in sources) {
      source.isOutdated = _statusById[source.id] == FontHostStatus.outdated;
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fontHostAutoCheckEnabled', _autoCheckEnabled);
    await prefs.setInt(
      'fontHostCheckIntervalMinutes',
      _checkInterval.inMinutes,
    );
    await prefs.setInt('fontHostLastCheckedAtMs', _lastCheckedAtMs);
    await prefs.setString(
      _statusByIdKey,
      jsonEncode(
        _statusById.map(
          (id, status) => MapEntry(id, status.name),
        ),
      ),
    );
  }

  Map<String, FontHostStatus> _decodeStatuses(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          FontHostStatus.values.firstWhere(
            (status) => status.name == value.toString(),
            orElse: () => FontHostStatus.unknown,
          ),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Uri? _resolveMangaHealthUri(Fonte source) {
    final fromBase = source.api.baseUri;
    if (fromBase.hasScheme && fromBase.host.isNotEmpty) return fromBase;

    final fromImage = Uri.tryParse(source.image);
    if (fromImage != null && fromImage.host.isNotEmpty) {
      return Uri(
        scheme: fromImage.scheme.isEmpty ? 'https' : fromImage.scheme,
        host: fromImage.host,
        path: '/',
      );
    }
    return null;
  }

  void _notifyChanged() {
    if (!_disposed) onChanged();
  }

  static Future<bool> _defaultReachabilityCheck(Uri uri) async {
    try {
      final head = await http.head(uri).timeout(const Duration(seconds: 8));
      if (head.statusCode > 0 && head.statusCode < 500) return true;
    } catch (_) {}

    try {
      final get = await http.get(uri).timeout(const Duration(seconds: 8));
      if (get.statusCode > 0 && get.statusCode < 500) return true;
    } catch (_) {}
    return false;
  }
}
