import 'package:star_scrapper_app/classes/Scrappers/mangadex_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/pt-br/demon_sect_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/sites/luratoons_scrapper.dart';
import 'package:star_scrapper_app/classes/Scrappers/sites/mediocrescan_scrapper.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/data/sources/anime/anitube_source.dart';
import 'package:star_scrapper_app/data/sources/anime/aniwave_source.dart';
import 'package:star_scrapper_app/data/sources/anime/smart_animes_source.dart';
import 'package:star_scrapper_app/infrastructure/webview/browser_html_loader.dart';

/// Single registry for the sources bundled with the application.
abstract final class SourceCatalog {
  /// Video providers use the typed [AnimeSource] contract and stay separate
  /// from the legacy image/chapter scrapers.
  static List<AnimeSource> createAnimeSources() => [
        AnitubeSource(),
        AniwaveSource(),
        SmartAnimesSource(browserHtmlLoader: BrowserHtmlLoader.load),
      ];

  static List<Fonte> createAll() => [
        Fonte(
          id: 'mangadex',
          image: 'https://mangadex.org/img/brand/mangadex-logo.svg',
          name: 'Mangadex',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: MangadexScrapper(),
          contentType: SourceContentType.manga,
          isRRated: true,
        ),
        Fonte(
          id: 'seita_celestial',
          image:
              'https://seitacelestial.com/wp-content/uploads/2024/08/logo-extended.png',
          name: 'Seita Celestial',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: DemonSectScrapper(),
          contentType: SourceContentType.manga,
        ),
        Fonte(
          id: 'luratoons',
          image:
              'https://luratoons.net/media/images/cropped-lura_scans.format-webp.width-250.webp',
          name: 'LuraToons',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: LuraToonsScrapper(),
          contentType: SourceContentType.manga,
        ),
        Fonte(
          id: 'mediocrescan',
          image:
              'https://mediocrescan.com/_next/image?url=%2Flogo.png&w=48&q=75',
          name: 'MediocreScan',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: MediocreScanScrapper(),
          contentType: SourceContentType.manga,
        ),
      ];
}
