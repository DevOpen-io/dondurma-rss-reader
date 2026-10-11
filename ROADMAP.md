# Yol Haritası

PR #60 sonrası ertelenen iyileştirmeler. Her madde ayrı PR adayıdır.

## 1. `www.` normalizasyonunu doğrulanmış eşdeğer host'larla sınırlama

**Durum:** `lib/utils/host_key.dart` `www.` ön ekini tüm domain'lerden kaldırıyor.

Reddit için doğru — `reddit.com` ↔ `www.reddit.com` aynı servis. Ancak `www.example.com` ile `example.com` teknik olarak farklı servisler olabilir; aynı cooldown/pacing kovasına düşmeleri gereksiz kısıtlama üretebilir.

**Yön:** Açık bir eşdeğer-host listesi tanımla (başlangıç: `reddit.com`). `www.` strip yalnız listedeki origin'lerde uygulanır; diğer host'larda `www.example.com` ve `example.com` ayrı kova kalır. `FeedBackoff` ve `HostPacer` aynı `hostKey`'i kullanmaya devam etsin.

## 2. Eşzamanlı extraction çağrılarında deferred marker'ı sonuç bazında tutma

**Durum:** `FullTextExtractionService._deferredUrls` session-scoped bir `Set` — aynı URL'ye yarışan iki çağrı marker'ı paylaşır.

Senaryo: A çağrısı ağa çıkıp sayfanın kendi 429'unu yer (marker temizlenir), B çağrısı cooldown'a takılıp marker'ı işaretler → iki çağrının da sonucu "deferred" gibi görünür (ya da tam tersi sıralamada A yanlışlıkla marker'ı siler). Prep tarafında sınıflama yarışa duyarlı.

**Yön:** Deferred bilgisini çağrı sonucuna taşı — örn. `extractFullText`'ten dönen bir sonuç tipi (`{html, deferred}`) ya da çağrı-başına token. Public `String?` API'sini koruyup hazırlık hattına detaylı bir varyant açmak en düşük-ripple çözüm.
