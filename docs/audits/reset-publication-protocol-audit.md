# Dondurma RSS Reader — Reset Publication Protocol Audit

## 1. Initial repository state

- Dal: `main`.
- İlk/son HEAD: `409774ee3d1a05f5a713438a16047d3a69a0cf51`.
- Başlangıçta önceki iki denetimin bütün commit edilmemiş kaynak/test değişiklikleri ve izlenmeyen rapor/test dosyaları mevcuttu. Bunlar korunmuştur. `git diff HEAD` bu çalışmanın tek başına farkı değildir.
- Önce `incremental-refresh-stability-audit.md`, `durable-identity-followup.md`, mevcut KNOWN testleri ve gerçek reset/store/başlangıç yolları okundu.
- Flutter 3.47.6 / Dart 3.13.5, Linux x86_64. Önceki raporun 573 başarılı testi tarihsel baseline'dır.
- Bu çalışma **üretim protokolünü tamamlamadı**. Güvenliği kanıtlanamayan kısmi publication yaması yerine, kullanıcının izin verdiği release-blocker fallback seçildi. Üretim kaynaklarına yeni lifecycle davranışı eklenmedi. Pozitif güvenlik assertion'ları eklendi ve başarısız halleri gizlenmeden bırakıldı.

## 2. Previous confirmed P0 failures

### P0-A: HTTP sonrası dosya yayını

`ArticlePreparationService._fetchAndStore` HTTP cevabını aldıktan sonra `ArticleMediaStore.put` çağırıyor. Manifest commit'i daha sonra archive epoch kontrolünden geçiyor. `put` içindeki temp yazma/rename, archive resetinin kilidine katılmıyor:

- `lib/services/article_media_store.dart:108-135`.
- `lib/services/article_preparation_service.dart:560-578,640-671`.
- `lib/providers/feed_provider.dart:1796-1808`.

Yeni **olumlu kabul assertion'ı A**, reset tamamlandıktan sonra managed dosyanın **yok** olmasını bekliyor; gerçek sonuç **var**. Önceki KNOWN assertion güvenli davranış diye yeniden adlandırılmadı.

### P0-B: Eski background namespace'i

Archive `expectedEpoch` eski writer'ı reddetse de observation store'un ayrı kilidi bu işin hangi reset döneminden geldiğini bilmiyor. `claimCheck` foreground closure'ı child isolate'a taşınmıyor. Yeni **olumlu kabul assertion'ı B**, gerçek child isolate reset sonrasında devam ettiğinde `feeds` map'inin boş kalmasını bekliyor; eski namespace yeniden oluşuyor.

Kaynak: `lib/services/observed_article_store.dart:54-145,148-163`; background caller `lib/services/background_fetch_service.dart:274-285`.

### Bu çalışmada ek olarak doğrulanan ihlaller

- **J:** Yeni dönemde aynı URL'ye indirilen `[7,8,9]` bytes, eski HTTP cevabının `[1,2,3]` bytes'ıyla eziliyor. Yeni record ve `ready` manifest'i kalıyor; boyutlar eşit olduğundan `verify()` de sorunu yakalayamıyor. Sadece eski manifest'i reddetmek yeni veriyi korumuyor.
- **C:** Gerçek `runBgFetch()` loopback HTTP isteği reset öncesinde başlatıldı; reset tamamlandıktan sonra yeni archive/history/cache/validator girdileri yazıldı; eski cevap bırakıldı. Eski archive/history geri oluştu; yeni cache ve validator projection'ı eski görev tarafından değiştirildi. Yeni archive/history'nin ayrı girdileri kaldı; bütün yeni verinin silindiği iddia edilmiyor.
- **E2:** GC orphan listesi çıktıktan sonra aynı managed dosyaya yeni bookmark record'u bağlandı. GC eski silme kararını uygulayıp hâlâ kullanılan dosyayı sildi. İki dakikalık grace bunu engellemiyor: dosya eski, fakat **referans yeni** olabilir.

## 3. New lifecycle protocol

**Durum: tasarım/uygulama planı; uygulanmış garanti değildir.** Bu bölüm Durable Identity V2 gerektirmez; mevcut makale ID'leri korunabilir.

