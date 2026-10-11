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

- **`recordSuccess`**: feed'in kendi kaydı her zaman silinir (kendi 200'ü kendi cooldown'unu çürütür). Host kaydına **hiç dokunulmaz** — kardeş 200, origin-çapı kısıtı (mandate olsun olmasın) çürütemez; host clear-marker **üretilmez** (marker sızıp diğer isolate'in mandate'ini bastırmasın diye).
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

`lib/services/feed_backoff.dart` (v3 model, `isMandatedBackedOff`), `lib/providers/feed_provider.dart` (iki-slot okuma + backoff enjeksiyonu), `lib/services/background_fetch_service.dart` (kendi slotu, paylaşılan pacer+backoff, post-pace recheck), `lib/services/feed_refresh.dart` (post-pace recheck), `lib/services/full_text_extraction_service.dart` (paylaşılan backoff sorgusu), `lib/services/article_preparation_service.dart` (`backoff` ctor parametresi + `_hostCooled` kapıları), `lib/utils/host_key.dart` (yeni — kanonik host anahtarı), `lib/utils/host_pacer.dart` (`hostKey` kullanımı), `test/feed_backoff_test.dart` (20 senaryo), `test/full_text_extraction_test.dart` (+2), `test/s3_preparation_engine_test.dart` (+3), `test/host_pacer_test.dart` (+1), `test/rss_lifecycle_regression_test.dart` (+2 senaryo).

## 3a. Son Tur — Üç Davranışın Kapanışı

Bu turda önceki mimari korunarak üç davranış kapatıldı:

1. **`recordSuccess` artık host kaydına hiç dokunmuyor.** Local-estimate host cooldown'ları da kardeş 200 ile silinemez — 429 `Retry-After` taşısın taşımasın, origin-çapı sinyal sona erme anına kadar yürürlükte. Başarı yalnız feed'in kendi kaydını siler ve feed-anahtarlı clear marker üretir (host marker üretilmez → snapshot'a sızıp karşı isolate'in mandated kaydını bastıramaz).
2. **Extraction ve medya hazırlığı aynı `FeedBackoff`'a bağlandı.** `FullTextExtractionService.backoff` ve `ArticlePreparationService(backoff:)` — feed 429'undan öğrenilen host cooldown iki serviste de ağa çıkmadan önce denetlenir. Atlanan parçalar `pending` kalır, failure sayılmaz; **RSS body'si korunur** (extraction yalnız upgrade). Manuel retry: local tahmini atlayabilir (`isMandatedBackedOff`), server mandate'ini asla.
3. **`hostKey` kanonikleştirmesi** — lowercase + `www.` strip + etkin port: `reddit.com` ↔ `www.reddit.com` ↔ `:443` aynı kova (`reddit.com:443`), `old.reddit.com` gibi gerçekten farklı host'lar etkilenmez. `FeedBackoff._authority` ve `HostPacer` aynı anahtarı kullanır → cooldown ve pacing tek politikada birleşir, persist slot'ları da aynı anahtarla yazılır.

## 3b. Final Review Turu — CodeRabbit A–F + Medya Recheck

Bağımsız incelemede 6 CodeRabbit thread'i + 1 ek senaryo doğrulandı; tümü kapatıldı:

- **A — Extraction post-pace recheck**: `extractFullText` uygunluk kontrolünü `pace()` **öncesi** yapıyordu; kuyrukta beklerken öğrenilen 429'a kayıtsız kalıyordu. `pace()` dönüşünde `_blocked(url, forceRefresh)` tekrarlanıyor — ağa çıkmadan önce son kontrol. Manuel retry semantiği korunur: local tahmin atlanır, server mandate'i asla.
- **B — Mandate penceresi ayrıldı**: `_recordFailure`, var olan `Retry-After` deadline'ını daha kısa local failure cooldown'uyla ezebiliyordu (429 sonrası geç dönen 500/timeout senaryosu). `_failedUntil` kayıtları artık `{until, mandatedUntil}` çift pencere taşıyor: `until` her zaman max ile birleşir, `mandatedUntil` bağımsız birleşir — kısa local tahmin mandate'i kesemez, uzun olan mandate'i silemez, yeni geçerli mandate yine uzatabilir. Mandate aktifken `until`'i de aşar.
- **C — Medya `Retry-After` taze saat**: `_fetchAndStore` ve `_preparePiece`, sweep başında yakalanan `now` ile `Retry-After`/local-backoff hesaplıyordu; semaphore+pacer kuyruğunda geçen süre deadline'ı geçmişe kaydırıyordu. Tüm retry matematiği artık response anındaki `_now()`'dan hesaplanıyor.
- **D — Completer çift-tamamlama**: `_readBoundedBody`/`_discardBody` dinleyicilerinde error+done veya çoklu error dizisi ikinci `complete*` çağrısı üretiyordu (`Bad state: Future already completed` unhandled async hatası). Tüm tamamlama yolları `isCompleted` korumalı; `_discardBody` timeout'unda `sub.cancel` sonucu artık `unawaited` ile tüketiliyor. `debugReadBoundedBody`/`debugDiscardBody` test seam'leri eklendi.
- **E — Yanlış deklare charset**: `ISO-8859-1`/`Windows-1252` deklare edip UTF-8 gönderen sunucular mojibake üretiyordu. Bu legacy deklarasyonlarda önce strict UTF-8 deneniyor, başarısızsa deklare edilen kodlamaya düşülüyor. Windows-1252'nin 0x80–0x9F smart-punctuation eşlemesi korunuyor (gerçek CP1252 gövdelerde UTF-8 strict zaten fail eder).
- **F — `Retry-After` üst sınırı**: `maxRetryAfter = 24h` — devasa saniye değerleri veya uzak HTTP-date'ler artık aylara uzanan kilitlenme üretemez. Negatif değerler null; Duration mikrosaniye overflow'u clamp-öncesi karşılaştırmayla engellendi. Trade-off: >24h'lik gerçek mandate 1 güne kısaltılır — bu sürenin üstü broken-server ile ayırt edilemez.
- **Ek — Medya post-pace recheck + `deferred` outcome**: `_fetchAndStore` pacing sonrası `_hostCooled(url, _now(), manual:)` kontrolü yapıyor; cooldown'da `deferred` döner → parça `pending` kalır, failure sayılmaz, retry planlanmaz, RSS body'si korunur, expiry sonrası tekrar uygun. Manuel bayrağı `_prepareRecord→_preparePiece→_fetchAndStore` zincirine taşındı — manuel retry local tahmini atlar, mandate'i atlamaz.

## 3c. Merge Öncesi Son İki Bulgu

- **Ertelenen extraction isteği hata sayılıyordu**: prep, extraction'ın `null` dönüşünü hep failure sayıyordu; cooldown yüzünden hiç ağa çıkmayan istek `attempts++` + `bodyState=failed` üretiyordu. Artık `null` sonrası `_hostCooled(link, _now(), manual:)` kontrolü yapılıyor — cooldown aktifse kayıt `pending` kalır, attempts/nextRetryAt dokunulmaz (medyadaki `deferred` ile aynı semantik). RSS body'si korunur; gerçek çıkarım hataları (404, boş içerik, 500) yine failure sayılır.
- **Extraction/medya 429'u ortak backoff'a bildirilmiyordu**: 429/503/`Retry-After` taşıyan article-page ve media yanıtları artık `FeedBackoff.recordFailure`'a `FeedFetchException` olarak aktarılıyor → host-seviye (mandate'li) cooldown tüm origin'i korur; kardeş feed fetch, extraction ve medya istekleri aynı sinyali görür.
- **Doc düzeltmesi**: `recordSuccess` açıklaması eski "local-estimate silinir" semantiğini anlatıyordu — güncel "host kaydına hiç dokunulmaz" davranışıyla hizalandı.

## 3d. Preparation-Sonrası Cooldown Persist'i

Önceki turda öğrenilen 429'ların persist edilmesi eksikti:

