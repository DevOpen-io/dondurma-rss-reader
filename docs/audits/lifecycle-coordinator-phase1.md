# Dondurma RSS Reader — Lifecycle Coordinator Phase 1

## 1. Uygulanan mimari ve başlangıç durumu

Dal `main`; ilk/son HEAD `409774ee3d1a05f5a713438a16047d3a69a0cf51`. Başlangıçta önceki denetimlerin bütün commit edilmemiş ve izlenmeyen dosyaları vardı; korundu. Commit, push, merge veya history değişikliği yapılmadı.

Önce `reset-publication-protocol-audit.md` ve `durable-identity-followup.md`, mevcut store lock/epoch mekanizmaları, factoryReset sırası, media rename, background claim/publication, main initialization ve adversarial testler incelendi. Mevcut `FileObservedArticlePersistence` yaşa dayalı orphan recovery kullanıyor; yeni coordinator bu kilidi **kullanmıyor**. Archive'ın cache epoch'u ve notification subscription epoch'u da yeni lifecycle otoritesinin yerine geçirilmedi.

Bu kez çalışan bir temel uygulandı:

- Bağımsız `LifecycleCoordinator`, immutable ticket ve versioned durable journal.
- Linux için küçük C/FFI `flock(2)` mutex backend'i; lease expiry veya Dart `RandomAccessFile.lock()` fallback'i yok.
- Authorization kontrolü ve callback aynı publication mutex'i altında.
- Pending reset, sıralı/idempotent stage acknowledgement ve explicit recovery API'si.
- Gerçek file IO, isolate ve process termination kullanan **24 başarılı coordinator testi**.

**Entegrasyon yok:** ArticleMediaStore, ArticlePreparationService, ObservedArticleStore, BackgroundFetchService, factoryReset, startup, UI ve production writer'ları bu sınıfa bağlanmadı. Durable Identity V2 veya bookmark/read şeması değiştirilmedi. Uygulama genelindeki beş reset-publication acceptance testi bu fazda hâlâ kırmızıdır.

## 2. Oluşturulan ve değiştirilen dosyalar

Bu faz yalnız aşağıdaki yeni dosyaları ekledi; mevcut kaynak/test dosyalarında düzenleme yapılmadı. Not: çalışma ağacında bu fazdan önceki, commit edilmemiş 27 değişiklik ayrıca bulunuyor (incremental refresh, source-local identity); bunlar bu fazın kapsamı değildir (bkz. §11):

```text
lib/services/lifecycle_coordinator.dart
lib/services/lifecycle_mutex.dart
native/lifecycle/lifecycle_mutex.c
native/lifecycle/README.md
test/lifecycle_coordinator_test.dart
test/support/lifecycle_worker.dart
docs/audits/lifecycle-coordinator-phase1.md
```

Önemli konumlar:

- Ticket/reset/state ve strict decode: `lib/services/lifecycle_coordinator.dart:8-176`.
- Coordinator construction, mutex scope, non-reentrancy: aynı dosya `183-255`.
- Atomic replace, bootstrap, initialized marker: `257-334`.
- Public ticket/publication/reset/recovery API'leri: `336-460`.
- Native ABI/FFI ve finalizable handle: `lib/services/lifecycle_mutex.dart:7-119`.
- Gerçek OS lock ve directory fsync: `native/lifecycle/lifecycle_mutex.c:12-56`.
- Ana testler: `test/lifecycle_coordinator_test.dart:100-774`; process/isolate helper: `test/support/lifecycle_worker.dart:8-121`.

Yeni Dart dependency eklenmedi. `ffi`/`win32` mevcut lockfile'da transitif olsa da bu implementasyon yalnız SDK `dart:ffi` kullanır; allocation/free işlemleri küçük helper ABI'sinde tanımlıdır. Mevcut Flutter runner/CMake/Gradle/release dosyaları değiştirilmedi.

## 3. Ticket ve journal API'leri

```dart
final coordinator = LifecycleCoordinator(
  directory: dedicatedLifecycleDirectory,
  nativeLibraryPath: explicitlyBuiltLinuxLibrary,
);
final ticket = await coordinator.beginWork();
// Input snapshot, HTTP/extraction burada; kilit tutulmaz.
await coordinator.withPublication(ticket, () async {
  // İleride yalnız await edilen, bounded publication işlemleri.
});
```

### API sözleşmesi