Gerekli sözleşme:

1. `beginWork()` publication yetkisini işin başında verir; dönen immutable `LifecycleTicket` HTTP/extraction, kuyruk ve commit boyunca taşınır.
2. `publish(ticket, action)` ortak publication mutex'i altında epoch ve reset-journal durumunu doğrular. Stale iş callback'e dahi giremez.
3. `reset()` aynı mutex altında yeni dönemi ve `resetPending` journal'ını kalıcılaştırır. Yeni işler pending dönemde durur/fail-closed olur.
4. Temizlik bittiği kanıtlanınca pending kaldırılır. Ancak bundan sonra yeni döneme ait normal iş başlayabilir.
5. `recoverReset()` startup/background girişinde, provider restoration veya subscription snapshot'ı okunmadan önce pending temizliği tamamlar.

Üç farklı sıralama ayrı test edilmelidir:

- Eski publisher kritik bölümü önce aldıysa commit edebilir; sonraki reset onu temizler.
- Reset önce tamamlandıysa eski ticket ile publisher callback'i çalışmaz; dosya, history veya Hive snapshot oluşturamaz.
- Yeni ticket reset sonrasında alındıysa yazı geçerlidir. Eski cleanup/reset continuation'ı bu yeni veriyi silemez.

Şu an bu ortak API, tüm caller'ları kapsayan adaptör ve startup recovery **yok**. Yalnız iki store'a birer epoch if'i eklemek A/B/J/C/E2'nin tamamını çözmez. Bu nedenle kısmen güvenli üretim protokolü yayınlanmadı.

## 4. Persisted reset epoch design

Önerilen otorite: feeds kutusuyla aynı uygulama storage kökünde, Hive ve makale archive ID şemasından bağımsız, küçük versioned lifecycle journal dosyası:

```text
schema
resetEpoch          # güçlü rastgele, tekrar kullanılmayan token
resetId             # cleanup/recovery çalışmasının kimliği
resetPending
completedCleanupStages
```

- İlk bootstrap, mevcut kullanıcı verisini silmeden initial epoch oluşturmalı. Eski archive `epoch` değeri cache/record fencing için kalabilir; yeni ortak reset otoritesiyle karıştırılmamalı.
- Journal update temp+flush+atomic rename ile olmalı; bozuk/foreign journal'da “yok say, epoch=0” fallback'i yasak olmalı.
- Ticket **network öncesinde**, hatta subscription/cache input snapshot'larından önce alınmalı. `_persistBgCache` içinde HTTP'den sonra yeni epoch almak yetki kazandırmamalı.
- Her başarılı reset yeni epoch üretmeli. Pending reset recovery aynı resetId'yi tamamlayabilir; pending durumda normal iş yetkilendirilemediği için eski işi yeniden yetkilendiremez.
- Callback veya late `_saveChain` link'i execution anında fresh ticket almamalı; enqueue/iş başlangıcında yakalanan ticket'ı taşımalı.
- Legacy kayıtların body/ownership'i bu dosya eklenirken migrate edilmemeli. `clearCache()` observation history'yi silmemeli veya factory-reset epoch'u gibi davranmamalı.

**Mevcut doğrulama:** H testi yalnız archive epoch'larının dört wipe sonrası tekrar yetki vermediğini kanıtlar. Bu bir shared reset epoch testi değildir. C testi, monotonic archive epoch mevcut olsa da onu geç okumanın tehlikesini gösterir.

## 5. Lock ordering and deadlock analysis

Önerilen tek sıra:

```text
lifecycle/publication mutex
  archive lock VEYA observation lock
  filesystem rename/delete veya await edilen Hive projection
```