- **`runBgFetch`**: `feedBackoffUntil.bg` snapshot'ı feed-fazının hemen ardından yazılıyordu; preparation sweep'i (extraction + medya) bu yazımdan **sonra** koşuyor → sweep sırasında öğrenilen host cooldown yalnız bellekte kalıyor, görev bittiğinde kayboluyordu. `preparePending`'in `finally`'sinde slot tekrar merge + yazılıyor.
- **`FeedProvider`**: `_preparation.preparePending` sonrası `_saveFeedBackoff()` eklendi; `_prefetchFullText`'in `finally`'sinde de aynı persist — sayfa 429'ları artık fg slotuna düşer. İki slot (fg `feedBackoffUntil`, bg `feedBackoffUntil.bg`) ve merge-then-write davranışı korunuyor.

Regresyon testi: wifi mock'u ile bg preparation'ı çalıştır, medya URL'si 429+`Retry-After` döndür → `.bg` slotunda `hosts` kaydı oluştuğunu doğrula → **ikinci `runBgFetch`** (Hive'dan hidrate olan yeni `FeedBackoff`, yeni-isolate simülasyonu) aynı host'a feed ve medya isteği **sıfır** gönderiyor.

## 4. Yeni Regresyon Testleri

- Kardeş başarı **hiçbir** aktif host cooldown'unu silemez — Retry-After'lı da olmasa da (deadline'a kadar blok, sonra açılır)
- Failure→success→stale snapshot: `since < clearedAt` → feed kaydı dirilmez; host kaydı politika gereği ayakta (local + mandated varyantları)
- Başka isolate'ten öğrenilen clear feed kaydını bellekten de düşürür; host cooldown durur
- Eşzamanlı yazarlar union'a yakınsar; restart'ta kayıtlar + clear marker'ları round-trip
- Legacy flat + v2 snapshot uyumluluğu; expired kayıtlar snapshot'tan düşer
- Refresh'te: A yavaş 429 → pacer kuyruğundaki B hiç ağa çıkmaz (`unprovenUrls`'te)
- `runBgFetch`: aynı senaryo bg'de; cooldown `feedBackoffUntil.bg`'ye yazılır, ikinci pass sıfır istek
- `www.reddit.com`↔`reddit.com`↔`:443` tek cooldown kovası + tek pacing kovası; `old.reddit.com` bağımsız
- Extraction: feed-kaynaklı host cooldown'da **sıfır HTTP isteği**; forceRefresh local tahmini atlar, server mandate'ine uyar
- Prep: cooldown'da extraction+medya atlanır, failure sayılmaz, RSS body'si korunur; manuel retry mandated'da 0 istek, local'de çalışır
- Extraction post-pace: pace kuyruğunda bekleyen istek, beklerken öğrenilen 429 sonrası **sıfır HTTP** ile döner (deterministik kuyruk senaryosu)
- `_recordFailure` sırasız-yanıt: 429+`Retry-After` sonrası dönen 500 mandate'i kısaltamaz; yeni daha uzun mandate uzatır; local 500 cooldown expiry'de retry serbest
- Medya: gecikmeli istekte `Retry-After` deadline'ı response saatinden hesaplanır; pace kuyruğundaki parça cooldown'da `deferred` → pending + sıfır istek; expiry sonrası tekrar denenir
- Bounded body: error→done ve error×2 tek tamamlama, timeout, oversize, normal body, drain toleransı — asılı future/subscription yok
- Charset: UTF-8'in ISO-8859-1/Windows-1252 diye etiketlendiği gövdeler düzgün decode; gerçek Latin-1 ve gerçek CP1252 smart punctuation korunur
- `parseRetryAfter`: 24h clamp (saniye + HTTP-date), negatif→null, sıradan değerler birebir
- Extraction'da cooldown'a takılan `null` → `pending` + sıfır attempts + retry planlanmaz + RSS body korunur
- Sayfa 429'u (`Retry-After` ile) shared backoff'a yazılır → `isMandatedBackedOff` tüm origin'i kapsar
- Medya 429'u shared backoff'a yazılır → hiç istek yememiş komşu URL bile cooled
- Bg preparation'da öğrenilen cooldown `.bg` slotuna düşer → yeni pass/isolate Hive'dan yükler, aynı host'a sıfır istek

## 5. Doğrulama

- `flutter test` → **446/446 geçti** (445 + 1 yeni)
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
Commit: 2c6aef0
PR:     https://github.com/DevOpen-io/dondurma-rss-reader/pull/60 — AÇIK, MERGE EDİLMEDİ
Testler: 446/446 geçti
```
