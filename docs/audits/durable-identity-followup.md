# Dondurma RSS Reader — Durable Identity Follow-up

> **Güncel durum (2026-10-26):** Kaynak bazlı kimlik uygulandı: okundu durumu (`readItemRefs`, legacy ID tek seferlik bağlama), archive schema 2 (`ArticleRef` anahtarlı, ayrı dosya, kilit altında lazy migration, belirsiz kayıtlar karantinada), status/membership/bookmark claim/saved-copy okuması instance bazlı. Eski KNOWN kimlik testleri bağımsız kimliği doğrulayacak şekilde çevrildi. Ertelenen: DocumentRef ile içerik paylaşımı (dedup) ve karantina için ayrı UI. Aşağıdaki metin tarihsel kayıttır.

> **Yeni takip:** [Reset publication protocol audit](reset-publication-protocol-audit.md).
> Ortak reset protokolü tamamlanmadı. Olumlu A/B/C/J/E2 güvenlik acceptance'ları hâlâ kırmızı; önceki 573 başarılı test aşağıda tarihsel baseline olarak korunuyor.
> Güncel genel sonuç: 576 başarılı / 5 başarısız. Yeni-generation medya overwrite, geç background Hive/cache publication ve orphan-scan sonrası yeni referansın silinmesi de kanıtlandı.
> **NOT READY FOR RELEASE** kararı değişmedi; üretime kısmen güvenli epoch/rename yaması eklenmedi. Eksik protokol ve recovery planı yeni raporda.

## 1. Başlangıç ve mevcut sözleşmeler

Dal `main`; başlangıç HEAD `409774ee3d1a05f5a713438a16047d3a69a0cf51`. Önceki audit ve commit edilmemiş bütün değişiklikler başlangıçta mevcuttu. Bunlar geri alınmayacak; bu takip çalışmasının farkları ayrıca listelenecek.

### Mevcut kimlik ve kalıcılık sözleşmesi (değişiklik öncesi)

- `FeedItem.id`: parser'ın GUID/link/fallback seçimi; `FeedItem.operator ==` ve hash yalnız bu ID'yi kullanır. Feed-yerel instance kimliği UI ve tam bookmark JSON'unda `(feedUrl,id)` olarak uygulanmıştır; model eşitliği değişmemiştir.
- `ArticleIdentity.normalizeItemId`: ID'yi trim/URL-normalize eder; feed namespace'i içermez. URL normalizasyonu fragment'i kaldırır, query'yi korur; rastgele GUID'nin URL olduğu varsayılmamalıdır.
- `ArticleRecordStore`: `feeds` Hive dosyasının yanındaki `.article-archive.json`, schema 1. `records` ve `seen` map'lerinin anahtarı global normalize ID'dir. Payload `feedUrl`, `link`, `body`, media manifest ve yalnız tür belirten `owners` (`bookmark`, `tempCache`) taşır; her sahibin hangi feed instance'ından geldiği kaydedilmez.
- `ArticlePreparationService.registerArticle`: aynı global ID'de sahibin birleşimini, eski hazır gövde/link/medya korunmasını ve yeni metadata eklenmesini yapar. Bu davranış aynı makale için idempotenttir; ortak GUID'li farklı makalelerde içerik/provenance karışabilir. `prepareArticle(String id)` feed bilgisi almaz.
- `ArticleMediaStore`: URL'den FNV-1a dosya adı; ortak URL ortak dosya. Dosya temp+rename ile yayınlanır. Sahiplik medya dosyasında değil record manifest'inde tutulur. GC bütün record manifest'lerini referans kabul eder.
- `TempCacheMembership`: global canonical ID'li candidate map ve global en yeni N üyelik. `bookmarkedIds` de globaldir. Bir kaynağın silinmesi aynı ID'li başka kaynağın kayıt/provenance sorununu çözmez.
- `BookmarkProvider`: iki feed'in tam snapshot'ını korur; `bookmarkedItemIds` legacy global üyelik kümesidir. Startup restoration tam snapshot'ları aynı global arşive register eder. Yalnız-ID legacy bookmark kaynak bilgisi içermez.
- `FeedProvider`: Hive `readItemIds` global raw ID kümesi. `markAsRead`, toggle, unread badge, filter ve UI çağrıları String ID ile çalışır. İlk gözlem tarihi archive `seen` map'inde ayrıca normalize ID ile tutulur. Cache JSON'da feed bilgisi mevcut olsa da archive key'si değildir.
- `ArticlePageProvider.loadSavedCopy`: yalnız normalize ID üzerinden arşiv gövdesini okur; kaynak eşleşmesiyle ayırmaz.
- `ObservedArticleStore`: ayrı `.observed-articles.json`, schema 1; feed URL + subscription notification epoch içinde normalize article ID. Bu geçmiş temp cache/read/ownership değildir. Reset wipe'ı ve foreground canlı `claimCheck` vardır; kalıcı reset epoch'u bulunmaz.
- `BackgroundFetchService`: Hive isolate-local snapshot'ları, ortak archive ve observation dosyaları. İki sidecar kendi dosya kilidini kullanır; Hive + archive + observation + medya için tek transaction yoktur. Archive epoch'u `_persistBgCache` içinde HTTP'den sonra örneklenir.
- Archive mutasyonları file lock içinde yapılır. `expectedEpoch` opsiyoneldir; tombstone generation ve persisted lifecycle epoch farklı amaçlara hizmet eder. `resetFence` yalnız aynı preparation instance'ının register kuyruğuna aittir. Medya rename'i ve Hive yazısı bu kilit altında değildir.

