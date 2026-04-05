# Star Scrapper App

Manga and comics scrapper app built with Flutter, focused on Android and Windows, with authentication-aware sources, native chapter reading, and a flexible personal library system.

Heavily inspired by [MangaDex](https://mangadex.org/) and Mihon, with its own approach to source integration and library organization.

## Banner

![Star Scrapper App Banner](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Banner/1775403379926.png)

## Why Star Scrapper App?

- Multi-source reading experience in a single app.
- Protected-source authentication support (OAuth, Cloudflare, form login).
- Native chapter reading with fallback to WebView when needed.
- Dynamic library tabs and subtabs with automatic migration from legacy data.
- Background update tracker with local notifications.
- Built-in backup and restore for app state.

## What is new in v1.3.0

### New Scrapers

- **LuraToons**: PT-BR source with Google OAuth and Django form authentication, full chapter support, and WebView proxy for HttpOnly session cookies.
- **MediocreScan**: PT-BR source with Cloudflare Turnstile authentication, native chapter image reader, and RSC-based "Recently Updated" feed sorted by last chapter date.
- **Seita Celestial**: now marked as outdated in the UI due to unstable host availability.

### Authentication System

- WebView login flow for Cloudflare Turnstile, Google OAuth, and form-based auth.
- Persistent sessions via `SessionManager` and `SharedPreferences`.
- Automatic session restore when opening a source library.
- Dedicated **Scrapper Logins** settings page to log in, renew, and log out per source.

### Dynamic Library Tabs and Subtabs

- Hierarchical tab structure (primary tabs + nested subtabs).
- Drag-and-drop primary tab nesting.
- Reordering, renaming, and deleting tabs with automatic book remapping.
- Legacy single-tab migration to multi-tab model.

### Native Chapter Reader

- Paginated mode and vertical scroll mode.
- Right-to-left reading support.
- Auto-hiding controls with tap-to-show.
- Automatic fallback to WebView when native loading is not available.
- Per-book chapter progress tracking.

### Chapter Update Tracker

- Background scheduled checks for selected tabs (default: every 24 hours).
- Push notifications via `flutter_local_notifications`.
- Manual "Run tracker now" trigger in Settings.
- Last-known chapter token tracking to avoid false positives.

### Font Host Status Checker

- Automatic periodic host health checks (HEAD/GET) for each source base URL.
- Status values: `online`, `outdated`, `checking`, and `unknown`.
- Configurable check interval (default: every 6 hours).

### Backup and Restore

- Full app state backup to `.starsbackup` (versioned JSON schema + typed entries).
- Covers favorites, tabs, chapter history, and settings.
- Export backup to Downloads.
- Import from Downloads or Documents.
- In-app backup manager to list, restore, and delete backups.

### Image Loading and Pagination Improvements

- Migration from `Image.network` to `CachedNetworkImage` across core screens.
- Per-source `imageHeaders` to improve compatibility (including Cloudflare-protected CDNs).
- Skeleton placeholders and graceful error widgets for failed image loads.
- Infinite scroll fix for live-updated pagination and proper loading/error state handling.

### UI and Build Updates

- Visual refresh across major screens.
- Settings reorganization with dedicated subsections (Library, Tabs, Backup, Scrapper Logins).
- Android build upgrades:
  - AGP `8.5.1` -> `8.9.1`
  - Gradle `8.7` -> `8.11.1`
  - Kotlin `2.0.0` -> `2.1.0`
- Core library desugaring enabled for `flutter_local_notifications`.
- Fixed `dependencies {}` placement in `app/build.gradle`.

## Supported Platforms

- Android
- Windows

## Tech Stack

- Flutter / Dart
- `provider` for state management
- `http` and HTML parsing for source communication
- `webview_flutter` and `webview_windows` for authenticated sources
- `shared_preferences` for persistence
- `flutter_local_notifications` + `cron` for update tracking
- `cached_network_image` for robust media loading

## Screenshots and Media

### Reading Page

![Reading Page](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-08-506_com.example.star_scrapper_app.jpg)

### Download Fonts Page

![Download Fonts Page](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-21-198_com.example.star_scrapper_app.jpg)

### Fonts List Page

![Fonts List Page](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-25-131_com.example.star_scrapper_app.jpg)

### Search Books Page

![Search Books Page](https://pixeldrain.com/d/me/utilitaries/Starsscrapper/Screenshot_2026-04-05-12-28-31-113_com.example.star_scrapper_app.jpg)

## Getting Started

### Requirements

- Flutter SDK `>=3.4.3 <4.0.0`
- Dart SDK compatible with the Flutter version above
- Android Studio or VS Code with Flutter extensions

### Run Locally

```bash
git clone https://github.com/darlanZero/Star-Scrapper-App.git
cd Star-Scrapper-App/star_scrapper_app
flutter pub get
flutter run
```

### Build

```bash
flutter build apk
flutter build windows
```

## Project Structure

```text
lib/
  classes/
    Scrappers/
    services/
    static/
  components/
  pages/
```

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Open a Pull Request

## Disclaimer

Star Scrapper App is an open-source project intended for educational and personal use.
Users are responsible for respecting the terms of service and copyright rules of third-party content providers.
