import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
    Locale('pt', 'BR')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'StarsLibrary'**
  String get appTitle;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navDiscover;

  /// No description provided for @navSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get navSources;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @searchForMangas.
  ///
  /// In en, this message translates to:
  /// **'Search for manga'**
  String get searchForMangas;

  /// No description provided for @searchForAnime.
  ///
  /// In en, this message translates to:
  /// **'Search for anime'**
  String get searchForAnime;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @loadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more...'**
  String get loadingMore;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @loginRequired.
  ///
  /// In en, this message translates to:
  /// **'Login required'**
  String get loginRequired;

  /// No description provided for @settingsTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsTabGeneral;

  /// No description provided for @settingsTabAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsTabAccount;

  /// No description provided for @settingsTabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsTabAbout;

  /// No description provided for @generalTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalTitle;

  /// No description provided for @generalLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get generalLibraryTitle;

  /// No description provided for @generalLibraryDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage library tabs, saved items, backups, reading history, and update behavior.'**
  String get generalLibraryDesc;

  /// No description provided for @generalSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get generalSourcesTitle;

  /// No description provided for @generalSourcesDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose which manga and anime sources are enabled and available throughout the app.'**
  String get generalSourcesDesc;

  /// No description provided for @generalPlaybackTitle.
  ///
  /// In en, this message translates to:
  /// **'Video playback'**
  String get generalPlaybackTitle;

  /// No description provided for @generalPlaybackDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjust native player behavior, hardware decoding, gestures, subtitles, and compatibility options.'**
  String get generalPlaybackDesc;

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSectionTitle;

  /// No description provided for @languageSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystemDefault;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languagePortugueseBrazil.
  ///
  /// In en, this message translates to:
  /// **'Português (Brasil)'**
  String get languagePortugueseBrazil;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get languageSpanish;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceTitle;

  /// No description provided for @accountSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get accountSettingsTitle;

  /// No description provided for @accountSourceLoginsTitle.
  ///
  /// In en, this message translates to:
  /// **'Source logins'**
  String get accountSourceLoginsTitle;

  /// No description provided for @accountSourceLoginsDesc.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sources that require an account, renew browser sessions, or disconnect stored source access.'**
  String get accountSourceLoginsDesc;

  /// No description provided for @accountTrackersTitle.
  ///
  /// In en, this message translates to:
  /// **'Trackers'**
  String get accountTrackersTitle;

  /// No description provided for @accountTrackersDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect and configure services such as AniList and MyAnimeList for Discover, progress, and library tracking.'**
  String get accountTrackersDesc;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About StarsLibrary'**
  String get aboutTitle;

  /// No description provided for @aboutHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Your stories, one library'**
  String get aboutHeroTitle;

  /// No description provided for @aboutHeroDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse, organize, read manga, and watch anime from your enabled sources — with tracker-powered discovery and native playback.'**
  String get aboutHeroDesc;

  /// No description provided for @aboutChipMultiSource.
  ///
  /// In en, this message translates to:
  /// **'Multi-source'**
  String get aboutChipMultiSource;

  /// No description provided for @aboutChipNoAds.
  ///
  /// In en, this message translates to:
  /// **'No ads'**
  String get aboutChipNoAds;

  /// No description provided for @aboutChipOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get aboutChipOpenSource;

  /// No description provided for @aboutApplicationTitle.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get aboutApplicationTitle;

  /// No description provided for @aboutVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersionLabel;

  /// No description provided for @aboutBuildLabel.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get aboutBuildLabel;

  /// No description provided for @aboutCheckingUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get aboutCheckingUpdates;

  /// No description provided for @aboutCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheckUpdates;

  /// No description provided for @aboutSourceCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCodeTitle;

  /// No description provided for @aboutSourceCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View the project on GitHub'**
  String get aboutSourceCodeSubtitle;

  /// No description provided for @aboutWebsiteTitle.
  ///
  /// In en, this message translates to:
  /// **'StarsLibrary website'**
  String get aboutWebsiteTitle;

  /// No description provided for @aboutWebsiteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Project news and information'**
  String get aboutWebsiteSubtitle;

  /// No description provided for @aboutDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'StarsLibrary does not host third-party content and is not affiliated with content providers, authors, or publishers.'**
  String get aboutDisclaimer;

  /// No description provided for @aboutCouldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get aboutCouldNotOpenLink;

  /// No description provided for @aboutUpToDateTitle.
  ///
  /// In en, this message translates to:
  /// **'StarsLibrary is up to date'**
  String get aboutUpToDateTitle;

  /// No description provided for @aboutUpToDateMessage.
  ///
  /// In en, this message translates to:
  /// **'You are using version {version}.'**
  String aboutUpToDateMessage(String version);

  /// No description provided for @aboutUpdateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get aboutUpdateAvailableTitle;

  /// No description provided for @aboutUpdateAvailableMessage.
  ///
  /// In en, this message translates to:
  /// **'StarsLibrary {releaseVersion} is available. You currently have {currentVersion}.'**
  String aboutUpdateAvailableMessage(
      String releaseVersion, String currentVersion);

  /// No description provided for @aboutViewUpdate.
  ///
  /// In en, this message translates to:
  /// **'View update'**
  String get aboutViewUpdate;

  /// No description provided for @aboutUpdateCheckFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates'**
  String get aboutUpdateCheckFailedTitle;

  /// No description provided for @aboutUpdateCheckFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get aboutUpdateCheckFailedMessage;

  /// No description provided for @manageOrganization.
  ///
  /// In en, this message translates to:
  /// **'Manage Organization'**
  String get manageOrganization;

  /// No description provided for @noSubtabsForPrimaryTab.
  ///
  /// In en, this message translates to:
  /// **'No subtabs for this primary tab.'**
  String get noSubtabsForPrimaryTab;

  /// No description provided for @chapterNavigationNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Chapter navigation is not supported for this source.'**
  String get chapterNavigationNotSupported;

  /// No description provided for @noNextChapter.
  ///
  /// In en, this message translates to:
  /// **'There is no next chapter.'**
  String get noNextChapter;

  /// No description provided for @noPreviousChapter.
  ///
  /// In en, this message translates to:
  /// **'There is no previous chapter.'**
  String get noPreviousChapter;

  /// No description provided for @webViewSessionCleared.
  ///
  /// In en, this message translates to:
  /// **'WebView session and cookies cleared.'**
  String get webViewSessionCleared;

  /// No description provided for @clearWebViewSessionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear WebView session and cookies (debug)'**
  String get clearWebViewSessionTooltip;

  /// No description provided for @catalogFilterFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get catalogFilterFeatured;

  /// No description provided for @catalogFilterCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get catalogFilterCatalog;

  /// No description provided for @catalogFilterAllAnime.
  ///
  /// In en, this message translates to:
  /// **'All anime'**
  String get catalogFilterAllAnime;

  /// No description provided for @catalogFilterSubtitled.
  ///
  /// In en, this message translates to:
  /// **'Subtitled'**
  String get catalogFilterSubtitled;

  /// No description provided for @catalogFilterDubbed.
  ///
  /// In en, this message translates to:
  /// **'Dubbed'**
  String get catalogFilterDubbed;

  /// No description provided for @catalogFilterManhwa.
  ///
  /// In en, this message translates to:
  /// **'Manhwa'**
  String get catalogFilterManhwa;

  /// No description provided for @catalogFilterDonghua.
  ///
  /// In en, this message translates to:
  /// **'Donghua'**
  String get catalogFilterDonghua;

  /// No description provided for @catalogFilterMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get catalogFilterMovies;

  /// No description provided for @catalogFilterSubtitledMovies.
  ///
  /// In en, this message translates to:
  /// **'Subtitled movies'**
  String get catalogFilterSubtitledMovies;

  /// No description provided for @catalogFilterDubbedMovies.
  ///
  /// In en, this message translates to:
  /// **'Dubbed movies'**
  String get catalogFilterDubbedMovies;

  /// No description provided for @catalogFilterAdult.
  ///
  /// In en, this message translates to:
  /// **'Adult'**
  String get catalogFilterAdult;

  /// No description provided for @catalogFilterAdult18.
  ///
  /// In en, this message translates to:
  /// **'Hentai (+18)'**
  String get catalogFilterAdult18;

  /// No description provided for @catalogFilterPopular.
  ///
  /// In en, this message translates to:
  /// **'Most viewed'**
  String get catalogFilterPopular;

  /// No description provided for @catalogFilterMostLiked.
  ///
  /// In en, this message translates to:
  /// **'Most liked'**
  String get catalogFilterMostLiked;

  /// No description provided for @catalogFilterPopularToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get catalogFilterPopularToday;

  /// No description provided for @catalogFilterPopularWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get catalogFilterPopularWeek;

  /// No description provided for @catalogFilterPopularMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get catalogFilterPopularMonth;

  /// No description provided for @catalogFilterRecent.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get catalogFilterRecent;

  /// No description provided for @catalogFilterLatestEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Latest episodes'**
  String get catalogFilterLatestEpisodes;

  /// No description provided for @catalogFilterNewEpisodes.
  ///
  /// In en, this message translates to:
  /// **'New episodes'**
  String get catalogFilterNewEpisodes;

  /// No description provided for @catalogFilterNewDubbed.
  ///
  /// In en, this message translates to:
  /// **'New dubbed'**
  String get catalogFilterNewDubbed;

  /// No description provided for @catalogFilterNewReleases.
  ///
  /// In en, this message translates to:
  /// **'New releases'**
  String get catalogFilterNewReleases;

  /// No description provided for @catalogFilterEpisodeMostViewed.
  ///
  /// In en, this message translates to:
  /// **'Most viewed episodes'**
  String get catalogFilterEpisodeMostViewed;

  /// No description provided for @catalogFilterSeriesNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest series'**
  String get catalogFilterSeriesNewest;

  /// No description provided for @catalogFilterSeriesPopular.
  ///
  /// In en, this message translates to:
  /// **'Popular series'**
  String get catalogFilterSeriesPopular;

  /// No description provided for @catalogFilterSeriesMostViewed.
  ///
  /// In en, this message translates to:
  /// **'Most viewed series'**
  String get catalogFilterSeriesMostViewed;

  /// No description provided for @catalogFilterUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get catalogFilterUpdated;

  /// No description provided for @catalogFilterAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get catalogFilterAdded;

  /// No description provided for @catalogFilterAiring.
  ///
  /// In en, this message translates to:
  /// **'Airing'**
  String get catalogFilterAiring;

  /// No description provided for @catalogFilterUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get catalogFilterUpcoming;

  /// No description provided for @catalogFilterCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get catalogFilterCompleted;

  /// No description provided for @catalogFilterEpisodesPopular.
  ///
  /// In en, this message translates to:
  /// **'Episodes · Popular'**
  String get catalogFilterEpisodesPopular;

  /// No description provided for @catalogFilterEpisodesMostViewed.
  ///
  /// In en, this message translates to:
  /// **'Episodes · Most viewed'**
  String get catalogFilterEpisodesMostViewed;

  /// No description provided for @weekdaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get weekdaySunday;

  /// No description provided for @weekdayMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get weekdayMonday;

  /// No description provided for @weekdayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get weekdayTuesday;

  /// No description provided for @weekdayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get weekdayWednesday;

  /// No description provided for @weekdayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get weekdayThursday;

  /// No description provided for @weekdayFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get weekdayFriday;

  /// No description provided for @weekdaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get weekdaySaturday;

  /// No description provided for @weekdayUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get weekdayUnknown;

  /// No description provided for @discoverAtAGlance.
  ///
  /// In en, this message translates to:
  /// **'Discover at a glance'**
  String get discoverAtAGlance;

  /// No description provided for @discoverSearchCatalog.
  ///
  /// In en, this message translates to:
  /// **'Search the tracker catalog'**
  String get discoverSearchCatalog;

  /// No description provided for @discoverOpenOrFindSource.
  ///
  /// In en, this message translates to:
  /// **'Open or find a source'**
  String get discoverOpenOrFindSource;

  /// No description provided for @discoverStartExploring.
  ///
  /// In en, this message translates to:
  /// **'Start exploring'**
  String get discoverStartExploring;

  /// No description provided for @endOfList.
  ///
  /// In en, this message translates to:
  /// **'— end of list —'**
  String get endOfList;

  /// No description provided for @loginRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Please log in to {sourceName} to access the content.'**
  String loginRequiredMessage(String sourceName);

  /// No description provided for @subtabsOfPrimaryTab.
  ///
  /// In en, this message translates to:
  /// **'Subtabs of \"{tabName}\"'**
  String subtabsOfPrimaryTab(String tabName);

  /// No description provided for @sourcesTabSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sourcesTabSources;

  /// No description provided for @sourcesTabManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get sourcesTabManage;

  /// No description provided for @sourcesTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get sourcesTabHistory;

  /// No description provided for @sourcesTabMigrate.
  ///
  /// In en, this message translates to:
  /// **'Migrate'**
  String get sourcesTabMigrate;

  /// No description provided for @libraryTabManga.
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get libraryTabManga;

  /// No description provided for @libraryTabAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get libraryTabAnime;

  /// No description provided for @sortBooksTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort books'**
  String get sortBooksTooltip;

  /// No description provided for @configureTabsInSettings.
  ///
  /// In en, this message translates to:
  /// **'Configure your tabs in Settings.'**
  String get configureTabsInSettings;

  /// No description provided for @emptyShelfTitle.
  ///
  /// In en, this message translates to:
  /// **'Your shelf is ready'**
  String get emptyShelfTitle;

  /// No description provided for @emptyShelfSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore a source and add your first title to this collection.'**
  String get emptyShelfSubtitle;

  /// No description provided for @exploreSources.
  ///
  /// In en, this message translates to:
  /// **'Explore sources'**
  String get exploreSources;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchTitlesHint.
  ///
  /// In en, this message translates to:
  /// **'Search titles...'**
  String get searchTitlesHint;

  /// No description provided for @searchEnabledSources.
  ///
  /// In en, this message translates to:
  /// **'Search enabled sources'**
  String get searchEnabledSources;

  /// No description provided for @typeToSearchLibrary.
  ///
  /// In en, this message translates to:
  /// **'Type to search your library'**
  String get typeToSearchLibrary;

  /// No description provided for @noResultsInLibrary.
  ///
  /// In en, this message translates to:
  /// **'No results in your library.'**
  String get noResultsInLibrary;

  /// No description provided for @couldNotSearchSource.
  ///
  /// In en, this message translates to:
  /// **'Could not search this source.'**
  String get couldNotSearchSource;

  /// No description provided for @noResultsInSource.
  ///
  /// In en, this message translates to:
  /// **'No results in this source.'**
  String get noResultsInSource;

  /// No description provided for @noTitlesFound.
  ///
  /// In en, this message translates to:
  /// **'No titles found.'**
  String get noTitlesFound;

  /// No description provided for @searchAnimeSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Search anime sources'**
  String get searchAnimeSourcesTitle;

  /// No description provided for @searchEnabledAnimeSourcesHint.
  ///
  /// In en, this message translates to:
  /// **'Search enabled anime sources'**
  String get searchEnabledAnimeSourcesHint;

  /// No description provided for @clearSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearchTooltip;

  /// No description provided for @animeSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This anime source is unavailable.'**
  String get animeSourceUnavailable;

  /// No description provided for @verifyInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Verify in browser'**
  String get verifyInBrowser;

  /// No description provided for @hostsCheckedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Hosts checked successfully.'**
  String get hostsCheckedSuccess;

  /// No description provided for @hostsCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check hosts: {error}'**
  String hostsCheckFailed(String error);

  /// No description provided for @sourceHostMonitorTitle.
  ///
  /// In en, this message translates to:
  /// **'Source Host Monitor'**
  String get sourceHostMonitorTitle;

  /// No description provided for @automaticHostChecks.
  ///
  /// In en, this message translates to:
  /// **'Automatic host checks'**
  String get automaticHostChecks;

  /// No description provided for @automaticHostChecksDesc.
  ///
  /// In en, this message translates to:
  /// **'Monitor manga and anime source availability'**
  String get automaticHostChecksDesc;

  /// No description provided for @autoCheckInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto-check interval'**
  String get autoCheckInterval;

  /// No description provided for @lastCheck.
  ///
  /// In en, this message translates to:
  /// **'Last check'**
  String get lastCheck;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @checkNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

  /// No description provided for @mangaSources.
  ///
  /// In en, this message translates to:
  /// **'Manga sources'**
  String get mangaSources;

  /// No description provided for @animeSources.
  ///
  /// In en, this message translates to:
  /// **'Anime sources'**
  String get animeSources;

  /// No description provided for @hostStatusOnline.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get hostStatusOnline;

  /// No description provided for @hostStatusOutdated.
  ///
  /// In en, this message translates to:
  /// **'outdated'**
  String get hostStatusOutdated;

  /// No description provided for @hostStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'checking'**
  String get hostStatusChecking;

  /// No description provided for @hostStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get hostStatusUnknown;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(int minutes);

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String hoursShort(int hours);

  /// No description provided for @hoursCount.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours'**
  String hoursCount(int hours);

  /// No description provided for @librarySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Library Settings'**
  String get librarySettingsTitle;

  /// No description provided for @libraryTabsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Library Tabs Settings'**
  String get libraryTabsSettingsTitle;

  /// No description provided for @libraryItemsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Library Items Settings'**
  String get libraryItemsSettingsTitle;

  /// No description provided for @backupAndRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupAndRestoreTitle;

  /// No description provided for @decoderTitle.
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get decoderTitle;

  /// No description provided for @decoderAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get decoderAutoTitle;

  /// No description provided for @decoderAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Prefer hardware decoding and fall back when necessary.'**
  String get decoderAutoDesc;

  /// No description provided for @decoderHardwareTitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get decoderHardwareTitle;

  /// No description provided for @decoderHardwareDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the device video decoder for lower battery usage.'**
  String get decoderHardwareDesc;

  /// No description provided for @decoderSoftwareTitle.
  ///
  /// In en, this message translates to:
  /// **'Software compatibility'**
  String get decoderSoftwareTitle;

  /// No description provided for @decoderSoftwareDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the CPU when a device codec produces visual errors.'**
  String get decoderSoftwareDesc;

  /// No description provided for @gesturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Gestures'**
  String get gesturesTitle;

  /// No description provided for @playerGesturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Player gestures'**
  String get playerGesturesTitle;

  /// No description provided for @playerGesturesDesc.
  ///
  /// In en, this message translates to:
  /// **'Double tap to seek; swipe left for volume and right for brightness.'**
  String get playerGesturesDesc;

  /// No description provided for @doubleTapSeekTitle.
  ///
  /// In en, this message translates to:
  /// **'Double-tap seek'**
  String get doubleTapSeekTitle;

  /// No description provided for @secondsCount.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds'**
  String secondsCount(int seconds);

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String secondsShort(int seconds);

  /// No description provided for @episodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodesTitle;

  /// No description provided for @autoSkipIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically skip intros'**
  String get autoSkipIntroTitle;

  /// No description provided for @autoSkipIntroDesc.
  ///
  /// In en, this message translates to:
  /// **'Only applies when the source supplies a verified intro range.'**
  String get autoSkipIntroDesc;

  /// No description provided for @subtitlesTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitlesTitle;

  /// No description provided for @preferredSubtitleLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferred subtitle language'**
  String get preferredSubtitleLanguageTitle;

  /// No description provided for @preferredSubtitleLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Use “auto” or a language code such as en, pt-BR or ja.'**
  String get preferredSubtitleLanguageDesc;

  /// No description provided for @subtitleFontTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle font'**
  String get subtitleFontTitle;

  /// No description provided for @subtitleFontDesc.
  ///
  /// In en, this message translates to:
  /// **'Noto Sans includes Portuguese and other extended characters.'**
  String get subtitleFontDesc;

  /// No description provided for @subtitleSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtitle size · {size} px'**
  String subtitleSizeLabel(int size);

  /// No description provided for @playbackHardwareWarning.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoding is recommended. Software mode may use considerably more battery and make the device warmer.'**
  String get playbackHardwareWarning;

  /// No description provided for @testVideoPlayer.
  ///
  /// In en, this message translates to:
  /// **'Test video player'**
  String get testVideoPlayer;

  /// No description provided for @playerDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'StarsLibrary player diagnostics'**
  String get playerDiagnosticsTitle;

  /// No description provided for @publicSampleVideo.
  ///
  /// In en, this message translates to:
  /// **'Public sample video'**
  String get publicSampleVideo;

  /// No description provided for @trackerCompletedUpdates.
  ///
  /// In en, this message translates to:
  /// **'{mediaType} tracker completed: {count} update(s).'**
  String trackerCompletedUpdates(String mediaType, int count);

  /// No description provided for @trackerRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to run tracker: {error}'**
  String trackerRunFailed(String error);

  /// No description provided for @enableChapterTracker.
  ///
  /// In en, this message translates to:
  /// **'Enable Chapter Tracker'**
  String get enableChapterTracker;

  /// No description provided for @enableEpisodeTracker.
  ///
  /// In en, this message translates to:
  /// **'Enable Episode Tracker'**
  String get enableEpisodeTracker;

  /// No description provided for @updateInterval.
  ///
  /// In en, this message translates to:
  /// **'Update Interval'**
  String get updateInterval;

  /// No description provided for @tabsToUpdate.
  ///
  /// In en, this message translates to:
  /// **'Tabs to Update'**
  String get tabsToUpdate;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// No description provided for @connectProvider.
  ///
  /// In en, this message translates to:
  /// **'Connect {provider}'**
  String connectProvider(String provider);

  /// No description provided for @oauthBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'Sign in on {provider}. StarsLibrary never sees or stores your password.'**
  String oauthBannerMessage(String provider);

  /// No description provided for @addPrimaryTabHint.
  ///
  /// In en, this message translates to:
  /// **'Add primary tab'**
  String get addPrimaryTabHint;

  /// No description provided for @tabsReorderTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: long-press and drag a primary tab onto another to nest it as subtab.'**
  String get tabsReorderTip;

  /// No description provided for @addSubtabToHint.
  ///
  /// In en, this message translates to:
  /// **'Add subtab to \"{tab}\"'**
  String addSubtabToHint(String tab);

  /// No description provided for @renameTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Tab'**
  String get renameTabTitle;

  /// No description provided for @enterNewTabNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter new tab name'**
  String get enterNewTabNameHint;

  /// No description provided for @backupCreatedIn.
  ///
  /// In en, this message translates to:
  /// **'Backup created in: {path}'**
  String backupCreatedIn(String path);

  /// No description provided for @backupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create backup: {error}'**
  String backupCreateFailed(String error);

  /// No description provided for @restoreBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get restoreBackupTitle;

  /// No description provided for @restoreBackupConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will replace your current library, history, tabs, and saved logins with the selected backup. Do you want to continue?'**
  String get restoreBackupConfirmMessage;

  /// No description provided for @restoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreAction;

  /// No description provided for @backupRestoredSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup restored successfully.'**
  String get backupRestoredSuccess;

  /// No description provided for @backupRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to restore backup: {error}'**
  String backupRestoreFailed(String error);

  /// No description provided for @backupSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup saved successfully.'**
  String get backupSavedSuccess;

  /// No description provided for @backupDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to download backup: {error}'**
  String backupDownloadFailed(String error);

  /// No description provided for @backupLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load backup: {error}'**
  String backupLoadFailed(String error);

  /// No description provided for @encryptedCompleteBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted complete backup'**
  String get encryptedCompleteBackupTitle;

  /// No description provided for @encryptedCompleteBackupDesc.
  ///
  /// In en, this message translates to:
  /// **'Includes manga and anime history, favorites, tabs, stored logins, and enabled sources. Keep the password safe.'**
  String get encryptedCompleteBackupDesc;

  /// No description provided for @createBackupButton.
  ///
  /// In en, this message translates to:
  /// **'Create Backup'**
  String get createBackupButton;

  /// No description provided for @loadBackupButton.
  ///
  /// In en, this message translates to:
  /// **'Load Backup'**
  String get loadBackupButton;

  /// No description provided for @noBackupsFound.
  ///
  /// In en, this message translates to:
  /// **'No backups found.'**
  String get noBackupsFound;

  /// No description provided for @downloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadTooltip;

  /// No description provided for @restoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreTooltip;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @protectBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Protect your backup'**
  String get protectBackupTitle;

  /// No description provided for @unlockBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock backup'**
  String get unlockBackupTitle;

  /// No description provided for @protectBackupDesc.
  ///
  /// In en, this message translates to:
  /// **'This password encrypts your library and stored logins. It cannot be recovered if you forget it.'**
  String get protectBackupDesc;

  /// No description provided for @unlockBackupDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the password used when this backup was created.'**
  String get unlockBackupDesc;

  /// No description provided for @backupPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPasswordLabel;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @createBackupAction.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get createBackupAction;

  /// No description provided for @unlockAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockAction;

  /// No description provided for @scrapperLoginsTitle.
  ///
  /// In en, this message translates to:
  /// **'Scrapper Logins'**
  String get scrapperLoginsTitle;

  /// No description provided for @loginWithTitle.
  ///
  /// In en, this message translates to:
  /// **'Login — {sourceName}'**
  String loginWithTitle(String sourceName);

  /// No description provided for @emailAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Email and password'**
  String get emailAndPassword;

  /// No description provided for @googleOrDiscord.
  ///
  /// In en, this message translates to:
  /// **'Google or Discord'**
  String get googleOrDiscord;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @loginAction.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginAction;

  /// No description provided for @logoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout from {sourceName}'**
  String logoutTitle(String sourceName);

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will remove the saved session for this scrapper. Are you sure you want to logout?'**
  String get logoutConfirmMessage;

  /// No description provided for @logoutAction.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutAction;

  /// No description provided for @scrapperLoginsInfo.
  ///
  /// In en, this message translates to:
  /// **'Manage the logins for sites that require authentication. Tokens are stored locally on the device. Logout to remove an expired or compromised token.'**
  String get scrapperLoginsInfo;

  /// No description provided for @noAuthScrappers.
  ///
  /// In en, this message translates to:
  /// **'No scrappers with authentication configured.'**
  String get noAuthScrappers;

  /// No description provided for @completeLogin.
  ///
  /// In en, this message translates to:
  /// **'Complete Login'**
  String get completeLogin;

  /// No description provided for @renewSession.
  ///
  /// In en, this message translates to:
  /// **'Renew Session'**
  String get renewSession;

  /// No description provided for @discoveryAndTrackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Discovery and tracking'**
  String get discoveryAndTrackingTitle;

  /// No description provided for @discoveryAndTrackingDesc.
  ///
  /// In en, this message translates to:
  /// **'Discover anime and manga with tracker metadata, then match titles against your enabled sources.'**
  String get discoveryAndTrackingDesc;

  /// No description provided for @aniListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Public catalog, dynamic tags and airing calendar'**
  String get aniListSubtitle;

  /// No description provided for @aniListOptionalLoginNote.
  ///
  /// In en, this message translates to:
  /// **'Login is optional for discovery and required only for future personal-list synchronization.'**
  String get aniListOptionalLoginNote;

  /// No description provided for @configuredByBuild.
  ///
  /// In en, this message translates to:
  /// **'Configured by this build'**
  String get configuredByBuild;

  /// No description provided for @aniListClientIdLabel.
  ///
  /// In en, this message translates to:
  /// **'AniList Client ID'**
  String get aniListClientIdLabel;

  /// No description provided for @malSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rankings, seasonal catalogs and account lists'**
  String get malSubtitle;

  /// No description provided for @malClientIdRequiredNote.
  ///
  /// In en, this message translates to:
  /// **'MAL requires a Client ID even for public requests.'**
  String get malClientIdRequiredNote;

  /// No description provided for @malClientIdLabel.
  ///
  /// In en, this message translates to:
  /// **'MAL Client ID'**
  String get malClientIdLabel;

  /// No description provided for @includeAdultContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Include adult content'**
  String get includeAdultContentTitle;

  /// No description provided for @includeAdultContentDesc.
  ///
  /// In en, this message translates to:
  /// **'Works with public tracker data; login is not required.'**
  String get includeAdultContentDesc;

  /// No description provided for @preferEnglishTitlesTitle.
  ///
  /// In en, this message translates to:
  /// **'Prefer English titles'**
  String get preferEnglishTitlesTitle;

  /// No description provided for @preferEnglishTitlesDesc.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Romaji titles are used whenever available.'**
  String get preferEnglishTitlesDesc;

  /// No description provided for @trackerConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Tracker configuration saved.'**
  String get trackerConfigSaved;

  /// No description provided for @trackerAccountConnected.
  ///
  /// In en, this message translates to:
  /// **'{provider} account connected.'**
  String trackerAccountConnected(String provider);

  /// No description provided for @registeredRedirectUriLabel.
  ///
  /// In en, this message translates to:
  /// **'Registered redirect URI'**
  String get registeredRedirectUriLabel;

  /// No description provided for @disconnectAction.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectAction;

  /// No description provided for @connectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectAction;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @connectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected as {username}'**
  String connectedAs(String username);

  /// No description provided for @trackerSecurityNote.
  ///
  /// In en, this message translates to:
  /// **'Register StarsLibrary in each tracker and use the exact redirect URI shown here. Tokens are kept in secure device storage; passwords and client secrets are never stored.'**
  String get trackerSecurityNote;

  /// No description provided for @searchingSourceInline.
  ///
  /// In en, this message translates to:
  /// **'{sourceTitle} · Searching…'**
  String searchingSourceInline(String sourceTitle);

  /// No description provided for @moreAction.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreAction;

  /// No description provided for @searchingThisSource.
  ///
  /// In en, this message translates to:
  /// **'Searching this source…'**
  String get searchingThisSource;

  /// No description provided for @unpinSourceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unpin source'**
  String get unpinSourceTooltip;

  /// No description provided for @pinSourceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pin source'**
  String get pinSourceTooltip;

  /// No description provided for @latestLabel.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latestLabel;

  /// No description provided for @trendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trendingLabel;

  /// No description provided for @sourceCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{source} other{sources}}'**
  String sourceCountLabel(int count);

  /// No description provided for @noActiveAnimeSources.
  ///
  /// In en, this message translates to:
  /// **'No active anime sources.'**
  String get noActiveAnimeSources;

  /// No description provided for @noActiveMangaSources.
  ///
  /// In en, this message translates to:
  /// **'No active manga sources.'**
  String get noActiveMangaSources;

  /// No description provided for @enableAnimeSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Enable an anime source in the Manage tab.'**
  String get enableAnimeSourceHint;

  /// No description provided for @enableMangaSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Enable a source in the Manage tab.'**
  String get enableMangaSourceHint;

  /// No description provided for @pinnedSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Pinned sources'**
  String get pinnedSourcesTitle;

  /// No description provided for @savedCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} saved'**
  String savedCountLabel(int count);

  /// No description provided for @enableProvidersToPlay.
  ///
  /// In en, this message translates to:
  /// **'Enable providers to browse and play episodes.'**
  String get enableProvidersToPlay;

  /// No description provided for @animeSourcesFutureUpdate.
  ///
  /// In en, this message translates to:
  /// **'Anime sources will be added in a future update.'**
  String get animeSourcesFutureUpdate;

  /// No description provided for @activeSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Active Sources'**
  String get activeSourcesTitle;

  /// No description provided for @inactiveSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Inactive Sources'**
  String get inactiveSourcesTitle;

  /// No description provided for @lastChapterReadSummary.
  ///
  /// In en, this message translates to:
  /// **'Last: Ch. {chapterTitle} • {readCount} read'**
  String lastChapterReadSummary(String chapterTitle, int readCount);

  /// No description provided for @chapterShort.
  ///
  /// In en, this message translates to:
  /// **'Ch. {title}'**
  String chapterShort(String title);

  /// No description provided for @noWatchedAnimeYet.
  ///
  /// In en, this message translates to:
  /// **'No watched anime yet.'**
  String get noWatchedAnimeYet;

  /// No description provided for @howDiscoverWorksTooltip.
  ///
  /// In en, this message translates to:
  /// **'How Discover works'**
  String get howDiscoverWorksTooltip;

  /// No description provided for @browseSeasonArchive.
  ///
  /// In en, this message translates to:
  /// **'Browse season archive'**
  String get browseSeasonArchive;

  /// No description provided for @searchTrackerTitlesHint.
  ///
  /// In en, this message translates to:
  /// **'Search tracker titles'**
  String get searchTrackerTitlesHint;

  /// No description provided for @filtersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filtersTooltip;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @discoverStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Choose what to explore'**
  String get discoverStep1Title;

  /// No description provided for @discoverStep1Desc.
  ///
  /// In en, this message translates to:
  /// **'Switch between Anime and Manga. Discover combines the trackers enabled in Account Settings.'**
  String get discoverStep1Desc;

  /// No description provided for @discoverStep2Desc.
  ///
  /// In en, this message translates to:
  /// **'Type a title or use filters to browse by popularity, rating, genres, and tags.'**
  String get discoverStep2Desc;

  /// No description provided for @discoverStep3Desc.
  ///
  /// In en, this message translates to:
  /// **'Tap a title for tracker details. Touch and hold it to search your enabled sources for that same title.'**
  String get discoverStep3Desc;

  /// No description provided for @noTrackerResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No tracker results found.'**
  String get noTrackerResultsFound;

  /// No description provided for @tryLoadingMoreAgain.
  ///
  /// In en, this message translates to:
  /// **'Try loading more again'**
  String get tryLoadingMoreAgain;

  /// No description provided for @youReachedTheEnd.
  ///
  /// In en, this message translates to:
  /// **'You reached the end.'**
  String get youReachedTheEnd;

  /// No description provided for @episodeNumber.
  ///
  /// In en, this message translates to:
  /// **'Episode {number}'**
  String episodeNumber(int number);

  /// No description provided for @orderByLabel.
  ///
  /// In en, this message translates to:
  /// **'Order by'**
  String get orderByLabel;

  /// No description provided for @sortPopularity.
  ///
  /// In en, this message translates to:
  /// **'Popularity'**
  String get sortPopularity;

  /// No description provided for @sortMostRecent.
  ///
  /// In en, this message translates to:
  /// **'Most recent'**
  String get sortMostRecent;

  /// No description provided for @sortHighestRated.
  ///
  /// In en, this message translates to:
  /// **'Highest rated'**
  String get sortHighestRated;

  /// No description provided for @findGenresOrTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Find genres or tags'**
  String get findGenresOrTagsLabel;

  /// No description provided for @applyAction.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyAction;

  /// No description provided for @couldNotLoadGenresAndTags.
  ///
  /// In en, this message translates to:
  /// **'Could not load genres and tags: {error}'**
  String couldNotLoadGenresAndTags(String error);

  /// No description provided for @noMatchingGenresOrTags.
  ///
  /// In en, this message translates to:
  /// **'No matching genres or tags.'**
  String get noMatchingGenresOrTags;

  /// No description provided for @genresLabel.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genresLabel;

  /// No description provided for @genresSelectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Genres ({count} selected)'**
  String genresSelectedLabel(int count);

  /// No description provided for @tagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsLabel;

  /// No description provided for @tagsSelectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags ({count} selected)'**
  String tagsSelectedLabel(int count);

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @couldNotLoadTrackerData.
  ///
  /// In en, this message translates to:
  /// **'Could not load tracker data.'**
  String get couldNotLoadTrackerData;

  /// No description provided for @enableTrackerToDiscover.
  ///
  /// In en, this message translates to:
  /// **'Enable a tracker to start discovering titles.'**
  String get enableTrackerToDiscover;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @searchSources.
  ///
  /// In en, this message translates to:
  /// **'Search sources'**
  String get searchSources;

  /// No description provided for @episodesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} episodes'**
  String episodesCount(int count);

  /// No description provided for @chaptersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} chapters'**
  String chaptersCount(int count);

  /// No description provided for @volumesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} volumes'**
  String volumesCount(int count);

  /// No description provided for @minutesPerEpisode.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min / episode'**
  String minutesPerEpisode(int minutes);

  /// No description provided for @scorePercentLabel.
  ///
  /// In en, this message translates to:
  /// **'{score}% score'**
  String scorePercentLabel(int score);

  /// No description provided for @synopsisTitle.
  ///
  /// In en, this message translates to:
  /// **'Synopsis'**
  String get synopsisTitle;

  /// No description provided for @genresSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genresSectionTitle;

  /// No description provided for @tagsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsSectionTitle;

  /// No description provided for @studiosSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Studios'**
  String get studiosSectionTitle;

  /// No description provided for @openOnTracker.
  ///
  /// In en, this message translates to:
  /// **'Open on tracker'**
  String get openOnTracker;

  /// No description provided for @reviewsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviewsSectionTitle;

  /// No description provided for @readFullReview.
  ///
  /// In en, this message translates to:
  /// **'Read full review'**
  String get readFullReview;

  /// No description provided for @seasonArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Season archive'**
  String get seasonArchiveTitle;

  /// No description provided for @browseAnyAnimeSeason.
  ///
  /// In en, this message translates to:
  /// **'Browse any anime season'**
  String get browseAnyAnimeSeason;

  /// No description provided for @browseAnyAnimeSeasonDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose a season and year, then scroll to load more titles.'**
  String get browseAnyAnimeSeasonDesc;

  /// No description provided for @seasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get seasonLabel;

  /// No description provided for @yearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get yearLabel;

  /// No description provided for @seasonWinter.
  ///
  /// In en, this message translates to:
  /// **'Winter'**
  String get seasonWinter;

  /// No description provided for @seasonSpring.
  ///
  /// In en, this message translates to:
  /// **'Spring'**
  String get seasonSpring;

  /// No description provided for @seasonSummer.
  ///
  /// In en, this message translates to:
  /// **'Summer'**
  String get seasonSummer;

  /// No description provided for @seasonFall.
  ///
  /// In en, this message translates to:
  /// **'Fall'**
  String get seasonFall;

  /// No description provided for @noTitlesForSeason.
  ///
  /// In en, this message translates to:
  /// **'No titles found for this season.'**
  String get noTitlesForSeason;

  /// No description provided for @enableAnimeSourceBeforeSearching.
  ///
  /// In en, this message translates to:
  /// **'Enable an anime source before searching.'**
  String get enableAnimeSourceBeforeSearching;

  /// No description provided for @noAnimeSourceAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'No anime source is available yet.'**
  String get noAnimeSourceAvailableYet;

  /// No description provided for @enableMangaSourceBeforeSearching.
  ///
  /// In en, this message translates to:
  /// **'Enable a manga source before searching.'**
  String get enableMangaSourceBeforeSearching;

  /// No description provided for @animeShelfReady.
  ///
  /// In en, this message translates to:
  /// **'Your anime shelf is ready'**
  String get animeShelfReady;

  /// No description provided for @animeShelfSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open an anime source and tap the heart to save a title.'**
  String get animeShelfSubtitle;

  /// No description provided for @exploreAnimeSources.
  ///
  /// In en, this message translates to:
  /// **'Explore anime sources'**
  String get exploreAnimeSources;

  /// No description provided for @moveAnimeTo.
  ///
  /// In en, this message translates to:
  /// **'Move anime to'**
  String get moveAnimeTo;

  /// No description provided for @watchedLabel.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get watchedLabel;

  /// No description provided for @lastEpisodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Last: {episodeTitle}'**
  String lastEpisodeLabel(String episodeTitle);

  /// No description provided for @searchSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Search {sourceName}'**
  String searchSourceHint(String sourceName);

  /// No description provided for @advancedFilters.
  ///
  /// In en, this message translates to:
  /// **'Advanced filters'**
  String get advancedFilters;

  /// No description provided for @resetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetAction;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get applyFilters;

  /// No description provided for @anyOption.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get anyOption;

  /// No description provided for @couldNotOpenEpisode.
  ///
  /// In en, this message translates to:
  /// **'Could not open this episode: {error}'**
  String couldNotOpenEpisode(String error);

  /// No description provided for @chooseVideoServer.
  ///
  /// In en, this message translates to:
  /// **'Choose a video server'**
  String get chooseVideoServer;

  /// No description provided for @chooseVideoServerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can try another server if playback fails.'**
  String get chooseVideoServerSubtitle;

  /// No description provided for @renameAnimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename anime'**
  String get renameAnimeTitle;

  /// No description provided for @libraryTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Library title'**
  String get libraryTitleLabel;

  /// No description provided for @manageAnimeTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage anime tabs'**
  String get manageAnimeTabsTitle;

  /// No description provided for @enableAnotherAnimeSourceBeforeMigrating.
  ///
  /// In en, this message translates to:
  /// **'Enable another anime source before migrating.'**
  String get enableAnotherAnimeSourceBeforeMigrating;

  /// No description provided for @noMatchingTitleInEnabledSources.
  ///
  /// In en, this message translates to:
  /// **'No matching title was found in enabled sources.'**
  String get noMatchingTitleInEnabledSources;

  /// No description provided for @migrateAnimeTo.
  ///
  /// In en, this message translates to:
  /// **'Migrate anime to'**
  String get migrateAnimeTo;

  /// No description provided for @addToConnectedTrackersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add to connected trackers'**
  String get addToConnectedTrackersTooltip;

  /// No description provided for @removeFromLibraryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get removeFromLibraryTooltip;

  /// No description provided for @addToLibraryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get addToLibraryTooltip;

  /// No description provided for @animeOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Anime options'**
  String get animeOptionsTooltip;

  /// No description provided for @migrateAnimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Migrate anime'**
  String get migrateAnimeTitle;

  /// No description provided for @manageTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage tabs'**
  String get manageTabsTitle;

  /// No description provided for @noEpisodesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No episodes available.'**
  String get noEpisodesAvailable;

  /// No description provided for @playbackSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Playback settings'**
  String get playbackSettingsTooltip;

  /// No description provided for @seekBackwardTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back {seconds}s'**
  String seekBackwardTooltip(int seconds);

  /// No description provided for @seekForwardTooltip.
  ///
  /// In en, this message translates to:
  /// **'Forward {seconds}s'**
  String seekForwardTooltip(int seconds);

  /// No description provided for @embeddedAndSourceTracks.
  ///
  /// In en, this message translates to:
  /// **'Embedded and source-provided tracks'**
  String get embeddedAndSourceTracks;

  /// No description provided for @offLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get offLabel;

  /// No description provided for @embeddedLabel.
  ///
  /// In en, this message translates to:
  /// **'Embedded'**
  String get embeddedLabel;

  /// No description provided for @videoDecoderTitle.
  ///
  /// In en, this message translates to:
  /// **'Video decoder'**
  String get videoDecoderTitle;

  /// No description provided for @paginatedMode.
  ///
  /// In en, this message translates to:
  /// **'Paginated mode'**
  String get paginatedMode;

  /// No description provided for @reverseReadingDirection.
  ///
  /// In en, this message translates to:
  /// **'Reverse reading direction'**
  String get reverseReadingDirection;

  /// No description provided for @saveStoryReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Save story reminder'**
  String get saveStoryReminderTitle;

  /// No description provided for @whatHappenedHereLabel.
  ///
  /// In en, this message translates to:
  /// **'What happened here?'**
  String get whatHappenedHereLabel;

  /// No description provided for @addShortNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a short note about this key moment'**
  String get addShortNoteHint;

  /// No description provided for @saveReminderAction.
  ///
  /// In en, this message translates to:
  /// **'Save reminder'**
  String get saveReminderAction;

  /// No description provided for @imageOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Image Options'**
  String get imageOptionsTitle;

  /// No description provided for @saveImageAction.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImageAction;

  /// No description provided for @saveAsStoryReminderAction.
  ///
  /// In en, this message translates to:
  /// **'Save as Story Reminder'**
  String get saveAsStoryReminderAction;

  /// No description provided for @saveAsStoryReminderDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep this image with a chapter note'**
  String get saveAsStoryReminderDesc;

  /// No description provided for @shareImageAction.
  ///
  /// In en, this message translates to:
  /// **'Share Image'**
  String get shareImageAction;

  /// No description provided for @webViewNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Web view not supported on this platform.'**
  String get webViewNotSupported;

  /// No description provided for @openExternally.
  ///
  /// In en, this message translates to:
  /// **'Open externally'**
  String get openExternally;

  /// No description provided for @unsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Unsupported platform'**
  String get unsupportedPlatform;

  /// No description provided for @readingProgressSaved.
  ///
  /// In en, this message translates to:
  /// **'Reading progress saved'**
  String get readingProgressSaved;

  /// No description provided for @combineTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Combine tags'**
  String get combineTagsTitle;

  /// No description provided for @searchCountAction.
  ///
  /// In en, this message translates to:
  /// **'Search ({count})'**
  String searchCountAction(int count);

  /// No description provided for @couldNotLoadStoryReminders.
  ///
  /// In en, this message translates to:
  /// **'Could not load story reminders'**
  String get couldNotLoadStoryReminders;

  /// No description provided for @deleteReminderQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete reminder?'**
  String get deleteReminderQuestion;

  /// No description provided for @updatingBookDetails.
  ///
  /// In en, this message translates to:
  /// **'Updating book details...'**
  String get updatingBookDetails;

  /// No description provided for @bookDetailsUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Book details updated successfully!'**
  String get bookDetailsUpdatedSuccess;

  /// No description provided for @failedToUpdateBookDetails.
  ///
  /// In en, this message translates to:
  /// **'Failed to update book details: {error}'**
  String failedToUpdateBookDetails(String error);

  /// No description provided for @tabsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get tabsLabel;

  /// No description provided for @renameBookAction.
  ///
  /// In en, this message translates to:
  /// **'Rename book'**
  String get renameBookAction;

  /// No description provided for @migrateBookAction.
  ///
  /// In en, this message translates to:
  /// **'Migrate book'**
  String get migrateBookAction;

  /// No description provided for @readingProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'Reading progress'**
  String get readingProgressLabel;

  /// No description provided for @markChapterRead.
  ///
  /// In en, this message translates to:
  /// **'Mark chapter as read'**
  String get markChapterRead;

  /// No description provided for @markThisAndPreviousRead.
  ///
  /// In en, this message translates to:
  /// **'Mark this and previous chapters as read'**
  String get markThisAndPreviousRead;

  /// No description provided for @markChapterUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark chapter as unread'**
  String get markChapterUnread;

  /// No description provided for @removeReadMarksThroughHere.
  ///
  /// In en, this message translates to:
  /// **'Remove read marks through this chapter'**
  String get removeReadMarksThroughHere;

  /// No description provided for @loadingChapter.
  ///
  /// In en, this message translates to:
  /// **'Loading chapter...'**
  String get loadingChapter;

  /// No description provided for @failedToLoadChapter.
  ///
  /// In en, this message translates to:
  /// **'Failed to load chapter: {error}'**
  String failedToLoadChapter(String error);

  /// No description provided for @loginWithEmailPassword.
  ///
  /// In en, this message translates to:
  /// **'Login with email and password'**
  String get loginWithEmailPassword;

  /// No description provided for @loginViaBrowser.
  ///
  /// In en, this message translates to:
  /// **'Login via browser'**
  String get loginViaBrowser;

  /// No description provided for @fillEmailAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Please fill in both email and password.'**
  String get fillEmailAndPassword;

  /// No description provided for @noDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get noDataAvailable;

  /// No description provided for @loginToSource.
  ///
  /// In en, this message translates to:
  /// **'Login to {sourceName}'**
  String loginToSource(String sourceName);

  /// No description provided for @loadingBookDetails.
  ///
  /// In en, this message translates to:
  /// **'Loading book details...'**
  String get loadingBookDetails;

  /// No description provided for @failedToLoadBookDetails.
  ///
  /// In en, this message translates to:
  /// **'Failed to load book details: {error}'**
  String failedToLoadBookDetails(String error);

  /// No description provided for @couldNotLoadFilters.
  ///
  /// In en, this message translates to:
  /// **'Could not load filters: {error}'**
  String couldNotLoadFilters(String error);

  /// No description provided for @couldNotLoadGenres.
  ///
  /// In en, this message translates to:
  /// **'Could not load genres: {error}'**
  String couldNotLoadGenres(String error);

  /// No description provided for @filterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterTitle;

  /// No description provided for @filterByLabel.
  ///
  /// In en, this message translates to:
  /// **'Filter by:'**
  String get filterByLabel;

  /// No description provided for @genreLabel.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genreLabel;

  /// No description provided for @authorLabel.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get authorLabel;

  /// No description provided for @ratingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ratingLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
