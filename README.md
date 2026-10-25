# StarsLibrary

StarsLibrary is an open-source Flutter app for discovering, organizing, reading, and watching manga and anime from multiple sources in one library.

The project combines native readers and video playback with source-specific WebView fallbacks, progressive multi-source search, personal library organization, and AniList/MyAnimeList integration. Android is the primary tested platform; Windows support is also included.

> Third-party sources can change or become unavailable without notice. StarsLibrary does not host or distribute media.

## Highlights

- Separate manga and anime libraries with tabs, subtabs, history, favorites, and migration between compatible sources.
- Progressive multi-source search: each source appears as soon as it finishes instead of waiting for every provider.
- Discover experience backed by AniList and MyAnimeList metadata, seasonal listings, release calendar, and source matching.
- Native manga reader with vertical/webtoon and paginated modes, page preloading, progress tracking, and WebView fallback.
- Native anime player with quality/server selection, subtitles, decoder controls, and browser-assisted stream resolution when required.
- Source grouping by content type and language, including optional R-rated providers.
- Source health checks, library update tracking, local notifications, and manual refresh.
- Versioned backup and restore for library data and settings.
- Authentication-aware sources with browser verification and persistent sessions where supported.

## What is new in 1.4.0

### Anime support

- Added a typed anime-source architecture and a dedicated anime library.
- Added native catalog, details, episode, search, and playback flows.
- Added progressive multi-source anime search, including matches from the local library.
- Added server and quality selection plus native playback/WebView resolution for protected or embedded players.
- Grouped anime sources by language in the source manager.

### Manga improvements

- Migrated bundled manga providers to the typed `MangaSource` contract.
- Added source-grouped search results with horizontal title carousels.
- Improved normalized metadata in manga catalogs and library cards.
- Improved the native reader with per-page streaming, visible loading states, theme alignment, and preload behavior.
- Fixed Leitura Manga chapters whose image URLs do not include conventional file extensions.

### Discovery and trackers

- Added AniList and MyAnimeList discovery and tracking flows.
- AniList uses the bundled StarsLibrary OAuth client configuration.
- Added seasonal discovery, media details, release calendar, account lists, and matching tracker titles against enabled sources.

### New sources

Anime:

- AniTube
- AniWave
- Smart Animes
- Goyabu
- Hentai Haven (R-rated)
- AnimeQ

Manga:

- MangaDex
- Seita Celestial
- LuraToons
- MediocreScan
- Leitura Manga
- HDoujin (R-rated)

Source availability and individual features depend on each upstream website. Adult providers and adult discovery results are labeled and can be kept disabled.

## Screenshots and media

- [Project banner](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Banner/1775403379926.png)
- [Reader](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-08-506_com.example.star_scrapper_app.jpg)
- [Source browser](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-21-198_com.example.star_scrapper_app.jpg)
- [Library](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-25-131_com.example.star_scrapper_app.jpg)
- [Search](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-31-113_com.example.star_scrapper_app.jpg)

## Supported platforms

- Android (primary tested platform)
- Windows

## Tech stack

- Flutter and Dart
- `provider` for application state
- `http` and `html` for source integrations
- `webview_flutter`, `webview_windows`, and `desktop_webview_window` for authentication and browser-assisted playback
- `media_kit` for native video playback
- `shared_preferences` and `flutter_secure_storage` for local state and tracker sessions
- `flutter_local_notifications` and `cron` for library update alerts
- `cached_network_image` for cover and artwork caching

## Getting started

### Requirements

- Flutter SDK compatible with Dart `>=3.4.3 <4.0.0`
- Android Studio for Android builds, or Visual Studio with Desktop development with C++ for Windows builds

### Run locally

```bash
git clone https://github.com/darlanZero/Star-Scrapper-App.git
cd Star-Scrapper-App
flutter pub get
flutter run
```

### Build

```bash
flutter build apk --release --split-per-abi
flutter build windows --release
```

## Project structure

```text
lib/
  application/       # Library, tracker, and source state
  classes/           # Shared configuration and legacy-compatible services
  components/        # Reusable UI
  data/
    sources/          # Manga and anime integrations
    trackers/         # AniList and MyAnimeList services
  domain/             # Typed source and tracker contracts
  infrastructure/     # Browser/WebView integration
  pages/              # App screens, reader, and player
```

## Contributing

Contributions are welcome. Please keep source integrations isolated behind the typed contracts and include focused tests for parsing, catalog behavior, and playback or reader resolution.

1. Fork the repository.
2. Create a feature branch.
3. Commit and test your changes.
4. Open a pull request describing the source behavior and validation performed.

## Disclaimer

StarsLibrary is intended for educational and personal use. Users are responsible for complying with the terms, licenses, and copyright rules that apply to third-party services and content in their jurisdiction.
