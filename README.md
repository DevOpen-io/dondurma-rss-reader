<p align="center">
  <img src="assets/Logo.png" width="160" alt="Dondurma RSS Reader Logo" />
</p>

<h1 align="center">🍦 Dondurma RSS Reader</h1>

<p align="center">
  <strong>A modern, feature-rich RSS/Atom feed reader built with Flutter & Material 3</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Material_3-Design-6750A4?style=for-the-badge&logo=material-design&logoColor=white" alt="Material 3" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License" />
  <img src="https://img.shields.io/badge/Platform-Android%20|%20iOS%20|%20Web%20|%20Desktop-43A047?style=for-the-badge" alt="Platforms" />
</p>

<p align="center">
  <a href="#-english">English</a> · <a href="#-türkçe">Türkçe</a>
</p>

---

# 🇬🇧 English

## 📖 About

**Dondurma** (Turkish for "ice cream" 🍦) is a beautifully crafted, open-source RSS/Atom feed reader that puts you in control of your news consumption. Built with Flutter and Material 3 design principles, it delivers a premium reading experience across **Android, iOS, Web, Windows, macOS, and Linux**.

No algorithms. No tracking. Just your feeds, your way.

## ✨ Features

### 📰 Feed Management
- **RSS & Atom Support** — Subscribe to any RSS 2.0 or Atom feed
- **Category & Folder Organization** — Group your feeds into custom categories with emoji icons
- **OPML Import/Export** — Easily migrate from other readers or share your subscriptions
- **Feed Discovery** — Curated list of suggested feeds to explore new content
- **Per-Feed Keyword Filtering** — Exclude articles containing unwanted keywords
- **Global Content Filtering** — Define excluded keywords that apply across all feeds

### 📱 Reading Experience
- **Beautiful Article Viewer** — Full-screen article reading with image carousels
- **Swipe Navigation** — Swipe between articles with fluid PageView transitions
- **Full-Text Extraction** — Automatically extract complete articles from excerpt-only feeds
- **Reading Progress Tracking** — Resume reading right where you left off
- **Estimated Reading Time** — Know how long an article will take before diving in
- **Search & Search History** — Find articles quickly with persistent search suggestions
- **On-Device Translation** 🌐 — Translate articles locally using Google ML Kit. Supports offline translation by downloading language packages, preserving HTML tags, formatting, and carousels.

