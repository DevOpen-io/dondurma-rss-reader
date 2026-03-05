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

### 📱 Reading Experience
- **Beautiful Article Viewer** — Full-screen article reading with image carousels
- **Swipe Navigation** — Swipe between articles with fluid PageView transitions
- **Full-Text Extraction** — Automatically extract complete articles from excerpt-only feeds
- **Reading Progress Tracking** — Resume reading right where you left off
- **Estimated Reading Time** — Know how long an article will take before diving in
- **Search & Search History** — Find articles quickly with persistent search suggestions

### 🎨 Theming & Customization
- **9 Theme Options** — System, Light, Dark, 4 Catppuccin flavors (Latte, Frappé, Macchiato, Mocha), and 2 High Contrast themes
- **Google Fonts (Outfit)** — Premium typography throughout the app
- **iOS-Style Scroll Physics** — Buttery-smooth bouncing scroll on all platforms

### 🌐 In-App Browser
- **Built-in WebView** — Read articles without leaving the app
- **Ad Blocker** — EasyList + AdGuard filter-based ad blocking with toggle
- **External Browser Option** — Choose between built-in, external, or system browser

### 🔔 Notifications
- **New Article Alerts** — Get notified when new articles arrive in your subscribed feeds
- **Quiet Hours** — Silence notifications during specified time windows
- **Digest Mode** — Configure how notification summaries are delivered
- **Tap-to-Navigate** — Tap a notification to jump directly to the article

### 💾 Offline & Performance
- **Offline Caching** — Read previously loaded articles without an internet connection
- **Background Sync** — Configurable auto-refresh intervals to keep feeds up to date
- **Image Caching** — Optimized network image loading with persistent cache
- **Skeleton Shimmer Loading** — Beautiful loading states that mirror the actual content layout
- **Pagination** — Date-based sections (Today / Yesterday / Older) with load-more support

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
├── main.dart                  # App entry point, provider wiring, Hive init
├── models/                    # Data models (FeedItem, FeedSubscription)
├── providers/                 # State management (5 ChangeNotifier providers)
│   ├── feed_provider.dart         # Feed fetching, filtering, pagination, caching
│   ├── subscription_provider.dart # Feed subscriptions & categories
│   ├── bookmark_provider.dart     # Saved articles persistence
│   ├── settings_provider.dart     # Theme, locale, sync, notification prefs
│   └── article_page_provider.dart # Per-article scroll & reading state
├── services/                  # Business logic services
│   ├── feed_service.dart              # HTTP fetch + RSS/Atom parsing
│   ├── full_text_extraction_service.dart  # Heuristic content extraction
│   ├── notification_service.dart      # Local notifications wrapper
│   └── opml_service.dart              # OPML import/export
├── screens/                   # Full-page UI screens
│   ├── home_screen.dart           # Main screen with bottom nav
│   ├── article_screen.dart        # Article viewer with swipe
│   ├── folders_screen.dart        # Category/folder management
│   ├── bookmarks_screen.dart      # Saved articles list
│   ├── settings_screen.dart       # Premium iOS-style settings
│   ├── debug_screen.dart          # Developer utilities
│   └── what_is_rss_page.dart      # Educational RSS explainer
├── widgets/                   # Reusable UI components
│   ├── feed_list_item.dart        # Article card with swipe actions
│   ├── app_drawer.dart            # Category navigation drawer
│   ├── in_app_browser.dart        # WebView with ad blocker
│   ├── add_feed_dialog.dart       # Feed subscription dialog
│   ├── explore_feeds_dialog.dart  # Feed discovery page
│   └── keyword_input_dialog.dart  # Keyword filter input
├── theme/
│   └── app_theme.dart         # 9 theme variants + Material 3 config
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
| **Theming** | catppuccin_flutter + Google Fonts |
| **WebView** | webview_flutter + adblocker_webview |
| **Notifications** | flutter_local_notifications |
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

This project is open source. See the repository for license details.

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

### 📱 Okuma Deneyimi
- **Güzel Makale Görüntüleyici** — Tam ekran makale okuma ve resim karuseli
- **Kaydırarak Gezinme** — Akıcı PageView geçişleriyle makaleler arası kaydırma
- **Tam Metin Çıkarma** — Sadece özet veren akışlardan otomatik tam metin çıkarma
- **Okuma İlerlemesi Takibi** — Kaldığınız yerden okumaya devam edin
- **Tahmini Okuma Süresi** — Makaleye başlamadan önce ne kadar süreceğini bilin
- **Arama ve Arama Geçmişi** — Kalıcı arama önerileriyle makaleleri hızla bulun

