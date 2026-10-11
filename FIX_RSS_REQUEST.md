# RSS Motoru — Son Denetim Raporu (PR #60)

## 1. Üç Bulgunun Kök Nedeni

### Bulgu 1 — Kardeş feed'in başarısı host cooldown'unu erken siliyor

`recordSuccess` koşulsuz `_hostRetryAt.remove(...)` yapıyordu. Senaryo: A 429 + `Retry-After: 600` alır → host 10 dk soğur → önceden uçuşta olan B 200 döner → başarı host kaydını siler → C, sunucunun 10 dk'lık kısıtı bitmeden istek atabilir. Kardeş 200, origin çapında geçerli bir server kısıtını çürütmez.

### Bulgu 2 — Temizlenen cooldown persist'ten dirilebiliyor

`_cleared[key] = <temizleme anı>` ile persist'teki `until` (sona erme anı) karşılaştırılıyordu — iki farklı zaman ekseni. 10:00'da `Retry-After: 1800` ile oluşan kaydın deadline'ı 10:30'dur; 10:06'daki başarı bu kaydı temizler; ama `until (10:30) > clearedAt (10:06)` olduğu için eski snapshot kaydı geri yüklerdi. Event-zamanı ile expiry-zamanı karşılaştırılamaz.

### Bulgu 3 — Isolate içi/ler arası pacing ve yarış

- `runBgFetch` kendi `HostPacer`'ını oluşturuyor ama `ArticlePreparationService` ve `FullTextExtractionService` bağımsız instance'lar kullanıyordu → aynı isolate içinde iki ayrı zamanlama.
- Pacing kuyruğunda bekleyen istek, cooldown uygunluğunu **beklemeden önce** kontrol ediyordu; boşluk süresi önceki isteğin bittiğini garanti etmez → 429 öğrenildikten sonra gereksiz istek çıkıyordu.
- Hive `get→merge→put` iki isolate arasında atomik değil: aynı anahtara son yazan kazanır → kayıp güncelleme riski gerçekti.

## 2. Düzeltilen Model

### `FeedBackoff` v3 kayıtları

