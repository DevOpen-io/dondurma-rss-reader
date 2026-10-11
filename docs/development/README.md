# Geliştirme ve Doğrulama

[Belge dizini](../README.md) · [Mimari](architecture.md) · [Çevrimdışı saklama](offline-storage.md)

## Gereksinimler

Dart SDK kısıtı [pubspec.yaml](../../pubspec.yaml) içinde `^3.11.0` olarak tanımlıdır. CI'ın kullandığı Flutter sürümü [build-and-release.yml](../../.github/workflows/build-and-release.yml) içindeki `FLUTTER_VERSION` alanıdır. Tekrarlanabilir doğrulama için bu sürümü kullanın; sürüm numarasının asıl kaynağı workflow'dur.

Android build için Android SDK ve Java 17; iOS build için macOS, Xcode ve projenin Swift Package Manager yapılandırması gerekir. Platform bağımlılıkları, imzalama ve mağaza gönderimi [yayın rehberinde](../operations/releases.md) açıklanır.

## Kurulum ve çalıştırma

Depo kökünde:

```bash
flutter pub get --enforce-lockfile
flutter run
```

Bağımlılık sürümleri `pubspec.lock` ile takip edilir. Bağımlılık değişikliği yaparken lock dosyasını da güncelleyin.

## Kaynak kodunu okuma sırası

1. [main.dart](../../lib/main.dart): başlangıç, Hive migration, provider bağlantıları ve sistem callback'leri.
2. [app_router.dart](../../lib/router/app_router.dart): onboarding ve makale yönlendirmesi.
3. [feed_provider.dart](../../lib/providers/feed_provider.dart): refresh, UI durumu ve servislerin koordinasyonu.
4. [feed_refresh.dart](../../lib/services/feed_refresh.dart) ve [feed_service.dart](../../lib/services/feed_service.dart): HTTP, parse, merge ve observation akışı.
5. [Çevrimdışı saklama rehberi](offline-storage.md): kalıcı makale/medya hattı ve yaşam döngüsü.
6. Değiştirilecek alanın `lib/screens/`, `lib/widgets/` bileşenleri ve `test/` regresyonları.

## Otomatik doğrulama

```bash
flutter analyze
flutter test
```

Hedefli bir regresyonu çalıştırmak için:

```bash
flutter test test/feed_backoff_test.dart
flutter test test/s4_temp_cache_selection_test.dart
```

HTTP/parse, notification observation, saklama/hazırlık/temizleme, UI etkileşimleri ve geniş ekran davranışları testlerde ayrı alanlar olarak bulunur. Davranış değiştiğinde ilgili regresyonları güncelleyin. Platform callback'leri, izinler, widget'lar ve arka plan çalışması ayrıca ilgili cihazda doğrulanır.

## Yerelleştirme

UI metinleri `lib/l10n/app_en.arb`, `app_tr.arb`, `app_es.arb` içindedir. Dil listesi [supported_languages.dart](../../lib/l10n/supported_languages.dart) üzerinden türetilir. ARB değişikliklerinden sonra:

```bash
flutter gen-l10n
```

Üretilen `app_localizations*.dart` dosyalarını elle düzenlemeyin.

## Build ve yayın

Yerel Android denemesi için:

```bash
flutter build apk --debug
```

İmzalı Android/iOS build, credential gereksinimleri, tag kuralları ve gönderimden bağımsız doğrulama komutları [yayın rehberindedir](../operations/releases.md). Yayın tag'i iki mağazaya gönderimi başlatır; doğrulama için debug build veya rehberdeki gönderimsiz adımları kullanın.

## Belgeleri güncelleme

Mimari değişikliklerini [mimari rehberine](architecture.md), sahiplik/cache davranışlarını [çevrimdışı saklama rehberine](offline-storage.md), uygulanan özellikleri [ürün durumuna](../product/status.md) yansıtın. Tarihsel planlar güncel yapılacaklar listesi değildir.
