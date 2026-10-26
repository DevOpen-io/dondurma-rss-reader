# Kademeli Feed Yenileme Uygulama Planı

**Amaç:** Başarılı kaynakları diğerlerini beklemeden göstermek ve kullanıcının okuduğu satırı korumak.

**Tasarım:** [Onaylanan davranış](../specs/2026-10-24-incremental-feed-refresh-design.md).

## 1. Kaynak sonucu ve ortak birleştirme

- [x] `lib/services/feed_refresh.dart`: başarılı 200 gövdeleri için ayrı callback; nihai sonuç API'si korundu.
- [x] Yeni bir merge dosyası yerine mevcut `lib/services/feed_cache_policy.dart` genişletildi: kaynak snapshot değiştirme, kaynak+ID tekilleştirme, prefetched text ve bookmark koruması, ortak effective-date sıralaması.
- [x] `test/rss_lifecycle_regression_test.dart`: kontrollü hızlı/yavaş HTTP; mevcut 304/hata regresyonları ve nihai sonuç uyumu.

## 2. Provider yayını

- [x] `lib/providers/feed_provider.dart`: 100 ms timer ile kaynak sonuçlarını birleştirme; bitişte son grubu uygulama; güncel abonelik/yer imi ile nihai uzlaştırma.
- [x] Reset, cache temizliği, dispose ve pass-local durum eski sonuçları reddediyor; ara yayınlar kalıcı yan etki başlatmıyor. Cache temizliği sunucudan öğrenilen Retry-After politikasını silmiyor.
- [x] Provider testleri: yavaş istek açıkken görünür veri, disk snapshot'ının değişmemesi, batching, kaldırılan kaynaklar, yenileme sırasında değişen yer imleri, pending timer ve generation fences.

## 3. Görünür satırın korunması

- [x] `lib/widgets/anchored_feed_list.dart`: tek viewport içinde keyed, lazy sliver listeleri. Veri sırası değişirken hayatta kalan görünür makaleyi yeni merkez yaparak aynı piksel konumunu koruma; üstteyken yeni başlığı gösterme.
- [x] `lib/screens/home_screen.dart` ve `lib/screens/desktop/desktop_article_list.dart`: ortak liste; ayrı tarih başlığı/footer kimlikleri; kaynak+ID+occurrence anahtarları.
- [x] `test/anchored_feed_list_test.dart`: dar/geniş ekran, değişken yükseklik, prepend/reorder/remove, tarih başlıkları, ardışık güncelleme, iki yönde kaydırma, boşaltma, listenin başı ve sanallaştırma.
- [x] Mobil/masaüstü regresyonları ve okuyucu scroll testleri çalıştırıldı. `desktop_runtime_regressions_test.dart` artık platform guard nedeniyle sessizce geçmek yerine Linux hedef varyantıyla gerçekten çalışıyor; masaüstü satır konumu testi eklendi.

## 4. Doğrulama ve belgeler

- [x] Değişen Dart dosyaları biçimlendirildi.
- [x] Hedefli testler, `flutter analyze`, ardından tam `flutter test` paketi.
- [x] Mimari rehberi, ürün durumu ve tasarım indeksi güncellendi.

Doğrulama Linux host üzerinde Flutter birim/widget testleriyle yapıldı. Fiziksel cihaz veya yerel masaüstü uygulamasında manuel smoke testi yapılmadı; Windows/macOS/iOS cihaz doğrulaması iddia edilmez.

## Hızlı kaydırma regresyonu

Kullanıcının bildirdiği yenileme sırasında hızlı masaüstü kaydırma hatası testte aynen üretildi: offscreen keep-alive satırın `NaN` koordinatı scroll offset'ine taşınıyor, önce viewport assertion'ı, ardından `_elements.contains(element)` widget yaşam döngüsü assertion'ı oluşuyordu. Anchor seçiminde sonlu koordinat kontrolü eklendi. Minimal keep-alive regresyonu ile hover, fling ve art arda kaynak sonuçları içeren deterministik masaüstü stres testi düzeltmeyi koruyor.

Kullanıcının mevcut skill/gitignore değişiklikleri kapsam dışı bırakıldı.