### 🎨 Theming & Customization
- **10 Color Schemes** — Material, Blue, Indigo, Deep Purple, Sakura, Red, Teal, Green, Amber, and Outer Space — powered by [FlexColorScheme](https://pub.dev/packages/flex_color_scheme)
- **3 Brightness Modes** — System, Light, and Dark for each color scheme
- **Google Fonts (Outfit)** — Premium typography throughout the app
- **iOS-Style Scroll Physics** — Buttery-smooth bouncing scroll on all platforms

### ✏️ Display & Readability
- **Font Size** — Choose from Small, Medium, Large, or Extra Large
- **Typeface** — Switch between System, Serif, Sans-Serif, and Mono
- **Line Spacing** — Tight (1.2), Normal (1.5), or Relaxed (1.8)

### 🌐 In-App Browser
- **Built-in WebView** — Read articles without leaving the app
- **Ad Blocker** — EasyList + AdGuard filter-based ad blocking with toggle
- **WebView Dark Mode** — Force dark mode in the in-app browser
- **External Browser Option** — Choose between built-in, external, or system browser

### 🔔 Notifications & Background Sync
- **New Article Alerts** — Get notified when new articles arrive in your subscribed feeds
- **Quiet Hours** — Silence notifications during specified time windows
- **Digest Mode** — Configure how notification summaries are delivered (Instant / Daily / Weekly)
- **Tap-to-Navigate** — Tap a notification to jump directly to the article
- **Background Sync** 🔄 — Automatic background feed fetching via `Workmanager` even when the app is closed, with customizable schedules.

### 💾 Offline & Performance
- **Offline Caching** — Read previously loaded articles without an internet connection
- **Image Caching** — Optimized network image loading with persistent cache for articles & thumbnails
- **Skeleton Shimmer Loading** — Beautiful loading states that mirror the actual content layout
- **Pagination** — Date-based sections (Today / Yesterday / Older) with load-more support

### 🚀 Onboarding Flow
- **Interactive Onboarding** 🍦 — Multi-step onboarding experience featuring suggested Turkish & Global feeds grouped by categories with background blobs animation to kickstart the feed collection.

### 📌 Bookmarks & Sharing
- **Bookmark Articles** — Save articles for later with swipe-left gesture
- **Share Articles** — Share article links via system share sheet
- **Read/Unread Management** — Swipe right to toggle read status

### 🌍 Localization
- **English** 🇬🇧 & **Turkish** 🇹🇷 fully supported
- Easily extendable to new languages via ARB files

## 🏗️ Architecture

```
lib/
├── main.dart                  # App entry point, provider wiring, Hive init, Workmanager setup
├── models/                    # Data models (FeedItem, FeedSubscription)
├── providers/                 # State management (5 ChangeNotifier providers)
│   ├── feed_provider.dart         # Feed fetching, filtering, pagination, caching
│   ├── subscription_provider.dart # Feed subscriptions & categories
│   ├── bookmark_provider.dart     # Saved articles persistence
│   ├── settings_provider.dart     # Theme, locale, sync, notification prefs
│   └── article_page_provider.dart # Per-article scroll, reading state & ML Kit translations
├── services/                  # Business logic services
│   ├── feed_service.dart              # HTTP fetch + RSS/Atom parsing
│   ├── full_text_extraction_service.dart  # Heuristic content extraction
│   ├── notification_service.dart      # Local notifications wrapper
│   ├── opml_service.dart              # OPML import/export
│   ├── background_fetch_service.dart  # Workmanager background fetch dispatcher
│   └── image_cache_service.dart       # Article and thumbnail cache managers
├── screens/                   # Full-page UI screens
│   ├── home_screen.dart           # Main screen with bottom nav
│   ├── article_screen.dart        # Article viewer with swipe
│   ├── categories_screen.dart     # Category/folder management
│   ├── bookmarks_screen.dart      # Saved articles list
│   ├── settings_screen.dart       # Premium iOS-style settings
│   ├── debug_screen.dart          # Developer utilities
│   ├── onboarding_screen.dart     # Onboarding setup flow
│   ├── what_is_rss_page.dart      # Educational RSS explainer
│   ├── privacy_policy_page.dart   # Privacy policy
│   └── terms_of_service_page.dart # Terms of service
├── widgets/                   # Reusable UI components
│   ├── feed_list_item.dart        # Article card with swipe actions
│   ├── app_drawer.dart            # Category navigation drawer
│   ├── in_app_browser.dart        # WebView with ad blocker
│   ├── add_feed_dialog.dart       # Feed subscription dialog
│   ├── explore_feeds_dialog.dart  # Feed discovery page
│   ├── keyword_input_sheet.dart   # Keyword filter bottom sheet
│   ├── language_packs_sheet.dart  # Translation language pack download sheet
│   ├── article/                   # Article-specific widgets
│   │   ├── article_circle_buttons.dart
│   │   ├── article_content_skeleton.dart
│   │   ├── article_image_carousel.dart
│   │   ├── article_reading_mode_toggle.dart
│   │   └── article_translation_sheet.dart # On-device translation interface
│   ├── folders/                   # Folder-specific widgets
│   │   ├── feed_action_sheet.dart
│   │   └── folder_dialogs.dart
│   ├── home/                      # Home screen widgets
│   │   ├── add_category_dialog.dart   # Add custom category dialog
│   │   ├── feed_list_skeleton.dart
│   │   ├── home_bottom_nav.dart
│   │   ├── home_pagination_footer.dart
│   │   └── home_search_history_panel.dart
│   └── settings/                  # Settings screen widgets
│       └── settings_widgets.dart
├── theme/
│   └── app_theme.dart         # FlexColorScheme + Material 3 config
├── router/
│   └── app_router.dart        # GoRouter declarative routing
└── l10n/                      # Localization (EN & TR)
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter 3.11+ / Dart 3.11+ |
| **State Management** | Provider (ChangeNotifier) |
| **Persistence** | Hive CE (3 boxes: settings, feeds, bookmarks) |
| **Routing** | GoRouter |
| **Networking** | http package |
| **Feed Parsing** | dart_rss (RSS 2.0 & Atom) |
| **Theming** | FlexColorScheme + Google Fonts (Outfit) |
| **Image Caching** | cached_network_image_ce |
| **WebView** | webview_flutter + adblocker_webview |
| **Notifications** | flutter_local_notifications |
| **Background Work** | workmanager |
| **Translation** | google_mlkit_translation (Google ML Kit On-Device Translation) |
| **Skeleton Loading** | skeletonizer |
| **XML** | xml (for OPML) |
| **Sharing** | share_plus, url_launcher |

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `3.11.0` or higher
- Dart SDK `3.11.0` or higher

### Installation

```bash
# Clone the repository
git clone https://github.com/DevOpen-io/Dondurma-Rss-Reader.git
cd Dondurma-Rss-Reader

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Build for Production

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues and pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the [MIT License](LICENSE).

Privacy policy: [English](docs/privacy-policy.en.md) | [Türkçe](docs/privacy-policy.tr.md).

---

# 🇹🇷 Türkçe

## 📖 Hakkında

**Dondurma** 🍦 güzel tasarlanmış, açık kaynaklı bir RSS/Atom haber okuyucusudur ve haber tüketiminizin kontrolünü tamamen size bırakır. Flutter ve Material 3 tasarım ilkeleriyle geliştirilmiş olup **Android, iOS, Web, Windows, macOS ve Linux** platformlarında premium bir okuma deneyimi sunar.

Algoritma yok. Takip yok. Sadece sizin akışlarınız, sizin kurallarınız.

## ✨ Özellikler

### 📰 Akış Yönetimi
- **RSS & Atom Desteği** — Herhangi bir RSS 2.0 veya Atom akışına abone olun
- **Kategori ve Klasör Düzeni** — Akışlarınızı emoji ikonlarla özel kategorilere ayırın
- **OPML İçe/Dışa Aktarım** — Diğer okuyuculardan kolayca geçiş yapın veya aboneliklerinizi paylaşın
- **Akış Keşfi** — Yeni içerik keşfetmek için önerilen akışlar listesi
- **Akış Bazlı Anahtar Kelime Filtreleme** — İstenmeyen anahtar kelimeleri içeren makaleleri hariç tutun
- **Genel İçerik Filtreleme** — Tüm akışlara uygulanan hariç tutma anahtar kelimeleri belirleyin

### 📱 Okuma Deneyimi
- **Güzel Makale Görüntüleyici** — Tam ekran makale okuma ve resim karuseli
- **Kaydırarak Gezinme** — Akıcı PageView geçişleriyle makaleler arası kaydırma
- **Tam Metin Çıkarma** — Sadece özet veren akışlardan otomatik tam metin çıkarma
- **Okuma İlerlemesi Takibi** — Kaldığınız yerden okumaya devam edin
- **Tahmini Okuma Süresi** — Makaleye başlamadan önce ne kadar süreceğini bilin
- **Arama ve Arama Geçmişi** — Kalıcı arama önerileriyle makaleleri hızla bulun
- **Cihaz İçi Çeviri** 🌐 — Google ML Kit kullanarak makaleleri yerel olarak çevirin. Dil paketlerini cihazınıza indirerek internet olmadan çeviri desteği sağlar; bu sırada HTML yapısını, biçimlendirmeleri ve görselleri korur.

### 🎨 Tema ve Özelleştirme
- **10 Renk Şeması** — Material, Blue, Indigo, Deep Purple, Sakura, Red, Teal, Green, Amber ve Outer Space — [FlexColorScheme](https://pub.dev/packages/flex_color_scheme) ile
- **3 Parlaklık Modu** — Her renk şeması için Sistem, Açık ve Koyu
- **Google Fonts (Outfit)** — Uygulama genelinde premium tipografi
- **iOS Tarzı Kaydırma Fiziği** — Tüm platformlarda ipeksi-akıcı kaydırma

### ✏️ Görüntüleme ve Okunabilirlik
- **Yazı Tipi Boyutu** — Küçük, Orta, Büyük veya Çok Büyük arasında seçim yapın
- **Yazı Tipi** — Sistem, Serif, Sans-Serif ve Mono arasında geçiş yapın
- **Satır Aralığı** — Dar (1.2), Normal (1.5) veya Geniş (1.8)

### 🌐 Uygulama İçi Tarayıcı
- **Yerleşik WebView** — Uygulamadan çıkmadan makaleleri okuyun
- **Reklam Engelleyici** — EasyList + AdGuard filtre tabanlı reklam engelleme
- **WebView Karanlık Mod** — Uygulama içi tarayıcıda karanlık mod zorlama
- **Harici Tarayıcı Seçeneği** — Yerleşik, harici veya sistem tarayıcısı arasında seçim yapın

### 🔔 Bildirimler ve Arka Plan Senkronizasyonu
- **Yeni Makale Uyarıları** — Abone olduğunuz akışlara yeni makale geldiğinde bildirim alın
- **Sessiz Saatler** — Belirlediğiniz zaman dilimlerinde bildirimleri susturun
- **Özet Modu** — Bildirim özetlerinin nasıl gönderileceğini yapılandırın (Anlık / Günlük / Haftalık)
- **Dokunarak Git** — Bildirime dokunarak doğrudan makaleye gidin
- **Arka Plan Senkronizasyonu** 🔄 — `Workmanager` aracılığıyla uygulama kapalıyken bile akışları arka planda otomatik güncel tutma ve bildirim gönderme.

### 💾 Çevrimdışı ve Performans
- **Çevrimdışı Önbellekleme** — İnternet bağlantısı olmadan daha önce yüklenen makaleleri okuyun
- **Görsel Önbellekleme** — Makaleler ve küçük resimler için kalıcı önbellekle optimize edilmiş görsel yükleme
- **İskelet Yükleme Animasyonu** — İçerik düzenini yansıtan güzel yükleme durumları
- **Sayfalama** — Tarih bazlı bölümler (Bugün / Dün / Daha Eski) ve daha fazla yükleme desteği

### 🚀 Başlangıç Rehberi (Onboarding)
- **Etkileşimli Tanıtım** 🍦 — Uygulamaya başlarken dinamik blob animasyonlu, Türkçe ve İngilizce önerilen akışları kategori bazlı seçerek hızlıca abone olmanızı sağlayan onboarding akışı.

### 📌 Yer İmleri ve Paylaşım
- **Makale Yer İmlerine Ekleme** — Sola kaydırma hareketiyle makaleleri daha sonrası için kaydedin
- **Makale Paylaşımı** — Sistem paylaşım sayfası üzerinden makale bağlantılarını paylaşın
- **Okundu/Okunmadı Yönetimi** — Sağa kaydırma ile okundu durumunu değiştirin

### 🌍 Yerelleştirme
- **İngilizce** 🇬🇧 ve **Türkçe** 🇹🇷 tam destek
- ARB dosyaları aracılığıyla kolayca yeni dillere genişletilebilir

## 🏗️ Mimari

```
lib/
├── main.dart                  # Uygulama giriş noktası, provider bağlantıları, Hive başlatma ve Workmanager kurulumu
├── models/                    # Veri modelleri (FeedItem, FeedSubscription)
├── providers/                 # Durum yönetimi (5 ChangeNotifier provider)
│   ├── feed_provider.dart         # Akış getirme, filtreleme, sayfalama, önbellekleme
│   ├── subscription_provider.dart # Akış abonelikleri ve kategoriler
│   ├── bookmark_provider.dart     # Kaydedilmiş makalelerin kalıcılığı
│   ├── settings_provider.dart     # Tema, dil, senkronizasyon, bildirim ayarları
│   └── article_page_provider.dart # Her makale için kaydırma, okuma durumu ve ML Kit çeviri yönetimi
├── services/                  # İş mantığı servisleri
│   ├── feed_service.dart              # HTTP istekleri + RSS/Atom ayrıştırma
│   ├── full_text_extraction_service.dart  # Sezgisel içerik çıkarma
│   ├── notification_service.dart      # Yerel bildirimler sarmalayıcı
│   ├── opml_service.dart              # OPML içe/dışa aktarım
│   ├── background_fetch_service.dart  # Workmanager arka plan işleyicisi
│   └── image_cache_service.dart       # Makale ve küçük resim önbellek yöneticileri
├── screens/                   # Tam sayfa UI ekranları
│   ├── home_screen.dart           # Alt navigasyonlu ana ekran
│   ├── article_screen.dart        # Kaydırmalı makale görüntüleyici
│   ├── categories_screen.dart     # Kategori/klasör yönetimi
│   ├── bookmarks_screen.dart      # Kaydedilmiş makaleler listesi
│   ├── settings_screen.dart       # Premium iOS tarzı ayarlar
│   ├── debug_screen.dart          # Geliştirici araçları
│   ├── onboarding_screen.dart     # Kurulum ve akış seçimi onboarding ekranı
│   ├── what_is_rss_page.dart      # Eğitici RSS açıklama sayfası
│   ├── privacy_policy_page.dart   # Gizlilik politikası
│   └── terms_of_service_page.dart # Kullanım koşulları
├── widgets/                   # Tekrar kullanılabilir UI bileşenleri
│   ├── feed_list_item.dart        # Kaydırma aksiyonlu makale kartı
│   ├── app_drawer.dart            # Kategori navigasyon çekmecesi
│   ├── in_app_browser.dart        # Reklam engelleyicili WebView
│   ├── add_feed_dialog.dart       # Akış abonelik diyaloğu
│   ├── explore_feeds_dialog.dart  # Akış keşif sayfası
│   ├── keyword_input_sheet.dart   # Anahtar kelime filtre bottom sheet
│   ├── language_packs_sheet.dart  # Çeviri dil paketleri indirme paneli
│   ├── article/                   # Makale bileşenleri
│   │   ├── article_circle_buttons.dart
│   │   ├── article_content_skeleton.dart
│   │   ├── article_image_carousel.dart
│   │   ├── article_reading_mode_toggle.dart
│   │   └── article_translation_sheet.dart # Cihaz içi çeviri paneli
│   ├── folders/                   # Klasör bileşenleri
│   │   ├── feed_action_sheet.dart
│   │   └── folder_dialogs.dart
│   ├── home/                      # Ana ekran bileşenleri
│   │   ├── add_category_dialog.dart   # Özel kategori ekleme diyaloğu
│   │   ├── feed_list_skeleton.dart
│   │   ├── home_bottom_nav.dart
│   │   ├── home_pagination_footer.dart
│   │   └── home_search_history_panel.dart
│   └── settings/                  # Ayarlar bileşenleri
│       └── settings_widgets.dart
├── theme/
│   └── app_theme.dart         # FlexColorScheme + Material 3 yapılandırma
├── router/
│   └── app_router.dart        # GoRouter deklaratif yönlendirme
└── l10n/                      # Yerelleştirme (EN & TR)
```

### Teknoloji Yığını

| Katman | Teknoloji |
|--------|----------|
| **Çatı** | Flutter 3.11+ / Dart 3.11+ |
| **Durum Yönetimi** | Provider (ChangeNotifier) |
| **Kalıcılık** | Hive CE (3 kutu: settings, feeds, bookmarks) |
| **Yönlendirme** | GoRouter |
| **Ağ İstekleri** | http paketi |
| **Akış Ayrıştırma** | dart_rss (RSS 2.0 & Atom) |
| **Tema** | FlexColorScheme + Google Fonts (Outfit) |
| **Görsel Önbellek** | cached_network_image_ce |
| **WebView** | webview_flutter + adblocker_webview |
| **Bildirimler** | flutter_local_notifications |
| **Arka Plan İşleri** | workmanager |
| **Çeviri** | google_mlkit_translation (Google ML Kit Cihaz İçi Çeviri) |
| **İskelet Yükleme** | skeletonizer |
| **XML** | xml (OPML için) |
| **Paylaşım** | share_plus, url_launcher |

## 🚀 Başlarken

### Gereksinimler

- Flutter SDK `3.11.0` veya üzeri
- Dart SDK `3.11.0` veya üzeri

### Kurulum

```bash
# Depoyu klonlayın
git clone https://github.com/DevOpen-io/Dondurma-Rss-Reader.git
cd Dondurma-Rss-Reader

# Bağımlılıkları yükleyin
flutter pub get

# Uygulamayı çalıştırın
flutter run
```

### Prodüksiyon İçin Derleme

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

## 🤝 Katkıda Bulunma

Katkılarınızı bekliyoruz! Sorun bildirmek ve pull request göndermekten çekinmeyin.

1. Depoyu forklayın
2. Özellik dalınızı oluşturun (`git checkout -b feature/harika-ozellik`)
3. Değişikliklerinizi kaydedin (`git commit -m 'feat: harika özellik ekle'`)
4. Dalı gönderin (`git push origin feature/harika-ozellik`)
5. Pull Request açın

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) altında lisanslanmıştır.

Gizlilik politikası: [English](docs/privacy-policy.en.md) | [Türkçe](docs/privacy-policy.tr.md).

---

<p align="center">
  Made with 🍦 and ❤️ using Flutter
</p>
