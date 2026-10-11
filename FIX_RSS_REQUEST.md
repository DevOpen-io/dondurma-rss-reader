# RSS Motoru — Takip Denetimi Raporu

## 1. Doğrulanan Kusurlar ve Kök Nedenler

| # | Kusur | Kök neden |
|---|-------|-----------|
| 1 | `HostPacer` gerçekte paylaşılmıyordu | `FeedRefresher`, `ArticlePreparationService` ve `FullTextExtractionService` kendi instance'larını oluşturuyordu — "paylaşılan" yalnızca aynı sınıftı, aynı zamanlama değildi |
| 2 | `FeedBackoff` yarışı | İki isolate aynı snapshot'ı okuyup eski halini yazabiliyordu; başarı kaydı temizlenmiş bir cooldown persist'ten dirilebiliyordu; aynı host'taki kardeş feed'ler 429'dan etkilenmiyordu |
| 3 | Redirect hijyeni | Origin karşılaştırması yalnız `host`'a bakıyordu (scheme/port değişimi validator sızdırırdı); redirect gövdesi drain'siz/sınırsız bırakılabiliyordu |
| 4 | `extractFullText(forceRefresh: true)` | Server'ın `Retry-After`'ını da bypass ediyordu — yalnız yerel heuristic TTL'i atlamalıydı; `_parseRetryAfter` HTTP-date'i anlamıyordu |
| 5 | CodeRabbit bulguları | Tam-origin karşılaştırma eksikti; Windows-1252 `latin1.decode` ile okunuyordu (0x80–0x9F arası karakterler bozuluyordu); extraction'da HTTP-date `Retry-After` yoktu |
| 6 | Prefix'li Atom parse | Keyfi prefix regex'i namespace URI'sini doğrulamıyordu — Atom-olmayan `<x:feed>` da dönüştürülebilirdi |
| 7 | Gövde okuma kilidi | `sub.cancel()` sonrası `asFuture()` deterministik tamamlanmıyordu — cap testi 20 sn timeout'a düşüyordu |

## 2. Yapılan Değişiklikler

- **`lib/services/feed_service.dart`**
  - `sameOrigin(a, b)` (`@visibleForTesting`): redirect'te tam origin karşılaştırması (scheme + host + port); cross-origin'de `If-None-Match`/`If-Modified-Since` silinir
  - HTTP/HTTPS dışı redirect hedefi (`file:`, `javascript:`) reddedilir
  - `_readBoundedBody` → `Completer` tabanlı: boyut cap'i ve `bodyDeadline` (test-mutable, varsayılan 20 sn) stream'i deterministik `cancel` eder
  - `_discardBody` → aynı sınırlarla redirect-hop drain'i; takılan/şişkin hop gövdesi socket'i bağlayamaz
  - Windows-1252 decode: 0x80–0x9F `_cp1252` tablosuyla (kıvırcık tırnak, tire, €); tanımsız baytlar U+FFFD
- **`lib/utils/retry_after.dart`** *(yeni)* — `parseRetryAfter`: delta-saniye + HTTP-date (`HttpDate.parse`); tüm servisler tek util'i kullanır
- **`lib/services/full_text_extraction_service.dart`** — `_failedUntil` kaydı `serverMandated` bayrağı taşır; `forceRefresh` yalnız heuristic TTL'i atlar, server cooldown'u (`_inServerCooldown`) her zaman geçerlidir; enjekte edilebilir `pacer`
- **`lib/utils/host_pacer.dart`** — per-call `gap` parametresi, saat enjeksiyonu; "daha katı rezervasyon kısaltılamaz" semantiği
- **`lib/providers/feed_provider.dart`** — tek `_hostPacer` üç servise de enjekte edilir; refresh başı `_loadFeedBackoff()` reload; `_saveFeedBackoff` merge-on-save
- **`lib/services/feed_backoff.dart`** — host-seviye + feed-seviye cooldown, snapshot v2 (`feeds`/`hosts`/`cleared`), legacy flat-format load, merge-asla-kısaltmaz, `_cleared` dirilme koruması
- **`lib/services/background_fetch_service.dart`** — kendi `HostPacer`'ı (ayrı isolate) + persist cooldown merge-on-save
- **`lib/services/feed_refresh.dart`** + **`lib/services/article_preparation_service.dart`** — enjekte edilebilir pacer

## 3. Değişen Dosyalar

`lib/services/feed_service.dart`, `lib/services/feed_refresh.dart`, `lib/services/feed_backoff.dart`, `lib/services/full_text_extraction_service.dart`, `lib/services/article_preparation_service.dart`, `lib/services/background_fetch_service.dart`, `lib/providers/feed_provider.dart`, `lib/utils/host_pacer.dart`, `lib/utils/retry_after.dart` (yeni) + 4 test dosyası (2'si yeni: `feed_backoff_test.dart`, `host_pacer_test.dart`).

## 4. Yeni Regresyon Testleri

- Aynı host'ta iki feed: birinin 429'u kardeşi de soğutur; farklı host etkilenmez
- Persist edilmiş cooldown yeni refresher'da da geçerli (fg↔bg yönü)
- `load` merge: deadline'lar asla kısalmaz; cleared-sonrası dirilme yok
- Shared `HostPacer`: iki caller aynı host'ta serileşir, katı rezervasyon kısalmaz, farklı host bloklamaz
- `forceRefresh`: heuristic TTL'i atlar; delta-saniye ve HTTP-date `Retry-After`'a saygı gösterir
- Redirect: port-değişimi validator düşürür; şişkin gövde hop'u durdurmaz; takılan gövde deadline'la hop'a izin verir; `file:` hedefi reddedilir; origin matrisi (scheme/host/port)
- Windows-1252: 0x93/0x94/0x96 doğru karaktere, C1 kontrolleri U+FFFD'ye
- Feed 429 + HTTP-date `Retry-After` deadline'ı açığa çıkarır
- Atom-olmayan namespace'e bağlı `<prefix:feed>` parse hatası verir; geçerli keyfi-prefix Atom parse edilir

## 5. CI/Test Sonuçları

- `flutter test` → **402/402 geçti**
- `flutter analyze` → temiz
- `dart format` → temiz
- Android debug build → çalıştırılmadı (kalan risk)
- Gerçek cihaz/iOS → doğrulanmadı, iddia edilmiyor

## 6. Kalan Riskler

- Reddit'in IP-bazlı limiti sunucu taraflı — saygılı davranış garanti değil
- Isolate'ler arası anlık pacing mümkün değil (ayrı bellek); koordinasyon persist'li `FeedBackoff` üzerinden — iki isolate aynı saniye içinde okuyup yazarsa son yazanın merge'i kazanır, deadline kısalmaz
- `feedBackoffUntil` içinde silinmiş abonelik kalıntıları süresi dolunca etkisiz kalır
- Emülatör/cihaz smoke testi bu turda yapılmadı

## 7. Review Bilgisi

```
Branch:       fix/rss-engine-reliability
Uygulama:     de4f997 · Rapor: 068079d (HEAD)
PR:           https://github.com/DevOpen-io/dondurma-rss-reader/pull/60 — AÇIK, MERGE EDİLMEDİ
Testler:      402/402 geçti, 0 başarısız
```
