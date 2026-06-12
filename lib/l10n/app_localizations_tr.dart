// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'RSS Okuyucu';

  @override
  String get appName => 'Dondurma Rss Reader';

  @override
  String get feedsTab => 'Haberler';

  @override
  String get foldersTab => 'Kategoriler';

  @override
  String get bookmarksTab => 'Yer İşaretleri';

  @override
  String get settingsTab => 'Ayarlar';

  @override
  String get myFeeds => 'Haber Kaynaklarım';

  @override
  String get searchFeeds => 'Haber kaynakları ara...';

  @override
  String get today => 'BUGÜN';

  @override
  String get yesterday => 'DÜN';

  @override
  String get older => 'DAHA ESKİ';

  @override
  String get subscribedOnly => 'Yalnızca Abonelikler';

  @override
  String get noFeedsFound =>
      'Hiç haber kaynağı bulunamadı. + düğmesini kullanarak yeni bir kaynak ekleyin.';

  @override
  String noFeedsInCategory(String category) {
    return '$category kategorisinde hiç haber kaynağı bulunamadı.';
  }

  @override
  String get noFeedsMatchFilter => 'Mevcut filtrenize uygun haber kaynağı yok.';

  @override
  String get offlineBanner =>
      'Çevrimdışısınız — önbelleğe alınmış makaleleri gösteriyor.';

  @override
  String get loadMore => 'Daha fazla yükle';

  @override
  String get allCaughtUp => 'Tüm haberleri okudunuz ✓';

  @override
  String get noBookmarks => 'Henüz yer işaretli makale yok.';

  @override
  String get noFolders =>
      'Henüz kategori yok. Kaynaklarınızı düzenlemek için bir kategori ekleyin.';

  @override
  String get renameFolder => 'Kategoriyi Yeniden Adlandır';

  @override
  String get folderName => 'Kategori Adı';

  @override
  String get deleteFolder => 'Kategoriyi Sil';

  @override
  String deleteFolderConfirm(String categoryName, int feedCount) {
    return '\"$categoryName\" kategorisini silmek istediğinizden emin misiniz?\n\nBu işlem, içindeki $feedCount RSS kaynağını kalıcı olarak aboneliklerinizden kaldıracak.';
  }

  @override
  String get deleteAll => 'Tümünü Sil';

  @override
  String get editFeed => 'Kaynağı Düzenle';

  @override
  String get feedName => 'Kaynak Adı';

  @override
  String get feedUrl => 'Kaynak URL\'si';

  @override
  String get deleteFeed => 'Kaynağı Sil';

  @override
  String deleteFeedConfirm(String feedName) {
    return '\"$feedName\" kaynağını aboneliklerinizden tamamen kaldırmak istediğinizden emin misiniz?';
  }

  @override
  String get cancel => 'İptal';

  @override
  String get save => 'Kaydet';

  @override
  String get delete => 'Sil';

  @override
  String get reset => 'Sıfırla';

  @override
  String get addRssFeed => 'RSS Kaynağı Ekle';

  @override
  String get addFeedSubtitle =>
      'Abone olmak için bir web sitesi URL\'si yapıştırın';

  @override
  String useSuggestedName(String name) {
    return '\"$name\" adını kullan';
  }

  @override
  String get addingFeed => 'Ekleniyor…';

  @override
  String get feedUrlLabel => 'Kaynak URL\'si';

  @override
  String get feedUrlHint => 'örn. https://techcrunch.com/feed/';

  @override
  String get siteNameLabel => 'Site Adı';

  @override
  String get categoryOptional => 'Kategori (İsteğe Bağlı)';

  @override
  String get categoryHint => 'Teknoloji, Haber, vb.';

  @override
  String get pleaseEnterUrl => 'Lütfen bir URL girin';

  @override
  String get pleaseEnterValidUrl => 'Lütfen geçerli bir URL girin';

  @override
  String get pleaseEnterName => 'Lütfen bir ad girin';

  @override
  String get saveFeed => 'Kaynağı Kaydet';

  @override
  String errorAddingFeed(String error) {
    return 'Kaynak ekleme hatası: $error';
  }

  @override
  String get feedAlreadyExists => 'Bu kaynak zaten mevcut.';

  @override
  String get categories => 'KATEGORİLER';

  @override
  String get allNews => 'Tüm Haberler';

  @override
  String get uncategorized => 'KATEGORİSİZ';

  @override
  String get randomBlogs => 'Rastgele Bloglar';

  @override
  String get discover => 'KEŞFET';

  @override
  String get suggestedFeeds => 'Önerilen Kaynaklar';

  @override
  String get whatIsRss => 'RSS Nedir?';

  @override
  String get all => 'Tümü';

  @override
  String get noFeedsInThisCategory => 'Bu kategoride kaynak yok';

  @override
  String get addSubscription => 'Abonelik Ekle';

  @override
  String addSubscriptionConfirm(String name) {
    return '\"$name\" kaynağını haber listenize eklemek ister misiniz?';
  }

  @override
  String get addSource => 'Abone Ol';

  @override
  String get subscribed => 'Abone Olundu';

  @override
  String get undo => 'Geri Al';

  @override
  String addedSubscription(String name) {
    return '$name aboneliğinize eklendi!';
  }

  @override
  String get suggestedFeedsWarning =>
      'Uyarı: Bazı RSS kaynakları bozulmuş veya artık çalışmıyor olabilir.';

  @override
  String get errorLoadingSuggestedFeeds =>
      'Önerilen kaynaklar yüklenemedi. Lütfen daha sonra tekrar deneyin.';

  @override
  String get general => 'Genel';

  @override
  String get theme => 'Tema';

  @override
  String get language => 'Dil';

  @override
  String get changeAppLanguage => 'Uygulama dilini değiştirin';

  @override
  String get english => 'English';

  @override
  String get turkish => 'Türkçe';

  @override
  String get dataAndStorage => 'Veri ve Depolama';

  @override
  String get offlineCacheLimit => 'Önbellek Sınırı';

  @override
  String get offlineCacheLimitDesc =>
      'Çevrimdışı okuma için saklanan son makaleler';

  @override
  String get none => 'Yok';

  @override
  String get autoRefreshFeeds => 'Otomatik Yenileme';

  @override
  String get autoRefreshFeedsDesc =>
      'Arka planda haberlerin ne sıklıkla senkronize edileceği';

  @override
  String get thirtySeconds => '30 Saniye';

  @override
  String get oneMinute => '1 Dakika';

  @override
  String get fiveMinutes => '5 Dakika';

  @override
  String get clearCache => 'Önbelleği Temizle';

  @override
  String get clearCacheDesc => 'Alan açmak için indirilen makaleleri kaldır';

  @override
  String get cacheClearedSuccess => 'Önbellek başarıyla temizlendi.';

  @override
  String get syncBackground => 'Arka Plan Senkronizasyonu';

  @override
  String get syncBackgroundDesc => 'Uygulama açıkken yeni makaleleri getir';

  @override
  String get exportSubscriptions => 'Abonelikleri Dışa Aktar (OPML)';

  @override
  String get exportSubscriptionsDesc => 'Kaynaklarınızı bir dosyaya yedekleyin';

  @override
  String get noSubscriptionsToExport => 'Dışa aktarılacak abonelik yok.';

  @override
  String get exportSuccess => 'Abonelikler başarıyla dışa aktarıldı.';

  @override
  String get exportFailed => 'Dışa aktarma başarısız. Lütfen tekrar deneyin.';

  @override
  String get importSubscriptions => 'Abonelikleri İçe Aktar (OPML)';

  @override
  String get importSubscriptionsDesc =>
      'Bir OPML dosyasından kaynakları geri yükleyin';

  @override
  String get noFeedsFoundOrCancelled =>
      'Kaynak bulunamadı veya içe aktarma iptal edildi.';

  @override
  String importedFeeds(int count) {
    return '$count yeni kaynak içe aktarıldı.';
  }

  @override
  String get allFeedsExist =>
      'Tüm kaynaklar zaten mevcut — içe aktarılacak yeni kaynak yok.';

  @override
  String get about => 'Hakkında';

  @override
  String get version => 'Sürüm';

  @override
  String get versionDesc => 'Dondurma Rss Reader güncel derlemesi';

  @override
  String get rateTheApp => 'Uygulamayı Puanla';

  @override
  String get rateTheAppDesc => 'App Store\'da geliştirmeyi destekleyin';

  @override
  String get displayAndReadability => 'Görünüm ve Okunabilirlik';

  @override
  String get fontSize => 'Yazı Tipi Boyutu';

  @override
  String get fontSizeSmall => 'Küçük';

  @override
  String get fontSizeMedium => 'Orta';

  @override
  String get fontSizeLarge => 'Büyük';

  @override
  String get fontSizeXl => 'Çok Büyük';

  @override
  String get typeface => 'Yazı Tipi Ailesi';

  @override
  String get typefaceDefault => 'Sistem Varsayılanı';

  @override
  String get typefaceSerif => 'Serif';

  @override
  String get typefaceSansSerif => 'Sans-Serif';

  @override
  String get typefaceMono => 'Aralıklı (Monospace)';

  @override
  String get lineSpacing => 'Satır Aralığı';

  @override
  String get lineSpacingTight => 'Dar';

  @override
  String get lineSpacingNormal => 'Normal';

  @override
  String get lineSpacingRelaxed => 'Geniş';

  @override
  String get contentFiltering => 'İçerik Filtreleme';

  @override
  String get globalExcludedKeywords => 'Genel Hariç Tutulan Kelimeler';

  @override
  String get globalExcludedKeywordsDesc =>
      'Tüm kaynaklarda bu kelimeleri içeren makaleleri gizle';

  @override
  String get excludedKeywords => 'Hariç Tutulan Kelimeler';

  @override
  String get excludedKeywordsHint => 'örn. reklam, sponsor, spoiler';

  @override
  String get commaSeparated => 'Virgülle ayırın';

  @override
  String get addKeyword => 'Kelime Ekle';

  @override
  String get noKeywordsAdded => 'Henüz kelime eklenmedi.';

  @override
  String get openInBrowser => 'Tarayıcıda Aç';

  @override
  String get shareArticle => 'Makaleyi Paylaş';

  @override
  String get readOnOriginalWebpage => 'Orijinal Web Sitesinde Oku';

  @override
  String get invalidUrlFormat => 'Geçersiz URL biçimi';

  @override
  String get close => 'Kapat';

  @override
  String get openInExternalBrowser => 'Harici Tarayıcıda Aç';

  @override
  String get back => 'Geri';

  @override
  String get forward => 'İleri';

  @override
  String get refresh => 'Yenile';

  @override
  String get brightness => 'Parlaklık';

  @override
  String get brightnessSystem => 'Sistem';

  @override
  String get brightnessLight => 'Açık';

  @override
  String get brightnessDark => 'Koyu';

  @override
  String get manageFeeds => 'Kaynakları Yönet';

  @override
  String get noFeedsSubscribed =>
      'Abone olunan kaynak yok.\nAna Ekrandan bir tane ekleyin.';

  @override
  String get removeFeed => 'Kaynağı Kaldır';

  @override
  String removeFeedConfirm(String name) {
    return '\"$name\" kaynağını takip etmeyi bırakmak istediğinizden emin misiniz?';
  }

  @override
  String get remove => 'Kaldır';

  @override
  String get addFolder => 'Kategori Ekle';

  @override
  String get newFolderName => 'Yeni Kategori Adı';

  @override
  String get folderAlreadyExists => 'Bu isimde bir kategori zaten mevcut.';

  @override
  String get pleaseEnterFolderName => 'Lütfen bir kategori adı girin';

  @override
  String get moveToFolder => 'Kategoriye Taşı';

  @override
  String get moveFeed => 'Kaynağı Taşı';

  @override
  String feedMovedToFolder(String feedName, String folderName) {
    return '\"$feedName\" \"$folderName\" kategorisine taşındı';
  }

  @override
  String get notifications => 'Bildirimler';

  @override
  String get enableNotifications => 'Bildirimleri Etkinleştir';

  @override
  String get enableNotificationsDesc => 'Yeni makaleler hakkında bildirim al';

  @override
  String get digestMode => 'Bildirim Modu';

  @override
  String get digestModeDesc => 'Bildirimleri nasıl alacağınız';

  @override
  String get digestInstant => 'Anında';

  @override
  String get digestDaily => 'Günlük Özet';

  @override
  String get digestWeekly => 'Haftalık Özet';

  @override
  String get quietHours => 'Sessiz Saatler';

  @override
  String get quietHoursDesc => 'Bu saatlerde bildirimleri sessize al';

  @override
  String get quietHoursEnabled => 'Sessiz Saatleri Etkinleştir';

  @override
  String get quietHoursFrom => 'Başlangıç';

  @override
  String get quietHoursTo => 'Bitiş';

  @override
  String newArticlesNotification(int count) {
    return '$count yeni makale';
  }

  @override
  String get feedNotifications => 'Kaynak Bildirimleri';

  @override
  String get notificationsNotSupported =>
      'Bu platformda bildirimler desteklenmiyor';

  @override
  String get notificationsSupportedPlatforms =>
      'Desteklenen platformlar: Android, iOS';

  @override
  String get fullTextExtraction => 'Tam Metin Modu';

  @override
  String get fullTextExtractionDesc =>
      'Orijinal web sayfasından tam içeriği getir';

  @override
  String get fullTextLoading => 'Tam makale yükleniyor…';

  @override
  String get fullTextFailed =>
      'Tam içerik yüklenemedi. Akış özeti gösteriliyor.';

  @override
  String get fullTextToggle => 'Tam Metin';

  @override
  String get shortTextMode => 'Kısa Metin Modu';

  @override
  String get readingModeLabel => 'Okuma modu';

  @override
  String get modeShort => 'Özet';

  @override
  String get modeFull => 'Tam Makale';

  @override
  String get searchHistory => 'Arama Geçmişi';

  @override
  String get clearSearchHistory => 'Arama Geçmişini Temizle';

  @override
  String get clearSearchHistoryDesc =>
      'Kaydedilen tüm arama sorgularını kaldır';

  @override
  String get searchHistoryCleared => 'Arama geçmişi temizlendi.';

  @override
  String get recentSearches => 'Son Aramalar';

  @override
  String get factoryReset => 'Fabrika Ayarlarına Sıfırla';

  @override
  String get factoryResetDesc =>
      'Tüm verileri silin ve varsayılan ayarlara dönün';

  @override
  String get factoryResetConfirmTitle => 'Emin misiniz?';

  @override
  String get factoryResetConfirmDesc =>
      'Bu işlem takip ettiğiniz tüm haber kaynaklarını, kategorileri, yer işaretlerini ve ayarları kalıcı olarak silecektir. Uygulama varsayılan ilk yükleme durumuna dönecektir. Bu işlem geri alınamaz.';

  @override
  String get factoryResetSuccess => 'Tüm veri ve ayarlar silindi.';

  @override
  String get browserMode => 'Tarayıcı Modu';

  @override
  String get browserModeDesc => 'Bağlantıların nasıl açılacağını seçin';

  @override
  String get browserBuiltin => 'Dahili Tarayıcı';

  @override
  String get browserExternal => 'Harici Tarayıcı';

  @override
  String get browserSystem => 'Sistem Uygulama İçi Tarayıcı';

  @override
  String get browserSystemMobileOnly =>
      'Sistem uygulama içi tarayıcı yalnızca mobil cihazlarda (Android ve iOS) kullanılabilir';

  @override
  String get adBlocker => 'Reklam Engelleyici';

  @override
  String get adBlockerDesc =>
      'Uygulama içi tarayıcıda reklamları ve izleyicileri engelle';

  @override
  String get webviewDarkMode => 'Uygulama İçi Tarayıcı Karanlık Modu';

  @override
  String get webviewDarkModeDesc =>
      'Uygulama içindeki makalelerde karanlık modu uygula';

  @override
  String get semanticToggleRead => 'Okundu durumunu değiştir';

  @override
  String get semanticToggleBookmark => 'Yer işaretini değiştir';

  @override
  String get semanticMarkAsRead => 'Okundu olarak işaretle';

  @override
  String get semanticMarkAsUnread => 'Okunmadı olarak işaretle';

  @override
  String get semanticBookmark => 'Makaleyi yer işaretine ekle';

  @override
  String get semanticRemoveBookmark => 'Yer işaretini kaldır';

  @override
  String get semanticArticleRead => 'Okunmuş makale';

  @override
  String get semanticArticleUnread => 'Okunmamış makale';

  @override
  String semanticOpenArticle(String title) {
    return 'Makaleyi aç: $title';
  }

  @override
  String get semanticFilterUnread => 'Okunmamış makaleleri filtrele';

  @override
  String get semanticShowAll => 'Tüm makaleleri göster';

  @override
  String get semanticOpenSearch => 'Aramayı aç';

  @override
  String get semanticCloseSearch => 'Aramayı kapat';

  @override
  String get semanticAddFeed => 'Yeni kaynak ekle';

  @override
  String get semanticOfflineCached => 'Çevrimdışı kullanılabilir';

  @override
  String get debugScreen => 'Hata Ayıklama Konsolu';

  @override
  String get debugScreenDesc => 'Dahili tanılama ve depolama metrikleri';

  @override
  String get syncStatus => 'Senkronizasyon Durumu';

  @override
  String get syncActive => 'Aktif';

  @override
  String get syncInactive => 'Pasif';

  @override
  String get syncInProgress => 'Senkronize ediliyor…';

  @override
  String get lastSyncTime => 'Son Senkronizasyon';

  @override
  String get lastSyncDuration => 'Senkronizasyon Süresi';

  @override
  String get noSyncYet => 'Henüz senkronize edilmedi';

  @override
  String get hiveStorage => 'Hive Depolama';

  @override
  String get settingsBoxSize => 'Ayarlar Kutusu';

  @override
  String get feedsBoxSize => 'Haberler Kutusu';

  @override
  String get bookmarksBoxSize => 'Yer İşaretleri Kutusu';

  @override
  String get dataSummary => 'Veri Özeti';

  @override
  String get totalArticlesCached => 'Önbellekteki Makaleler';

  @override
  String get readArticles => 'Okunan Makaleler';

  @override
  String get bookmarkedArticles => 'Yer İşaretli Makaleler';

  @override
  String get subscribedFeeds => 'Abone Olunan Kaynaklar';

  @override
  String get backgroundSync => 'Arka Plan Senkronizasyonu';

  @override
  String estimatedReadTime(int minutes) {
    return '$minutes dk okuma';
  }

  @override
  String get lessThanOneMinRead => '1 dk\'dan kısa okuma';

  @override
  String articlePosition(int current, int total) {
    return '$current / $total';
  }

  @override
  String get semanticNextArticle => 'Sonraki makale';

  @override
  String get semanticPreviousArticle => 'Önceki makale';

  @override
  String get semanticReadingProgress => 'Okuma ilerlemesi';

  @override
  String get whatIsRssTitle1 => 'Kişisel Gazeteniz';

  @override
  String get whatIsRssDesc1 =>
      'RSS\'i, size özel bir gazete dağıtım sistemi gibi düşünün. Her gün yeni makaleler olup olmadığını kontrol etmek için 10 farklı web sitesini dolaşmak yerine, bu uygulamaya sitenin \"RSS adresini\" verirsiniz.\n\nWeb sitesi yeni bir şey yayınladığında, buradaki akışınıza otomatik olarak ulaşır. Neyi göreceğinize karar veren algoritmalar yok, dikkat dağıtıcı unsurlar yok ve dolup taşan e-posta kutuları yok.';

  @override
  String get whatIsRssTitle2 => 'Yeni RSS akışları nasıl bulunur?';

  @override
  String get whatIsRssDesc2 =>
      'Akışları bulmak tahmin ettiğinizden daha kolaydır. İşte onları bulmanın en yaygın yolları:';

  @override
  String get whatIsRssMethod1Title => 'Simgeyi Arayın';

  @override
  String get whatIsRssMethod1Desc =>
      'Birçok blog ve haber sitesinin ana sayfasında veya alt bilgisinde belirli bir RSS simgesi bulunur.';

  @override
  String get whatIsRssMethod2Title =>
      'Sadece Web Sitesi Bağlantısını Yapıştırın';

  @override
  String get whatIsRssMethod2Desc =>
      'Çoğu zaman tam RSS bağlantısına bile ihtiyacınız yoktur. Bu uygulamada \'Kaynak Ekle\' düğmesine dokunduğunuzda, normal web sitesi adresini (örn. \'verge.com\' veya \'techcrunch.com\') yapıştırmanız yeterlidir. Uygulama otomatik olarak sizin için gizli RSS akışını bulmaya çalışacaktır!';

  @override
  String get whatIsRssMethod3Title => 'Önerilen Akışları Kullanın';

  @override
  String get whatIsRssMethod3Desc =>
      'Nereden başlayacağınızdan emin değil misiniz? Kategoriye göre ayrılmış özel kürate edilmiş harika içerik listelerine göz atmak için menüdeki \'Önerilen Akışlar\' bölümünü inceleyin.';

  @override
  String get gotItLetsRead => 'Anladım, hadi okuyalım!';

  @override
  String get contactUs => 'Bize Ulaşın';

  @override
  String get contactUsDesc => 'Geri bildirim gönderin veya sorun bildirin';

  @override
  String get privacyPolicy => 'Gizlilik Politikası';

  @override
  String get privacyPolicyDesc => 'Verilerinizi nasıl işlediğimiz hakkında';

  @override
  String get termsOfService => 'Kullanım Koşulları';

  @override
  String get termsOfServiceDesc => 'Kullanım şartları ve koşulları';

  @override
  String get openSourceLicenses => 'Açık Kaynak Lisansları';

  @override
  String get openSourceLicensesDesc =>
      'Bu uygulamada kullanılan üçüncü taraf kütüphaneler';

  @override
  String get developerInfo => 'DevOpen tarafından geliştirildi';

  @override
  String get developerInfoDesc => 'Talha Aksoy & Eren Gün';

  @override
  String get tabGlobal => 'Global';

  @override
  String get tabTurkish => 'Türkçe';

  @override
  String get categoriesSheetTitle => 'Kategoriler';

  @override
  String get onboardingTitle => 'İlgi Alanlarını Seç';

  @override
  String get onboardingSubtitle =>
      'Takip etmek istediğin kategorileri seç. En popüler kaynakları sana ekleyelim.';

  @override
  String get onboardingContinue => 'Başlayalım';

  @override
  String get onboardingExploreHint =>
      'Önerilen Kaynaklar\'da istediğin zaman daha fazlasını keşfedebilirsin.';

  @override
  String get onboardingLoadError =>
      'Kategoriler yüklenemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get onboardingSkip => 'Şimdilik atla';

  @override
  String get add => 'Ekle';

  @override
  String get siteNameHint => 'TechCrunch, BBC News…';

  @override
  String get folderNameHint => 'Teknoloji, Spor, Finans…';

  @override
  String get aboutApp => 'Uygulama Hakkında';

  @override
  String get lastUpdated => 'Son güncelleme: Haziran 2026';

  @override
  String get translateArticle => 'Makaleyi Çevir';

  @override
  String get translationSourceLang => 'Kaynak Dil';

  @override
  String get translationTargetLang => 'Hedef Dil';

  @override
  String get translationTranslate => 'Çevir';

  @override
  String get translationClear => 'Orijinali Göster';

  @override
  String get translationInProgress => 'Çeviriliyor…';

  @override
  String get translationError => 'Çeviri başarısız. Lütfen tekrar deneyin.';

  @override
  String get translationSwapLanguages => 'Dilleri değiştir';

  @override
  String get translationNeedsDownload => 'Çeviri için dil paketleri gerekiyor.';

  @override
  String get translationGoToDownload => 'Dil Paketlerini İndir';

  @override
  String get languagePacks => 'Dil Paketleri';

  @override
  String get languagePacksDesc => 'Cihazda çeviri modellerini yönet';

  @override
  String get languagePackDownload => 'İndir';

  @override
  String get languagePackDelete => 'Sil';

  @override
  String get languagePackRequired => 'Gerekli';

  @override
  String get languagePackDownloading => 'İndiriliyor…';

  @override
  String get languagePackCheckingStatus => 'Kontrol ediliyor…';
}
