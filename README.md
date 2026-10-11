<p align="center"><img src="assets/Logo.png" width="160" alt="Dondurma RSS Reader logo" /></p>

# Dondurma RSS Reader

Fast, private RSS/Atom reader built with Flutter and Material 3. No accounts, algorithms, analytics, or ads. Your feeds, your device.

[English](#english) · [Türkçe](#türkçe)

[Documentation / Belgeler](docs/README.md) · [Development / Geliştirme](docs/development/README.md) · [Product / Ürün](docs/product/guide.md)

## English

[App Store](https://apps.apple.com/tr/app/dondurma-rss-reader/id6782334224?l=tr) · [Google Play](https://play.google.com/store/apps/details?id=io.devopen.dondurma)

### Features

- RSS 2.0/Atom, feed discovery, custom folders/icons/order, OPML import/export
- Global/per-feed keyword exclusion, search history, date sections, 50-item pagination
- Swipe read/bookmark actions; PageView navigation, progress, reading time, image carousel
- Global and per-feed full-text extraction with isolate processing
- Built-in WebView, EasyList/AdGuard, DarkReader, external browser modes
- Offline article/image cache; foreground and Workmanager background sync
- Local notifications, per-feed controls, quiet hours, digest selection
- Latest-news and category home-screen widgets
- 10 FlexColorScheme palettes; system/light/dark; reading typography controls
- Responsive widths, semantic controls, EN/TR/ES localization
- Modal-aware global toast feedback respecting reduced-motion settings

### Architecture

```text
lib/
├── main.dart       # startup, Hive migration, providers, OS integrations
├── models/         # FeedItem, FeedSubscription
├── providers/      # settings, subscriptions, bookmarks, feeds, article state
├── services/       # feed, offline records/media, preparation, OS integrations
├── screens/        # onboarding, home tabs, article, settings, legal, debug
├── widgets/        # reusable article, folder, home, settings UI
├── router/         # GoRouter routes and onboarding redirect
├── theme/          # Material 3 themes
├── utils/          # global toast, pacing, retry, motion helpers
└── l10n/           # EN/TR/ES localization
```

Five `ChangeNotifier` providers power UI state. `FeedProvider` receives subscription, settings, and bookmark state through `ChangeNotifierProxyProvider3`. Hive CE uses `settings`, `feeds`, and `bookmarks` boxes.

Durable article records and a shared media pool support offline preparation independently of disposable image caches. See [architecture](docs/development/architecture.md) and [offline storage](docs/development/offline-storage.md). Native platform behavior requires platform-specific verification; dated findings are indexed under [audits and research](docs/README.md#denetim-ve-araştırma).

### Development

Requires Flutter compatible with Dart `^3.11.0`.

```bash
git clone https://github.com/DevOpen-io/Dondurma-Rss-Reader.git
cd Dondurma-Rss-Reader
flutter pub get
flutter test
flutter run
```

Build, signing and store submission: [release guide](docs/operations/releases.md).

Details: [developer guide](docs/development/README.md) · [product guide](docs/product/guide.md) · [status and backlog](docs/product/status.md)

## Türkçe

[App Store](https://apps.apple.com/tr/app/dondurma-rss-reader/id6782334224?l=tr) · [Google Play](https://play.google.com/store/apps/details?id=io.devopen.dondurma)

### Özellikler

- RSS 2.0/Atom, akış keşfi, özel klasör/simge/sıralama, OPML içe/dışa aktarma
- Genel/akış bazlı kelime filtresi, arama geçmişi, tarih bölümleri, 50 öğelik sayfalama
- Kaydırarak okundu/yer imi; PageView, okuma ilerlemesi/süresi, görsel galerisi
- Genel ve akış bazlı tam metin çıkarma; isolate tabanlı işleme
- Yerleşik WebView, EasyList/AdGuard, DarkReader, harici tarayıcı modları
- Çevrimdışı makale/görsel önbelleği; ön plan ve Workmanager senkronizasyonu
- Yerel bildirimler, akış kontrolleri, sessiz saatler, özet seçimi
- Son haberler ve kategori ana ekran widget'ları
- 10 renk şeması; sistem/açık/koyu; okuma tipografisi ayarları
- Duyarlı genişlik, semantik kontroller, EN/TR/ES
- Azaltılmış hareket ayarına uyan, modal farkındalıklı global toast

### Geliştirme

```bash
flutter pub get
flutter test
flutter run
```

Ayrıntılar: [geliştirici rehberi](docs/development/README.md) · [ürün rehberi](docs/product/guide.md) · [durum ve backlog](docs/product/status.md) · [teknik yol haritası](docs/product/roadmap.md)

## Privacy and license

[English privacy policy](docs/privacy-policy.en.md) · [Türkçe gizlilik politikası](docs/privacy-policy.tr.md) · [MIT License](LICENSE)
