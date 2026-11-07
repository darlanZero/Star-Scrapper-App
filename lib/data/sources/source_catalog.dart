import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/data/sources/anime/anitube_source.dart';
import 'package:star_scrapper_app/data/sources/anime/aniwave_source.dart';
import 'package:star_scrapper_app/data/sources/anime/smart_animes_source.dart';
import 'package:star_scrapper_app/data/sources/anime/goyabu_source.dart';
import 'package:star_scrapper_app/data/sources/anime/hentai_haven_source.dart';
import 'package:star_scrapper_app/data/sources/anime/animeq_source.dart';
import 'package:star_scrapper_app/data/sources/anime/animy_anime_source.dart';
import 'package:star_scrapper_app/data/sources/anime/porn_comic_video_source.dart';
import 'package:star_scrapper_app/data/sources/anime/hanime1_source.dart';
import 'package:star_scrapper_app/data/sources/manga/mangadex_source.dart';
import 'package:star_scrapper_app/data/sources/manga/seita_celestial_source.dart';
import 'package:star_scrapper_app/data/sources/manga/luratoons_source.dart';
import 'package:star_scrapper_app/data/sources/manga/mediocrescan_source.dart';
import 'package:star_scrapper_app/data/sources/manga/imperio_britannia_source.dart';
import 'package:star_scrapper_app/data/sources/manga/nexus_toons_source.dart';
import 'package:star_scrapper_app/data/sources/manga/leitura_manga_source.dart';
import 'package:star_scrapper_app/data/sources/manga/manga_livre_source.dart';
import 'package:star_scrapper_app/data/sources/manga/animy_manga_source.dart';
import 'package:star_scrapper_app/data/sources/manga/yomu_source.dart';
import 'package:star_scrapper_app/data/sources/manga/mangaflix_source.dart';
import 'package:star_scrapper_app/data/sources/manga/hdoujin_source.dart';
import 'package:star_scrapper_app/data/sources/manga/onisaga_source.dart';
import 'package:star_scrapper_app/data/sources/manga/nhentai_source.dart';
import 'package:star_scrapper_app/data/sources/manga/nhentai_xxx_source.dart';
import 'package:star_scrapper_app/data/sources/manga/xcomic_source.dart';
import 'package:star_scrapper_app/data/sources/manga/comick_source.dart';
import 'package:star_scrapper_app/data/sources/manga/porn_comic_source.dart';
import 'package:star_scrapper_app/infrastructure/webview/browser_html_loader.dart';

/// Single registry for the sources bundled with the application.
abstract final class SourceCatalog {
  /// Video providers use the typed [AnimeSource] contract and stay separate
  /// from the legacy image/chapter scrapers.
  static List<AnimeSource> createAnimeSources() => [
        AnitubeSource(),
        AniwaveSource(),
        SmartAnimesSource(browserHtmlLoader: BrowserHtmlLoader.load),
        GoyabuSource(
          browserHtmlLoader: BrowserHtmlLoader.load,
          browserImageLoader: BrowserHtmlLoader.loadImage,
        ),
        HentaiHavenSource(),
        AnimeQSource(),
        AnimyAnimeSource(),
        PornComicVideoSource(),
        Hanime1Source(
          browserHtmlLoader: (uri, userAgent) => BrowserHtmlLoader.loadRawWhen(
            uri,
            userAgent,
            uri.path == '/watch'
                ? '#shareBtn-title, video#player'
                : uri.path == '/download'
                    ? '.download-table a[data-url]'
                    : '.video-item-container, .genre-option',
          ),
          browserImageLoader: BrowserHtmlLoader.loadImage,
        ),
      ];