Bu sözleşmeler nedeniyle yalnız persisted ID'ye feedUrl eklemek geriye uyumlu bir çözüm değildir: okuyucu, sahiplik, retry, cleanup, read state, eski background writer ve URL paylaşımı birlikte ele alınmalıdır.

## 2. Karar ve kök neden analizi

**Kimlik migration'ı uygulanmadı.** Kullanıcının izin verdiği güvenli fallback seçildi: mevcut bozuk davranış deterministik testlerle kanıtlandı, somut migration/protokol planı aşağıya kaydedildi. Yapılan üretim değişikliği yalnız kanıtlanmış preparation lifecycle hatalarını düzeltir; kısmi kimlik migration'ı değildir.

Gerekçe: bir legacy record'un `feedUrl` alanı A'yı gösterirken `body/link` A'dan, `title` B'den, media manifest'i her ikisinden gelebiliyor. İkinci source'un hiç saklanmamış bağımsız extracted body'sini eldeki tek record'dan geri çıkarmak mümkün değil. `owners: {bookmark,tempCache}` hangi instance'ın ne talep ettiğini söylemiyor. Aynı raw GUID ile iki snapshot bulunması da bütün eski body/media alanlarının provenance'ını kanıtlamıyor. `feedUrl`'yi record ID'sinin başına eklemek, karışmış bütün alanları tek source'a yanlış atar; her iki source'a kopyalamak da yanlış içeriği çoğaltır.

Read API'sinin imzası zaten `markAsRead(String id)`; çağrı A için mi B için mi yapıldı bilgisi store'a ulaşmıyor. Bu nedenle yalnız ArticleRecordStore'a yeni anahtar eklemek, yeni read kayıtlarını dahi bağımsız yapamaz. UI, badges, runtime filter, article reader, retry ve background caller'ları birlikte değişmelidir.

### Kanıtlanan, henüz çözülmeyen kimlik sorunları

`test/durable_identity_followup_test.dart:186-396` içindeki karakterizasyonlar gerçek dosya persistence'ı kullanır:

1. İki ayrı feed, aynı GUID, farklı URL ve body: `BookmarkProvider.restoration` iki snapshot'ı korur; archive **tek** record olur. Record'da A body/link, B title görülür. B bookmark'ını `ArticlePageProvider.loadSavedCopy` ile açınca A body'si gösterilir (`187-226`).
2. A restore edilmiş, B kilit öncesinde beklerken restore durdurulur. Hive snapshot'ları aynen kalır; restart restoration iki öğeyi yine tek karışık record'a yakınsar (`228-270`). Bu **migration interruption testi değildir**, mevcut restore sürecinin sınırını gösterir.
3. Yeni iki instance için bir ID'nin okunması ikisini de okundu yapar; legacy Hive restart aynı durumu geri getirir (`272-296`).
4. Temp-cache aday map'i ortak GUID'de B'yi tutar. B aboneliği kalkıp yalnız A kalınca record B feed/body'sini korur (`298-332`). A'nın doğru bağımsız offline kaydına dönüştüğü iddia edilemez.
5. Foreground A'yı bookmark, gerçek başka Dart isolate B'yi tempCache olarak register eder: owner türleri birleşir, iki farklı makale tek record olur (`334-352`). Native Workmanager plugin'i çalıştırılmaz; aynı dosya/lock kullanan gerçek isolate store yolu çalışır.

Bu testlerin başlığındaki **KNOWN**, testin güvenli davranışı değil, mevcut kusuru doğruladığını belirtir. Geçmeleri release acceptance değildir.

## 3. Uygulanan güvenli lifecycle düzeltmeleri

### R1 — Kuyruktan çıkmış, dosya kilidini bekleyen mutasyon reseti aşıyor

