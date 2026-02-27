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
  String get foldersTab => 'Klasörler';

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
    return '$category klasöründe hiç haber kaynağı bulunamadı.';
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
  String get noFolders => 'Henüz klasör yok. Kategoriler burada görünecek.';

  @override
  String get renameFolder => 'Klasörü Yeniden Adlandır';

  @override
  String get folderName => 'Klasör Adı';

  @override
  String get deleteFolder => 'Klasörü Sil';

  @override
  String deleteFolderConfirm(String categoryName, int feedCount) {
    return '\"$categoryName\" klasörünü silmek istediğinizden emin misiniz?\n\nBu işlem, içindeki $feedCount RSS kaynağını kalıcı olarak aboneliklerinizden kaldıracak.';
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
  String get addRssFeed => 'RSS Kaynağı Ekle';

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
  String get addSource => 'Kaynak Ekle';

  @override
  String addedSubscription(String name) {
    return '$name aboneliğinize eklendi!';
  }

  @override
  String get suggestedFeedsWarning =>
      'Uyarı: Bazı RSS kaynakları bozulmuş veya artık çalışmıyor olabilir.';

  @override
  String get general => 'Genel';

  @override
  String get theme => 'Tema';

  @override
  String get selectAppStyle => 'Uygulama stilini seçin';

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
  String get openInBrowser => 'Tarayıcıda Aç';

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
  String get themeSystemDefault => 'Sistem Varsayılanı';

  @override
  String get themeLightClassic => 'Aydınlık (Klasik)';

  @override
  String get themeDarkClassic => 'Karanlık (Klasik)';

  @override
  String get themeLatte => 'Latte (Aydınlık)';

  @override
  String get themeFrappe => 'Frappé (Karanlık)';

  @override
  String get themeMacchiato => 'Macchiato (Karanlık)';

  @override
  String get themeMocha => 'Mocha (Karanlık)';

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
  String get addFolder => 'Klasör Ekle';

  @override
  String get newFolderName => 'Yeni Klasör Adı';

  @override
  String get folderAlreadyExists => 'Bu isimde bir klasör zaten mevcut.';

  @override
  String get pleaseEnterFolderName => 'Lütfen bir klasör adı girin';

  @override
  String get moveToFolder => 'Klasöre Taşı';

  @override
  String get moveFeed => 'Kaynağı Taşı';

  @override
  String feedMovedToFolder(String feedName, String folderName) {
    return '\"$feedName\" \"$folderName\" klasörüne taşındı';
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
}