- Store lock'u tutan kod lifecycle lock'unu sonradan istememeli.
- `publish` içinden store çağırırken aynı lifecycle mutex'i yeniden edinmeye çalışmak deadlock oluşturur. Bunu engelleyen scoped publication permit/internal locked API gerekir; rastgele boolean veya global “lock held” bayrağı yeterli değildir.
- Reset, global lock altında eski `_saveChain`, registration kuyruğu veya network future'ını beklememeli: bunlar aynı lock'u isteyebilir. Eski işler ticket ile reddedilmeli; reset kuyrukların bitişine bağımlı olmamalı.
- HTTP/extraction/pacing kilit dışında; ownership doğrulama, dosya publication ve ready commit kilit içinde olmalı.
- E2 nedeniyle GC'nin son reference kararı ve delete'i de aynı mutex'e katılmalı. Sadece manifest writer'larını korumak yeterli değil.

### Mutex için açık güvenlik önkoşulu

Mevcut `FileObservedArticlePersistence` (`lib/services/observed_article_persistence_io.dart:25-38,79-125,149-211`) atomic guard/file ownership kullanıyor, fakat iki dakika sonra lock/guard'ı orphan **varsayabiliyor**. Bu, süresi sınırlı kısa store kritik bölümleri için mevcut politikadır; geniş reset/GC/Hive/disk publication kritik bölümüne koşulsuz mutual-exclusion garantisi diye taşınamaz. Canlı, duraklamış sahibin ne zaman öldüğü yalnız timestamp'tan çıkarılamaz. Bu risk için gerçek iki dakikalık active-owner-steal testi yapılmadı; source seviyesinde tasarım sınırı olarak kaydediliyor.

Sadece `RandomAccessFile.lock()` ile değiştirmek de güvenli drop-in değildir. Kurulu Dart SDK `lib/io/file.dart:934-942`, Linux/macOS advisory lock'larının process düzeyinde olduğunu ve aynı process'in birden fazla isolate'ının exclusive lock alabildiğini açıkça belirtiyor. Bu SDK sözleşmesi incelendi; burada native mutex implementasyonu test edilmedi.

Gerekli önkoşul: aynı process içindeki bütün engine/isolate'lar ile farklı process'leri kapsayan, owner-death recovery'si kanıtlanmış mutex. Platform helper/broker + OS lock veya uygun handle-owned lock seçimi native testle doğrulanmalıdır. Lease expiry'yi lock-owner ölüm kanıtı sayan bir protokol, bu görevin katı reset sözleşmesini kanıtlamaz.

## 6. Media publication guarantees

**Uygulanmış yeni garanti yok; A ve J kırmızı.** Güvenli implementasyon için somut işlem:

1. Mevcut en fazla 15 MB HTTP cevabını network sırasında lock tutmadan al.
2. Eski ticket ile publication mutex'ine gir; current reset epoch, archive epoch, record generation, canlı owner ve ilgili manifest niyetini doğrula. Başarısızsa managed veya staging dosya yaratma.
3. Publication permit altında epoch-etiketli geçici dosyayı yaz, flush et ve managed ada rename et; ardından owning manifest'i ready yap. Store lock'larını aynı sabit sırayla kullan.
4. Reset bu kritik bölümün arasına giremesin. Reset önce bitmişse eski byte'lar yazılamasın; publisher önce bitmişse reset dosyayı silebilsin.
5. Rename ile JSON ready commit tek OS transaction'ı değildir. Önceden durable pending manifest bulunmalı; aradaki crash “ready fakat eksik dosya” üretmemeli. Recovery/GC pending referansı görmeli; orphan/staging politikası ayrıca tanımlanmalı.
6. Reddedilmiş eski commit sonrası URL dosyasını keyfi silme: yeni record aynı dosyayı kullanıyor olabilir. J ve E2 bu hata sınıfına doğrudan acceptance sağlar.
7. GC reference check + deletion ve reset medya temizliği de aynı publication permit'i kullanmalı. Reset daha sonraki epoch'un staging/managed dosyasını silememeli.

Sadece epoch check + daha sonra rename güvenli değil. Sadece ayrı epoch staging klasörüne eski kişisel bytes yazıp “aktif değil” demek de tam veri silme garantisi olarak sunulmamalı. Burada böyle bir yama yapılmadı.

## 7. Observation publication guarantees

**Uygulanmış yeni garanti yok; B ve C kırmızı.** Gerekli değişiklikler:

- `claimFeedBatch` API'si iş başlangıcında alınan lifecycle ticket'ı almalı. Claim başladığında fresh token edinmek, eski HTTP işini meşrulaştırır.
- Namespace initialization dahil bütün claim mutasyonları publication mutex'i altında ticket'ı doğrulamalı; sonra observation lock'u edinilmeli.
- Subscription notification epoch'u ile reset epoch'u farklıdır. Mevcut ilk-fetch sessiz initialization ve observed-before-delivery kuralları korunmalı.
- Foreground `claimCheck` ek bir canlı abonelik kontrolü olarak kalabilir; persisted fencing'in yerine geçmemeli.
- Reset/history wipe, ortak reset coordinator'ın ayrıcalıklı cleanup yolu olmalı. Ordinary cache eviction unrelated history'yi silmemeli.

## 8. Background Hive/cache boundaries

C testi aşağıdaki gerçek yürütmeyi sürer (`test/rss_lifecycle_regression_test.dart:305-394`):

- Loopback server HTTP isteğini Completer ile tutar.
- `FeedProvider.factoryReset()` başarıyla tamamlanır.
- Yeni döneme ait archive/bookmark claim'i, observation, `cachedItemsJson` ve validator girdileri yazılır.
- Eski HTTP cevabı bırakılır; gerçek `runBgFetch()` bitişi beklenir.

Gerçek sonuç:

```text
oldArchivePresent = true       # beklenen false
newArchivePresent = true
oldObservationPresent = true   # beklenen false
newObservationPresent = true
cachedIds = [pre-reset-item]   # beklenen [post-reset-item]
validatorKeys = [oldFeedUrl]   # beklenen [current-key]
```

Bu test native Workmanager çalıştırmaz. Notification init ve connectivity plugin'leri test ortamında bulunmadığından log üretir; network/observation/archive/cache/validator evreleri gerçekten gerçekleşir. Başarısızlık plugin log'una değil yukarıdaki somut state farkına dayanır.

Gerekli ticket taşıma/publication noktaları:

- `runBgFetch`: Hive/subscription snapshot + HTTP öncesi `beginWork`.
- HTTP validator ve cooldown persist (`background_fetch_service.dart:253-268`).
- Observation claim (`274-285`).
- `_persistBgCache` registration/membership (`398-459`) ve final `cachedItemsJson` put (`483-493`).
- Widget/notification publication ve preparation sweep: eski task'ın reset sonrası yan etkileri ayrıca gate edilmeli.
- Foreground `refreshAll`, add-subscription, bookmark restoration, full-text prefetch, queued `_saveCachedItems` ve ilgili Hive writer'lar: operation ticket'ı async sınır boyunca korumalı.

Hive kutuları isolate-local cache tutar. Yeni ticket'lı iş eski açık kutunun pre-reset memory snapshot'ını yeni veri saymamalı: lock altında fresh disk view/uyumlu reopen veya durable projection otoritesi gerekir. Projection'ın writer'ı ile reset aynı mutex'e katılmalı; salt `cacheEpoch` check ve ayrı await edilen `box.put` arasında boşluk bırakılmamalı.

Bütün HTTP sonuçları, archive JSON, history JSON ve Hive için tek atomik transaction varmış gibi davranılamaz. En küçük savunulabilir garanti: her publication epoch açısından serializable; pending reset journal ile startup'ta tamamlanır; işin farklı evreleri ayrı commit edilebilir. Eski iş hiçbir evrede fresh authorization alamaz.

## 9. Reset interruption and recovery

**Recovery uygulanmadı; release blocker.**

- Startup `lib/main.dart:59-64` kutuları açıp `_migrateHiveBoxes()` çalıştırıyor; ortak incomplete-reset journal kontrolü yok.
- `FeedProvider.factoryReset()` (`1763-1820`) kutu, archive, observation ve medyayı ardışık temizliyor; reset intent'i başlangıçta ortak journal'a yazılmıyor.
- UI sırası `lib/screens/settings_screen.dart:911-914`: bookmark, subscriptions, feeds, settings ayrı async reset'ler. Journal'ın yalnız feed reset içinde başlatılması, önceki partial silmeleri veya son settings temizliğini kapsamaz.

Somut recovery planı:

1. Bütün factory-reset disk işlerini bir coordinator-owned cleanup altında topla; UI/provider state reset'leri bu işi ikinci kez diskten silmemeli.
2. Herhangi bir kişisel veriyi silmeden önce mutex altında yeni epoch/resetId ve pending state'i kalıcılaştır.
3. Archive/history/Hive/media cleanup aşamalarını idempotent yap; tamamlanan aşamaları atomik journal update ile kaydet. Foreign dosya ve ambiguous legacy archive normal startup'ta silinmesin; yalnız açık reset intent'i silme yetkisi versin.
4. Main ve background girişleri provider restoration, migration veya fetch'ten önce pending reseti tamamlasın. Yeni normal işler pending süresince başlamasın.
5. Reset başka recovery tarafından tamamlandıktan sonra geri dönen eski cleanup continuation'ı resetId/pending eşleşmesini mutex altında yeniden kontrol etsin; yeni lifecycle verisini silemesin.
6. Journal pending bayrağını ancak bütün gerekli cleanup ve await edilen projection flush'ları bittikten sonra kaldır. Corrupt journal/IO hatasında fail-closed ve dürüst başarısız reset sonucu ver.
7. Her checkpoint'te gerçek process termination testi yap: intent sonrası, archive wipe sonrası, history wipe sonrası, Hive sonrası, staging/managed delete sonrası, pending-clear öncesi/sonrası. Yeni process aynı journal'dan recovery yapmalı.

Bu çalışmada process-kill/restart veya G kabul testi yapılmadı. Store nesnesini yeniden oluşturmak gerçek startup recovery kanıtı değildir. Böyle bir kanıt varmış gibi davranılmadı.

## 10. Exact modified files and line ranges

Bu turda production kaynak değişikliği **yok**. Önceki turların production farkları korunmuştur.

- `test/durable_identity_followup_test.dart:90-104`: orphan scan sonrasına deterministik writer koyan `_AfterOrphanScanMedia` test double'ı.
- Aynı dosya `492-787`: A/B/D/E/E2/H/J pozitif acceptance grubu. Eski KNOWN assertion'lar korunur; güvenlik assertion'ına çevrilmiş gibi gösterilmez.
- `test/rss_lifecycle_regression_test.dart:305-394`: C, gerçek background HTTP/projection acceptance'ı.
- `docs/audits/reset-publication-protocol-audit.md`: bu rapor.
- `docs/audits/durable-identity-followup.md:3-6`: güncel kırmızı acceptance / release-blocker takip notu. Eski 573 sonucu tarihsel bırakıldı.

Paket, Hive key, archive identity, JSON schema, equality, UI/localization, OPML, backup ve release workflow değişmedi. Commit/push/merge yapılmadı.

## 11. Red/green test evidence

Yeni testler keyfi sleep kullanmaz: Completer HTTP bariyeri, child isolate port handshake, gerçek dosya store'ları, locked mutation ve orphan-scan hook'u kullanır.

```bash
flutter test test/durable_identity_followup_test.dart --plain-name 'reset publication acceptance'
flutter test test/rss_lifecycle_regression_test.dart --plain-name 'reset publication acceptance C'
```

- A: `Expected: false / Actual: true` — eski managed dosya var.
- B: `Expected: empty / Actual: {old namespace ...}`.
- J: `Expected: [7,8,9] / Actual: [1,2,3]` — yeni dönemin bytes'ı ezilmiş.
- E2: `Expected: true / Actual: false` — yeni record'un referansladığı dosya silinmiş.
- C: yeni projection yerine eski archive/history/cache/validator state'i, bölüm 8.

**Green yok:** bu beş acceptance hâlâ başarısızdır. Testler unsafe sonuca göre değiştirilmedi, skip edilmedi veya default suite'ten saklanmadı.

Pozitif kontroller: D yeni-generation download'u çalıştırıyor; E yeni referans GC'nin ikinci snapshot'ından **önce** geldiğinde korunuyor; H eski archive epoch'larını reddediyor. Bunlar ortak protokolün var olduğunu kanıtlamaz. E2, E'nin korumasının ikinci snapshot sonrası boşluğu kapatmadığını gösterir.