- Önce `_enqueueGuarded`, `_queueEpoch`'u yalnız iş başlarken kontrol ediyordu. Store lock'u beklemeye başlamış register/owner update, `resetFence()` ve `wipeAll()` bittikten sonra yeni record yazabiliyordu.
- Artık güncellik closure'ı işin içine taşınıyor; `mutateRecord` ve register'ın `claimCheck` kontrolü, store kilidinde state okunduktan sonra yeniden değerlendiriliyor.
- Kaynak: `lib/services/article_preparation_service.dart:142-168,271-290`; store'un kilitli callback çağrısı `lib/services/article_record_store.dart:437-464`.
- Testler: `test/durable_identity_followup_test.dart:501-540`. `_BeforeLock` yazarı lock edinmeden durdurur; diğer store reseti tamamlar; eski yazar serbest bırakılır; archive boş kalır. Düzeltme öncesinde iki varyant da `Expected: empty / Actual: [Instance of 'ArticleRecord']` verdi.
- Kapsam: aynı preparation instance'ındaki reset fence. Cross-isolate register için eski çağrı başlangıcında yakalanmış persisted `expectedEpoch` hâlâ gereklidir. Kilit içinde no-op, mevcut store sözleşmesine göre `applied` dönebilir; test güvenlik sonucunu, yani yazı olmamasını doğrular.

### R2 — Eski snapshot yeni epoch ile yetkilendiriliyor

- Önce `prepareArticle` record'u, `preparePending` bütün record listesini okuyor; epoch **sonra** alınıyordu. Bu arada reset + aynı ID'nin yeni generation 1 kaydı oluşturulunca eski snapshot yeni epoch ile commit edilebiliyordu.
- Epoch artık her iki snapshot'tan **önce** yakalanıyor. Sonraki locked mutasyon resetin eski epoch'unu reddeder.
- Kaynak: `lib/services/article_preparation_service.dart:398-444`.
- Testler: `test/durable_identity_followup_test.dart:611-646`. Store hook eski snapshot'ı okur; reset + B kaydını araya sokar; eski A snapshot'ını döndürür. Önce yeni B gövdesi yerine `STALE https://a.test/article` yazılıyordu; şimdi B body'si kalır.
- Aynı epoch altında tombstone/revive, yalnız epoch kontrolüyle çözülemez; R3 ayrı gereklidir.

### R3 — Eski preparation sonucu yeniden canlandırılan record'u değiştiriyor

- Önce body/media commit yalnız tombstone ve owners kontrol ediyordu. İndirme sırasında tombstone + yeni register olursa yeni generation canlı olduğundan eski yanıt yeni gövdeyi veya manifest'i değiştirebiliyordu.
- Body commit, yeni media snapshot'ı ve piece commit artık beklenen record generation'ını da kontrol ediyor. Media piece'e generation açıkça taşınıyor.
- Kaynak: `lib/services/article_preparation_service.dart:488-493,533-540,554-578`.
- Testler: `test/durable_identity_followup_test.dart:542-609`. Completer ile extraction/media cevabı tutulur; tombstone ve yeniden register tamamlandıktan sonra eski cevap bırakılır. Önce yeni gövde `STALE BODY`, yeni manifest yanlışlıkla `ready` oluyordu; şimdi B body'si ve `pending` manifest korunur.
- Reset sırasında devam eden body extraction için ayrı varyant da mevcut; persisted epoch'un korumasını doğrular.

### Mevcut doğru kilit davranışının adversarial kontrolü

`test/durable_identity_followup_test.dart:477-499`: `.write()` fiziksel commit'inden hemen önce, **kritik bölüm içindeyken** durdurulur. Reset başka store üzerinden başlatılır; eski write bırakılır. Eski commit başarıyla tamamlanabilir, fakat reset aynı lock'u aldıktan sonra onu siler; sonuç boş archive. Her “write resetten sonra bitti” durumu resurrection değildir: lock/reset **tamamlanma** sırası önemlidir.

## 4. Reset protokolünde doğrulanan açıklar

### P0 — Reset sonrası fiziksel medya geri geliyor (düzeltilmedi)

Test `test/durable_identity_followup_test.dart:429-475`:

1. Image HTTP cevabını Completer ile tut.
2. `resetFence`, archive `wipeAll`, medya `deleteAllManaged` işlemlerini tamamla.
3. Eski HTTP 200 cevabını serbest bırak.
4. Manifest commit epoch ile reddedilir, archive boş kalır; fakat eski özel resmin `m_*` dosyası yeniden vardır.

Kök neden: `ArticleMediaStore.put` (`108-135`) temp+rename'i lifecycle/record kilidi dışında yapar. `_fetchAndStore` önce bu dosyayı yayınlar (`lib/services/article_preparation_service.dart:640-671`), sonra manifest commit dener. Manifest'in reddi dosyayı geri almaz. Reset `deleteAllManaged` (`article_media_store.dart:204-220`) bu rename ile ortak protokolde değildir. Test factoryReset'in ilgili store/media sırasını sürer; native ayarlar ekranını çalıştırmaz.

Sadece `put()` öncesi epoch okumak güvenli çözüm değildir: check ile rename arasına reset girebilir. Sadece manifest reddinde dosyayı silmek de başka canlı record'un aynı URL'deki ortak dosyasını silebilir. Bu nedenle testle kanıtlanamayan böyle bir kısmi yama eklenmedi.

### P0 — Geç background claim, silinmiş observation history'yi yeniden initialize ediyor (düzeltilmedi)

