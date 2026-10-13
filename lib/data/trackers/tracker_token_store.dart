import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';

class TrackerTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  const TrackerTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

class TrackerTokenStore {
  final FlutterSecureStorage _storage;

  const TrackerTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  String _prefix(TrackerKind kind) => 'tracker_${kind.name}_';

  Future<TrackerTokens?> read(TrackerKind kind) async {
    final prefix = _prefix(kind);
    final accessToken = await _storage.read(key: '${prefix}access_token');
    if (accessToken == null || accessToken.isEmpty) return null;
    final expiresAtRaw = await _storage.read(key: '${prefix}expires_at');
    return TrackerTokens(
      accessToken: accessToken,
      refreshToken: await _storage.read(key: '${prefix}refresh_token'),
      expiresAt: expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw),
    );
  }

  Future<void> write(TrackerKind kind, TrackerTokens tokens) async {
    final prefix = _prefix(kind);
    await _storage.write(
      key: '${prefix}access_token',
      value: tokens.accessToken,
    );
    if (tokens.refreshToken == null || tokens.refreshToken!.isEmpty) {
      await _storage.delete(key: '${prefix}refresh_token');
    } else {
      await _storage.write(
        key: '${prefix}refresh_token',
        value: tokens.refreshToken,
      );
    }
    if (tokens.expiresAt == null) {
      await _storage.delete(key: '${prefix}expires_at');
    } else {
      await _storage.write(
        key: '${prefix}expires_at',
        value: tokens.expiresAt!.toUtc().toIso8601String(),
      );
    }
  }

  Future<void> clear(TrackerKind kind) async {
    final prefix = _prefix(kind);
    await Future.wait([
      _storage.delete(key: '${prefix}access_token'),
      _storage.delete(key: '${prefix}refresh_token'),
      _storage.delete(key: '${prefix}expires_at'),
    ]);
  }
}
