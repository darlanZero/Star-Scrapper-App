import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:star_scrapper_app/data/trackers/anilist_tracker_service.dart';
import 'package:star_scrapper_app/data/trackers/tracker_oauth_service.dart';

void main() {
  test('AniList implicit redirect extracts the fragment token', () {
    final service = TrackerOAuthService();

    final tokens = service.parseAniListRedirect(
      'starslibrary://oauth/anilist#access_token=token-123&expires_in=3600',
    );

    expect(tokens.accessToken, 'token-123');
    expect(tokens.expiresAt, isNotNull);
  });

  test('AniList authorization accepts only the official HTTPS host', () {
    final service = TrackerOAuthService();

    final uri = service.aniListAuthorizationUri(
      clientId: '123',
      authorizationUrl: 'https://anilist.co/api/v2/oauth/authorize',
    );

    expect(uri.queryParameters['client_id'], '123');
    expect(uri.queryParameters['response_type'], 'token');
    expect(
      () => service.aniListAuthorizationUri(
        clientId: '123',
        authorizationUrl: 'https://example.com/oauth',
      ),
      throwsA(isA<TrackerRequestException>()),
    );
  });

  test('MAL authorization uses PKCE, state and the registered redirect', () {
    final service = TrackerOAuthService();

    final session = service.createMalAuthorization(
      clientId: 'client-id',
      redirectUri: 'starslibrary://oauth/mal',
    );

    expect(session.authorizationUri.queryParameters['code_challenge'],
        session.codeVerifier);
    expect(session.authorizationUri.queryParameters['code_challenge_method'],
        'plain');
    expect(session.authorizationUri.queryParameters['state'], session.state);
    expect(session.authorizationUri.queryParameters['redirect_uri'],
        'starslibrary://oauth/mal');
  });

  test('MAL token exchange validates state and sends the verifier', () async {
    late Map<String, String> form;
    final service = TrackerOAuthService(
      client: MockClient((request) async {
        form = request.bodyFields;
        return http.Response(
          jsonEncode({
            'access_token': 'mal-access',
            'refresh_token': 'mal-refresh',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );
    final session = service.createMalAuthorization(
      clientId: 'client-id',
      redirectUri: 'starslibrary://oauth/mal',
    );

    final tokens = await service.completeMalAuthorization(
      session: session,
      redirectUrl:
          'starslibrary://oauth/mal?code=auth-code&state=${session.state}',
      clientId: 'client-id',
      redirectUri: 'starslibrary://oauth/mal',
    );

    expect(tokens.accessToken, 'mal-access');
    expect(tokens.refreshToken, 'mal-refresh');
    expect(form['code_verifier'], session.codeVerifier);
  });

  test('MAL token exchange rejects a mismatched state', () async {
    final service = TrackerOAuthService();
    final session = service.createMalAuthorization(
      clientId: 'client-id',
      redirectUri: 'starslibrary://oauth/mal',
    );

    expect(
      () => service.completeMalAuthorization(
        session: session,
        redirectUrl: 'starslibrary://oauth/mal?code=x&state=wrong',
        clientId: 'client-id',
        redirectUri: 'starslibrary://oauth/mal',
      ),
      throwsA(isA<TrackerRequestException>()),
    );
  });
}