- `initialize()`: var olan state'i doğrular; yalnız ilk bootstrap'ta yeni journal oluşturur. Pending reseti temizlemez veya görmezden gelmez.
- `beginWork()`: operation başlangıcında immutable `LifecycleTicket` verir. Pending reset varsa `LifecycleResetPending` ile reddeder.
- `withPublication(ticket, action)`: **kilit edinildikten sonra** storage incarnation, reset epoch ve pending flag'i diskten doğrular. Stale ticket'ta callback çalışmaz. Callback'in döndürdüğü future bitene kadar kilit tutulur.
- `beginReset(cleanupStages: ...)`: eski ticket'ları geçersiz kılan yeni epoch ve reset ID üretir, `resetPending=true` yazar, immutable `LifecycleReset` döndürür. Zaten pending reset varsa ikinci reset başlatmaz.
- `performCleanupStage(reset, stage, action)`: doğru reset handle'ı ve kayıtlı stage sırasını kontrol eder. Daha önce acknowledge edilmiş stage callback'i tekrar çalıştırmaz. Başarılı action sonrası stage journal'a yazılır.
- `completeReset(reset)`: bütün required stage'ler acknowledge edilmeden pending flag'i kaldıramaz. Aynı tamamlanmış handle için idempotenttir; eski lifecycle handle'ı yeni reset döneminde reddedilir. Tamamlanma epoch nonce'unu yeniler: pending sırasında gözlenen ticket'lar (reset handle'ınınki dahil) sonrasında stale'dir (§11).
- `recoverPendingReset(cleanupStages: handlers)`: recorded plan'ın her stage'i için callback ister (fazlası yok sayılır); eksik planla hiçbir callback çalıştırmaz. Tamamlanmış stage'leri atlar, kalanları sırayla uygular, sonra pending flag'ini kaldırır.

Ticket `storageId/resetEpoch` taşır; `toJson/fromJson` isolate/process sınırında aktarım için vardır. Bu değerler secret/security credential değil, fencing token'dır. Coordinator, çağıranın HTTP'yi ne zaman başlattığını göremez: **eski HTTP cevabından sonra fresh ticket edinmek yetki değildir**. Phase 2 aynı operation-start ticket'ını kuyruk boyunca taşımak zorundadır.

### Journal alanları

```text
schemaVersion = 1
storageId                    # bootstrap incarnation, 256-bit secure nonce
resetEpoch                   # storageId:resetSequence:secureNonce
resetSequence                # kalıcı monoton sayaç
resetId                      # ilk bootstrap dışında secure nonce
resetPending
requiredCleanupStages
completedCleanupStages
```

Sequence, aynı incarnation içindeki resetlerde epoch tekrarını önler; secure nonce farklı bootstrap/root incarnation'larını ayırır. Saat kullanılarak epoch oluşturulmaz. Sequence exhaustion fail-closed'dur.

Stage isimleri sınırlı ASCII isimlerdir, plan en fazla 128 stage'dir; completed listesi required listenin sıralı prefix'i olmak zorundadır. State listeleri değiştirilemez. Foreign schema, bozuk JSON, hatalı tip, duplicate/unknown/out-of-order stage veya tutarsız reset state'i `LifecycleJournalException` verir. Parse error'da boş state'e dönüş yoktur.

## 4. Mutex seçimi ve platform garantileri

### Neden küçük C helper?

Linux `flock(2)` lock'u **open-file description**'a bağlar. Her acquisition ayrı `open()` yaptığı için aynı process'in iki Dart isolate'ı/Flutter engine'i de aynı inode üzerinde çakışan lock alır. Bu, Dart `RandomAccessFile.lock()` için belgelenmiş process-scoped POSIX lock davranışından farklıdır.

İncelenen birincil kaynak: yerel `man 2 flock` (Linux man-pages 6.13). Açıkça ayrı `open()` descriptor'larının aynı process içinde bağımsız sayıldığını ve lock'un bütün duplicate descriptor'lar kapandığında bırakıldığını belirtir. Yeni kod duplicate descriptor üretmez; `O_CLOEXEC` kullanır.

C katmanı:

- `open(O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600)`.
- `flock(LOCK_EX | LOCK_NB)`.
- Contention durumunda Dart async retry; timeout **bekleyeni reddeder**, sahibin lock'unu çalmaz.
- Normal release: awaited `finally` içinde `close(fd)`.
- Process ölümü: kernel fd'yi kapatır; owner-age kontrolü veya orphan tahmini gerekmez.
- Kalıcı `publication.lock` dosyası asla silinmez/değiştirilmez. Inode'u değiştirmek mutex'i ikiye böler.

