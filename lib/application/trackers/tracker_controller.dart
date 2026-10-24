import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/data/trackers/anilist_tracker_service.dart';
import 'package:star_scrapper_app/data/trackers/mal_tracker_service.dart';
import 'package:star_scrapper_app/data/trackers/tracker_oauth_service.dart';
import 'package:star_scrapper_app/data/trackers/tracker_token_store.dart';
import 'package:star_scrapper_app/classes/config/tracker_build_config.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';

class TrackerController extends ChangeNotifier {
  static const _aniListEnabledKey = 'tracker_anilist_enabled';
  static const _malEnabledKey = 'tracker_mal_enabled';
  static const _includeAdultKey = 'tracker_include_adult';
  static const _preferEnglishTitlesKey = 'tracker_prefer_english_titles';
  static const _malClientIdKey = 'tracker_mal_client_id';
  static const _aniListClientIdKey = 'tracker_anilist_client_id';
  static const _aniListRedirectUriKey = 'tracker_anilist_redirect_uri';
  static const _malRedirectUriKey = 'tracker_mal_redirect_uri';

  final TrackerTokenStore _tokenStore;
  final TrackerOAuthService _oauthService;

  bool _aniListEnabled = true;
  bool _malEnabled = false;
  bool _includeAdult = false;
  bool _preferEnglishTitles = false;
  String _malClientId = '';
  String _aniListClientId = TrackerBuildConfig.aniListClientId;
  String _aniListRedirectUri = TrackerBuildConfig.aniListRedirectUrl;
  String _malRedirectUri = 'starslibrary://oauth/mal';
  TrackerTokens? _aniListTokens;
  TrackerTokens? _malTokens;
  TrackerAccount? _aniListAccount;
  TrackerAccount? _malAccount;
  bool _authBusy = false;
  String? _authError;
  bool _initialized = false;

  TrackerController({
    TrackerTokenStore tokenStore = const TrackerTokenStore(),
    TrackerOAuthService? oauthService,
  })  : _tokenStore = tokenStore,
        _oauthService = oauthService ?? TrackerOAuthService();

  bool get aniListEnabled => _aniListEnabled;
  bool get malEnabled => _malEnabled;
  bool get includeAdult => _includeAdult;
  bool get preferEnglishTitles => _preferEnglishTitles;
  String get malClientId => _malClientId;
  String get aniListClientId => _aniListClientId;
  String get aniListClientName => TrackerBuildConfig.aniListClientName;
  bool get aniListConfigurationManaged => TrackerBuildConfig.hasAniListClient;
  String get aniListRedirectUri => _aniListRedirectUri;
  String get malRedirectUri => _malRedirectUri;
  TrackerAccount? get aniListAccount => _aniListAccount;
  TrackerAccount? get malAccount => _malAccount;
  bool get aniListConnected => _aniListTokens != null;
  bool get malConnected => _malTokens != null;
  bool get authBusy => _authBusy;
  String? get authError => _authError;
  bool get initialized => _initialized;
  bool get hasEnabledTracker => _aniListEnabled || _malEnabled;
  String? get connectedUsername =>
      _aniListAccount?.username ?? _malAccount?.username;

  int get connectedTrackerCount =>
      (_aniListConnectedAndEnabled ? 1 : 0) + (_malConnectedAndEnabled ? 1 : 0);

