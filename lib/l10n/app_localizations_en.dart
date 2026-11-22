// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'StarsLibrary';

  @override
  String get navLibrary => 'Library';

  @override
  String get navDiscover => 'Discover';

  @override
  String get navSources => 'Sources';

  @override
  String get navSettings => 'Settings';

  @override
  String get searchForMangas => 'Search for manga';

  @override
  String get searchForAnime => 'Search for anime';

  @override
  String get ok => 'OK';

  @override
  String get gotIt => 'Got it';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get clear => 'Clear';

  @override
  String get later => 'Later';

  @override
  String get loading => 'Loading...';

  @override
  String get loadingMore => 'Loading more...';

  @override
  String get error => 'Error';

  @override
  String get search => 'Search';

  @override
  String get all => 'All';

  @override
  String get loginRequired => 'Login required';

  @override
  String get settingsTabGeneral => 'General';

  @override
  String get settingsTabAccount => 'Account';

  @override
  String get settingsTabAbout => 'About';

  @override
  String get generalTitle => 'General';

  @override
  String get generalLibraryTitle => 'Library';

  @override
  String get generalLibraryDesc =>
      'Manage library tabs, saved items, backups, reading history, and update behavior.';

  @override
  String get generalSourcesTitle => 'Sources';

  @override
  String get generalSourcesDesc =>
      'Choose which manga and anime sources are enabled and available throughout the app.';

  @override
  String get generalPlaybackTitle => 'Video playback';

  @override
  String get generalPlaybackDesc =>
      'Adjust native player behavior, hardware decoding, gestures, subtitles, and compatibility options.';

  @override
  String get languageSectionTitle => 'Language';

  @override
  String get languageSystemDefault => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePortugueseBrazil => 'Português (Brasil)';

  @override
  String get languageSpanish => 'Español';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get accountSettingsTitle => 'Account Settings';

  @override
  String get accountSourceLoginsTitle => 'Source logins';

  @override
  String get accountSourceLoginsDesc =>
      'Sign in to sources that require an account, renew browser sessions, or disconnect stored source access.';

  @override
  String get accountTrackersTitle => 'Trackers';

  @override
  String get accountTrackersDesc =>
      'Connect and configure services such as AniList and MyAnimeList for Discover, progress, and library tracking.';

  @override
  String get aboutTitle => 'About StarsLibrary';

  @override
  String get aboutHeroTitle => 'Your stories, one library';

  @override
  String get aboutHeroDesc =>
      'Browse, organize, read manga, and watch anime from your enabled sources — with tracker-powered discovery and native playback.';

  @override
  String get aboutChipMultiSource => 'Multi-source';

  @override
  String get aboutChipNoAds => 'No ads';

  @override
  String get aboutChipOpenSource => 'Open source';

  @override
  String get aboutApplicationTitle => 'Application';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutBuildLabel => 'Build';

  @override
  String get aboutCheckingUpdates => 'Checking…';

  @override
  String get aboutCheckUpdates => 'Check for updates';

  @override
  String get aboutSourceCodeTitle => 'Source code';

  @override
  String get aboutSourceCodeSubtitle => 'View the project on GitHub';

  @override
  String get aboutWebsiteTitle => 'StarsLibrary website';

  @override
  String get aboutWebsiteSubtitle => 'Project news and information';

  @override
  String get aboutDisclaimer =>
      'StarsLibrary does not host third-party content and is not affiliated with content providers, authors, or publishers.';

  @override
  String get aboutCouldNotOpenLink => 'Could not open link';

  @override
  String get aboutUpToDateTitle => 'StarsLibrary is up to date';

  @override
  String aboutUpToDateMessage(String version) {
    return 'You are using version $version.';
  }

  @override
  String get aboutUpdateAvailableTitle => 'Update available';

  @override
  String aboutUpdateAvailableMessage(
      String releaseVersion, String currentVersion) {
    return 'StarsLibrary $releaseVersion is available. You currently have $currentVersion.';
  }

  @override
  String get aboutViewUpdate => 'View update';

  @override
  String get aboutUpdateCheckFailedTitle => 'Could not check for updates';

  @override
  String get aboutUpdateCheckFailedMessage =>
      'Check your connection and try again.';

  @override
  String get manageOrganization => 'Manage Organization';

  @override
  String get noSubtabsForPrimaryTab => 'No subtabs for this primary tab.';

  @override
  String get chapterNavigationNotSupported =>
      'Chapter navigation is not supported for this source.';

  @override
  String get noNextChapter => 'There is no next chapter.';

  @override
  String get noPreviousChapter => 'There is no previous chapter.';

  @override
  String get webViewSessionCleared => 'WebView session and cookies cleared.';

  @override
  String get clearWebViewSessionTooltip =>
      'Clear WebView session and cookies (debug)';

  @override
  String get catalogFilterFeatured => 'Featured';

  @override
  String get catalogFilterCatalog => 'Catalog';

  @override
  String get catalogFilterAllAnime => 'All anime';

  @override
  String get catalogFilterSubtitled => 'Subtitled';

  @override
  String get catalogFilterDubbed => 'Dubbed';

  @override
  String get catalogFilterManhwa => 'Manhwa';

  @override
  String get catalogFilterDonghua => 'Donghua';

  @override
  String get catalogFilterMovies => 'Movies';

  @override
  String get catalogFilterSubtitledMovies => 'Subtitled movies';

  @override
  String get catalogFilterDubbedMovies => 'Dubbed movies';

  @override
  String get catalogFilterAdult => 'Adult';

  @override
  String get catalogFilterAdult18 => 'Hentai (+18)';

  @override
  String get catalogFilterPopular => 'Most viewed';

  @override
  String get catalogFilterMostLiked => 'Most liked';

  @override
  String get catalogFilterPopularToday => 'Today';

  @override
  String get catalogFilterPopularWeek => 'This week';

  @override
  String get catalogFilterPopularMonth => 'This month';

  @override
  String get catalogFilterRecent => 'Latest';

  @override
  String get catalogFilterLatestEpisodes => 'Latest episodes';

  @override
  String get catalogFilterNewEpisodes => 'New episodes';

  @override
  String get catalogFilterNewDubbed => 'New dubbed';

  @override
  String get catalogFilterNewReleases => 'New releases';

  @override
  String get catalogFilterEpisodeMostViewed => 'Most viewed episodes';

  @override
  String get catalogFilterSeriesNewest => 'Newest series';

  @override
  String get catalogFilterSeriesPopular => 'Popular series';

  @override
  String get catalogFilterSeriesMostViewed => 'Most viewed series';

  @override
  String get catalogFilterUpdated => 'Updated';

  @override
  String get catalogFilterAdded => 'Recently added';

  @override
  String get catalogFilterAiring => 'Airing';

  @override
  String get catalogFilterUpcoming => 'Upcoming';

  @override
  String get catalogFilterCompleted => 'Completed';

  @override
  String get catalogFilterEpisodesPopular => 'Episodes · Popular';

  @override
  String get catalogFilterEpisodesMostViewed => 'Episodes · Most viewed';

  @override
  String get weekdaySunday => 'Sunday';

  @override
  String get weekdayMonday => 'Monday';

  @override
  String get weekdayTuesday => 'Tuesday';

  @override
  String get weekdayWednesday => 'Wednesday';

  @override
  String get weekdayThursday => 'Thursday';

  @override
  String get weekdayFriday => 'Friday';

  @override
  String get weekdaySaturday => 'Saturday';

  @override
  String get weekdayUnknown => 'Unknown';

  @override
  String get discoverAtAGlance => 'Discover at a glance';

  @override
  String get discoverSearchCatalog => 'Search the tracker catalog';

  @override
  String get discoverOpenOrFindSource => 'Open or find a source';

  @override
  String get discoverStartExploring => 'Start exploring';

  @override
  String get endOfList => '— end of list —';

  @override
  String loginRequiredMessage(String sourceName) {
    return 'Please log in to $sourceName to access the content.';
  }

  @override
  String subtabsOfPrimaryTab(String tabName) {
    return 'Subtabs of \"$tabName\"';
  }

  @override
  String get sourcesTabSources => 'Sources';

  @override
  String get sourcesTabManage => 'Manage';

  @override
  String get sourcesTabHistory => 'History';

  @override
  String get sourcesTabMigrate => 'Migrate';

  @override
  String get libraryTabManga => 'Manga';

  @override
  String get libraryTabAnime => 'Anime';

  @override
  String get sortBooksTooltip => 'Sort books';

  @override
  String get configureTabsInSettings => 'Configure your tabs in Settings.';

  @override
  String get emptyShelfTitle => 'Your shelf is ready';

  @override
  String get emptyShelfSubtitle =>
      'Explore a source and add your first title to this collection.';

  @override
  String get exploreSources => 'Explore sources';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchTitlesHint => 'Search titles...';

  @override
  String get searchEnabledSources => 'Search enabled sources';

  @override
  String get typeToSearchLibrary => 'Type to search your library';

  @override
  String get noResultsInLibrary => 'No results in your library.';

  @override
  String get couldNotSearchSource => 'Could not search this source.';

  @override
  String get noResultsInSource => 'No results in this source.';

  @override
  String get noTitlesFound => 'No titles found.';

  @override
  String get searchAnimeSourcesTitle => 'Search anime sources';

  @override
  String get searchEnabledAnimeSourcesHint => 'Search enabled anime sources';

  @override
  String get clearSearchTooltip => 'Clear search';

  @override
  String get animeSourceUnavailable => 'This anime source is unavailable.';

  @override
  String get verifyInBrowser => 'Verify in browser';

  @override
  String get hostsCheckedSuccess => 'Hosts checked successfully.';

  @override
  String hostsCheckFailed(String error) {
    return 'Failed to check hosts: $error';
  }

  @override
  String get sourceHostMonitorTitle => 'Source Host Monitor';

  @override
  String get automaticHostChecks => 'Automatic host checks';

  @override
  String get automaticHostChecksDesc =>
      'Monitor manga and anime source availability';

  @override
  String get autoCheckInterval => 'Auto-check interval';

  @override
  String get lastCheck => 'Last check';

  @override
  String get never => 'Never';

  @override
  String get checkNow => 'Check now';

  @override
  String get mangaSources => 'Manga sources';

  @override
  String get animeSources => 'Anime sources';

  @override
  String get hostStatusOnline => 'online';

  @override
  String get hostStatusOutdated => 'outdated';

  @override
  String get hostStatusChecking => 'checking';

  @override
  String get hostStatusUnknown => 'unknown';

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String hoursShort(int hours) {
    return '$hours h';
  }

  @override
  String hoursCount(int hours) {
    return '$hours hours';
  }

  @override
  String get librarySettingsTitle => 'Library Settings';

  @override
  String get libraryTabsSettingsTitle => 'Library Tabs Settings';

  @override
  String get libraryItemsSettingsTitle => 'Library Items Settings';

  @override
  String get backupAndRestoreTitle => 'Backup & Restore';

  @override
  String get decoderTitle => 'Decoder';

  @override
  String get decoderAutoTitle => 'Automatic';

  @override
  String get decoderAutoDesc =>
      'Prefer hardware decoding and fall back when necessary.';

  @override
  String get decoderHardwareTitle => 'Hardware';

  @override
  String get decoderHardwareDesc =>
      'Use the device video decoder for lower battery usage.';

  @override
  String get decoderSoftwareTitle => 'Software compatibility';

  @override
  String get decoderSoftwareDesc =>
      'Use the CPU when a device codec produces visual errors.';

  @override
  String get gesturesTitle => 'Gestures';

  @override
  String get playerGesturesTitle => 'Player gestures';

  @override
  String get playerGesturesDesc =>
      'Double tap to seek; swipe left for volume and right for brightness.';

  @override
  String get doubleTapSeekTitle => 'Double-tap seek';

  @override
  String secondsCount(int seconds) {
    return '$seconds seconds';
  }

  @override
  String secondsShort(int seconds) {
    return '$seconds s';
  }

  @override
  String get episodesTitle => 'Episodes';

  @override
  String get autoSkipIntroTitle => 'Automatically skip intros';

  @override
  String get autoSkipIntroDesc =>
      'Only applies when the source supplies a verified intro range.';

  @override
  String get subtitlesTitle => 'Subtitles';

  @override
  String get preferredSubtitleLanguageTitle => 'Preferred subtitle language';

  @override
  String get preferredSubtitleLanguageDesc =>
      'Use “auto” or a language code such as en, pt-BR or ja.';

  @override
  String get subtitleFontTitle => 'Subtitle font';

  @override
  String get subtitleFontDesc =>
      'Noto Sans includes Portuguese and other extended characters.';

  @override
  String subtitleSizeLabel(int size) {
    return 'Subtitle size · $size px';
  }

  @override
  String get playbackHardwareWarning =>
      'Hardware decoding is recommended. Software mode may use considerably more battery and make the device warmer.';

  @override
  String get testVideoPlayer => 'Test video player';

  @override
  String get playerDiagnosticsTitle => 'StarsLibrary player diagnostics';

  @override
  String get publicSampleVideo => 'Public sample video';

  @override
  String trackerCompletedUpdates(String mediaType, int count) {
    return '$mediaType tracker completed: $count update(s).';
  }

  @override
  String trackerRunFailed(String error) {
    return 'Failed to run tracker: $error';
  }

  @override
  String get enableChapterTracker => 'Enable Chapter Tracker';

  @override
  String get enableEpisodeTracker => 'Enable Episode Tracker';

  @override
  String get updateInterval => 'Update Interval';

  @override
  String get tabsToUpdate => 'Tabs to Update';

  @override
  String get saveSettings => 'Save Settings';

  @override
  String connectProvider(String provider) {
    return 'Connect $provider';
  }

  @override
  String oauthBannerMessage(String provider) {
    return 'Sign in on $provider. StarsLibrary never sees or stores your password.';
  }

  @override
  String get addPrimaryTabHint => 'Add primary tab';

  @override
  String get tabsReorderTip =>
      'Tip: long-press and drag a primary tab onto another to nest it as subtab.';

  @override
  String addSubtabToHint(String tab) {
    return 'Add subtab to \"$tab\"';
  }

  @override
  String get renameTabTitle => 'Rename Tab';

  @override
  String get enterNewTabNameHint => 'Enter new tab name';

  @override
  String backupCreatedIn(String path) {
    return 'Backup created in: $path';
  }

  @override
  String backupCreateFailed(String error) {
    return 'Failed to create backup: $error';
  }

  @override
  String get restoreBackupTitle => 'Restore Backup';

  @override
  String get restoreBackupConfirmMessage =>
      'This will replace your current library, history, tabs, and saved logins with the selected backup. Do you want to continue?';

  @override
  String get restoreAction => 'Restore';

  @override
  String get backupRestoredSuccess => 'Backup restored successfully.';

  @override
  String backupRestoreFailed(String error) {
    return 'Failed to restore backup: $error';
  }

  @override
  String get backupSavedSuccess => 'Backup saved successfully.';

  @override
  String backupDownloadFailed(String error) {
    return 'Failed to download backup: $error';
  }

  @override
  String backupLoadFailed(String error) {
    return 'Failed to load backup: $error';
  }

  @override
  String get encryptedCompleteBackupTitle => 'Encrypted complete backup';

  @override
  String get encryptedCompleteBackupDesc =>
      'Includes manga and anime history, favorites, tabs, stored logins, and enabled sources. Keep the password safe.';

  @override
  String get createBackupButton => 'Create Backup';

  @override
  String get loadBackupButton => 'Load Backup';

  @override
  String get noBackupsFound => 'No backups found.';

  @override
  String get downloadTooltip => 'Download';

  @override
  String get restoreTooltip => 'Restore';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get protectBackupTitle => 'Protect your backup';

  @override
  String get unlockBackupTitle => 'Unlock backup';

  @override
  String get protectBackupDesc =>
      'This password encrypts your library and stored logins. It cannot be recovered if you forget it.';

  @override
  String get unlockBackupDesc =>
      'Enter the password used when this backup was created.';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get createBackupAction => 'Create backup';

  @override
  String get unlockAction => 'Unlock';

  @override
  String get scrapperLoginsTitle => 'Scrapper Logins';

  @override
  String loginWithTitle(String sourceName) {
    return 'Login — $sourceName';
  }

  @override
  String get emailAndPassword => 'Email and password';

  @override
  String get googleOrDiscord => 'Google or Discord';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginAction => 'Login';

  @override
  String logoutTitle(String sourceName) {
    return 'Logout from $sourceName';
  }

  @override
  String get logoutConfirmMessage =>
      'This will remove the saved session for this scrapper. Are you sure you want to logout?';

  @override
  String get logoutAction => 'Logout';

  @override
  String get scrapperLoginsInfo =>
      'Manage the logins for sites that require authentication. Tokens are stored locally on the device. Logout to remove an expired or compromised token.';

  @override
  String get noAuthScrappers => 'No scrappers with authentication configured.';

  @override
  String get completeLogin => 'Complete Login';

  @override
  String get renewSession => 'Renew Session';

  @override
  String get discoveryAndTrackingTitle => 'Discovery and tracking';

  @override
  String get discoveryAndTrackingDesc =>
      'Discover anime and manga with tracker metadata, then match titles against your enabled sources.';

  @override
  String get aniListSubtitle =>
      'Public catalog, dynamic tags and airing calendar';

  @override
  String get aniListOptionalLoginNote =>
      'Login is optional for discovery and required only for future personal-list synchronization.';

  @override
  String get configuredByBuild => 'Configured by this build';

  @override
  String get aniListClientIdLabel => 'AniList Client ID';

  @override
  String get malSubtitle => 'Rankings, seasonal catalogs and account lists';

  @override
  String get malClientIdRequiredNote =>
      'MAL requires a Client ID even for public requests.';

  @override
  String get malClientIdLabel => 'MAL Client ID';

  @override
  String get includeAdultContentTitle => 'Include adult content';

  @override
  String get includeAdultContentDesc =>
      'Works with public tracker data; login is not required.';

  @override
  String get preferEnglishTitlesTitle => 'Prefer English titles';

  @override
  String get preferEnglishTitlesDesc =>
      'Off by default. Romaji titles are used whenever available.';

  @override
  String get trackerConfigSaved => 'Tracker configuration saved.';

  @override
  String trackerAccountConnected(String provider) {
    return '$provider account connected.';
  }

  @override
  String get registeredRedirectUriLabel => 'Registered redirect URI';

  @override
  String get disconnectAction => 'Disconnect';

  @override
  String get connectAction => 'Connect';

  @override
  String get notConnected => 'Not connected';

  @override
  String connectedAs(String username) {
    return 'Connected as $username';
  }

  @override
  String get trackerSecurityNote =>
      'Register StarsLibrary in each tracker and use the exact redirect URI shown here. Tokens are kept in secure device storage; passwords and client secrets are never stored.';

  @override
  String searchingSourceInline(String sourceTitle) {
    return '$sourceTitle · Searching…';
  }

  @override
  String get moreAction => 'More';

  @override
  String get searchingThisSource => 'Searching this source…';

  @override
  String get unpinSourceTooltip => 'Unpin source';

  @override
  String get pinSourceTooltip => 'Pin source';

  @override
  String get latestLabel => 'Latest';

  @override
  String get trendingLabel => 'Trending';

  @override
  String sourceCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sources',
      one: 'source',
    );
    return '$count $_temp0';
  }

  @override
  String get noActiveAnimeSources => 'No active anime sources.';

  @override
  String get noActiveMangaSources => 'No active manga sources.';

  @override
  String get enableAnimeSourceHint =>
      'Enable an anime source in the Manage tab.';

  @override
  String get enableMangaSourceHint => 'Enable a source in the Manage tab.';

  @override
  String get pinnedSourcesTitle => 'Pinned sources';

  @override
  String savedCountLabel(int count) {
    return '$count saved';
  }

  @override
  String get enableProvidersToPlay =>
      'Enable providers to browse and play episodes.';

  @override
  String get animeSourcesFutureUpdate =>
      'Anime sources will be added in a future update.';

  @override
  String get activeSourcesTitle => 'Active Sources';

  @override
  String get inactiveSourcesTitle => 'Inactive Sources';

  @override
  String lastChapterReadSummary(String chapterTitle, int readCount) {
    return 'Last: Ch. $chapterTitle • $readCount read';
  }

  @override
  String chapterShort(String title) {
    return 'Ch. $title';
  }

  @override
  String get noWatchedAnimeYet => 'No watched anime yet.';

  @override
  String get howDiscoverWorksTooltip => 'How Discover works';

  @override
  String get browseSeasonArchive => 'Browse season archive';

  @override
  String get searchTrackerTitlesHint => 'Search tracker titles';

  @override
  String get filtersTooltip => 'Filters';

  @override
  String get notNow => 'Not now';

  @override
  String get discoverStep1Title => 'Choose what to explore';

  @override
  String get discoverStep1Desc =>
      'Switch between Anime and Manga. Discover combines the trackers enabled in Account Settings.';

  @override
  String get discoverStep2Desc =>
      'Type a title or use filters to browse by popularity, rating, genres, and tags.';

  @override
  String get discoverStep3Desc =>
      'Tap a title for tracker details. Touch and hold it to search your enabled sources for that same title.';

  @override
  String get noTrackerResultsFound => 'No tracker results found.';

  @override
  String get tryLoadingMoreAgain => 'Try loading more again';

  @override
  String get youReachedTheEnd => 'You reached the end.';

  @override
  String episodeNumber(int number) {
    return 'Episode $number';
  }

  @override
  String get orderByLabel => 'Order by';

  @override
  String get sortPopularity => 'Popularity';

  @override
  String get sortMostRecent => 'Most recent';

  @override
  String get sortHighestRated => 'Highest rated';

  @override
  String get findGenresOrTagsLabel => 'Find genres or tags';

  @override
  String get applyAction => 'Apply';

  @override
  String couldNotLoadGenresAndTags(String error) {
    return 'Could not load genres and tags: $error';
  }

  @override
  String get noMatchingGenresOrTags => 'No matching genres or tags.';

  @override
  String get genresLabel => 'Genres';

  @override
  String genresSelectedLabel(int count) {
    return 'Genres ($count selected)';
  }

  @override
  String get tagsLabel => 'Tags';

  @override
  String tagsSelectedLabel(int count) {
    return 'Tags ($count selected)';
  }

  @override
  String get tryAgain => 'Try again';

  @override
  String get couldNotLoadTrackerData => 'Could not load tracker data.';

  @override
  String get enableTrackerToDiscover =>
      'Enable a tracker to start discovering titles.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get searchSources => 'Search sources';

  @override
  String episodesCount(int count) {
    return '$count episodes';
  }

  @override
  String chaptersCount(int count) {
    return '$count chapters';
  }

  @override
  String volumesCount(int count) {
    return '$count volumes';
  }

  @override
  String minutesPerEpisode(int minutes) {
    return '$minutes min / episode';
  }

  @override
  String scorePercentLabel(int score) {
    return '$score% score';
  }

  @override
  String get synopsisTitle => 'Synopsis';

  @override
  String get genresSectionTitle => 'Genres';

  @override
  String get tagsSectionTitle => 'Tags';

  @override
  String get studiosSectionTitle => 'Studios';

  @override
  String get openOnTracker => 'Open on tracker';

  @override
  String get reviewsSectionTitle => 'Reviews';

  @override
  String get readFullReview => 'Read full review';

  @override
  String get seasonArchiveTitle => 'Season archive';

  @override
  String get browseAnyAnimeSeason => 'Browse any anime season';

  @override
  String get browseAnyAnimeSeasonDesc =>
      'Choose a season and year, then scroll to load more titles.';

  @override
  String get seasonLabel => 'Season';

  @override
  String get yearLabel => 'Year';

  @override
  String get seasonWinter => 'Winter';

  @override
  String get seasonSpring => 'Spring';

  @override
  String get seasonSummer => 'Summer';

  @override
  String get seasonFall => 'Fall';

  @override
  String get noTitlesForSeason => 'No titles found for this season.';

  @override
  String get enableAnimeSourceBeforeSearching =>
      'Enable an anime source before searching.';

  @override
  String get noAnimeSourceAvailableYet => 'No anime source is available yet.';

  @override
  String get enableMangaSourceBeforeSearching =>
      'Enable a manga source before searching.';

  @override
  String get animeShelfReady => 'Your anime shelf is ready';

  @override
  String get animeShelfSubtitle =>
      'Open an anime source and tap the heart to save a title.';

  @override
  String get exploreAnimeSources => 'Explore anime sources';

  @override
  String get moveAnimeTo => 'Move anime to';

  @override
  String get watchedLabel => 'Watched';

  @override
  String lastEpisodeLabel(String episodeTitle) {
    return 'Last: $episodeTitle';
  }

  @override
  String searchSourceHint(String sourceName) {
    return 'Search $sourceName';
  }

  @override
  String get advancedFilters => 'Advanced filters';

  @override
  String get resetAction => 'Reset';

  @override
  String get applyFilters => 'Apply filters';

  @override
  String get anyOption => 'Any';

  @override
  String couldNotOpenEpisode(String error) {
    return 'Could not open this episode: $error';
  }

  @override
  String get chooseVideoServer => 'Choose a video server';

  @override
  String get chooseVideoServerSubtitle =>
      'You can try another server if playback fails.';

  @override
  String get renameAnimeTitle => 'Rename anime';

  @override
  String get libraryTitleLabel => 'Library title';

  @override
  String get manageAnimeTabsTitle => 'Manage anime tabs';

  @override
  String get enableAnotherAnimeSourceBeforeMigrating =>
      'Enable another anime source before migrating.';

  @override
  String get noMatchingTitleInEnabledSources =>
      'No matching title was found in enabled sources.';

  @override
  String get migrateAnimeTo => 'Migrate anime to';

  @override
  String get addToConnectedTrackersTooltip => 'Add to connected trackers';

  @override
  String get removeFromLibraryTooltip => 'Remove from library';

  @override
  String get addToLibraryTooltip => 'Add to library';

  @override
  String get animeOptionsTooltip => 'Anime options';

  @override
  String get migrateAnimeTitle => 'Migrate anime';

  @override
  String get manageTabsTitle => 'Manage tabs';

  @override
  String get noEpisodesAvailable => 'No episodes available.';

  @override
  String get playbackSettingsTooltip => 'Playback settings';

  @override
  String seekBackwardTooltip(int seconds) {
    return 'Back ${seconds}s';
  }

  @override
  String seekForwardTooltip(int seconds) {
    return 'Forward ${seconds}s';
  }

  @override
  String get embeddedAndSourceTracks => 'Embedded and source-provided tracks';

  @override
  String get offLabel => 'Off';

  @override
  String get embeddedLabel => 'Embedded';

  @override
  String get videoDecoderTitle => 'Video decoder';

  @override
  String get paginatedMode => 'Paginated mode';

  @override
  String get reverseReadingDirection => 'Reverse reading direction';

  @override
  String get saveStoryReminderTitle => 'Save story reminder';

  @override
  String get whatHappenedHereLabel => 'What happened here?';

  @override
  String get addShortNoteHint => 'Add a short note about this key moment';

  @override
  String get saveReminderAction => 'Save reminder';

  @override
  String get imageOptionsTitle => 'Image Options';

  @override
  String get saveImageAction => 'Save Image';

  @override
  String get saveAsStoryReminderAction => 'Save as Story Reminder';

  @override
  String get saveAsStoryReminderDesc => 'Keep this image with a chapter note';

  @override
  String get shareImageAction => 'Share Image';

  @override
  String get webViewNotSupported => 'Web view not supported on this platform.';

  @override
  String get openExternally => 'Open externally';

  @override
  String get unsupportedPlatform => 'Unsupported platform';

  @override
  String get readingProgressSaved => 'Reading progress saved';

  @override
  String get combineTagsTitle => 'Combine tags';

  @override
  String searchCountAction(int count) {
    return 'Search ($count)';
  }

  @override
  String get couldNotLoadStoryReminders => 'Could not load story reminders';

  @override
  String get deleteReminderQuestion => 'Delete reminder?';

  @override
  String get updatingBookDetails => 'Updating book details...';

  @override
  String get bookDetailsUpdatedSuccess => 'Book details updated successfully!';

  @override
  String failedToUpdateBookDetails(String error) {
    return 'Failed to update book details: $error';
  }

  @override
  String get tabsLabel => 'Tabs';

  @override
  String get renameBookAction => 'Rename book';

  @override
  String get migrateBookAction => 'Migrate book';

  @override
  String get readingProgressLabel => 'Reading progress';

  @override
  String get markChapterRead => 'Mark chapter as read';

  @override
  String get markThisAndPreviousRead =>
      'Mark this and previous chapters as read';

  @override
  String get markChapterUnread => 'Mark chapter as unread';

  @override
  String get removeReadMarksThroughHere =>
      'Remove read marks through this chapter';

  @override
  String get loadingChapter => 'Loading chapter...';

  @override
  String failedToLoadChapter(String error) {
    return 'Failed to load chapter: $error';
  }

  @override
  String get loginWithEmailPassword => 'Login with email and password';

  @override
  String get loginViaBrowser => 'Login via browser';

  @override
  String get fillEmailAndPassword => 'Please fill in both email and password.';

  @override
  String get noDataAvailable => 'No data available';

  @override
  String loginToSource(String sourceName) {
    return 'Login to $sourceName';
  }

  @override
  String get loadingBookDetails => 'Loading book details...';

  @override
  String failedToLoadBookDetails(String error) {
    return 'Failed to load book details: $error';
  }

  @override
  String couldNotLoadFilters(String error) {
    return 'Could not load filters: $error';
  }

  @override
  String couldNotLoadGenres(String error) {
    return 'Could not load genres: $error';
  }

  @override
  String get filterTitle => 'Filter';

  @override
  String get filterByLabel => 'Filter by:';

  @override
  String get genreLabel => 'Genre';

  @override
  String get authorLabel => 'Author';

  @override
  String get ratingLabel => 'Rating';
}
