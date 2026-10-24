abstract final class TrackerBuildConfig {
  static const aniListClientName = String.fromEnvironment(
    'AnilistClientName',
    defaultValue: 'StarsLibrary',
  );

  /// Public OAuth application identifier registered for StarsLibrary.
  ///
  /// This is intentionally part of the build and must not be user-editable.
  static const aniListClientId = '53713';

  static const _aniListOAuthUrl = String.fromEnvironment('AnilistOAuthUrl');

  // Compatibility with the original local .env spelling.
  static const _legacyAniListOAuthUrl =
      String.fromEnvironment('AnilistOauhUrl');

  static const aniListRedirectUrl = String.fromEnvironment(
    'AnilistRedirectUrl',
    defaultValue: 'starslibrary://oauth/anilist',
  );

  static String get aniListOAuthUrl {
    if (_aniListOAuthUrl.isNotEmpty) return _aniListOAuthUrl;
    if (_legacyAniListOAuthUrl.isNotEmpty) return _legacyAniListOAuthUrl;
    return 'https://anilist.co/api/v2/oauth/authorize';
  }

  static const hasAniListClient = true;
}