Test `test/durable_identity_followup_test.dart:354-396`: gerçek child isolate iş başında archive epoch'unu yakalar ve bekler. Parent archive/history wipe'ını tamamlar, yeni B kaydı oluşturur. Eski child işi devam eder:

- Archive register eski `expectedEpoch` ile **rejected** olur; B korunur.
- Observation claim, native background caller gibi canlı foreground closure'ı olmadan çağrılınca eski namespace'i **yeniden initialize eder**; history dosyasında tekrar bir feed bulunur.

`ObservedArticleStore.wipeAll` (`148-163`) yalnız feeds'i boşaltır; persisted reset epoch'u yok. Foreground `claimCheck` düzeltmesi faydalıdır ama process/isolate ortak reset protokolü değildir. Background `claimFeedBatch` çağrısında bu closure zaten yok (`lib/services/background_fetch_service.dart:274-285`). Lock iki yazıyı sıralar; eski işin yeni reset döneminde yetkisiz olduğunu tek başına söylemez.

### Diğer kapsam sınırları

- Background archive epoch'u hâlâ fetch'ten sonra `_persistBgCache` içinde örnekleniyor (`background_fetch_service.dart:428-432`); geç yakalanmış yeni epoch eski HTTP sonucunu ayırt edemez. Yeni child-isolate testi yalnız **erken yakalanmış** epoch'un işe yaradığını kanıtlar; bütün `runBgFetch` reset yarışlarının çözüldüğünü değil.
- Background validator/cooldown Hive yazıları (`background_fetch_service.dart:253-268`) ve final Hive cache put'u tek sidecar transaction'ının parçası değildir. Hive'ın isolate-local görünümü durable fencing otoritesi sayılmamalıdır.
- Store `writeIfGeneration` API'si epoch almıyor (`article_record_store.dart:496-523`); reset sonrası generation 1 tekrar kullanılabilir. Şu anda production çağrısı bulunmadı; ileride yalnız generation'a dayanarak yeni lifecycle protokolü kurulamaz.

## 5. Önerilen collision-safe tasarım — UYGULANMADI

Bu bölüm sonraki uygulama için somut tasarım/acceptance planıdır; otomatik upgrade mekanizmasının bu patch'te bulunduğu anlamına gelmez.

### 5.1 Üç farklı kimliği ayırın

1. **InstanceRef:** versioned, lossless tuple `(canonicalSubscriptionUrl, rawItemId)`. Canonical URL aboneliğin kimliğidir; öğrenilen redirect target değildir. Subscription notification epoch'u kalıcı bookmark instance anahtarına katılmaz; unsubscribe/resubscribe eski yer imini kaybetmemelidir. Tuple encoding String delimiter birleştirmesi değil, typed encoding olmalı; eski raw ID yeni namespace gibi görünse de çakışmamalıdır.
2. **DocumentRef:** store'un atadığı opaque, kararlı reference. `instances[InstanceRef]` bu reference'a bağlanır. `documents[DocumentRef]` gövde/medya/retry'ı tutar; feedUrl'yi her ID'ye prefix etmek yerine açık instance-document ilişkisi vardır.
3. **AssetRef:** mevcut URL tabanlı fiziksel medya paylaşımı korunur; URL indeksi ile belge kimliği karıştırılmaz. İki bağımsız record aynı resmi referanslayabilir. Bu mevcut davranış `test/durable_identity_followup_test.dart:398-427` ile pozitif doğrulandı.

Aynı GUID, farklı URL/body: farklı InstanceRef ve DocumentRef. Aynı gerçek makalenin iki instance'ı, yalnız doğrulanmış içerik/provenance eşleşmesiyle aynı DocumentRef'e bağlanabilir. URL tek başına global unique document key olamaz; root/link reuse, GUID-as-URL ve çelişkili gövdeler için `urlIndex` bir adaylar kümesi tutmalıdır. Eşit normalize per-article URL + uyumlu, boş olmayan body/content fingerprint güçlü yeniden kullanım kanıtıdır; excerpt/full-text farkı otomatik yanlış eşitlik sayılmamalıdır. Kanıt yetersizse belgeler ayrı kalır, fiziksel medya yine paylaşılır. Sonraki çelişkili update, paylaşılan belgeyi bütün instance'lar için değiştirmek yerine copy-on-write ile ayırır. Sırf hash eşitliğine güvenmeyin; encoding ve asıl kanıt karşılaştırılmalı.

### 5.2 Sahiplik ve read durumu