### Kanıtlanan platform kapsamı

- Linux x86_64: aynı process içinde **dört gerçek Dart isolate**, ayrı Dart process, SIGKILL, mutex contention ve aynı path'te çoklu coordinator test edildi.
- Gerçek multi-engine Flutter embedding testi **yapılmadı**. Ayrı native open description modeli engine-local Dart state'e dayanmaz; bu OS tasarım özelliği ile gerçek multi-engine test sonucu karıştırılmamalıdır.
- Android, iOS, macOS, Windows backend/packaging **bu fazda yok**. Dart binding Linux dışındaki platformlarda açık `UnsupportedError` verir. Linux sonuçlarından bu platformların güvenli olduğu çıkarılmıyor.
- `.so` dosyası uygulamaya henüz paketlenmiyor; constructor explicit `nativeLibraryPath` ister. Yanlış/missing ABI/library'de fallback yoktur. Native helper testlerde `cc -shared -fPIC -Wall -Wextra -Werror` ile geçici dizinde derlenir; binary commit edilmedi.

### Isolate owner death sınırı

`LifecycleMutexHandle implements Finalizable`; C `void(void*)` destructor'ı `NativeFinalizer`'a bağlıdır. Await edilen kritik bölüm boyunca handle canlı tutulur. Bu VM'de same-process isolate immediate kill sonrası sonraki acquire başarılı oldu.

Ancak Dart SDK yalnız isolate-**group** kapanışına kadar native finalization garantisi verir; tek isolate ölümü için bounded latency sözü yoktur. Finalization gecikirse descriptor kilitli kalabilir; diğer caller timeout ile **fail closed** olur, lock çalınmaz. Bu availability sınırı gizlenmedi. Process SIGKILL sonrası kernel release ayrı testle doğrulandı ve finalizer'ın zamanında çalışmasına bağlı değildir.

### Varsayımlar

Trusted application-private directory; bütün participating writer'lar aynı protokole uyar; local Linux filesystem `flock`, same-directory atomic rename ve directory fsync semantiğini sağlar. NFS/SMB, kötü niyetli aynı-user writer, dışarıdan mutex inode replacement, valid journal rollback ve gerçek hardware power-loss fault injection doğrulanmadı. Mutex advisory'dir; protokolü kullanmayan mevcut app writer'larını kendiliğinden engellemez.

## 5. Lock sırası ve deadlock analizi

Phase 1 yalnız bir native publication mutex'i edinir. Callback içinde herhangi bir coordinator API'sinin yeniden çağrılması, başka instance/root üzerinden olsa dahi, Zone guard ile hemen `StateError` verir. Böylece aynı non-reentrant mutex'i tekrar acquire etme ve root'lar arası ABBA modeli önlenir.

İleride önerilen sıra:

```text
lifecycle publication mutex
  archive VEYA observation store lock
  bounded media/Hive publication
```

Callback, başka bir coordinator acquisition'ını gerektiren kuyruk/isolate RPC'sinin tamamlanmasını beklememeli. Native `flock` kendisi deadlock detection sağlamaz; yanlış caller bağımlılıklarını mutex çözemez. `lockTimeout` yalnız acquisition bekleyişini sınırlar; action'ı zaman aşımında arka planda bırakıp kilidi serbest bırakmaz.

HTTP, extraction, host pacing ve kullanıcı etkileşimi callback dışında kalmalıdır. Callback'teki bütün yan etkiler await edilmelidir; fire-and-forget iş coordinator'ın garantisi altında sayılmaz. Phase 2 iç store adaptörleri aynı coordinator'ı recursive edinmek yerine açık publication permit/locked internal API kullanmalıdır.

## 6. Crash ve restart davranışı

### Atomic journal publication

Journal aynı directory'de exclusive oluşturulmuş benzersiz temp dosyaya yazılır, flush edilir, rename ile değiştirilir ve directory `fsync` edilir. Yeni oluşturulmuş directory zincirinin parent entry'leri de sync edilir. Linux dışında atomic replace semantiği varsayılmadığından backend açık değildir.