Her cooldown kaydı üç alan taşır: `since` (oluşum event-zamanı), `until` (expiry), `serverMandated` (deadline `Retry-After`'dan mı geldi).

- **`recordSuccess`**: feed'in kendi kaydı her zaman silinir (kendi 200'ü kendi cooldown'unu çürütür). Host kaydı yalnız local-estimate veya süresi dolmuşsa silinir; aktif server-mandated kayıt korunur ve host clear-marker **üretilmez** (marker sızıp diğer isolate'in mandate'ini bastırmasın diye).
- **`load`**: önce `cleared` birleşir (en yeni event kazanır), sonra kayıtlar — `since <= clearedAt` olanlar bastırılır (host bölümünde mandated kayıtlar muaf), expiry'ler max ile birleşir; sonda öğrenilen clear'lar bellekteki kayıtlara da uygulanır (simetrik yayılım).
- **Legacy**: v2 `{feeds: {url: ms}}` ve flat `{url: ms}` → `since = epoch` okunur; kaydedilmiş bir clear onları bastırır (güvenli varsayım), temizlenmemiş anahtarlar normal yüklenir.
- **`snapshot`**: `{feeds, hosts}` kayıtları `{u, s, m}` + `cleared` haritası. Süresi dolmuş kayıtlar yazılmaz (sınır).

### Çapraz-isolate persist modeli

Ortak `feedBackoffUntil` üzerinde read-modify-write yerine **yazar-başına slot**: ön plan `feedBackoffUntil`, arka plan `feedBackoffUntil.bg` yazar; **her okuyucu iki slotu da merge eder**. Paylaşılan register yok → isolate'ler birbirinin snapshot'ını ezemez. Clear'lar snapshot içinde taşınır → karşı tarafa yayılır.

Dürüst garanti: yakınsama her iki tarafın bir sonraki load döngüsünde sağlanır; aynı milisaniyede yazılan iki slot yine de kaybolmaz çünkü ayrı anahtarlardır. Gerçek process-wide anlık koordinasyon yok — isolate'ler sıradan nesne paylaşamaz; bu model atomiklik iddiası olmadan lost-update'i ortadan kaldırır.

### Aynı-host istek koordinasyonu

- Ön planda tek `HostPacer` → `FeedRefresher` + `ArticlePreparationService` + `FullTextExtractionService` aynı instance'ı paylaşır.
- Arkaplan isolate'inde tek `pacer`: feed fetch döngüsü + iki `ArticlePreparationService` yapımı + `FullTextExtractionService.instance.pacer` hepsi aynı schedule'a bağlandı. Double-pacing yok — prep içindeki çağrı zaten paylaşılan instance farkındalığıyla tasarlanmış.
- **Recheck-after-pace**: `FeedRefresher` ve `runBgFetch` artık `pace()` beklemesinden hemen sonra `isBackedOff` kontrolünü tekrarlıyor — kuyrukta beklerken öğrenilen host cooldown'u gereksiz isteği engeller (sonuç `skipped/unproven` → cache + hata korunur).

## 3. Değişen Dosyalar

`lib/services/feed_backoff.dart` (v3 model), `lib/providers/feed_provider.dart` (iki-slot okuma), `lib/services/background_fetch_service.dart` (kendi slotu, paylaşılan pacer, post-pace recheck), `lib/services/feed_refresh.dart` (post-pace recheck), `test/feed_backoff_test.dart` (16 senaryo), `test/rss_lifecycle_regression_test.dart` (+2 senaryo).

## 4. Yeni Regresyon Testleri

- Kardeş başarı local host cooldown'unu siler; **server-mandated** cooldown'u silemez (deadline'a kadar blok, sonra açılır)
- Failure→success→stale snapshot: `since < clearedAt` → dirilme yok (local + mandated varyantları)
- Başka isolate'ten öğrenilen clear bellek kayıtlarını da düşürür; eşzamanlı yazarlar union'a yakınsar
- Restart: kayıtlar + clear marker'ları round-trip; mandated host cooldown başarı+restart'a rağmen kalır
- Legacy flat + v2 snapshot uyumluluğu; expired kayıtlar snapshot'tan düşer
- Refresh'te: A yavaş 429 → pacer kuyruğundaki B hiç ağa çıkmaz (`unprovenUrls`'te)
- `runBgFetch`: aynı senaryo bg'de; cooldown `feedBackoffUntil.bg`'ye yazılır, ikinci pass sıfır istek

## 5. Doğrulama

- `flutter test` → **413/413 geçti** (önceki 402 + 11 yeni)
- `flutter analyze` → temiz
- `dart format --set-exit-if-changed` → temiz
- `flutter build apk --debug` → **başarılı** (`app-debug.apk`)
- GitHub Actions → push sonrası PR sayfasında görülecek
- Gerçek cihaz/iOS → çalıştırılmadı, iddia edilmiyor

## 6. Kalan Sınırlar

- Isolate'ler arası anlık (in-memory) koordinasyon mümkün değil; converge latency = bir sonraki load anı. Crash anında yazılmamış clear kaybolabilir — en kötü durum muhafazakâr (cooldown doğal expiry'de biter).
- `cleared` marker'ları anahtar-başına saklanır; silinmiş aboneliklerin marker'ları kalır ama bounded (distinct key sayısı).
- Reddit IP limiti sunucu taraflı — davranış saygılı, garanti yok.

## 7. Review Bilgisi

```
Branch: fix/rss-engine-reliability
PR:     https://github.com/DevOpen-io/dondurma-rss-reader/pull/60 — AÇIK, MERGE EDİLMEDİ
Testler: 413/413 geçti
```