- `bookmark` ve `tempCache` sahiplerini yalnız tür kümesi olarak değil, **instance reference + claim version** ile tutun. Document byte retention, yaşayan claim'lerin birleşimidir.
- Unsubscribe yalnız ilgili subscription instance'larının tempCache claim'lerini kaldırır. Bookmark claim'i ve diğer source'un claim'i kalır. Cleanup manifest referanslarını bütün yaşayan document/legacy-retention kayıtlarından hesaplar.
- Provider/preparation/reader/status/read API'leri ArticleRef/InstanceRef almalı; belirsiz bare ID lookup “ilk eşleşeni seç” yapmamalı. Legacy overload yalnız tek kanıtlanmış eşleşmede kullanılabilir; diğer durumda unresolved sonucu vermeli.
- Yeni read state instance bazında tutulmalı. Legacy `readItemIds` silinmemeli. Migration sırasında mevcut bilinen instance'ların eski görünür durumunu korumak için inherited legacy mark kaynak etiketiyle aktarılabilir; bu gerçek eski kullanıcı niyetinin yeniden çıkarıldığı anlamına gelmez.
- Yeni instance override'ı inherited mark'tan öncelikli olmalı. Sonradan gelen ortak GUID'li yeni source'a sınırsız global fallback uygulanmamalı. Hiç instance kanıtı olmayan eski read ID'leri unresolved history olarak korunmalı; belirli source'a sessiz atanmamalı.

### 5.3 Legacy gövde/medya aktarım kuralları

- Başlangıçta schema-1 ham archive, Hive bookmark/cache/read snapshot'ları ve epoch değerlerinin immutable, hash'li migration girdisini saklayın. Orijinali tamamlanma bayrağıyla erken silmeyin.
- Record'un `feedUrl`/`link` alanları **tek başına bütün alanların aidiyet kanıtı değildir**. Alan bazında mevcut snapshot body'si, link ve media referanslarıyla eşleştirme yapılmalı; çelişen title/body/link/media vakaları test fixture olmalı.
- Yalnız kanıtlanan body/full-text/media mapping'ini yeni document'a bağlayın. Ready medya gerçekten diskte ve beklenen byte size'da olmalı; indirilen hazır body'yi yeniden fetch ile gereksiz yere silmeyin.
- Kaynak aidiyeti çözülemeyen legacy record'u bütün byte/metadata ile **quarantine/unresolved legacy archive** olarak koruyun. Yanlış makalede “offline ready” göstermeyin. Özellikle mevcut collision bug'larıyla bozulmuş record'a güven derecesi uydurmayın.
- Quarantine bookmark ihtimali taşıyorsa otomatik unsubscribe/temp eviction onu yok etmemeli. Kaynak atamadan erişilebilen legacy arşiv görünümü/route'u gerekir; EN/TR/ES metinleri ve dürüst durum etiketi ayrı tasarlanmalı. Kullanıcıdan upgrade işlemi istenmez; yalnız kanıtlanamayan gövdenin yeni source'a otomatik atanması engellenir.
- Reset quarantine dahil kişisel veriyi siler. Clear-cache, bookmark bağlantısı bilinen veya belirsiz arşivi bookmark silme gibi değerlendirmemeli. Alanı hiç olmayan eski şema ile bozuk ownership/manifest container'ı birbirine çevrilmemeli; corruption fail-closed kalmalı.

### 5.4 İdempotent ve interruption-safe rollout

A. Önce bütün caller'ları typed reference ve writer-version/lifecycle protokolüne hazırlayın; aktif migration kapısı açılmadan global ID'den scoped ID'ye tek taraflı write yapmayın.

B. Ortak lifecycle lock altında schema-2 envelope oluşturun: legacy snapshot, instance/document map'leri, kalıcı reset epoch'u, migration journal, allocation/alias kararları. Her chunk atomic temp+rename ile yazılır. Journal'ın input fingerprint ve instance-to-document kararları restart'ta aynı reference'ları tekrar üretmeli; ikinci çalıştırma duplicate belge/owner oluşturamaz.

C. Adayları örneğin 100 kayıtlık bounded chunk'larla sınıflandırın. Her chunk beklenen reset epoch'unu kontrol etsin. UI/user mutation migration ile aynı otoriteye girsin; eski Hive snapshot'ının sonradan geri oynatılması yeni unbookmark/read override'ını ezmesin. Journal yalnız input cursor değil, sonradan gelen claim sürümlerini de taşımalı.

D. Yeni authoritative state ve read/ownership transaction'larını aynı kilitli envelope'da tutun. Hive'da projection gerekiyorsa outbox/journal acknowledgement kullanın; iki dosyaya yazıp global boolean `migrationDone` koymak crash-safe değildir. Projection tekrar oynatılabilir ve epoch ile fenced olmalı.

E. Bütün reader/writer'lar aynı kimliği kullandığı ve projection doğrulandığı zaman cutover'ı atomic işaretleyin. Eski ambiguous snapshot'ı GC'ye bırakmayın. Native arka plan işleri ve uygulama başlangıcı cutover sürümünü kontrol etmeli; eski schema writer'ının yeni state'i silmesine izin verilmemeli. Old-worker/downgrade davranışı ayrıca kanıtlanmalıdır; sadece yeni kodun parse edebilmesi yeterli değildir.