`initialized` marker storage incarnation'ını tutar. Daha önce acknowledge edilmiş journal kaybolmuşsa bootstrap'a dönülmez. Journal rename edilmiş fakat ilk marker henüz yazılmamışsa restart aynı journal'ı benimser; epoch yenilenmez. Mevcut legacy Hive/archive/media dosyalarına dokunulmaz.

Process ölümü sonrası kalan `.tmp-*` journal dosyaları authoritative state olarak **adopt edilmez**. Bu faz bunları otomatik silmez; bounded orphan housekeeping ileride aynı mutex altında eklenebilir. Corrupt journal'da temp içinden en yeni timestamp seçilerek kişisel state tahmin edilmez.

### Recovery semantiği

Action bittikten sonra, stage acknowledgement'tan önce process ölürse action tekrar çalışabilir. Sözleşme **at least once**; callback idempotent olmalıdır. Complete stage prefix'i durable olduğunda tekrar çalıştırılmaz. Pending state normal publication'ı kapatır.

Journal rename öncesi kesinti: önceki committed state geçerlidir; henüz cleanup başlamamış resetin kaydedilmemiş intent'i yeni epoch diye kabul edilmez. Rename sonrası directory sync hatası gibi IO sonuçları caller için belirsiz olabilir; coordinator exception verir, sonraki caller journal'ı tekrar kilit altında okur. Action replay'i/acknowledgement bu yüzden idempotent tasarlanmıştır.

Gerçek child process `exit(73)` ile cleanup action sonrası/ack öncesinde; `exit(74)` ile journal temp flush sonrası/rename öncesinde sonlandırıldı. Ayrı SIGKILL testi aktif publication sırasında çalıştı. Bunlar process interruption kanıtıdır; elektrik kesintisi/hardware flush testi değildir.

**Tam app recovery uygulanmadı:** `main`, `factoryReset` ve background girişleri hâlâ eski akışta. Bu faz yalnız journal state machine ve callback arayüzünü sağlar.

## 7. Deterministik test kanıtı

`flutter test test/lifecycle_coordinator_test.dart`: **24 başarılı, 0 başarısız, Linux'ta 0 skipped**.

Red/green kanıtı: corruption testine `schemaVersion: 1.0` girdisi eklendiğinde yeni implementasyonun numeric equality nedeniyle ticket verdiği görüldü (`Expected: throws LifecycleJournalException / emitted LifecycleTicket`). Journal ve ticket version alanlarına strict integer kontrolü eklendi; aynı test ve son 24-test koşusu yeşil. Bu yeni modül içindeki hardening'dir; mevcut beş app acceptance testinin düzeldiği anlamına gelmez.

İstenen senaryoların eşlemesi:

1. Çoklu isolate publication: `four real isolates serialize publication over the same storage path` (`399-458`). Parent kritik bölümünü tutar; dört worker'ın contention sinyali alınır; bariyer bırakılır; 48 read-modify-write sonucu tam 48'dir.
2. Eski ticket reddi: `stale ticket is rejected after epoch change...` (`119-157`). Callback'in çağrılmadığı ayrıca assert edilir; pending döneminin kendi epoch ticket'ı da publication yapamaz.
3. Yeni ticket kabulü: aynı test ve `reset wins first...` (`198-217`).
4. Publication önce bitiş: `publication owns mutex until its awaited action ends...` (`158-197`). Reset contention sinyali alınmadan owner bırakılmaz.
5. Reset önce bitiş: `reset wins first; callback cannot publish...`.
6. Ardışık resetler: 12 reset, eski bütün ticket'ların ve ilk reset handle'ının reddi (`218-247`).
7. Corruption: malformed/foreign/inconsistent journal ve kaybolmuş acknowledged journal (`248-288`). Bytes'ın otomatik değiştirilmediği doğrulanır.
8. Pending reset restart: acknowledged archive stage atlanır, media bir kez çalışır, tekrar recovery callback'leri çağırmaz (`289-329`).
9. Kesilmiş journal update: exception injection (`359-382`) ve gerçek process exit-before-rename (`581-603`).
10. Owner death: SIGKILL (`489-505`), immediate isolate kill (`506-539`) ve cleanup içinde process exit (`540-580`).
11. Concurrent reset/publication ve non-reentrancy: mutex-order testleri, nested-call rejection (`383-398`), sekiz eşzamanlı reset caller'ından yalnız birinin pending reset açması (`755-774`).
12. Aynı storage path'te çoklu instance: bu testlerin tamamında farklı instance'lar; ayrıca symlink alias canonicalization (`734-754`).