  /// Manga/comic providers using the typed [MangaSource] contract (replaces the
  /// legacy [Scrapper] registration below).
  static List<MangaSource> createMangaSources() => [
        MangadexSource(),
        SeitaCelestialSource(),
        LuraToonsSource(
          browserHtmlLoader: BrowserHtmlLoader.load,
          binaryLoader: BrowserHtmlLoader.loadBytes,
        ),
        MediocrescanSource(),
        ImperioBritanniaSource(),
        NexusToonsSource(),
        LeituraMangaSource(),
        MangaLivreSource(),
        AnimyMangaSource(),
        YomuSource(
          browserHtmlLoader: BrowserHtmlLoader.load,
          scrolledHtmlLoader: BrowserHtmlLoader.loadScrolled,
          readerPageLoader: BrowserHtmlLoader.lazyReaderUrls,
        ),
        MangaFlixSource(),
        HDoujinSource(),
        NHentaiSource(),
        NHentaiXxxSource(),
        XComicSource(),
        ComickSource(
          browserHtmlLoader: (uri, userAgent) => BrowserHtmlLoader.loadWhen(
            uri,
            userAgent,
            'pre',
          ),
          binaryLoader: BrowserHtmlLoader.loadBytes,
        ),
        OniSagaSource(
          browserHtmlLoader: (uri, userAgent) => BrowserHtmlLoader.loadWhen(
            uri,
            userAgent,
            'a[href*="/manga/"]',
          ),
          browserImageLoader: BrowserHtmlLoader.loadImage,
          interactedHtmlLoader: (
            uri,
            userAgent,
            clickSelector, {
            required maxClicks,
          }) =>
              BrowserHtmlLoader.loadInteracted(
            uri,
            userAgent,
            clickSelector,
            maxClicks: maxClicks,
          ),
        ),
        PornComicMangaSource(),
      ];

