// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'StarsLibrary';

  @override
  String get navLibrary => 'Biblioteca';

  @override
  String get navDiscover => 'Descubrir';

  @override
  String get navSources => 'Fuentes';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get searchForMangas => 'Buscar mangas';

  @override
  String get searchForAnime => 'Buscar animes';

  @override
  String get ok => 'OK';

  @override
  String get gotIt => 'Entendido';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get retry => 'Reintentar';

  @override
  String get refresh => 'Actualizar';

  @override
  String get clear => 'Limpiar';

  @override
  String get later => 'Más tarde';

  @override
  String get loading => 'Cargando...';

  @override
  String get loadingMore => 'Cargando más...';

  @override
  String get error => 'Error';

  @override
  String get search => 'Buscar';

  @override
  String get all => 'Todos';

  @override
  String get loginRequired => 'Inicio de sesión requerido';

  @override
  String get settingsTabGeneral => 'General';

  @override
  String get settingsTabAccount => 'Cuenta';

  @override
  String get settingsTabAbout => 'Acerca de';

  @override
  String get generalTitle => 'General';

  @override
  String get generalLibraryTitle => 'Biblioteca';

  @override
  String get generalLibraryDesc =>
      'Administra pestañas de la biblioteca, elementos guardados, copias de seguridad, historial de lectura y actualizaciones.';

  @override
  String get generalSourcesTitle => 'Fuentes';

  @override
  String get generalSourcesDesc =>
      'Elige qué fuentes de manga y anime están habilitadas y disponibles en toda la aplicación.';

  @override
  String get generalPlaybackTitle => 'Reproducción de video';

  @override
  String get generalPlaybackDesc =>
      'Ajusta el reproductor nativo, decodificación por hardware, gestos, subtítulos y opciones de compatibilidad.';

  @override
  String get languageSectionTitle => 'Idioma';

  @override
  String get languageSystemDefault => 'Predeterminado del sistema';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePortugueseBrazil => 'Português (Brasil)';

  @override
  String get languageSpanish => 'Español';

  @override
  String get appearanceTitle => 'Apariencia';

  @override
  String get accountSettingsTitle => 'Ajustes de Cuenta';

  @override
  String get accountSourceLoginsTitle => 'Inicios de sesión de fuentes';

  @override
  String get accountSourceLoginsDesc =>
      'Inicia sesión en fuentes que requieren cuenta, renueva sesiones del navegador o desconecta accesos guardados.';

  @override
  String get accountTrackersTitle => 'Trackers';

  @override
  String get accountTrackersDesc =>
      'Conecta y configura servicios como AniList y MyAnimeList para Descubrir, progreso y sincronización.';

  @override
  String get aboutTitle => 'Acerca de StarsLibrary';

  @override
  String get aboutHeroTitle => 'Tus historias, una biblioteca';

  @override
  String get aboutHeroDesc =>
      'Explora, organiza, lee manga y mira anime desde tus fuentes activas — con descubrimiento por trackers y reproductor nativo.';

  @override
  String get aboutChipMultiSource => 'Multifuente';

  @override
  String get aboutChipNoAds => 'Sin anuncios';

  @override
  String get aboutChipOpenSource => 'Código abierto';

  @override
  String get aboutApplicationTitle => 'Aplicación';

  @override
  String get aboutVersionLabel => 'Versión';

  @override
  String get aboutBuildLabel => 'Compilación';

  @override
  String get aboutCheckingUpdates => 'Comprobando…';

  @override
  String get aboutCheckUpdates => 'Buscar actualizaciones';

  @override
  String get aboutSourceCodeTitle => 'Código fuente';

  @override
  String get aboutSourceCodeSubtitle => 'Ver el proyecto en GitHub';

  @override
  String get aboutWebsiteTitle => 'Sitio web de StarsLibrary';

  @override
  String get aboutWebsiteSubtitle => 'Noticias e información del proyecto';

  @override
  String get aboutDisclaimer =>
      'StarsLibrary no aloja contenido de terceros y no está afiliado con proveedores, autores ni editoriales.';

  @override
  String get aboutCouldNotOpenLink => 'No se pudo abrir el enlace';

  @override
  String get aboutUpToDateTitle => 'StarsLibrary está actualizado';

  @override
  String aboutUpToDateMessage(String version) {
    return 'Estás usando la versión $version.';
  }

  @override
  String get aboutUpdateAvailableTitle => 'Actualización disponible';

  @override
  String aboutUpdateAvailableMessage(
      String releaseVersion, String currentVersion) {
    return 'StarsLibrary $releaseVersion está disponible. Actualmente tienes $currentVersion.';
  }

  @override
  String get aboutViewUpdate => 'Ver actualización';

  @override
  String get aboutUpdateCheckFailedTitle => 'No se pudo buscar actualizaciones';

  @override
  String get aboutUpdateCheckFailedMessage =>
      'Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get manageOrganization => 'Administrar Organización';

  @override
  String get noSubtabsForPrimaryTab =>
      'No hay subpestañas para esta pestaña principal.';

  @override
  String get chapterNavigationNotSupported =>
      'La navegación entre capítulos no es compatible con esta fuente.';

  @override
  String get noNextChapter => 'No hay un capítulo siguiente.';

  @override
  String get noPreviousChapter => 'No hay un capítulo anterior.';

  @override
  String get webViewSessionCleared => 'Sesión y cookies de WebView borradas.';

  @override
  String get clearWebViewSessionTooltip =>
      'Borrar sesión y cookies de WebView (debug)';

  @override
  String get catalogFilterFeatured => 'Destacados';

  @override
  String get catalogFilterCatalog => 'Catálogo';

  @override
  String get catalogFilterAllAnime => 'Todos los animes';

  @override
  String get catalogFilterSubtitled => 'Subtitulados';

  @override
  String get catalogFilterDubbed => 'Doblados';

  @override
  String get catalogFilterManhwa => 'Manhwa';

  @override
  String get catalogFilterDonghua => 'Donghua';

  @override
  String get catalogFilterMovies => 'Películas';

  @override
  String get catalogFilterSubtitledMovies => 'Películas subtituladas';

  @override
  String get catalogFilterDubbedMovies => 'Películas dobladas';

  @override
  String get catalogFilterAdult => 'Adulto';

  @override
  String get catalogFilterAdult18 => 'Hentai (+18)';

  @override
  String get catalogFilterPopular => 'Más vistos';

  @override
  String get catalogFilterMostLiked => 'Más gustados';

  @override
  String get catalogFilterPopularToday => 'Hoy';

  @override
  String get catalogFilterPopularWeek => 'Esta semana';

  @override
  String get catalogFilterPopularMonth => 'Este mes';

  @override
  String get catalogFilterRecent => 'Recientes';

  @override
  String get catalogFilterLatestEpisodes => 'Últimos episodios';

  @override
  String get catalogFilterNewEpisodes => 'Nuevos episodios';

  @override
  String get catalogFilterNewDubbed => 'Nuevos doblados';

  @override
  String get catalogFilterNewReleases => 'Novedades';

  @override
  String get catalogFilterEpisodeMostViewed => 'Episodios más vistos';

  @override
  String get catalogFilterSeriesNewest => 'Series más nuevas';

  @override
  String get catalogFilterSeriesPopular => 'Series populares';

  @override
  String get catalogFilterSeriesMostViewed => 'Series más vistas';

  @override
  String get catalogFilterUpdated => 'Actualizados';

  @override
  String get catalogFilterAdded => 'Agregados recientemente';

  @override
  String get catalogFilterAiring => 'En emisión';

  @override
  String get catalogFilterUpcoming => 'Próximamente';

  @override
  String get catalogFilterCompleted => 'Finalizados';

  @override
  String get catalogFilterEpisodesPopular => 'Episodios · Populares';

  @override
  String get catalogFilterEpisodesMostViewed => 'Episodios · Más vistos';

  @override
  String get weekdaySunday => 'Domingo';

  @override
  String get weekdayMonday => 'Lunes';

  @override
  String get weekdayTuesday => 'Martes';

  @override
  String get weekdayWednesday => 'Miércoles';

  @override
  String get weekdayThursday => 'Jueves';

  @override
  String get weekdayFriday => 'Viernes';

  @override
  String get weekdaySaturday => 'Sábado';

  @override
  String get weekdayUnknown => 'Desconocido';

  @override
  String get discoverAtAGlance => 'Descubrir de un vistazo';

  @override
  String get discoverSearchCatalog => 'Buscar en el catálogo del tracker';

  @override
  String get discoverOpenOrFindSource => 'Abrir o encontrar una fuente';

  @override
  String get discoverStartExploring => 'Empezar a explorar';

  @override
  String get endOfList => '— fin de la lista —';

  @override
  String loginRequiredMessage(String sourceName) {
    return 'Inicia sesión en $sourceName para acceder al contenido.';
  }

  @override
  String subtabsOfPrimaryTab(String tabName) {
    return 'Subpestañas de \"$tabName\"';
  }

  @override
  String get sourcesTabSources => 'Fuentes';

  @override
  String get sourcesTabManage => 'Administrar';

  @override
  String get sourcesTabHistory => 'Historial';

  @override
  String get sourcesTabMigrate => 'Migrar';

  @override
  String get libraryTabManga => 'Manga';

  @override
  String get libraryTabAnime => 'Anime';

  @override
  String get sortBooksTooltip => 'Ordenar títulos';

  @override
  String get configureTabsInSettings => 'Configura tus pestañas en Ajustes.';

  @override
  String get emptyShelfTitle => 'Tu estantería está lista';

  @override
  String get emptyShelfSubtitle =>
      'Explora una fuente y agrega tu primer título a esta colección.';

  @override
  String get exploreSources => 'Explorar fuentes';

  @override
  String get searchTitle => 'Buscar';

  @override
  String get searchTitlesHint => 'Buscar títulos...';

  @override
  String get searchEnabledSources => 'Buscar en fuentes activas';

  @override
  String get typeToSearchLibrary => 'Escribe para buscar en tu biblioteca';

  @override
  String get noResultsInLibrary => 'Sin resultados en tu biblioteca.';

  @override
  String get couldNotSearchSource => 'No se pudo buscar en esta fuente.';

  @override
  String get noResultsInSource => 'Sin resultados en esta fuente.';

  @override
  String get noTitlesFound => 'No se encontraron títulos.';

  @override
  String get searchAnimeSourcesTitle => 'Buscar fuentes de anime';

  @override
  String get searchEnabledAnimeSourcesHint =>
      'Buscar en fuentes de anime activas';

  @override
  String get clearSearchTooltip => 'Limpiar búsqueda';

  @override
  String get animeSourceUnavailable =>
      'Esta fuente de anime no está disponible.';

  @override
  String get verifyInBrowser => 'Verificar en el navegador';

  @override
  String get hostsCheckedSuccess => 'Hosts comprobados correctamente.';

  @override
  String hostsCheckFailed(String error) {
    return 'Error al comprobar hosts: $error';
  }

  @override
  String get sourceHostMonitorTitle => 'Monitor de Hosts';

  @override
  String get automaticHostChecks => 'Comprobación automática de hosts';

  @override
  String get automaticHostChecksDesc =>
      'Supervisar disponibilidad de fuentes de manga y anime';

  @override
  String get autoCheckInterval => 'Intervalo de comprobación';

  @override
  String get lastCheck => 'Última comprobación';

  @override
  String get never => 'Nunca';

  @override
  String get checkNow => 'Comprobar ahora';

  @override
  String get mangaSources => 'Fuentes de manga';

  @override
  String get animeSources => 'Fuentes de anime';

  @override
  String get hostStatusOnline => 'en línea';

  @override
  String get hostStatusOutdated => 'desactualizada';

  @override
  String get hostStatusChecking => 'comprobando';

  @override
  String get hostStatusUnknown => 'desconocido';

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
    return '$hours horas';
  }

  @override
  String get librarySettingsTitle => 'Ajustes de Biblioteca';

  @override
  String get libraryTabsSettingsTitle => 'Ajustes de Pestañas';

  @override
  String get libraryItemsSettingsTitle => 'Ajustes de Elementos';

  @override
  String get backupAndRestoreTitle => 'Copia de Seguridad y Restauración';

  @override
  String get decoderTitle => 'Decodificador';

  @override
  String get decoderAutoTitle => 'Automático';

  @override
  String get decoderAutoDesc =>
      'Prefiere decodificación por hardware y recurre a software si es necesario.';

  @override
  String get decoderHardwareTitle => 'Hardware';

  @override
  String get decoderHardwareDesc =>
      'Usa el decodificador de video del dispositivo para menor consumo de batería.';

  @override
  String get decoderSoftwareTitle => 'Compatibilidad por software';

  @override
  String get decoderSoftwareDesc =>
      'Usa la CPU cuando un códec del dispositivo produce errores visuales.';

  @override
  String get gesturesTitle => 'Gestos';

  @override
  String get playerGesturesTitle => 'Gestos del reproductor';

  @override
  String get playerGesturesDesc =>
      'Doble toque para avanzar/retroceder; desliza a la izquierda para volumen y a la derecha para brillo.';

  @override
  String get doubleTapSeekTitle => 'Salto con doble toque';

  @override
  String secondsCount(int seconds) {
    return '$seconds segundos';
  }

  @override
  String secondsShort(int seconds) {
    return '$seconds s';
  }

  @override
  String get episodesTitle => 'Episodios';

  @override
  String get autoSkipIntroTitle => 'Saltar intros automáticamente';

  @override
  String get autoSkipIntroDesc =>
      'Solo se aplica cuando la fuente proporciona un rango de intro verificado.';

  @override
  String get subtitlesTitle => 'Subtítulos';

  @override
  String get preferredSubtitleLanguageTitle => 'Idioma preferido de subtítulos';

  @override
  String get preferredSubtitleLanguageDesc =>
      'Usa “auto” o un código de idioma como en, pt-BR o ja.';

  @override
  String get subtitleFontTitle => 'Fuente de subtítulos';

  @override
  String get subtitleFontDesc =>
      'Noto Sans incluye español, portugués y otros caracteres extendidos.';

  @override
  String subtitleSizeLabel(int size) {
    return 'Tamaño de subtítulos · $size px';
  }

  @override
  String get playbackHardwareWarning =>
      'Se recomienda la decodificación por hardware. El modo por software puede consumir mucha más batería y calentar el dispositivo.';

  @override
  String get testVideoPlayer => 'Probar reproductor de video';

  @override
  String get playerDiagnosticsTitle =>
      'Diagnóstico del reproductor StarsLibrary';

  @override
  String get publicSampleVideo => 'Video de muestra público';

  @override
  String trackerCompletedUpdates(String mediaType, int count) {
    return 'Rastreo de $mediaType completado: $count actualización(es).';
  }

  @override
  String trackerRunFailed(String error) {
    return 'Error al ejecutar rastreador: $error';
  }

  @override
  String get enableChapterTracker => 'Activar Rastreador de Capítulos';

  @override
  String get enableEpisodeTracker => 'Activar Rastreador de Episodios';

  @override
  String get updateInterval => 'Intervalo de Actualización';

  @override
  String get tabsToUpdate => 'Pestañas a Actualizar';

  @override
  String get saveSettings => 'Guardar Ajustes';

  @override
  String connectProvider(String provider) {
    return 'Conectar $provider';
  }

  @override
  String oauthBannerMessage(String provider) {
    return 'Inicia sesión en $provider. StarsLibrary nunca ve ni guarda tu contraseña.';
  }

  @override
  String get addPrimaryTabHint => 'Agregar pestaña principal';

  @override
  String get tabsReorderTip =>
      'Consejo: mantén presionada y arrastra una pestaña principal sobre otra para anidarla como subpestaña.';

  @override
  String addSubtabToHint(String tab) {
    return 'Agregar subpestaña a \"$tab\"';
  }

  @override
  String get renameTabTitle => 'Renombrar Pestaña';

  @override
  String get enterNewTabNameHint => 'Ingresa el nuevo nombre de la pestaña';

  @override
  String backupCreatedIn(String path) {
    return 'Copia creada en: $path';
  }

  @override
  String backupCreateFailed(String error) {
    return 'Error al crear copia de seguridad: $error';
  }

  @override
  String get restoreBackupTitle => 'Restaurar Copia';

  @override
  String get restoreBackupConfirmMessage =>
      'Esto reemplazará tu biblioteca, historial, pestañas e inicios de sesión guardados actuales con la copia seleccionada. ¿Deseas continuar?';

  @override
  String get restoreAction => 'Restaurar';

  @override
  String get backupRestoredSuccess => 'Copia restaurada correctamente.';

  @override
  String backupRestoreFailed(String error) {
    return 'Error al restaurar copia: $error';
  }

  @override
  String get backupSavedSuccess => 'Copia guardada correctamente.';

  @override
  String backupDownloadFailed(String error) {
    return 'Error al descargar copia: $error';
  }

  @override
  String backupLoadFailed(String error) {
    return 'Error al cargar copia: $error';
  }

  @override
  String get encryptedCompleteBackupTitle => 'Copia completa cifrada';

  @override
  String get encryptedCompleteBackupDesc =>
      'Incluye historial de manga y anime, favoritos, pestañas, inicios de sesión guardados y fuentes activas. Guarda la contraseña de forma segura.';

  @override
  String get createBackupButton => 'Crear Copia';

  @override
  String get loadBackupButton => 'Cargar Copia';

  @override
  String get noBackupsFound => 'No se encontraron copias de seguridad.';

  @override
  String get downloadTooltip => 'Descargar';

  @override
  String get restoreTooltip => 'Restaurar';

  @override
  String get deleteTooltip => 'Eliminar';

  @override
  String get protectBackupTitle => 'Proteger copia de seguridad';

  @override
  String get unlockBackupTitle => 'Desbloquear copia';

  @override
  String get protectBackupDesc =>
      'Esta contraseña cifra tu biblioteca e inicios de sesión guardados. No se puede recuperar si la olvidas.';

  @override
  String get unlockBackupDesc =>
      'Ingresa la contraseña usada cuando se creó esta copia.';

  @override
  String get backupPasswordLabel => 'Contraseña de la copia';

  @override
  String get confirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get createBackupAction => 'Crear copia';

  @override
  String get unlockAction => 'Desbloquear';

  @override
  String get scrapperLoginsTitle => 'Inicios de Sesión de Fuentes';

  @override
  String loginWithTitle(String sourceName) {
    return 'Iniciar sesión — $sourceName';
  }

  @override
  String get emailAndPassword => 'Correo y contraseña';

  @override
  String get googleOrDiscord => 'Google o Discord';

  @override
  String get emailLabel => 'Correo';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get loginAction => 'Iniciar sesión';

  @override
  String logoutTitle(String sourceName) {
    return 'Cerrar sesión de $sourceName';
  }

  @override
  String get logoutConfirmMessage =>
      'Esto eliminará la sesión guardada de esta fuente. ¿Seguro que quieres cerrar sesión?';

  @override
  String get logoutAction => 'Cerrar sesión';

  @override
  String get scrapperLoginsInfo =>
      'Administra los inicios de sesión de sitios que requieren autenticación. Los tokens se guardan localmente en el dispositivo. Cierra sesión para eliminar un token caducado o comprometido.';

  @override
  String get noAuthScrappers => 'No hay fuentes con autenticación configurada.';

  @override
  String get completeLogin => 'Completar Inicio de Sesión';

  @override
  String get renewSession => 'Renovar Sesión';

  @override
  String get discoveryAndTrackingTitle => 'Descubrimiento y seguimiento';

  @override
  String get discoveryAndTrackingDesc =>
      'Descubre anime y manga con metadatos de trackers y busca títulos en tus fuentes activas.';

  @override
  String get aniListSubtitle =>
      'Catálogo público, etiquetas dinámicas y calendario de emisión';

  @override
  String get aniListOptionalLoginNote =>
      'El inicio de sesión es opcional para descubrir y solo se requiere para sincronización futura de listas personales.';

  @override
  String get configuredByBuild => 'Configurado por esta compilación';

  @override
  String get aniListClientIdLabel => 'Client ID de AniList';

  @override
  String get malSubtitle =>
      'Rankings, catálogos de temporada y listas de cuenta';

  @override
  String get malClientIdRequiredNote =>
      'MAL requiere un Client ID incluso para solicitudes públicas.';

  @override
  String get malClientIdLabel => 'Client ID de MAL';

  @override
  String get includeAdultContentTitle => 'Incluir contenido adulto';

  @override
  String get includeAdultContentDesc =>
      'Funciona con datos públicos de trackers; no requiere inicio de sesión.';

  @override
  String get preferEnglishTitlesTitle => 'Preferir títulos en inglés';

  @override
  String get preferEnglishTitlesDesc =>
      'Desactivado por defecto. Se usan títulos en romaji cuando están disponibles.';

  @override
  String get trackerConfigSaved => 'Configuración del tracker guardada.';

  @override
  String trackerAccountConnected(String provider) {
    return 'Cuenta de $provider conectada.';
  }

  @override
  String get registeredRedirectUriLabel => 'URI de redirección registrada';

  @override
  String get disconnectAction => 'Desconectar';

  @override
  String get connectAction => 'Conectar';

  @override
  String get notConnected => 'No conectado';

  @override
  String connectedAs(String username) {
    return 'Conectado como $username';
  }

  @override
  String get trackerSecurityNote =>
      'Registra StarsLibrary en cada tracker usando exactamente la URI de redirección mostrada aquí. Los tokens se guardan en el almacenamiento seguro del dispositivo; las contraseñas y secretos de cliente nunca se almacenan.';

  @override
  String searchingSourceInline(String sourceTitle) {
    return '$sourceTitle · Buscando…';
  }

  @override
  String get moreAction => 'Más';

  @override
  String get searchingThisSource => 'Buscando en esta fuente…';

  @override
  String get unpinSourceTooltip => 'Desfijar fuente';

  @override
  String get pinSourceTooltip => 'Fijar fuente';

  @override
  String get latestLabel => 'Recientes';

  @override
  String get trendingLabel => 'Tendencias';

  @override
  String sourceCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fuentes',
      one: 'fuente',
    );
    return '$count $_temp0';
  }

  @override
  String get noActiveAnimeSources => 'No hay fuentes de anime activas.';

  @override
  String get noActiveMangaSources => 'No hay fuentes de manga activas.';

  @override
  String get enableAnimeSourceHint =>
      'Activa una fuente de anime en la pestaña Administrar.';

  @override
  String get enableMangaSourceHint =>
      'Activa una fuente en la pestaña Administrar.';

  @override
  String get pinnedSourcesTitle => 'Fuentes fijadas';

  @override
  String savedCountLabel(int count) {
    return '$count guardadas';
  }

  @override
  String get enableProvidersToPlay =>
      'Activa proveedores para explorar y reproducir episodios.';

  @override
  String get animeSourcesFutureUpdate =>
      'Se agregarán fuentes de anime en una futura actualización.';

  @override
  String get activeSourcesTitle => 'Fuentes Activas';

  @override
  String get inactiveSourcesTitle => 'Fuentes Inactivas';

  @override
  String lastChapterReadSummary(String chapterTitle, int readCount) {
    return 'Último: Cap. $chapterTitle • $readCount leído(s)';
  }

  @override
  String chapterShort(String title) {
    return 'Cap. $title';
  }

  @override
  String get noWatchedAnimeYet => 'Aún no hay animes vistos.';

  @override
  String get howDiscoverWorksTooltip => 'Cómo funciona Descubrir';

  @override
  String get browseSeasonArchive => 'Explorar archivo de temporadas';

  @override
  String get searchTrackerTitlesHint => 'Buscar títulos en el tracker';

  @override
  String get filtersTooltip => 'Filtros';

  @override
  String get notNow => 'Ahora no';

  @override
  String get discoverStep1Title => 'Elige qué explorar';

  @override
  String get discoverStep1Desc =>
      'Alterna entre Anime y Manga. Descubrir combina los trackers activados en Ajustes de Cuenta.';

  @override
  String get discoverStep2Desc =>
      'Escribe un título o usa filtros para explorar por popularidad, puntuación, géneros y etiquetas.';

  @override
  String get discoverStep3Desc =>
      'Toca un título para ver detalles del tracker. Mantén presionado para buscar en tus fuentes activas.';

  @override
  String get noTrackerResultsFound =>
      'No se encontraron resultados en el tracker.';

  @override
  String get tryLoadingMoreAgain => 'Intentar cargar más de nuevo';

  @override
  String get youReachedTheEnd => 'Has llegado al final.';

  @override
  String episodeNumber(int number) {
    return 'Episodio $number';
  }

  @override
  String get orderByLabel => 'Ordenar por';

  @override
  String get sortPopularity => 'Popularidad';

  @override
  String get sortMostRecent => 'Más recientes';

  @override
  String get sortHighestRated => 'Mejor valorados';

  @override
  String get findGenresOrTagsLabel => 'Buscar géneros o etiquetas';

  @override
  String get applyAction => 'Aplicar';

  @override
  String couldNotLoadGenresAndTags(String error) {
    return 'No se pudieron cargar géneros y etiquetas: $error';
  }

  @override
  String get noMatchingGenresOrTags =>
      'No hay géneros ni etiquetas coincidentes.';

  @override
  String get genresLabel => 'Géneros';

  @override
  String genresSelectedLabel(int count) {
    return 'Géneros ($count seleccionados)';
  }

  @override
  String get tagsLabel => 'Etiquetas';

  @override
  String tagsSelectedLabel(int count) {
    return 'Etiquetas ($count seleccionadas)';
  }

  @override
  String get tryAgain => 'Intentar de nuevo';

  @override
  String get couldNotLoadTrackerData =>
      'No se pudieron cargar los datos del tracker.';

  @override
  String get enableTrackerToDiscover =>
      'Activa un tracker para empezar a descubrir títulos.';

  @override
  String get openSettings => 'Abrir ajustes';

  @override
  String get searchSources => 'Buscar fuentes';

  @override
  String episodesCount(int count) {
    return '$count episodios';
  }

  @override
  String chaptersCount(int count) {
    return '$count capítulos';
  }

  @override
  String volumesCount(int count) {
    return '$count volúmenes';
  }

  @override
  String minutesPerEpisode(int minutes) {
    return '$minutes min / episodio';
  }

  @override
  String scorePercentLabel(int score) {
    return '$score% puntuación';
  }

  @override
  String get synopsisTitle => 'Sinopsis';

  @override
  String get genresSectionTitle => 'Géneros';

  @override
  String get tagsSectionTitle => 'Etiquetas';

  @override
  String get studiosSectionTitle => 'Estudios';

  @override
  String get openOnTracker => 'Abrir en el tracker';

  @override
  String get reviewsSectionTitle => 'Reseñas';

  @override
  String get readFullReview => 'Leer reseña completa';

  @override
  String get seasonArchiveTitle => 'Archivo de temporadas';

  @override
  String get browseAnyAnimeSeason => 'Explorar cualquier temporada';

  @override
  String get browseAnyAnimeSeasonDesc =>
      'Elige una temporada y un año, luego desplázate para cargar más títulos.';

  @override
  String get seasonLabel => 'Temporada';

  @override
  String get yearLabel => 'Año';

  @override
  String get seasonWinter => 'Invierno';

  @override
  String get seasonSpring => 'Primavera';

  @override
  String get seasonSummer => 'Verano';

  @override
  String get seasonFall => 'Otoño';

  @override
  String get noTitlesForSeason =>
      'No se encontraron títulos para esta temporada.';

  @override
  String get enableAnimeSourceBeforeSearching =>
      'Activa una fuente de anime antes de buscar.';

  @override
  String get noAnimeSourceAvailableYet =>
      'Aún no hay fuentes de anime disponibles.';

  @override
  String get enableMangaSourceBeforeSearching =>
      'Activa una fuente de manga antes de buscar.';

  @override
  String get animeShelfReady => 'Tu estantería de anime está lista';

  @override
  String get animeShelfSubtitle =>
      'Abre una fuente de anime y toca el corazón para guardar un título.';

  @override
  String get exploreAnimeSources => 'Explorar fuentes de anime';

  @override
  String get moveAnimeTo => 'Mover anime a';

  @override
  String get watchedLabel => 'Visto';

  @override
  String lastEpisodeLabel(String episodeTitle) {
    return 'Último: $episodeTitle';
  }

  @override
  String searchSourceHint(String sourceName) {
    return 'Buscar en $sourceName';
  }

  @override
  String get advancedFilters => 'Filtros avanzados';

  @override
  String get resetAction => 'Restablecer';

  @override
  String get applyFilters => 'Aplicar filtros';

  @override
  String get anyOption => 'Cualquiera';

  @override
  String couldNotOpenEpisode(String error) {
    return 'No se pudo abrir este episodio: $error';
  }

  @override
  String get chooseVideoServer => 'Elige un servidor de video';

  @override
  String get chooseVideoServerSubtitle =>
      'Puedes probar otro servidor si falla la reproducción.';

  @override
  String get renameAnimeTitle => 'Renombrar anime';

  @override
  String get libraryTitleLabel => 'Título en la biblioteca';

  @override
  String get manageAnimeTabsTitle => 'Administrar pestañas de anime';

  @override
  String get enableAnotherAnimeSourceBeforeMigrating =>
      'Activa otra fuente de anime antes de migrar.';

  @override
  String get noMatchingTitleInEnabledSources =>
      'No se encontró ningún título coincidente en las fuentes activas.';

  @override
  String get migrateAnimeTo => 'Migrar anime a';

  @override
  String get addToConnectedTrackersTooltip => 'Agregar a trackers conectados';

  @override
  String get removeFromLibraryTooltip => 'Eliminar de la biblioteca';

  @override
  String get addToLibraryTooltip => 'Agregar a la biblioteca';

  @override
  String get animeOptionsTooltip => 'Opciones del anime';

  @override
  String get migrateAnimeTitle => 'Migrar anime';

  @override
  String get manageTabsTitle => 'Administrar pestañas';

  @override
  String get noEpisodesAvailable => 'No hay episodios disponibles.';

  @override
  String get playbackSettingsTooltip => 'Ajustes de reproducción';

  @override
  String seekBackwardTooltip(int seconds) {
    return 'Retroceder ${seconds}s';
  }

  @override
  String seekForwardTooltip(int seconds) {
    return 'Avanzar ${seconds}s';
  }

  @override
  String get embeddedAndSourceTracks =>
      'Pistas integradas y proporcionadas por la fuente';

  @override
  String get offLabel => 'Desactivado';

  @override
  String get embeddedLabel => 'Integrada';

  @override
  String get videoDecoderTitle => 'Decodificador de video';

  @override
  String get paginatedMode => 'Modo paginado';

  @override
  String get reverseReadingDirection => 'Invertir dirección de lectura';

  @override
  String get saveStoryReminderTitle => 'Guardar recordatorio de historia';

  @override
  String get whatHappenedHereLabel => '¿Qué pasó aquí?';

  @override
  String get addShortNoteHint => 'Agrega una nota breve sobre este momento';

  @override
  String get saveReminderAction => 'Guardar recordatorio';

  @override
  String get imageOptionsTitle => 'Opciones de Imagen';

  @override
  String get saveImageAction => 'Guardar Imagen';

  @override
  String get saveAsStoryReminderAction => 'Guardar como Recordatorio';

  @override
  String get saveAsStoryReminderDesc =>
      'Guarda esta imagen con una nota del capítulo';

  @override
  String get shareImageAction => 'Compartir Imagen';

  @override
  String get webViewNotSupported => 'WebView no compatible en esta plataforma.';

  @override
  String get openExternally => 'Abrir externamente';

  @override
  String get unsupportedPlatform => 'Plataforma no compatible';

  @override
  String get readingProgressSaved => 'Progreso de lectura guardado';

  @override
  String get combineTagsTitle => 'Combinar etiquetas';

  @override
  String searchCountAction(int count) {
    return 'Buscar ($count)';
  }

  @override
  String get couldNotLoadStoryReminders =>
      'No se pudieron cargar los recordatorios';

  @override
  String get deleteReminderQuestion => '¿Eliminar recordatorio?';

  @override
  String get updatingBookDetails => 'Actualizando detalles del título...';

  @override
  String get bookDetailsUpdatedSuccess =>
      '¡Detalles actualizados correctamente!';

  @override
  String failedToUpdateBookDetails(String error) {
    return 'Error al actualizar detalles: $error';
  }

  @override
  String get tabsLabel => 'Pestañas';

  @override
  String get renameBookAction => 'Renombrar título';

  @override
  String get migrateBookAction => 'Migrar título';

  @override
  String get readingProgressLabel => 'Progreso de lectura';

  @override
  String get markChapterRead => 'Marcar capítulo como leído';

  @override
  String get markThisAndPreviousRead =>
      'Marcar este y capítulos anteriores como leídos';

  @override
  String get markChapterUnread => 'Marcar capítulo como no leído';

  @override
  String get removeReadMarksThroughHere =>
      'Quitar marcas de leído hasta este capítulo';

  @override
  String get loadingChapter => 'Cargando capítulo...';

  @override
  String failedToLoadChapter(String error) {
    return 'Error al cargar capítulo: $error';
  }

  @override
  String get loginWithEmailPassword => 'Iniciar sesión con correo y contraseña';

  @override
  String get loginViaBrowser => 'Iniciar sesión con navegador';

  @override
  String get fillEmailAndPassword => 'Completa el correo y la contraseña.';

  @override
  String get noDataAvailable => 'No hay datos disponibles';

  @override
  String loginToSource(String sourceName) {
    return 'Iniciar sesión en $sourceName';
  }

  @override
  String get loadingBookDetails => 'Cargando detalles...';

  @override
  String failedToLoadBookDetails(String error) {
    return 'Error al cargar detalles: $error';
  }

  @override
  String couldNotLoadFilters(String error) {
    return 'No se pudieron cargar filtros: $error';
  }

  @override
  String couldNotLoadGenres(String error) {
    return 'No se pudieron cargar géneros: $error';
  }

  @override
  String get filterTitle => 'Filtrar';

  @override
  String get filterByLabel => 'Filtrar por:';

  @override
  String get genreLabel => 'Género';

  @override
  String get authorLabel => 'Autor';

  @override
  String get ratingLabel => 'Puntuación';
}