### 🎨 Tema ve Özelleştirme
- **9 Tema Seçeneği** — Sistem, Açık, Koyu, 4 Catppuccin aroması (Latte, Frappé, Macchiato, Mocha) ve 2 Yüksek Kontrast tema
- **Google Fonts (Outfit)** — Uygulama genelinde premium tipografi
- **iOS Tarzı Kaydırma Fiziği** — Tüm platformlarda ipeksi-akıcı kaydırma

### 🌐 Uygulama İçi Tarayıcı
- **Yerleşik WebView** — Uygulamadan çıkmadan makaleleri okuyun
- **Reklam Engelleyici** — EasyList + AdGuard filtre tabanlı reklam engelleme
- **Harici Tarayıcı Seçeneği** — Yerleşik, harici veya sistem tarayıcısı arasında seçim yapın

### 🔔 Bildirimler
- **Yeni Makale Uyarıları** — Abone olduğunuz akışlara yeni makale geldiğinde bildirim alın
- **Sessiz Saatler** — Belirlediğiniz zaman dilimlerinde bildirimleri susturun
- **Özet Modu** — Bildirim özetlerinin nasıl gönderileceğini yapılandırın
- **Dokunarak Git** — Bildirime dokunarak doğrudan makaleye gidin

### 💾 Çevrimdışı ve Performans
- **Çevrimdışı Önbellekleme** — İnternet bağlantısı olmadan daha önce yüklenen makaleleri okuyun
- **Arka Plan Senkronizasyonu** — Akışları güncel tutmak için yapılandırılabilir otomatik yenileme
- **Görsel Önbellekleme** — Kalıcı önbellekle optimize edilmiş ağ görseli yükleme
- **İskelet Yükleme Animasyonu** — İçerik düzenini yansıtan güzel yükleme durumları
- **Sayfalama** — Tarih bazlı bölümler (Bugün / Dün / Daha Eski) ve daha fazla yükleme desteği

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
├── main.dart                  # Uygulama giriş noktası, provider bağlantıları, Hive başlatma
├── models/                    # Veri modelleri (FeedItem, FeedSubscription)
├── providers/                 # Durum yönetimi (5 ChangeNotifier provider)
│   ├── feed_provider.dart         # Akış getirme, filtreleme, sayfalama, önbellekleme
│   ├── subscription_provider.dart # Akış abonelikleri ve kategoriler
│   ├── bookmark_provider.dart     # Kaydedilmiş makalelerin kalıcılığı
│   ├── settings_provider.dart     # Tema, dil, senkronizasyon, bildirim ayarları
│   └── article_page_provider.dart # Her makale için kaydırma ve okuma durumu
├── services/                  # İş mantığı servisleri
│   ├── feed_service.dart              # HTTP istekleri + RSS/Atom ayrıştırma
│   ├── full_text_extraction_service.dart  # Sezgisel içerik çıkarma
│   ├── notification_service.dart      # Yerel bildirimler sarmalayıcı
│   └── opml_service.dart              # OPML içe/dışa aktarım
├── screens/                   # Tam sayfa UI ekranları
│   ├── home_screen.dart           # Alt navigasyonlu ana ekran
│   ├── article_screen.dart        # Kaydırmalı makale görüntüleyici
│   ├── folders_screen.dart        # Kategori/klasör yönetimi
│   ├── bookmarks_screen.dart      # Kaydedilmiş makaleler listesi
│   ├── settings_screen.dart       # Premium iOS tarzı ayarlar
│   ├── debug_screen.dart          # Geliştirici araçları
│   └── what_is_rss_page.dart      # Eğitici RSS açıklama sayfası
├── widgets/                   # Tekrar kullanılabilir UI bileşenleri
│   ├── feed_list_item.dart        # Kaydırma aksiyonlu makale kartı
│   ├── app_drawer.dart            # Kategori navigasyon çekmecesi
│   ├── in_app_browser.dart        # Reklam engelleyicili WebView
│   ├── add_feed_dialog.dart       # Akış abonelik diyaloğu
│   ├── explore_feeds_dialog.dart  # Akış keşif sayfası
│   └── keyword_input_dialog.dart  # Anahtar kelime filtre girişi
├── theme/
│   └── app_theme.dart         # 9 tema varyantı + Material 3 yapılandırma
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
| **Tema** | catppuccin_flutter + Google Fonts |
| **WebView** | webview_flutter + adblocker_webview |
| **Bildirimler** | flutter_local_notifications |
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

Bu proje açık kaynaklıdır. Lisans detayları için depoya bakın.

---

<p align="center">
  Made with 🍦 and ❤️ using Flutter
</p>