F. Kesinti test noktaları: girdi snapshot'ından önce/sonra, ilk chunk'tan sonra, document tahsisinden sonra, owner/read projection'ından önce/sonra, cutover marker'ından hemen önce/sonra. Her restart'ta aynı mapping, orijinal legacy bytes, yeni kullanıcı değişiklikleri ve bounded bellek korunmalı. Her noktada reset de denenmeli; resetten sonraki restart eski journal'ı replay etmemeli.

## 6. Ortak reset/commit protokolü — UYGULANMADI

Kimlik geçişinden bağımsız olarak release için gereken protokol:

- Kalıcı reset epoch'u **HTTP/iş başlamadan önce** yakalanır; snapshot okunduktan sonra yeni epoch'u almak yasaktır. Foreground ve background aynı disk otoritesini kullanır.
- Lock sırası belgelenmeli ve tek olmalı: lifecycle lock, ardından gerekli archive/observation lock'ları. Network transferi sırasında lock tutulmaz.
- İndirme epoch-etiketli staging dosyasına yapılır. Managed `m_*` dosyasına rename ve manifest ready commit, lifecycle lease + record generation + instance claim sürümü doğrulandıktan sonra aynı publication kritik bölümünde yapılır.
- Reset aynı publication lock'unu alır, epoch'u ilerletir, reset journal'ını kalıcılaştırır; arşiv/gözlem/projection ve managed/staging byte silmesini tamamlar. Eski writer önce commit etmişse reset siler; reset önce bittiyse eski writer rename yapamaz. Ortak asset'i stale writer'ın keyfi silmesi çözüm sayılmaz.
- Observation claim de kalıcı reset epoch'u alır; lock içinde karşılaştırır. Subscription notification epoch'u reset epoch'unun yerine geçmez. Yeni namespace initialization için de aynı fence zorunlu olmalı.
- Background subscription membership, yalnız isolate-local Hive cache'inden doğrulanmamalı; authoritative aktif subscription/claim sürümü diskten okunmalı. Unsubscribe diğer source'un veya bookmark'ın claim'ini iptal etmez.
- Bütün mutation/CAS yolları reset epoch + record lifetime generation'ını taşımalı. Reset sonrası generation 1'in tekrar kullanılması eski commit'i yetkilendirmemeli.
- Reset yarıda kesilirse startup, tamamlanmamış reset journal'ını önce bitirmeli; migration veya background refresh'i önce çalıştırmamalı. Kilitlerin tek tek doğru olması çok dosyalı resetin atomik olduğu anlamına gelmez.

Bu protokolün tam uygulaması record store, media publisher, cleanup, observation, background ve Hive projection'ını birlikte değiştirir. Yalnız R1–R3 düzeltmeleriyle bu garanti verilmez.

## 7. Kabul testleri ve bu çalışmanın kapsama sınırı

İstenen sekiz senaryonun durumu:

1. Ortak GUID/farklı URL/body: karakterizasyon gerçek kusuru gösteriyor; migration sonrası iki doğru DocumentRef acceptance'ı **henüz yok**.
2. Bağımsız bookmark/offline preparation: iki snapshot ama tek yanlış offline record testi var; bağımsız arşiv acceptance'ı henüz karşılanmıyor. Pozitif ortak asset paylaşım testi mevcut.
3. Yeni read kayıtlarının bağımsızlığı: mevcut String API'nin iki source'u beraber işaretlediği kanıtlandı; yeni read modeli uygulanmadı.
4. Legacy Hive restart: global read ve iki bookmark snapshot'ının korunduğu test edildi; bu, güvenli scoped migration kanıtı değil.
5. Migration interruption: **migrator yok; acceptance çalıştırılamaz**. Mevcut restore'un kesilmesi/restart karakterizasyonu var. Bölüm 5.4'ün her checkpoint'inde future migrator'a fault injection gerekiyor.
6. Preparation sırasında reset: snapshot/epoch, kilit bekleyen registration ve body continuation için adversarial testler başarılı; fiziksel medya resurrection açık.
7. Unsubscribe/cleanup: aynı-ID temp-cache provenance hatası gösterildi; yeni instance-owner cleanup acceptance'ı açık. Mevcut s4/s5 suite'i farklı ID'li bookmark/ortak asset korumasını ayrıca kontrol eder.
8. Foreground/background: gerçek Dart isolate'larıyla owner aliasing, persisted archive epoch rejection ve observation resurrection test edildi. Native Workmanager scheduler/OS kill çalıştırılmadı.

Yeni dosyada **16 test** var: **7 bilinen-kusur karakterizasyonu**, **9 pozitif/regresyon kontrolü**. Sonuçları “16 kimlik güvenliği kabul testi geçti” diye yorumlamak yanlıştır. Kimlik modeli ve reset protokolü tamamlanınca KNOWN testleri doğru davranış assertion'larıyla değiştirilmelidir; mevcut hatayı kalıcı ürün sözleşmesi yapmak için yazılmadılar.

## 8. Değiştirilen dosyalar ve kesin kaynak konumları

