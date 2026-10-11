# RSS Motoru Güvenilirlik Raporu

## A. Kök Neden Analizi

**Kanıtlanmış kusurlar:**

1. **HBR `feed not found`** — Sunucu geçerli Atom dönüyor ama tüm elementler `ns6:` prefix'li (`<ns6:feed xmlns:ns6=".../Atom">`). `dart_rss` kökte literal `<feed>` arıyor; mevcut fallback yalnız `atom:` prefix'ini tanıyordu.
2. **Reddit 429** — IP-bazlı rate limit. Asıl çekiçleme kaynağı: arka plan sync'in kendi `FeedService`'i vardı — backoff yok, concurrency cap yok, **validator (etag) bile göndermiyordu**; her 15dk'da tüm feed'ler tam çekiliyordu. Üstüne prep motoru makale/medya indirmelerini aynı host'a burst yapıyordu.
3. **`_failedUrls` zehirlenmesi** — Tek bir timeout/503, URL'yi tüm oturum boyunca kalıcı başarısız işaretliyordu.
4. **`send()` timeout'u yalnız header'ları kapsıyordu** — damla-besleme sunucu gövdede takılırsa sonsuz bekleyebilirdi; response boyutu sınırsız buffer'lanıyordu.
5. **Cross-origin redirect hijyeni** — koşullu header'lar (If-None-Match vb.) başka origine sızabiliyordu.

**Şüpheli riskler (düzeltildi ama kusur olarak kanıtlanmadı):** aynı host'taki birden fazla subreddit'in 5-geniş semafor altında fan-out yapması; eşzamanlı retry'ların senkronize dönmesi (jitter eksikliği).

## B. Yapılan Değişiklikler

| Dosya | Değişiklik |
|---|---|
| `feed_service.dart` | Keyfi Atom prefix'i regex fallback; `accessRestricted`/`gone` kind'ları; `Retry-After` parse+propagasyon; 8MiB gövde cap'i (`_readBoundedBody`); gövde deadline'ı; BOM→charset decode sırası |
| `feed_refresh.dart` | `FeedBackoff` entegrasyonu (skip sonucu `unprovenUrls`'e); same-host `HostPacer` (500ms); skip'te cached items + error korunur |
| `feed_backoff.dart` *(yeni)* | Paylaşılan cooldown politikası: server `Retry-After` otoriter, yoksa doubling+jitter; `snapshot()`/`load()` Hive persist |
| `utils/host_pacer.dart` *(yeni)* | Host başına serialize + min-gap; prep ve refresh ortak kullanır |
| `article_preparation_service.dart` | Kendi pacing kodu → `HostPacer`; body+medya indirmeleri pace'li |
| `full_text_extraction_service.dart` | `_failedUrls` set → deadline map; transient (5dk veya Retry-After) vs kalıcı ayrımı |
| `background_fetch_service.dart` | Persist cooldown'ları yükle/kaydet; skip'lenen feed'in cache'i korunur |
| `feed_provider.dart` | `feedBackoffUntil` Hive persist |

## C. Reddit Uyumluluğu

**Düzelen:** tekrarlı 429 döngüsü (feed backoff + persist), aynı-host burst (pacing), arka plan bypass'ı (cooldown paylaşımı), Reddit-şekilli Atom parse (fixture testli).
**İyileşen:** extraction retry'ları artık transient hatalarda ölmüyor.
**Kalan sınır:** Reddit'in IP rate-limit'i sunucu taraflı — uygulama ancak saygılı davranabilir; ağır kullanımda 429 yine döner ama artık zarif beklenir, cached içerik korunur.

## D. Mimari Akış

`FeedRefresher` → önce `FeedBackoff.isBackedOff` (persist'li) → `HostPacer.pace` → `FeedService.fetchFeed` (validator'lı, bounded body, deadline, redirect hijyeni) → 200/304/parse → `FeedBackoff.recordSuccess/recordFailure` → sonuç: skip→unproven (cache+error korunur), fail→cached items korunur. Prep motoru aynı `HostPacer`'ı extraction+medya indirmede kullanır; extraction failure'ları TTL'li transient set ile yönetilir.

## E. Test Kanıtı

`flutter test` → **380/380 geçti**. `flutter analyze` temiz, `dart format --set-exit-if-changed` temiz. Yeni testler: ns6/arbitrary prefix parse, non-feed namespace korunumu, Reddit Atom fixture, 429 backoff+error korunumu+Retry-After sonrası refetch, persisted cooldown'un yeni refresher'da skip'i, same-host pacing, 403→accessRestricted/410→gone, geçerli boş feed, boyut cap'i, transient-vs-permanent extraction (5 test).

## F. Performans

Ölçülen kazanımlar: rate-limit'li feed cooldown'dayken **sıfır ağ isteği** (önceden her sync'te istek); aynı-host fetch'ler burst yerine 500ms aralıklı; medya indirmeleri 1.5s aralıklı; >8MiB gövdeler parse öncesi kesilir. Benchmark çalıştırılmadı — sayılar tasarım davranışından.

## G. Uyumluluk

Mevcut veri dokunulmadı: `feedBackoffUntil` yeni Hive anahtarı, yoksa boş davranır. Abonelik/bookmark/read-state/validator/redirect şemaları aynı. Skip/fail'de cached items hiçbir yolda silinmiyor (regresyon testli).

## H. Kalan Riskler

- Reddit sunucu tarafı limiti uygulama kontrolü dışında — resmi API entegrasyonu gerekmedikçe tam garanti yok.
- Emülatör cihaz testi bu batch'te çalıştırılmadı.
- `feedBackoffUntil` silinen aboneliklerin entry'lerini temizlemez (küçük kalıntı, süresi dolunca etkisiz).
- Adaptive refresh (seyrek değişen feed'leri daha az çekme) bilinçli olarak kapsam dışı bırakıldı.

## I. Review Bilgisi

```
Branch:            fix/rss-engine-reliability
Commits:           ba051ba → HEAD (8 commit)
Pull Request:      https://github.com/DevOpen-io/dondurma-rss-reader/pull/60
Changed Files:     ~10 lib + 4 test dosyası
Tests Passed:      380/380
Tests Failed:      0
Unverified Cases:  gerçek cihaz smoke testi, iOS
Known Limitations: yukarıdaki H bölümü
```