A–J kapsama özeti:

- A/B/C/J: doğrudan pozitif assertion, kırmızı.
- D: mevcut kodda başarılı.
- E: erken yeni referans başarılı; orphan scan sonrası geç referans E2 başarısız.
- F: önceki write-inside-archive-lock testi bir sıralamayı kontrol eder; yeni ortak mutex olmadığı için iki global publication/reset sırası doğrulanmadı.
- G: gerçek reset interruption/recovery kabulü yapılmadı; journal yok.
- H: yalnız archive epoch için başarılı; shared lifecycle token henüz yok.
- I: B gerçek child isolate kullanır; C gerçek `runBgFetch` fakat aynı test isolate'ı kullanır. Native background engine/process testi yapılmadı.

## 12. Full test and build results

Çalıştırılan doğrulamalar:

```bash
flutter analyze
flutter test
flutter test test/durable_identity_followup_test.dart --plain-name 'reset publication acceptance'
flutter test test/rss_lifecycle_regression_test.dart --plain-name 'reset publication acceptance C'
flutter test test/incremental_refresh_scheduler_test.dart
flutter build linux --debug
flutter build apk --debug
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

- Analyze: **No issues found!**
- Son genel suite: **576 başarılı, 5 başarısız**, exit 1; skip raporlanmadı. Eklenen 8 testin 3'ü yeşil, 5'i kırmızı. Eski 573 sonucu güncel suite'in tamamen geçtiği anlamına gelmez.
- Yeni dosyadaki ayrı acceptance grubu: **3 başarılı, 4 başarısız**.
- C ayrı koşusu: **0 başarılı, 1 başarısız**.
- İlk genel koşu ayrıca scheduler queued-pass testinde `FileSystemException: Deletion failed ... Directory not empty` teardown hatası verdi (**575 başarılı, 6 başarısız**). Ayrı scheduler ilk tekrarında da **10/1**; ikinci tekrarında **11/0**. Son genel suite'te bu ek hata yoktu. Sebebi izole edilmedi; gizlenmedi ve bu dosya değiştirilmedi.
- Linux debug build başarılı: `build/linux/x64/debug/bundle/dondurma`.
- Android debug build başarılı: `build/app/outputs/flutter-apk/app-debug.apk`. Mevcut plugin Built-in Kotlin/KGP uyarısı devam ediyor.
- `git diff --check`: başarılı.
- Native Workmanager, Android/Linux cihaz smoke, iOS/macOS/Windows build ve gerçek process-kill testi yapılmadı. Build başarısı reset güvenliği kanıtı değildir.

Format kontrolü exit 1: önceki **aynı 13 ilgisiz dosya**, değiştirilmedi:

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

Yalnız düzenlenen iki Dart test dosyası formatlandı. `--output=none` ilgisiz dosyaları yazmadı.

## 13. Remaining known defects

- **P0-A/P0-B açık**; olumlu acceptance'ları kırmızı.
- **P0/P1 J:** eski publisher yeni valid medyayı bozabiliyor; yalnız size verification yeterli değil.
- **P0/P1 C:** eski background işi reset sonrasında archive/history ve Hive projection yazabiliyor.
- **P1 E2:** orphan kararı ile delete arasında yeni referans korunmuyor.
- **Release blocker:** interrupted reset recovery ve shared mutex/token protokolü yok.
- **P1:** önceki ortak GUID durable identity/read sorunları değişmedi; bu görevde V2 yapılmadı.
- **Araştırma:** scheduler temp-directory teardown hatası aralıklı tekrarlandı; sebep kanıtlanmadı.
- Native/platform doğrulaması ve 13 format sorunu açık.

## 14. Performance implications

Ölçüm/benchmark yapılmadı; performans iyileşmesi iddiası yok.

Önerilen protokol uygulanırsa her durable publication ek mutex/epoch IO maliyeti getirir. HTTP/extraction concurrency ve 100 ms UI batching bu lock içine alınmamalı. Bounded disk publication ve GC aşamaları gerçek disk yavaşlığı altında ölçülmeli; uzun kritik bölümün aktif-owner lease varsayımını ihlal etmediği kanıtlanmalı. Büyük snapshot encode işlemi gate dışında yapılabilir, fakat final commit ticket'ı encode öncesinden taşınmalı ve mutex altında doğrulanmalı. Mutex yalnız UI micro-optimization amacıyla daraltılıp rename/reset boşluğu tekrar açılmamalı.

## 15. Release recommendation

**NOT READY FOR RELEASE**

Bu görev istenen tam implementasyonu tamamlamadı. Yeni güvenlik assertion'ları bilinen kusurları ürün acceptance'ı olarak açıkça kırmızı hale getirdi; daha önce yalnız araştırılan yeni-generation overwrite, stale-GC deletion ve gerçek background projection bozulması da kanıtlandı. Son genel test suite'i geçmiyor.

Neden kısmi yama yok: yalnız observation epoch veya yalnız media pre-check eklemek, C/J/E2 ve interrupted reset invariants'ını kapatmaz. Güvenli çözümün önkoşulları aynı anda karşılanmalıdır: owner-death-safe ortak mutex, tüm operation başlangıçlarına taşınan ticket, bütün yayın/silme yollarının aynı gate'e katılması, UI/main/background reset-journal entegrasyonu ve gerçek interruption testleri. Bunlar bu çalışmada güvenli biçimde tamamlanıp doğrulanamadı. Yukarıdaki tasarım uygulanmış garanti diye sunulmuyor.

## ChatGPT Independent Review Handoff

1. Önce iki komutla kırmızı güvenlik koşullarını yeniden üretin:
   `flutter test test/durable_identity_followup_test.dart --plain-name 'reset publication acceptance'` ve
   `flutter test test/rss_lifecycle_regression_test.dart --plain-name 'reset publication acceptance C'`.
2. `test/durable_identity_followup_test.dart:495-787`: A dosya varlığını, B gerçek eski isolate'ın history initialize etmemesini, J yeni valid bytes'ın korunmasını, E2 geç gelen canlı referansın korunmasını bekler. D/E/H mevcut doğru alt davranışların pozitif kontrolleridir. Beş mevcut KNOWN identity testi ile diğer iki KNOWN P0 karakterizasyonu güvenlik acceptance'ı değildir.
3. C fixture'ı `test/rss_lifecycle_regression_test.dart:305-394`, production `runBgFetch` yolunu loopback HTTP ile sürer. Test sonucu yeni cache/validator yerine eski projection'ı açıkça gösterir; native Workmanager yürütüldüğü iddia edilmiyor.
4. Üretim kökleri: `article_media_store.dart:108-135,204-220`; `article_preparation_service.dart:560-578,640-671`; `observed_article_store.dart:54-163`; `background_fetch_service.dart:253-312,398-493`; `article_cleanup_service.dart:145-166`; `feed_provider.dart:1763-1820`; `main.dart:59-64`; settings reset sırası `settings_screen.dart:911-914` (servisler `lib/services/`, provider `lib/providers/`, ekran `lib/screens/`).
5. Mutex için `observed_article_persistence_io.dart:25-38,79-125,149-211` ve Dart SDK `lib/io/file.dart:934-942` sözleşmesini inceleyin. Yeni coordinator'ı mevcut iki dakika orphan varsayımına veya process-level Dart file lock'una koşulsuz güvenerek kurmayın.
6. Uygulama öncesi sözleşme/API, journal, lock order, media/GC ve Hive boundary planı bölümler 3–9'da. V2 identity gerekmiyor; fakat bütün writer/cleanup/startup yollarının aynı protokole geçmesi gerekiyor. A/B/C/J/E2'yi yeşile çevirmeden garanti ilan etmeyin; F/G/I'nin eksik native/kill/lock-order kapsamını tamamlayın.
7. Son durum: HEAD/dal değişmedi; production protokolü eklenmedi; **576 başarılı/5 başarısız test**, temiz analyze, başarılı Linux/Android debug build, mevcut format exit 1. Ek aralıklı scheduler teardown hatası bölüm 12'de. Commit/push/merge yok; bütün önceki çalışma ve yeni kırmızı acceptance testleri çalışma ağacında.