Bu takip çalışmasının üretim değişikliği yalnız:

- `lib/services/article_preparation_service.dart:142-168` — locked callback'e taşınan local reset doğrulaması.
- Aynı dosya `271-290` — register claim check ile local fence'in birleşimi.
- `398-444` — epoch'un snapshot öncesine taşınması.
- `488-493,533-540,554-578` — body/media lifetime generation kontrolleri.

Eklenen dosyalar:

- `test/durable_identity_followup_test.dart:1-649` — gerçek file store, Completer barrier'ları, snapshot hook'ları, gerçek isolate testleri, açık KNOWN karakterizasyonlar.
- `docs/audits/durable-identity-followup.md` — sözleşmeler, bulgular, uygulanmamış geçiş tasarımı ve doğrulama.

Güncellenen önceki rapor: `docs/audits/incremental-refresh-stability-audit.md:3-7` takip notu; önceki 557 test sonucu tarihsel baseline olarak bırakıldı. O rapordaki eski kaynak aralıkları tarihsel referanstır; yeni preparation aralıkları yukarıdadır.

Diğer başlangıç değişikliklerine dokunulmadı. Commit/push/merge yapılmadı. Hive key, JSON schema, package sürümü, FeedItem equality, release workflow veya localization değişikliği yok.

## 9. Önce/sonra üretim ve doğrulama sonuçları

### Red / green

```bash
flutter test test/durable_identity_followup_test.dart
```

- İlk çalıştırma: 4 mevcut kimlik kusuru karakterizasyonu geçti; 4 gerçek güvenlik assertion'ı başarısızdı (iki kilit bekleme, iki snapshot/epoch yarışı).
- R1/R2 sonrası eklenen tombstone/revive kontrolleri: 2 hata (`STALE BODY`, yanlış `MediaState.ready`); R3 sonrası yeşil.
- Son genişletilmiş yeni dosya: 16/16 başarılı. Yedi KNOWN assertion hâlâ yanlış ürün davranışını gösterir; bunlara üretim çözümü uygulanmadı.
- Testler keyfi sleep kullanmaz. HTTP cevapları ve writer durakları Completer ile; writer/reset sırası gerçek dosya lock'larıyla; isolate geçişleri port handshake ile yönetilir.

### Son komutlar