  bool get _aniListConnectedAndEnabled =>
      _aniListEnabled && _aniListTokens != null && _aniListAccount != null;
  bool get _malConnectedAndEnabled =>
      _malEnabled && _malTokens != null && _malAccount != null;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _aniListEnabled = prefs.getBool(_aniListEnabledKey) ?? true;
    _malEnabled = prefs.getBool(_malEnabledKey) ?? false;
    _includeAdult = prefs.getBool(_includeAdultKey) ?? false;
    _preferEnglishTitles = prefs.getBool(_preferEnglishTitlesKey) ?? false;
    _malClientId = prefs.getString(_malClientIdKey) ?? '';
    _aniListClientId = TrackerBuildConfig.hasAniListClient
        ? TrackerBuildConfig.aniListClientId
        : prefs.getString(_aniListClientIdKey) ?? '';
    _aniListRedirectUri = TrackerBuildConfig.hasAniListClient
        ? TrackerBuildConfig.aniListRedirectUrl
        : prefs.getString(_aniListRedirectUriKey) ??
            'starslibrary://oauth/anilist';
    _malRedirectUri =
        prefs.getString(_malRedirectUriKey) ?? 'starslibrary://oauth/mal';
    if (_malClientId.isEmpty) _malEnabled = false;
    _aniListTokens = await _tokenStore.read(TrackerKind.aniList);
    _malTokens = await _tokenStore.read(TrackerKind.myAnimeList);
    await _refreshAccounts();
    _initialized = true;
    notifyListeners();
  }

  Future<void> setAniListEnabled(bool value) async {
    _aniListEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aniListEnabledKey, value);
    notifyListeners();
  }

  Future<void> setMalEnabled(bool value) async {
    _malEnabled = value && _malClientId.isNotEmpty;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_malEnabledKey, _malEnabled);
    notifyListeners();
  }

  Future<void> setIncludeAdult(bool value) async {
    _includeAdult = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_includeAdultKey, value);
    notifyListeners();
  }

  Future<void> setPreferEnglishTitles(bool value) async {
    _preferEnglishTitles = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferEnglishTitlesKey, value);
    notifyListeners();
  }

  String displayTitle(TrackerMedia media) =>
      media.title.display(preferEnglish: _preferEnglishTitles);

  Future<void> setMalClientId(String value) async {
    _malClientId = value.trim();
    if (_malClientId.isEmpty) _malEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_malClientIdKey, _malClientId);
    await prefs.setBool(_malEnabledKey, _malEnabled);
    notifyListeners();
  }

  Future<void> setOAuthConfiguration({
    required String aniListClientId,
    required String aniListRedirectUri,
    required String malClientId,
    required String malRedirectUri,
  }) async {
    if (!TrackerBuildConfig.hasAniListClient) {
      _aniListClientId = aniListClientId.trim();
      _aniListRedirectUri = aniListRedirectUri.trim();
    }
    _malClientId = malClientId.trim();
    _malRedirectUri = malRedirectUri.trim();
    if (_malClientId.isEmpty) _malEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      if (!TrackerBuildConfig.hasAniListClient)
        prefs.setString(_aniListClientIdKey, _aniListClientId),
      if (!TrackerBuildConfig.hasAniListClient)
        prefs.setString(_aniListRedirectUriKey, _aniListRedirectUri),
      prefs.setString(_malClientIdKey, _malClientId),
      prefs.setString(_malRedirectUriKey, _malRedirectUri),
      prefs.setBool(_malEnabledKey, _malEnabled),
    ]);
    notifyListeners();
  }

  Uri createAniListAuthorizationUri() {
    _requireOAuthValue(_aniListClientId, 'AniList Client ID');
    _requireOAuthValue(_aniListRedirectUri, 'AniList redirect URI');
    return _oauthService.aniListAuthorizationUri(
      clientId: _aniListClientId,
      authorizationUrl: TrackerBuildConfig.aniListOAuthUrl,
    );
  }

  MalAuthorizationSession createMalAuthorization() {
    _requireOAuthValue(_malClientId, 'MyAnimeList Client ID');
    _requireOAuthValue(_malRedirectUri, 'MyAnimeList redirect URI');
    return _oauthService.createMalAuthorization(
      clientId: _malClientId,
      redirectUri: _malRedirectUri,
    );
  }

  Future<void> completeAniListAuthorization(String redirectUrl) async {
    await _runAuth(() async {
      final tokens = _oauthService.parseAniListRedirect(redirectUrl);
      final account = await AniListTrackerService(
        accessToken: tokens.accessToken,
      ).loadCurrentAccount();
      await _tokenStore.write(TrackerKind.aniList, tokens);
      _aniListTokens = tokens;
      _aniListAccount = account;
    });
  }

  Future<void> completeMalAuthorization(
    MalAuthorizationSession session,
    String redirectUrl,
  ) async {
    await _runAuth(() async {
      final tokens = await _oauthService.completeMalAuthorization(
        session: session,
        redirectUrl: redirectUrl,
        clientId: _malClientId,
        redirectUri: _malRedirectUri,
      );
      final account = await MalTrackerService(
        clientId: _malClientId,
        accessToken: tokens.accessToken,
      ).loadCurrentAccount();
      await _tokenStore.write(TrackerKind.myAnimeList, tokens);
      _malTokens = tokens;
      _malAccount = account;
    });
  }

  Future<void> disconnect(TrackerKind kind) async {
    await _tokenStore.clear(kind);
    if (kind == TrackerKind.aniList) {
      _aniListTokens = null;
      _aniListAccount = null;
    } else {
      _malTokens = null;
      _malAccount = null;
    }
    _authError = null;
    notifyListeners();
  }

  Future<List<String>> addAnimeToConnectedTrackers({
    required String title,
    int? malId,
    int? aniListId,
  }) async {
    final operations = <Future<String>>[];
    if (_aniListConnectedAndEnabled) {
      operations.add(
        AniListTrackerService(accessToken: _aniListTokens!.accessToken)
            .addAnimeToList(
              aniListId: aniListId,
              malId: malId,
              title: title,
            )
            .then((_) => 'AniList'),
      );
    }
    if (_malConnectedAndEnabled) {
      operations.add(
        MalTrackerService(
          clientId: _malClientId,
          accessToken: _malTokens!.accessToken,
        ).addAnimeToList(malId: malId, title: title).then((_) => 'MyAnimeList'),
      );
    }
    if (operations.isEmpty) {
      throw const TrackerRequestException(
        'Connect and enable AniList or MyAnimeList first.',
      );
    }
    return Future.wait(operations);
  }

  Future<List<String>> updateAnimeProgressOnConnectedTrackers({
    required String title,
    required int episode,
    int? malId,
    int? aniListId,
  }) async {
    final operations = <Future<String>>[];
    if (_aniListConnectedAndEnabled) {
      operations.add(
        AniListTrackerService(accessToken: _aniListTokens!.accessToken)
            .updateAnimeProgress(
              aniListId: aniListId,
              malId: malId,
              title: title,
              progress: episode,
            )
            .then((_) => 'AniList'),
      );
    }
    if (_malConnectedAndEnabled) {
      operations.add(
        MalTrackerService(
          clientId: _malClientId,
          accessToken: _malTokens!.accessToken,
        )
            .updateAnimeProgress(
              malId: malId,
              title: title,
              progress: episode,
            )
            .then((_) => 'MyAnimeList'),
      );
    }
    if (operations.isEmpty) return const [];
    return Future.wait(operations);
  }

  Future<TrackerHomeData> loadHome(TrackedMediaType type) async {
    final services = _enabledServices();
    if (services.isEmpty) {
      return TrackerHomeData(sections: const []);
    }

    final attempts = await Future.wait(
      services.map(
        (service) async {
          try {
            final homeFuture = service.loadHome(
              type: type,
              includeAdult: _includeAdult,
            );
            final libraryFuture = service
                .loadLibrary(type: type)
                .catchError((_) => <TrackerSection>[]);
            final home = await homeFuture;
            final library = await libraryFuture;
            return _TrackerAttempt.success(
              TrackerHomeData(
                schedule: home.schedule,
                librarySections: library,
                sections: home.sections,
              ),
            );
          } catch (error) {
            return _TrackerAttempt<TrackerHomeData>.failure(error);
          }
        },
      ),
    );
    final results = attempts
        .map((attempt) => attempt.value)
        .whereType<TrackerHomeData>()
        .toList();
    if (results.isEmpty) throw attempts.first.error!;
    return TrackerHomeData(
      schedule: _deduplicateSchedule(
        results.expand((result) => result.schedule),
      ),
      librarySections: _mergeLibrarySections(
        results.expand((result) => result.librarySections),
      ),
      sections: results.expand((result) => result.sections),
    );
  }

  Future<TrackerSearchPage> search({
    required String query,
    required TrackedMediaType type,
    required List<String> tags,
    List<String> genres = const [],
    required TrackerSort sort,
    int page = 1,
  }) async {
    final services = _enabledServices();
    final attempts = await Future.wait(
      services.map(
        (service) async {
          try {
            return _TrackerAttempt.success(
              await service.search(
                TrackerSearchRequest(
                  query: query,
                  type: type,
                  tags: tags,
                  genres: genres,
                  sort: sort,
                  includeAdult: _includeAdult,
                  page: page,
                ),
              ),
            );
          } catch (error) {
            return _TrackerAttempt<TrackerSearchPage>.failure(error);
          }
        },
      ),
    );
    final results = attempts
        .map((attempt) => attempt.value)
        .whereType<TrackerSearchPage>()
        .toList();
    if (results.isEmpty && attempts.isNotEmpty) throw attempts.first.error!;
    return TrackerSearchPage(
      items: _deduplicateMedia(results.expand((result) => result.items)),
      page: page,
      hasNextPage: results.any((result) => result.hasNextPage),
    );
  }

  Future<TrackerSearchPage> loadSeason({
    required int year,
    required AnimeSeason season,
    required TrackerSort sort,
    int page = 1,
  }) async {
    final services = _enabledServices();
    if (services.isEmpty) {
      return TrackerSearchPage(items: const [], page: page, hasNextPage: false);
    }
    final attempts = await Future.wait(
      services.map((service) async {
        try {
          return _TrackerAttempt.success(
            await service.loadSeason(
              year: year,
              season: season,
              sort: sort,
              includeAdult: _includeAdult,
              page: page,
            ),
          );
        } catch (error) {
          return _TrackerAttempt<TrackerSearchPage>.failure(error);
        }
      }),
    );
    final results = attempts
        .map((attempt) => attempt.value)
        .whereType<TrackerSearchPage>()
        .toList();
    if (results.isEmpty) throw attempts.first.error!;
    return TrackerSearchPage(
      items: _deduplicateMedia(results.expand((result) => result.items)),
      page: page,
      hasNextPage: results.any((result) => result.hasNextPage),
    );
  }

  Future<TrackerMediaDetails> loadDetails(TrackerMedia media) async {
    final services = _enabledServices().toList()
      ..sort(
        (a, b) => (a.kind == TrackerKind.aniList ? 0 : 1)
            .compareTo(b.kind == TrackerKind.aniList ? 0 : 1),
      );
    Object? lastError;
    for (final service in services) {
      if (service.kind == TrackerKind.aniList &&
          media.tracker != TrackerKind.aniList &&
          media.malId == null) {
        continue;
      }
      try {
        return await service.loadDetails(media);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    throw const TrackerRequestException('No tracker is available for details.');
  }

  Future<TrackerTaxonomy> loadTaxonomy() async {
    final services = _enabledServices();
    if (services.isEmpty) return TrackerTaxonomy.empty;
    final attempts = await Future.wait(
      services.map((service) async {
        try {
          return await service.loadTaxonomy(includeAdult: _includeAdult);
        } catch (_) {
          return TrackerTaxonomy.empty;
        }
      }),
    );
    final genres = <String>{};
    final tags = <String, TrackerTag>{};
    for (final taxonomy in attempts) {
      genres.addAll(taxonomy.genres);
      for (final tag in taxonomy.tags) {
        tags.putIfAbsent(tag.name.toLowerCase(), () => tag);
      }
    }
    final sortedGenres = genres.toList()..sort();
    final sortedTags = tags.values.toList()
      ..sort((a, b) {
        final category = a.category.compareTo(b.category);
        return category != 0 ? category : a.name.compareTo(b.name);
      });
    return TrackerTaxonomy(genres: sortedGenres, tags: sortedTags);
  }

  List<TrackerService> _enabledServices() {
    return [
      if (_aniListEnabled)
        AniListTrackerService(
          accessToken: _aniListTokens?.accessToken,
          userId: _aniListAccount?.id,
        ),
      if (_malEnabled && _malClientId.isNotEmpty)
        MalTrackerService(
          clientId: _malClientId,
          accessToken: _malTokens?.accessToken,
        ),
    ];
  }

  Future<void> _refreshAccounts() async {
    if (_aniListTokens != null && !_aniListTokens!.isExpired) {
      try {
        _aniListAccount = await AniListTrackerService(
          accessToken: _aniListTokens!.accessToken,
        ).loadCurrentAccount();
      } catch (_) {
        _aniListAccount = null;
      }
    }
    if (_malTokens?.isExpired == true &&
        _malTokens?.refreshToken?.isNotEmpty == true &&
        _malClientId.isNotEmpty) {
      try {
        _malTokens = await _oauthService.refreshMalToken(
          clientId: _malClientId,
          refreshToken: _malTokens!.refreshToken!,
        );
        await _tokenStore.write(TrackerKind.myAnimeList, _malTokens!);
      } catch (_) {
        _malAccount = null;
      }
    }
    if (_malTokens != null &&
        !_malTokens!.isExpired &&
        _malClientId.isNotEmpty) {
      try {
        _malAccount = await MalTrackerService(
          clientId: _malClientId,
          accessToken: _malTokens!.accessToken,
        ).loadCurrentAccount();
      } catch (_) {
        _malAccount = null;
      }
    }
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    _authBusy = true;
    _authError = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _authError = error.toString();
      rethrow;
    } finally {
      _authBusy = false;
      notifyListeners();
    }
  }

  void _requireOAuthValue(String value, String label) {
    if (value.trim().isEmpty) {
      throw TrackerRequestException('Configure $label first.');
    }
  }

  List<TrackerMedia> _deduplicateMedia(Iterable<TrackerMedia> items) {
    final seen = <String>{};
    return items.where((item) {
      final key = item.malId != null
          ? 'mal:${item.malId}'
          : '${item.type.name}:${item.title.preferred.toLowerCase()}';
      return seen.add(key);
    }).toList();
  }

  List<TrackerScheduleEntry> _deduplicateSchedule(
    Iterable<TrackerScheduleEntry> entries,
  ) {
    final seen = <String>{};
    final result = entries.where((entry) {
      final key = '${entry.media.id}:${entry.releaseNumber}:${entry.releaseAt}';
      return seen.add(key);
    }).toList();
    result.sort((a, b) => a.releaseAt.compareTo(b.releaseAt));
    return result;
  }

  List<TrackerSection> _mergeLibrarySections(
    Iterable<TrackerSection> sections,
  ) {
    final grouped = <String, List<TrackerMedia>>{};
    final titles = <String, String>{};
    for (final section in sections) {
      final key = section.title.trim().toLowerCase();
      titles.putIfAbsent(key, () => section.title);
      grouped.putIfAbsent(key, () => []).addAll(
            section.items.where((item) => _includeAdult || !item.isAdult),
          );
    }
    return grouped.entries
        .map(
          (entry) => TrackerSection(
            id: 'library_${entry.key.replaceAll(' ', '_')}',
            title: titles[entry.key]!,
            items: _deduplicateMedia(entry.value),
          ),
        )
        .where((section) => section.items.isNotEmpty)
        .toList();
  }
}

class _TrackerAttempt<T> {
  final T? value;
  final Object? error;

  const _TrackerAttempt._({this.value, this.error});

  factory _TrackerAttempt.success(T value) => _TrackerAttempt._(value: value);

  factory _TrackerAttempt.failure(Object error) =>
      _TrackerAttempt._(error: error);
}