Ek kontroller: başka storage domain'inin ticket'ı reddedilir; eski lock-file mtime canlı owner'ı çaldırmaz; bounded/ordered cleanup ve completed reset replay'i yeni veriyi silemez; mutex symlink'i yabancı dosyaya yazamaz.

Reproduction için keyfi sleep yok. Yarış sırası Completer, port veya stdin/stdout handshake ile belirlenir. Mutex'in async retry interval'i ve fail-closed acquisition timeout'u algoritmanın parçasıdır; test yarışı yakalamak için uyku değildir.

## 8. Kalan sınırlamalar

- Linux backend ve test library dışında native deployment/packaging tamamlanmadı. Diğer platformlar açıkça disabled.
- Native finalizer'ın tek isolate ölümü sonrası gecikmesi availability kaybı yaratabilir; safety uğruna timeout/closed gate korunur.
- Her callback'i idempotent yapmak ve bütün IO'yu await etmek caller sorumluluğudur. Exactly-once cleanup veya callback'in kendi içindeki multi-file atomicity garantisi yoktur.
- Journal rollback/hostile external file replacement ve network filesystem desteklenmiyor.
- Uncommitted temp journal orphan'ları kalabilir; authoritative state'e yükseltilmez.
- Native multi-engine, mobil cihaz, Windows/macOS/iOS, hardware power-loss ve performance benchmark test edilmedi.
- Uygulamanın beş P0/reset-publication acceptance hatası ve durable identity/read çakışmaları aynen duruyor. Bu faz bunları düzelttiğini iddia etmez.

## 9. Tam doğrulama sonuçları

> İlk teslimin sonuçlarıdır; güncel sayılar için §11'e bakın.

Komutlar:

```bash
flutter analyze
flutter test test/lifecycle_coordinator_test.dart
flutter test test/s2_storage_foundation_test.dart test/s3_preparation_engine_test.dart test/s4_temp_cache_selection_test.dart test/s5_cleanup_lifecycle_test.dart test/observed_article_store_test.dart
flutter test
# Scheduler teardown araştırması: aynı komut üç ayrı kez
flutter test test/incremental_refresh_scheduler_test.dart
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

Sonuçlar:

- `flutter analyze`: **No issues found!**, exit 0.
- Yeni coordinator: **24/24**, exit 0. Önceki geliştirme koşuları da 18 ve 23 testle yeşildi; son kapsam 24'tür.
- İlgili mevcut beş store dosyası: **135/135**, exit 0.
- İlk genel suite: **600 başarılı, 5 başarısız**, exit 1. Beş hata mevcut A, B, C, E2, J reset-publication acceptance testleri.
- Son genel suite (strict schema-version hardening sonrası): **599 başarılı, 6 başarısız**, exit 1. Aynı beş acceptance'a scheduler'ın `all sources finish before timer; canceled callback cannot republish` teardown hatası eklendi. Hiçbir assertion silinmedi, rewrite/skip yapılmadı.
- `git diff --check`: başarılı.
- Bu fazda Flutter app build istenmedi/çalıştırılmadı. Native C helper Linux'ta warning-as-error ile her coordinator test koşusunda derlendi. Bu bir Android/iOS/desktop app deployment testi değildir.

### Scheduler teardown araştırması

Üç ayrı hedefli koşunun her biri **10 başarılı / 1 başarısız** verdi:

- Koşu 1: `queued second pass cannot be overwritten by first batch callback`.
- Koşu 2: `all sources finish before timer; canceled callback cannot republish`.
- Koşu 3: yine queued-pass testi.

Üçünde de failure assertion'dan değil `test/incremental_refresh_scheduler_test.dart:147` içindeki recursive temp directory delete'ten geliyor:

```text
FileSystemException: Deletion failed ... Directory not empty (errno = 39)
```

İlk genel suite'te bu teardown failure oluşmadı; son genel suite'te aynı directory-delete failure `all sources finish before timer; canceled callback cannot republish` testine bağlandı. Hata **timing'e duyarlı bir flake**'tir; 2026-10-26 review'unda üç hedefli koşu ve iki tam suite'te tekrar etmedi (§11). Fixture önce provider dispose/Hive close yapıp directory siler; `ArticlePreparationService.dispose()` yalnız client kapatır ve FeedProvider'da awaited olmayan cleanup/status işleri bulunur. Bunlar inceleme adayıdır; hangi writer'ın delete ile yarıştığı deterministik olarak izole edilmedi. Sonradan ilgili temp dizinlerde kalıcı dosya kalmadığı gözlendi; geçici sidecar/guard etkinliği olasılığı kanıtlanmış root cause diye sunulmuyor. Bu sistemde refactor veya retry/sleep yaması yapılmadı.

### Format kontrolü

Genel format kontrolü exit 1; önceki aynı 13 ilgisiz dosya. `--output=none` bunları yazmadı. Yeni dört Dart dosyası formatlandı.

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

Benchmark yapılmadı; 24 test yaklaşık 2 saniyede geçti ama bu production performans ölçümü değildir. Nonblocking flock + polling, contention altında starvation/fairness garantisi sağlamaz. Ağ kilit dışında kalmalı; callback IO ve fsync süresi Phase 2'de ölçülmelidir.

## 10. Phase 2 entegrasyon gereksinimleri

1. Native helper'ı doğru ABI/architecture ile paketleyin; diğer dört native hedef için uygun backend ve owner-death/isolate/process testleri ekleyin. UnsupportedError'u sessizce unsafe lock fallback'ine çevirmeyin.
2. Ortak, kalıcı, application-private lifecycle directory seçin. Bu directory/journal/mutex, reset medya/Hive bulk silme alanlarının dışında kalmalı; mutex inode'u silinmemeli.
3. Bütün iş girişlerinde input/network **öncesi** ticket alın. Background, foreground refresh, bookmark restoration, full-text preparation, queued persistence ve GC aynı eski ticket'ı taşımalı; late callback fresh ticket almamalı.
4. Archive/history mutation, managed media rename+manifest publication, GC son reference check+delete ve Hive/cache/validator/cooldown projection'larını aynı publication sınırına bağlayın. Store iç adaptörlerinde recursive coordinator acquisition yapmayın.
5. App'in gerçek factory-reset stage planını tanımlayın; cleanup callback'leri idempotent olsun. UI reset sırası ve ayrı settings/bookmark/subscription temizliği coordinator-owned transaction planına alınmalı.
6. Main ve native background başlangıcında pending recovery, restore/fetch/provider kurulmadan önce çalışmalı. Coordinator'ın tek başına var olması otomatik startup recovery değildir.
7. Yeni dönemde eski isolate-local Hive snapshot'ını fresh ticket ile yeniden yayınlama riskini çözün; eski journal/backup restore'unda incarnation politikasını belirleyin.
8. Mevcut A/B/C/E2/J testlerini integrasyon tamamlandıktan sonra yeşile çevirin; Phase 1 için assertion'larını zayıflatmayın. Gerçek native Workmanager ve süreç kesintisi testleri ekleyin.

Değerlendirme: **Phase 1 Linux temeli uygulanmış ve test edilmiş durumda; uygulama release'i hâlâ NOT READY FOR RELEASE.** App çapında reset güvenliği, multiplatform deployment veya Durable Identity V2 tamamlanmış değildir.

## ChatGPT Independent Review Handoff

- İncelenecek temel: `lib/services/lifecycle_coordinator.dart` (özellikle `_locked`, `_load`, `_replace`, `withPublication`, reset/recovery yöntemleri), `lib/services/lifecycle_mutex.dart`, `native/lifecycle/lifecycle_mutex.c`.
- Linux mutex semantiğini `man 2 flock` ile karşılaştırın: bağımsız open descriptions, descriptor close/process death, nonblocking acquisition; yaşa dayalı ownership steal yok. `NativeFinalizer` için isolate-group guarantee ile tek-isolate bounded latency arasındaki farkı koruyun.
- `test/lifecycle_coordinator_test.dart`: 24 pozitif test. Gerçek dört isolate counter, ayrı process contention, SIGKILL, isolate immediate kill, pending cleanup exit ve pre-rename exit vardır. Helper `test/support/lifecycle_worker.dart` pure Dart'tır; testlerdeki native library geçici derlenir.
- Yeniden doğrulama: `flutter analyze`; `flutter test test/lifecycle_coordinator_test.dart`; bölüm 9'daki store komutu; `flutter test`; `git diff --check`. İlk teslimde **24/0 coordinator**, **135/0 store**, **599/6 genel**; scheduler **10/1 teardown** bildirildi. **Güncel (§11, 2026-10-26): coordinator 28/28, genel 607/5 (yalnız A/B/C/E2/J), scheduler 12/12 ×3; teardown flake tekrar etmedi.**
- Yeni coordinator'a production import/call bağlantısı yapılmadığını doğrulayın. Mevcut beş acceptance testi hâlâ gerçekten kırmızı olmalı. Phase 2 zorunlulukları bölüm 10'da; hiçbir app-wide safety garantisi çıkarılmamalı.
- HEAD `409774ee3d1a05f5a713438a16047d3a69a0cf51`, dal `main`; bütün önceki değişiklikler korunuyor. Bu fazın yedi yeni dosyası çalışma ağacında; commit/push/merge yok.

## 11. Review düzeltmeleri (2026-10-26)

Bağımsız review sonrası TDD ile (önce kırmızı test, sonra düzeltme):

1. **Pending-epoch ticket sızıntısı.** `initialize().ticket` veya `LifecycleReset.ticket` pending sırasında alınabiliyor ve `completeReset`/`recoverPendingReset` epoch'u değiştirmediği için reset sonrası geçerli oluyordu. Tamamlanma artık epoch nonce'unu yeniler (`LifecycleState._finish`); reset handle doğrulaması `storageId + resetId` ile yapılır, böylece tamamlanmış handle replay'i idempotent kalır. Test: `tickets observed while pending cannot publish after complete|recover`.
2. **Kalıcı zone guard.** Nesting bayrağı callback'in zamanladığı işlere (Timer, `.then`) miras kalıp kilit bırakıldıktan sonra meşru çağrıları reddediyordu. Zone artık `finally` içinde pasifleşen bir token taşır. Test: `work scheduled by a callback may use the coordinator after release`.
3. **Fenced no-op `applied` dönüyordu** (`ArticlePreparationService._enqueueGuarded`): mutation sırasında `resetFence` gelirse sonuç artık `rejected`; claim listener'ları reset sonrası tetiklenmez.
4. **Kesilen ilk yükleme** (`FeedProvider`): observation refresher içinde ilerlediği için cache clear ile kesilen ilk yükleme de first-load suppression'ı bitirir; yalnız factory reset sıfırlar.
5. **Legacy ID-only bookmark** `removeBookmark` ile silinemiyordu (erken `return true`); artık üyelik kaldırılır ve kalıcıdır.
6. **Legacy bookmark kaybı** (önceden de mevcut): herhangi bir snapshot kaydedildikten sonra `_loadBookmarks` yalnız JSON snapshot'larından ID üretiyor, diğer legacy ID-only üyelikleri restart'ta siliyordu. Persisted `bookmarkedItemIds` artık snapshot ID'leriyle birleştirilir.
7. **Fenced strip** (`BookmarkProvider._stripBookmarkOwner`): `rejected` sonuç artık `_claimLanded`/`sweepCleanup` tetiklemez.

8. **Stage adı rename kilidi.** Journal stage adları kalıcı sözleşmedir; önceden tam eşleşme istendiği için rename sonrası `recoverPendingReset` her açılışta reddediyor, `beginWork` kalıcı kapanıyordu. Recovery artık handler superset'ini kabul eder; yeni sürümler eski stage handler'larını tutarak pending reseti bitirebilir. Eksik handler hâlâ fail-closed. Test: `recovery accepts a newer superset plan and runs only recorded stages`.
9. **Test seam'leri** (`onContention`, `beforeJournalReplace`) `@visibleForTesting`; `meta` transitive'den direct dependency'ye alındı (yeni paket yok).

Doğrulama: `flutter analyze` temiz; coordinator **28/28**; scheduler **12/12** (3 koşu); tam suite **607 başarılı / 5 başarısız** (yalnız A, B, C, E2, J acceptance). Scheduler teardown hatası bu koşularda görülmedi; §9'daki "her koşuda 10/1" bulgusu bu ortamda tekrar etmedi.

Açık kalanlar (bu review'da değiştirilmedi): Android/diğer platform backend'i; read/status/durable record'ların hâlâ global `id` kullanması (source-local identity yarım); `AnchoredFeedList`'in primary olmayan controller'ı ve rebuild başına O(n) maliyeti; desktop/feed_provider diff'lerindeki format gürültüsü; commit ayrıştırması.