```bash
dart format lib/services/article_preparation_service.dart test/durable_identity_followup_test.dart
flutter analyze
flutter test test/durable_identity_followup_test.dart test/s2_storage_foundation_test.dart test/s3_preparation_engine_test.dart test/s4_temp_cache_selection_test.dart test/s5_cleanup_lifecycle_test.dart test/observed_article_store_test.dart test/rss_lifecycle_regression_test.dart
flutter test
flutter build linux --debug
flutter build apk --debug
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

- Flutter **3.47.6**, Dart **3.13.5**, Linux x86_64 ortamı önceki raporla aynı.
- Analyze: **No issues found!**
- Hedefli yedi dosya: **198 başarılı, 0 başarısız**.
- Genel suite: **573 başarılı, 0 başarısız**; framework skip raporlamadı. Önceki 557'ye 16 yeni test eklendi.
- Linux debug build başarılı: `build/linux/x64/debug/bundle/dondurma`.
- Android debug build başarılı: `build/app/outputs/flutter-apk/app-debug.apk`.
- Android build'de mevcut plugin Kotlin Gradle Plugin/Built-in Kotlin geçiş uyarısı devam ediyor; dependency sürümleri değiştirilmedi.
- `git diff --check` başarılı.
- Gerçek cihaz smoke, OS process-kill, native Workmanager job, iOS/macOS/Windows build yapılmadı. Gerçek Dart isolate testi native Workmanager testi olarak sunulmuyor.
- Benchmark yapılmadı; bu takip için performans iyileşmesi iddiası yok.

### Ayrı mevcut format sorunu

Tüm depo format kontrolü **exit 1**; yine aynı 13, bu takipte değiştirilmemiş dosya:

```text
lib/screens/article_screen.dart
lib/screens/categories_screen.dart
lib/screens/desktop/desktop_sidebar.dart
lib/screens/explore_feeds_page.dart
lib/screens/onboarding_screen.dart
lib/widgets/add_feed_dialog.dart
lib/widgets/app_drawer.dart
lib/widgets/article/article_image_carousel.dart
lib/widgets/settings/settings_widgets.dart
test/desktop_layout_test.dart
test/desktop_nav_selection_test.dart
test/desktop_reader_width_test.dart
test/refresh_toast_test.dart
```

`--output=none` bunları değiştirmedi. Yalnız bu takipte değişen iki Dart dosyası formatlandı. Genel testlerin geçmesi format kapısının geçtiği anlamına gelmez.

## 10. Legacy uyumluluk garantileri ve sınırlar

Bu patch persistence encoding'i değiştirmediği için mevcut Hive read/bookmark kayıtları, archive key'leri, manifest dosya adları ve hazır içerik migration'a sokulmaz; yeniden numaralandırılmaz veya temizlenmez. Legacy restart fixture'ları mevcut davranışın aynen okunabildiğini doğrular. Yanlış source'a atanmış eski verinin doğruluğu garanti edilmez; tam tersine karakterizasyonlar bunu açıkça gösterir.

R1/R2/R3 yalnız eski async işlerin yetkisiz mutasyonlarını engeller. Doğru güncel epoch/generation'lı register/preparation davranışı s2–s5 ve lifecycle suite'lerinde başarılıdır. Body/media işlemleri kendi içinde aynı record lifetime'ını hedeflemeye devam eder; mevcut owner birleşimi sözleşmesi değiştirilmedi.

Otomatik, kullanıcı müdahalesiz scoped upgrade bu patch'te **yoktur**. İdempotence, interrupted migration recovery, ambiguous quarantine UI ve read inheritance kuralları bölüm 5'te planlanmıştır, test edilip uygulanmış garantiler değildir.

## 11. Kalan riskler ve yayın önerisi

**NOT READY FOR RELEASE**

Yayın engelleri:

- **P0:** tamamlanmış reset sonrasında eski medya byte'larının tekrar diske yayınlanması. Kişisel veri silme garantisi sağlanmıyor; yalnız manifest'in reddedilmesi yeterli değil.
- **P0:** late background observation'ın silinmiş eski namespace'i tekrar yaratması. Foreground local closure tüm isolate'ları korumuyor.
- **P1:** aynı GUID'li bağımsız makalelerin tek archive/body/owner kaydında karışması; B'de A body'sinin gösterilmesi testle kanıtlandı.
- **P1:** yeni read state dahi source bağımsız değil; unsubscribe/cleanup instance provenance'ını koruyamıyor.
- **P1 araştırma:** background'ın HTTP sonrası epoch örneklemesi, Hive projection/reset atomicity ve legacy CAS epoch eksikliği ortak protokolün parçası olarak ele alınmalı.
- **P2:** eski 13 format sorunu ve native platform/device doğrulama eksikleri ayrı kalıyor.

Bu takip, önceki “arşiv kimliği çözülmedi” değerlendirmesini değiştirmek yerine daha güçlü kanıtla destekliyor; ayrıca önce araştırma düzeyinde kalan iki reset açığını somutlaştırıyor. Üç preparation bug'ı düzeltildi; bundan tam identity migration veya tüm reset yarışlarının çözüldüğü sonucu çıkarılamaz.

## ChatGPT Independent Review Handoff

1. Önce `test/durable_identity_followup_test.dart` dosyasını okuyun. `KNOWN` assertion'ların kusuru doğruladığını görün; suite sayısından release güvenliği çıkarmayın. `187-226` bookmark restore + gerçek reader yanlış body'sini, `272-296` read coupling'i, `334-352` gerçek isolate owner birleşmesini gösterir.
2. Yeni üretim diff'i yalnız `lib/services/article_preparation_service.dart`. `142-168,271-290` locked reset check; `398-444` snapshot öncesi epoch; `488-578` generation kontrolleri. Queue başındaki check'in tek başına yeterli olmadığını `_BeforeLock` test seam'iyle doğrulayın. Beklenen güvenlik assertion'ları düzeltmelerden önce gerçekten kırmızıydı.
3. Açık release engellerini bağımsız çalıştırın: `flutter test test/durable_identity_followup_test.dart --plain-name 'KNOWN'`. Özellikle `354-396` eski background history resurrection; `429-475` reset sonrası fiziksel medya dosyasının tekrar var olması. Bunlar bu patch'te düzeltilmedi.
4. Migration'ı uygulamadan `article_record_store.dart:283,339-340,437-523`, `article_preparation_service.dart:291-393`, `temp_cache_membership.dart:66-105,145-185`, `article_page_provider.dart:116-145,327-337` ve read çağrılarını inceleyin. Instance/document/asset ayrımı, quarantine, read inheritance ve journal tasarımı bölüm 5'te; ortak reset/media/observation protokolü bölüm 6'da.
5. Kabul matrisi bölüm 7'de açık: migration yok, dolayısıyla migration interruption/upgrade acceptance'ı geçti iddiası yok. Quarantine'nın GC'den korunması ve native background cutover'ı uygulama öncesi çözülmeli.
6. Kanıtı tekrar çalıştırın: bölüm 9 komutları. Son sonuçlar analyze temiz, 573 genel / 198 hedefli test başarılı, Linux/Android debug build başarılı; format exit 1. iOS/macOS/Windows veya gerçek cihaz çalıştırılmadı.
7. Dal/HEAD değişmedi: `main`, `409774ee3d1a05f5a713438a16047d3a69a0cf51`. Commit edilmemiş önceki çalışmayı yeni düzeltmelerle karıştırmayın. Bu takipte yalnız bir production dosyası, bir yeni test dosyası ve iki audit belgesi eklendi/düzenlendi; commit, push, merge yok.
