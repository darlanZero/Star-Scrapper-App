import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/data/trackers/anilist_tracker_service.dart';
import 'package:star_scrapper_app/data/trackers/tracker_token_store.dart';

class MalAuthorizationSession {
  final Uri authorizationUri;
  final String codeVerifier;
  final String state;

  const MalAuthorizationSession({
    required this.authorizationUri,
    required this.codeVerifier,
    required this.state,
  });
}

class TrackerOAuthService {
  static final Uri _malAuthorize =
      Uri.parse('https://myanimelist.net/v1/oauth2/authorize');
  static final Uri _malToken =
      Uri.parse('https://myanimelist.net/v1/oauth2/token');

  final http.Client _client;
  final Random _random;

  TrackerOAuthService({http.Client? client, Random? random})
      : _client = client ?? http.Client(),
        _random = random ?? Random.secure();

  Uri aniListAuthorizationUri({
    required String clientId,
    required String authorizationUrl,
  }) {
    final endpoint = Uri.tryParse(authorizationUrl);
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.toLowerCase() != 'anilist.co') {
      throw const TrackerRequestException(
        'AniList OAuth URL must use https://anilist.co.',
      );
    }
    return endpoint.replace(queryParameters: {
      'client_id': clientId.trim(),
      'response_type': 'token',
    });
  }

  TrackerTokens parseAniListRedirect(String redirectUrl) {
    final uri = Uri.parse(redirectUrl);
    final fragment = Uri.splitQueryString(uri.fragment);
    final token = fragment['access_token'];
    if (token == null || token.isEmpty) {
      final error = fragment['error_description'] ?? fragment['error'];
      throw TrackerRequestException(error ?? 'AniList login was cancelled.');
    }
    final seconds = int.tryParse(fragment['expires_in'] ?? '');
    return TrackerTokens(
      accessToken: token,
      expiresAt: seconds == null
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: seconds)),
    );
  }

  MalAuthorizationSession createMalAuthorization({
    required String clientId,
    required String redirectUri,
  }) {
    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);
    return MalAuthorizationSession(
      codeVerifier: verifier,
      state: state,
      authorizationUri: _malAuthorize.replace(queryParameters: {
        'response_type': 'code',
        'client_id': clientId.trim(),
        'redirect_uri': redirectUri.trim(),
        'code_challenge': verifier,
        'code_challenge_method': 'plain',
        'state': state,
      }),
    );
  }

  Future<TrackerTokens> completeMalAuthorization({
    required MalAuthorizationSession session,
    required String redirectUrl,
    required String clientId,
    required String redirectUri,
  }) async {
    final uri = Uri.parse(redirectUrl);
    final returnedState = uri.queryParameters['state'];
    if (returnedState != session.state) {
      throw const TrackerRequestException(
        'MyAnimeList returned an invalid OAuth state.',
      );
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw TrackerRequestException(
        uri.queryParameters['error_description'] ??
            uri.queryParameters['error'] ??
            'MyAnimeList login was cancelled.',
      );
    }
    final response = await _client.post(
      _malToken,
      headers: const {'Accept': 'application/json'},
      body: {
        'client_id': clientId.trim(),
        'code': code,
        'code_verifier': session.codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.trim(),
      },
    );
    return _parseMalTokenResponse(response);
  }

  Future<TrackerTokens> refreshMalToken({
    required String clientId,
    required String refreshToken,
  }) async {
    final response = await _client.post(
      _malToken,
      headers: const {'Accept': 'application/json'},
      body: {
        'client_id': clientId.trim(),
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    return _parseMalTokenResponse(response);
  }

  TrackerTokens _parseMalTokenResponse(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map) {
      throw TrackerRequestException(
        'MyAnimeList token request failed (${response.statusCode}).',
      );
    }
    final token = decoded['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw TrackerRequestException(
        decoded['message']?.toString() ?? 'MyAnimeList returned no token.',
      );
    }
    final seconds = (decoded['expires_in'] as num?)?.toInt();
    return TrackerTokens(
      accessToken: token,
      refreshToken: decoded['refresh_token']?.toString(),
      expiresAt: seconds == null
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: seconds)),
    );
  }

  String _randomUrlSafe(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
