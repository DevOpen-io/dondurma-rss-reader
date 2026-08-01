// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Lector de RSS';

  @override
  String get appName => 'Dondurma Rss Reader';

  @override
  String get feedsTab => 'Fuentes';

  @override
  String get foldersTab => 'Categorías';

  @override
  String get bookmarksTab => 'Marcadores';

  @override
  String get settingsTab => 'Ajustes';

  @override
  String get myFeeds => 'Mis Fuentes';

  @override
  String get searchFeeds => 'Buscar fuentes...';

  @override
  String get today => 'HOY';

  @override
  String get yesterday => 'AYER';

  @override
  String get older => 'ANTERIORES';

  @override
  String get subscribedOnly => 'Solo suscripciones';

  @override
  String get noFeedsFound =>
      'No se encontraron fuentes. Añade una nueva fuente con el botón +.';

  @override
  String noFeedsInCategory(String category) {
    return 'No se encontraron fuentes en $category.';
  }

  @override
  String get noFeedsMatchFilter =>
      'Ninguna fuente coincide con tu filtro actual.';

  @override
  String get offlineBanner =>
      'Estás sin conexión: mostrando artículos en caché.';

  @override
  String get loadMore => 'Cargar más';

  @override
  String get allCaughtUp => 'Estás al día ✓';

  @override
  String get noBookmarks => 'Aún no hay artículos marcados.';

  @override
  String get noFolders =>
      'Aún no hay categorías. Añade una categoría para organizar tus fuentes.';

  @override
  String get renameFolder => 'Renombrar categoría';

  @override
  String get folderName => 'Nombre de la categoría';

  @override
  String get deleteFolder => 'Eliminar categoría';

  @override
  String deleteFolderConfirm(String categoryName, int feedCount) {
    return '¿Seguro que quieres eliminar la categoría \"$categoryName\"?\n\nEsto eliminará permanentemente las $feedCount fuentes RSS que contiene de tus suscripciones.';
  }

  @override
  String get deleteAll => 'Eliminar todo';

  @override
  String get markAllAsRead => 'Marcar todo como leído';

  @override
  String get editFeed => 'Editar fuente';

  @override
  String get feedName => 'Nombre de la fuente';

  @override
  String get feedUrl => 'URL de la fuente';

  @override
  String get deleteFeed => 'Eliminar fuente';

  @override
  String deleteFeedConfirm(String feedName) {
    return '¿Seguro que quieres eliminar \"$feedName\" por completo de tus suscripciones?';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get reset => 'Restablecer';

  @override
  String get addRssFeed => 'Añadir fuente RSS';

  @override
  String get addFeedSubtitle =>
      'Pega la dirección de una fuente para suscribirte';

  @override
  String useSuggestedName(String name) {
    return 'Usar \"$name\" como nombre';
  }

  @override
  String get addingFeed => 'Añadiendo…';

  @override
  String get feedUrlLabel => 'URL de la fuente';

  @override
  String get feedUrlHint => 'p. ej. https://techcrunch.com/feed/';

  @override
  String get siteNameLabel => 'Nombre del sitio';

  @override
  String get categoryOptional => 'Categoría (opcional)';

  @override
  String get categoryHint => 'Tecnología, Noticias, etc.';

  @override
  String get pleaseEnterUrl => 'Introduce una URL';

  @override
  String get pleaseEnterValidUrl => 'Introduce una URL válida';

  @override
  String get pleaseEnterName => 'Introduce un nombre';

  @override
  String get saveFeed => 'Guardar fuente';

  @override
  String get feedAlreadyExists => 'Esta fuente ya existe.';

  @override
  String get categories => 'CATEGORÍAS';

  @override
  String get allNews => 'Todas las noticias';

  @override
  String get uncategorized => 'SIN CATEGORÍA';

  @override
  String get randomBlogs => 'Blogs variados';

  @override
  String get discover => 'DESCUBRIR';

  @override
  String get suggestedFeeds => 'Fuentes sugeridas';

  @override
  String get whatIsRss => '¿Qué es RSS?';

  @override
  String get all => 'Todo';

  @override
  String get noFeedsInThisCategory => 'No hay fuentes en esta categoría';

  @override
  String get addSubscription => 'Añadir suscripción';

  @override
  String addSubscriptionConfirm(String name) {
    return '¿Quieres añadir \"$name\" a tu lista de fuentes?';
  }

  @override
  String get addSource => 'Suscribirse';

  @override
  String get subscribed => 'Suscrito';

  @override
  String get undo => 'Deshacer';

  @override
  String addedSubscription(String name) {
    return '¡$name añadido a tus suscripciones!';
  }

  @override
  String get suggestedFeedsWarning =>
      'Advertencia: algunas fuentes RSS pueden estar rotas o dejar de funcionar.';

  @override
  String get errorLoadingSuggestedFeeds =>
      'No se pudieron cargar las fuentes sugeridas. Inténtalo de nuevo más tarde.';

  @override
  String get general => 'General';

  @override
  String get theme => 'Tema';

  @override
  String get language => 'Idioma';

  @override
  String get changeAppLanguage => 'Cambiar el idioma de la aplicación';

  @override
  String get dataAndStorage => 'Datos y almacenamiento';

  @override
  String get offlineCacheLimit => 'Límite de caché sin conexión';

  @override
  String get offlineCacheLimitDesc =>
      'Artículos recientes guardados para lectura sin conexión';

  @override
  String get none => 'Ninguno';

  @override
  String get autoRefreshFeeds => 'Actualización automática';

  @override
  String get autoRefreshFeedsDesc =>
      'Con qué frecuencia se actualizan las fuentes con la app abierta';

  @override
  String get thirtySeconds => '30 segundos';

  @override
  String get oneMinute => '1 minuto';

  @override
  String get fiveMinutes => '5 minutos';

  @override
  String get clearCache => 'Vaciar caché';

  @override
  String get clearCacheDesc =>
      'Elimina los artículos descargados para liberar espacio';

  @override
  String get cacheClearedSuccess => 'Caché vaciada correctamente.';

  @override
  String get syncBackground => 'Sincronización automática';

  @override
  String get syncBackgroundDesc =>
      'Obtiene automáticamente artículos nuevos en la app y en segundo plano';

  @override
  String get exportSubscriptions => 'Exportar suscripciones (OPML)';

  @override
  String get exportSubscriptionsDesc =>
      'Haz una copia de seguridad de tus fuentes en un archivo';

  @override
  String get noSubscriptionsToExport => 'No hay suscripciones para exportar.';

  @override
  String get exportSuccess => 'Suscripciones exportadas correctamente.';

  @override
  String get exportFailed => 'Error al exportar. Inténtalo de nuevo.';

  @override
  String get importSubscriptions => 'Importar suscripciones (OPML)';

  @override
  String get importSubscriptionsDesc =>
      'Restaura fuentes desde un archivo OPML';

  @override
  String get noFeedsFoundOrCancelled =>
      'No se encontraron fuentes o la importación se canceló.';

  @override
  String importedFeeds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'nuevas fuentes',
      one: 'nueva fuente',
    );
    return 'Se importaron $count $_temp0.';
  }

  @override
  String get allFeedsExist =>
      'Todas las fuentes ya existen: no se importó nada nuevo.';

  @override
  String get about => 'Acerca de';

  @override
  String get version => 'Versión';

  @override
  String get versionDesc => 'Compilación actual de Dondurma Rss Reader';

  @override
  String get displayAndReadability => 'Pantalla y legibilidad';

  @override
  String get fontSize => 'Tamaño de fuente';

  @override
  String get fontSizeSmall => 'Pequeño';

  @override
  String get fontSizeMedium => 'Mediano';

  @override
  String get fontSizeLarge => 'Grande';

  @override
  String get fontSizeXl => 'Extra grande';

  @override
  String get typeface => 'Tipografía';

  @override
  String get typefaceDefault => 'Predeterminada del sistema';

  @override
  String get typefaceSerif => 'Serif';

  @override
  String get typefaceSansSerif => 'Sans-serif';

  @override
  String get typefaceMono => 'Monoespaciada';

  @override
  String get lineSpacing => 'Interlineado';

  @override
  String get lineSpacingTight => 'Compacto';

  @override
  String get lineSpacingNormal => 'Normal';

  @override
  String get lineSpacingRelaxed => 'Amplio';

  @override
  String get contentFiltering => 'Filtrado de contenido';

  @override
  String get globalExcludedKeywords => 'Palabras clave excluidas globales';

  @override
  String get globalExcludedKeywordsDesc =>
      'Oculta los artículos que contengan estas palabras en todas las fuentes';

  @override
  String get excludedKeywords => 'Palabras clave excluidas';

  @override
  String get excludedKeywordsHint => 'p. ej. anuncio, patrocinado, spoiler';

  @override
  String get commaSeparated => 'Separadas por comas';

  @override
  String get addKeyword => 'Añadir palabra clave';

  @override
  String get noKeywordsAdded => 'Aún no se han añadido palabras clave.';

  @override
  String get openInBrowser => 'Abrir en el navegador';

  @override
  String get shareArticle => 'Compartir artículo';

  @override
  String get readOnOriginalWebpage => 'Leer en la página web original';

  @override
  String get invalidUrlFormat => 'Formato de URL no válido';

  @override
  String get close => 'Cerrar';

  @override
  String get openInExternalBrowser => 'Abrir en navegador externo';

  @override
  String get back => 'Atrás';

  @override
  String get forward => 'Adelante';

  @override
  String get refresh => 'Actualizar';

  @override
  String get brightness => 'Brillo';

  @override
  String get brightnessSystem => 'Sistema';

  @override
  String get brightnessLight => 'Claro';

  @override
  String get brightnessDark => 'Oscuro';

  @override
  String get manageFeeds => 'Gestionar fuentes';

  @override
  String get noFeedsSubscribed =>
      'No hay fuentes suscritas.\nAñade una desde la pantalla principal.';

  @override
  String get removeFeed => 'Eliminar fuente';

  @override
  String removeFeedConfirm(String name) {
    return '¿Seguro que quieres dejar de seguir \"$name\"?';
  }

  @override
  String get remove => 'Eliminar';

  @override
  String get addFolder => 'Añadir categoría';

  @override
  String get newFolderName => 'Nombre de la nueva categoría';

  @override
  String get folderAlreadyExists => 'Ya existe una categoría con este nombre.';

  @override
  String get pleaseEnterFolderName => 'Introduce un nombre de categoría';

  @override
  String get moveToFolder => 'Mover a categoría';

  @override
  String get moveFeed => 'Mover fuente';

  @override
  String feedMovedToFolder(String feedName, String folderName) {
    return '\"$feedName\" se movió a la categoría \"$folderName\"';
  }

  @override
  String get notifications => 'Notificaciones';

  @override
  String get enableNotifications => 'Activar notificaciones';

  @override
  String get enableNotificationsDesc =>
      'Recibe notificaciones sobre artículos nuevos';

  @override
  String get digestMode => 'Modo de notificación';

  @override
  String get digestModeDesc => 'Cómo recibes las notificaciones';

  @override
  String get digestInstant => 'Instantáneo';

  @override
  String get digestDaily => 'Resumen diario';

  @override
  String get digestWeekly => 'Resumen semanal';

  @override
  String get quietHours => 'Horas de silencio';

  @override
  String get quietHoursDesc =>
      'Silencia las notificaciones durante estas horas';

  @override
  String get quietHoursEnabled => 'Activar horas de silencio';

  @override
  String get quietHoursFrom => 'Desde';

  @override
  String get quietHoursTo => 'Hasta';

  @override
  String newArticlesNotification(int count) {
    return '$count artículos nuevos';
  }

  @override
  String get feedNotifications => 'Notificaciones de fuentes';

  @override
  String get notificationsNotSupported =>
      'Las notificaciones no son compatibles con esta plataforma';

  @override
  String get notificationsSupportedPlatforms =>
      'Plataformas compatibles: Android, iOS';

  @override
  String get fullTextExtraction => 'Modo de texto completo';

  @override
  String get fullTextExtractionDesc =>
      'Obtiene el contenido completo de la página web original';

  @override
  String get fullTextLoading => 'Cargando el artículo completo…';

  @override
  String get fullTextFailed =>
      'No se pudo cargar el contenido completo. Mostrando el resumen de la fuente.';

  @override
  String get fullTextToggle => 'Texto completo';

  @override
  String get shortTextMode => 'Modo de texto corto';

  @override
  String get readingModeLabel => 'Modo de lectura';

  @override
  String get modeShort => 'Resumen';

  @override
  String get modeFull => 'Artículo completo';

  @override
  String get fullTextDefault => 'Predeterminado';

  @override
  String get fullTextOn => 'Activado';

  @override
  String get fullTextOff => 'Desactivado';

  @override
  String get searchHistory => 'Historial de búsqueda';

  @override
  String get clearSearchHistory => 'Borrar historial de búsqueda';

  @override
  String get clearSearchHistoryDesc => 'Elimina todas las búsquedas guardadas';

  @override
  String get searchHistoryCleared => 'Historial de búsqueda borrado.';

  @override
  String get recentSearches => 'Búsquedas recientes';

  @override
  String get factoryReset => 'Restablecer de fábrica';

  @override
  String get factoryResetDesc =>
      'Borra todos los datos y restaura la configuración predeterminada';

  @override
  String get factoryResetConfirmTitle => '¿Estás seguro?';

  @override
  String get factoryResetConfirmDesc =>
      'Esto borrará permanentemente todas tus fuentes, categorías, marcadores y ajustes. La aplicación se restaurará a su estado de instalación predeterminado. Esta acción no se puede deshacer.';

  @override
  String get factoryResetSuccess => 'Se han borrado todos los datos y ajustes.';

  @override
  String get browserMode => 'Modo de navegador';

  @override
  String get browserModeDesc => 'Elige cómo se abren los enlaces';

  @override
  String get browserBuiltin => 'Navegador integrado';

  @override
  String get browserExternal => 'Navegador externo';

  @override
  String get browserSystem => 'Navegador del sistema en la app';

  @override
  String get browserSystemMobileOnly =>
      'El navegador del sistema en la app solo está disponible en dispositivos móviles (Android e iOS)';

  @override
  String get adBlocker => 'Bloqueador de anuncios';

  @override
  String get adBlockerDesc =>
      'Bloquea anuncios y rastreadores en el navegador integrado';

  @override
  String get webviewDarkMode => 'Modo oscuro del navegador integrado';

  @override
  String get webviewDarkModeDesc =>
      'Aplica el modo oscuro a los artículos vistos dentro de la app';

  @override
  String get semanticToggleRead => 'Cambiar estado de lectura';

  @override
  String get semanticToggleBookmark => 'Cambiar marcador';

  @override
  String get semanticMarkAsRead => 'Marcar como leído';

  @override
  String get semanticMarkAsUnread => 'Marcar como no leído';

  @override
  String get semanticBookmark => 'Marcar artículo';

  @override
  String get semanticRemoveBookmark => 'Quitar marcador';

  @override
  String get semanticArticleRead => 'Artículo leído';

  @override
  String get semanticArticleUnread => 'Artículo no leído';

  @override
  String semanticOpenArticle(String title) {
    return 'Abrir artículo: $title';
  }

  @override
  String get semanticFilterUnread => 'Filtrar artículos no leídos';

  @override
  String get semanticShowAll => 'Mostrar todos los artículos';

  @override
  String get semanticOpenSearch => 'Abrir búsqueda';

  @override
  String get semanticCloseSearch => 'Cerrar búsqueda';

  @override
  String get semanticAddFeed => 'Añadir nueva fuente';

  @override
  String get semanticOfflineCached => 'Disponible sin conexión';

  @override
  String get debugScreen => 'Consola de depuración';

  @override
  String get debugScreenDesc =>
      'Diagnóstico interno y métricas de almacenamiento';

  @override
  String get syncStatus => 'Estado de sincronización';

  @override
  String get syncActive => 'Activa';

  @override
  String get syncInactive => 'Inactiva';

  @override
  String get syncInProgress => 'Sincronizando…';

  @override
  String get lastSyncTime => 'Última sincronización';

  @override
  String get lastSyncDuration => 'Duración de la sincronización';

  @override
  String get noSyncYet => 'Aún no hay sincronización';

  @override
  String get hiveStorage => 'Almacenamiento Hive';

  @override
  String get settingsBoxSize => 'Caja de ajustes';

  @override
  String get feedsBoxSize => 'Caja de fuentes';

  @override
  String get bookmarksBoxSize => 'Caja de marcadores';

  @override
  String get dataSummary => 'Resumen de datos';

  @override
  String get totalArticlesCached => 'Artículos en caché';

  @override
  String get readArticles => 'Artículos leídos';

  @override
  String get bookmarkedArticles => 'Artículos marcados';

  @override
  String get subscribedFeeds => 'Fuentes suscritas';

  @override
  String get backgroundSync => 'Sincronización en segundo plano';

  @override
  String estimatedReadTime(int minutes) {
    return '$minutes min de lectura';
  }

  @override
  String get lessThanOneMinRead => 'Menos de 1 min de lectura';

  @override
  String articlePosition(int current, int total) {
    return '$current de $total';
  }

  @override
  String get semanticNextArticle => 'Artículo siguiente';

  @override
  String get semanticPreviousArticle => 'Artículo anterior';

  @override
  String get semanticReadingProgress => 'Progreso de lectura';

  @override
  String get whatIsRssTitle1 => 'Tu periódico personal';

  @override
  String get whatIsRssDesc1 =>
      'Piensa en RSS como un sistema de entrega de periódicos personalizado. En lugar de visitar 10 sitios web diferentes cada día para comprobar si hay artículos nuevos, solo tienes que darle a esta app la \"dirección RSS\" del sitio.\n\nCuando el sitio publica algo nuevo, llega automáticamente a tu fuente. Sin algoritmos que decidan lo que ves, sin distracciones y sin bandejas de entrada saturadas.';

  @override
  String get whatIsRssTitle2 => '¿Cómo encontrar nuevas fuentes RSS?';

  @override
  String get whatIsRssDesc2 =>
      'Encontrar fuentes es más fácil de lo que crees. Estas son las formas más comunes:';

  @override
  String get whatIsRssMethod1Title => 'Busca el icono';

  @override
  String get whatIsRssMethod1Desc =>
      'Muchos blogs y sitios de noticias tienen un icono RSS específico en su página principal o en el pie de página.';

  @override
  String get whatIsRssMethod2Title => 'Pega la dirección de la fuente';

  @override
  String get whatIsRssMethod2Desc =>
      'Cuando toques \'Añadir fuente\', pega la dirección RSS del sitio. La mayoría de los sitios usan su dirección web más /feed o /rss (como techcrunch.com/feed). ¿No sabes por dónde empezar? Explora las Fuentes sugeridas.';

  @override
  String get whatIsRssMethod3Title => 'Usa las fuentes sugeridas';

  @override
  String get whatIsRssMethod3Desc =>
      '¿No sabes por dónde empezar? Consulta la sección \'Fuentes sugeridas\' del menú para explorar listas seleccionadas de buen contenido organizadas por categoría.';

  @override
  String get gotItLetsRead => '¡Entendido, a leer!';

  @override
  String get contactUs => 'Contacta con nosotros';

  @override
  String get contactUsDesc => 'Envíanos comentarios o informa de un problema';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get privacyPolicyDesc => 'Cómo gestionamos tus datos';

  @override
  String get termsOfService => 'Términos de servicio';

  @override
  String get termsOfServiceDesc => 'Términos y condiciones de uso';

  @override
  String get openSourceLicenses => 'Licencias de código abierto';

  @override
  String get openSourceLicensesDesc =>
      'Librerías de terceros utilizadas en esta app';

  @override
  String get developerInfo => 'Desarrollado por DevOpen';

  @override
  String get developerInfoDesc => 'Talha Aksoy & Eren Gün';

  @override
  String get tabGlobal => 'Global';

  @override
  String get tabTurkish => 'Turco';

  @override
  String get categoriesSheetTitle => 'Categorías';

  @override
  String get onboardingTitle => 'Elige tus intereses';

  @override
  String get onboardingSubtitle =>
      'Elige las categorías que quieres seguir. Añadiremos las mejores fuentes para que empieces.';

  @override
  String get onboardingContinue => 'Empezar';

  @override
  String get onboardingExploreHint =>
      'Puedes descubrir más fuentes cuando quieras en Fuentes sugeridas.';

  @override
  String get onboardingLoadError =>
      'No se pudieron cargar las categorías. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get onboardingSkip => 'Omitir por ahora';

  @override
  String get add => 'Añadir';

  @override
  String get siteNameHint => 'TechCrunch, BBC News…';

  @override
  String get folderNameHint => 'Tecnología, Deportes, Finanzas…';

  @override
  String get aboutApp => 'Acerca de la app';

  @override
  String get lastUpdated => 'Última actualización: junio de 2026';

  @override
  String get translateArticle => 'Traducir artículo';

  @override
  String get translationSourceLang => 'De';

  @override
  String get translationTargetLang => 'A';

  @override
  String get translationTranslate => 'Traducir';

  @override
  String get translationClear => 'Mostrar original';

  @override
  String get translationInProgress => 'Traduciendo…';

  @override
  String get translationError => 'Error de traducción. Inténtalo de nuevo.';

  @override
  String get translationSwapLanguages => 'Intercambiar idiomas';

  @override
  String get translationNeedsDownload =>
      'Se necesitan paquetes de idioma para traducir.';

  @override
  String get translationGoToDownload => 'Descargar paquetes de idioma';

  @override
  String get languagePacks => 'Paquetes de idioma';

  @override
  String get languagePacksDesc =>
      'Gestiona los modelos de traducción del dispositivo';

  @override
  String get languagePackDownload => 'Descargar';

  @override
  String get languagePackDelete => 'Eliminar';

  @override
  String get languagePackRequired => 'Necesario';

  @override
  String get languagePackDownloading => 'Descargando…';

  @override
  String get languagePackCheckingStatus => 'Comprobando…';

  @override
  String get bookmarksSwipeHint =>
      'Desliza un artículo hacia la izquierda para guardarlo aquí.';

  @override
  String get readSwipeHint =>
      'Consejo: desliza un artículo hacia la derecha para marcarlo como leído o no leído.';

  @override
  String get retry => 'Reintentar';

  @override
  String get feedAddError =>
      'No se encontró una fuente RSS en esta dirección. Comprueba la URL: la mayoría de las direcciones de fuentes terminan en /feed o /rss.';

  @override
  String get clearFilters => 'Mostrar todos los artículos';

  @override
  String get thirtyMinutes => '30 minutos';

  @override
  String get semanticCategoryOptions => 'Opciones de categoría';

  @override
  String get filterSheetTitle => 'Filtrar';

  @override
  String get filterReadStatus => 'Estado de lectura';

  @override
  String get filterOptionUnread => 'No leído';

  @override
  String get filterOptionRead => 'Leído';

  @override
  String get filterApply => 'Aplicar filtros';

  @override
  String get filterClear => 'Borrar filtros';
}
