# Kademeli feed yenileme

Durum: Kullanıcı tarafından onaylandı ve uygulandı. [Uygulama planı](../plans/2026-10-24-incremental-feed-refresh.md).

## Amaç

Başarılı kaynaklardan gelen haberler, diğer kaynakların tamamlanmasını beklemeden mobil ve masaüstü listelerine yansır. Yenileme sayacı kaynak bazında ilerlemeye devam eder.

## Seçilen yaklaşım

Her kaynak sonucu için tüm listeyi çizmek yerine, başarılı HTTP 200 sonuçları en fazla 100 ms'lik pencerelerde birleştirilerek yayımlanır. Böylece ilk sonuç gecikmeden kısa sürede görünür; yoğun sonuç akışı gereksiz sıralama ve widget rebuild üretmez. Son bekleyen grup yenileme tamamlanırken hemen uygulanır.

Yalnız yenileme sonunda güncelleme mevcut gecikmeyi koruduğundan; her sonuçta sınırsız güncelleme ise gereksiz UI yükü ürettiğinden tercih edilmez.

## Veri akışı ve sorumluluklar

- `FeedRefresher`, mevcut progress callback'inden ayrı, başarılı kaynak gövdesi callback'i sunar. Callback kanonik abonelik URL'si ve ayrıştırılan makaleleri taşır. Nihai sonuç API'si korunur.
- Kaynak bazlı birleştirme ayrı, saf ve test edilebilir bir yardımcıda tutulur. Başarılı kaynağın eski snapshot'ı yenisiyle değiştirilir; diğer kaynakların mevcut makaleleri korunur. Önceden çıkarılmış metin ve eksik yer imleri korunur; ID tekilleştirmesi uygulanır.
- `FeedProvider`, bekleyen sonuçları 100 ms pencerede uygular; filtre ve tarih grubu cache'lerini gerçek veri değiştiğinde geçersiz kılar. Mevcut arama, kategori, kaynak, okundu ve sayfalama tercihleri sıfırlanmaz.
- Ara ve nihai listeler aynı birleştirme/sıralama kurallarını kullanır; nihai sonuç eski bir snapshot ile görünür haberleri geri almaz. Yerel saat ve ileri tarih toleransı korunur.
- Nihai birleştirme güncel abonelikler ve yer imleriyle uzlaştırılır. Yenileme sırasında kaldırılan aboneliğin geç sonucu yeniden görünmez.

## Kaydırma ve seçim

- Liste başındayken yeni haberler doğal biçimde görünür.
- Aşağı kaydırılmışken ilk görünür makalenin kimliği ve viewport içindeki dikey konumu korunur. Yalnız scroll offset'i korumak yeterli değildir.
- Değişken yükseklikte satırlar ve tarih başlıkları hesaba katılır. Liste sanallaştırması korunur; tüm satırları oluşturma veya eski çift-viewport yapısına dönme yoktur.
- Anchor makale sonuçtan çıkarsa önceki görünür komşulardan kalan ilk makale kullanılır; hiçbiri kalmazsa konum geçerli scroll sınırlarına çekilir.
- Mobil ve masaüstü listeleri aynı davranışı sağlar. Masaüstü okuyucudaki seçili makale ve okuma konumu, yalnız liste güncellendi diye sıfırlanmaz.

## Yan etkiler ve yaşam döngüsü

- Ara yayınlar yalnız görünür veriyi günceller; bildirim, kalıcı cache üyeliği, makale hazırlığı veya widget yazımı başlatmaz.
- Observation/claim mevcut yenileme hattında kalır ve delivery gating'den önce tamamlanır. İlk kaynak initialization sessizliği, suppressed claim'lerin backfill edilmemesi korunur.
- Kalıcı cache, ownership uzlaştırması, bildirim teslimi ve tamamlanma toast'ı mevcut yenileme sonu akışında kalır.
- HTTP 304, hata veya cooldown mevcut haberleri düşürmez; yeni gövde gibi yayımlanmaz.
- Beş istek concurrency sınırı, host pacing/backoff ve refresh coalescing değişmez.
- Reset, cache temizleme ve dispose eski callback/timer sonuçlarını geçersiz kılar. Reset öncesi işler veriyi geri getiremez. Timer'lar iptal edilir; gecikmiş notify yapılmaz.
- Ara sonuçtan sonra başka bir kaynak hata verirse ekranda başarılı kaynakların güncel haberleri kalır.

## Doğrulama

- Yerel kontrollü HTTP sunucusunda hızlı kaynağın haberleri, yavaş kaynak serbest bırakılmadan görünür.
- Çok sayıda yakın sonuç batching ile sınırlı sayıda yayın üretir; son grup gecikmeden uygulanır.
- Hata/304/cooldown eski veriyi korur; tekrar eden ID'ler, yer imleri ve prefetched text doğru birleştirilir.
- Yenileme sırasında abonelik kaldırma, yer imi değiştirme, reset, cache temizleme, dispose ve çakışan refresh senaryoları sınanır.
- Mobil/dar ve masaüstü/geniş widget testlerinde değişken yükseklik ve tarih başlığı içeren listede görünür makale/konumu korunur; okuyucu seçim ve scroll durumu değişmez.
- Ara yayında bildirim/cache yan etkisi oluşmadığı; yenileme sonunda toast ve bildirim kurallarının korunduğu doğrulanır.
- İlgili hedefli testlerden sonra `flutter analyze` ve tam test paketi çalıştırılır. Çalıştırılmayan platform doğrulamaları açıkça belirtilir.