  static List<Fonte> createAll() => [
        Fonte(
          id: 'mangadex',
          image: 'https://mangadex.org/img/brand/mangadex-logo.svg',
          name: 'Mangadex',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: MangadexSource(),
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
          api: SeitaCelestialSource(),
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
          api: LuraToonsSource(
            browserHtmlLoader: BrowserHtmlLoader.load,
            binaryLoader: BrowserHtmlLoader.loadBytes,
            browserPostLoader: (uri, headers) => BrowserHtmlLoader.requestBytes(
              uri,
              headers,
              method: 'POST',
            ),
          ),
          contentType: SourceContentType.manga,
        ),
        Fonte(
          id: 'mediocrescan',
          image: 'https://mediocrescan.com/favicon.png',
          name: 'MediocreScan',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: MediocrescanSource(),
          contentType: SourceContentType.manga,
        ),
        Fonte(
          id: 'imperio_britannia',
          image: 'https://imperiodabritannia.net/favicon-32x32.png',
          name: 'Império da Britannia',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: ImperioBritanniaSource(),
          contentType: SourceContentType.manga,
          // Catálogo misto com um formato adulto separado.
          isRRated: false,
        ),
        Fonte(
          id: 'nexus_toons',
          image: 'https://nexustoons.com/favicon.ico',
          name: 'Nexus Toons',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: NexusToonsSource(),
          contentType: SourceContentType.manga,
          // Catálogo misto; conteúdo adulto é controlado pelo filtro da source.
          isRRated: false,
        ),
        Fonte(
          id: 'leitura_manga',
          image: 'https://leituramanga.net/icon.png',
          name: 'Leitura Manga',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: LeituraMangaSource(),
          contentType: SourceContentType.manga,
          // Catálogo misto: há obras adultas, mas esse não é o foco da source.
          isRRated: false,
        ),
        Fonte(
          id: 'manga_livre',
          image:
              'https://mangalivre.blog/wp-content/uploads/2026/09/download-2-1.png',
          name: 'MangaLivre',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: MangaLivreSource(),
          contentType: SourceContentType.manga,
          // Catálogo misto: possui títulos adultos, mas não é adult-only.
          isRRated: false,
        ),
        Fonte(
          id: 'animy_manga',
          image: 'https://animy.net/favicon.ico',
          name: 'Animy',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: AnimyMangaSource(),
          contentType: SourceContentType.manga,
          // Catálogo misto: conteúdo adulto é filtrável, não é o foco da source.
          isRRated: false,
        ),
        Fonte(
          id: 'yomu',
          image: 'https://yomu.com.br/favicon.ico',
          name: 'Yomu',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: YomuSource(
            browserHtmlLoader: BrowserHtmlLoader.load,
            scrolledHtmlLoader: BrowserHtmlLoader.loadScrolled,
            readerPageLoader: BrowserHtmlLoader.lazyReaderUrls,
          ),
          contentType: SourceContentType.manga,
          // Catálogo misto; os formatos adultos ficam separados nos filtros.
          isRRated: false,
        ),
        Fonte(
          id: 'mangaflix',
          image: 'https://mangaflix.net/favicon.ico',
          name: 'MangaFlix',
          languagePrefix: 'Pt-BR',
          flags: [
            'https://cdn.countryflags.com/thumbs/brazil/flag-3d-250.png',
          ],
          api: MangaFlixSource(),
          contentType: SourceContentType.manga,
          // Mixed catalog: adult releases are isolated in their own variant.
          isRRated: false,
        ),
        Fonte(
          id: 'hdoujin',
          image: 'https://hdoujin.org/favicon.png',
          name: 'HDoujin',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: HDoujinSource(),
          contentType: SourceContentType.manga,
          isRRated: true,
        ),
        Fonte(
          id: 'nhentai',
          image: 'https://nhentai.to/favicon.ico',
          name: 'nHentai',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: NHentaiSource(),
          contentType: SourceContentType.manga,
          isRRated: true,
        ),
        Fonte(
          id: 'nhentai_xxx',
          image: 'https://nhentai.xxx/favicon.ico',
          name: 'nHentai.xxx',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: NHentaiXxxSource(),
          contentType: SourceContentType.manga,
          isRRated: true,
        ),
        Fonte(
          id: 'xcomic',
          image: 'https://xcomic.net/static/img/fav.ico?3',
          name: 'xComic',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: XComicSource(),
          contentType: SourceContentType.manga,
          // Mixed catalog: adult titles coexist with general-audience works.
          isRRated: false,
        ),
        Fonte(
          id: 'comick',
          image: 'https://comick.live/favicon.ico',
          name: 'ComicK',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: ComickSource(
            browserHtmlLoader: (uri, userAgent) => BrowserHtmlLoader.loadWhen(
              uri,
              userAgent,
              'pre',
            ),
            binaryLoader: BrowserHtmlLoader.loadBytes,
          ),
          contentType: SourceContentType.manga,
          // Mixed catalog with Safe, Suggestive and Erotica rating filters.
          isRRated: false,
        ),
        Fonte(
          id: 'porn_comic',
          image: 'https://porn-comic.com/favicon.ico',
          name: 'Porn-Comic',
          languagePrefix: 'All',
          flags: ['https://cdn-icons-png.flaticon.com/512/44/44386.png'],
          api: PornComicMangaSource(),
          contentType: SourceContentType.manga,
          isRRated: true,
        ),
        Fonte(
          id: 'onisaga',
          image: 'https://onisaga.com/favicon.ico',
          name: 'OniSaga',
          languagePrefix: 'EN-US',
          flags: [
            'https://cdn.countryflags.com/thumbs/united-states-of-america/flag-3d-250.png',
          ],
          api: OniSagaSource(
            browserHtmlLoader: (uri, userAgent) => BrowserHtmlLoader.loadWhen(
              uri,
              userAgent,
              'a[href*="/manga/"]',
            ),
            browserImageLoader: BrowserHtmlLoader.loadImage,
            interactedHtmlLoader: (
              uri,
              userAgent,
              clickSelector, {
              required maxClicks,
            }) =>
                BrowserHtmlLoader.loadInteracted(
              uri,
              userAgent,
              clickSelector,
              maxClicks: maxClicks,
            ),
          ),
          contentType: SourceContentType.manga,
          // Mixed catalog: adult works are a subset, not the source focus.
          isRRated: false,
        ),
      ];
}
