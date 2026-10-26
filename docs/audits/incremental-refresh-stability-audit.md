# Dondurma RSS Reader — Incremental Refresh Stability Audit

> **Takip denetimi:** [Durable identity follow-up](durable-identity-followup.md).
> Arşiv/read kimliği migration'ı uygulanmadı; yanlış offline body ve global read coupling artık deterministik karakterizasyonlarla doğrulandı.
> Üç preparation lifecycle hatası düzeltildi; reset sonrası fiziksel medya ve geç background observation resurrection açıkları ayrıca kanıtlandı, henüz çözülmedi.
> Güncel sonuç: 573 genel / 198 hedefli test başarılı; 7 yeni karakterizasyon bilinen kusurları doğrular, release acceptance değildir. Analyze ve Linux/Android debug build başarılı; 13 mevcut format sorunu sürüyor.
> **NOT READY FOR RELEASE** kararı değişmedi. Aşağıdaki 557 test sonucu önceki denetimin tarihsel baseline'ıdır; güncel kanıt ve migration planı takip raporundadır.

## 1. Repository State

- Dal: `main`.
- İlk HEAD: `409774ee3d1a05f5a713438a16047d3a69a0cf51` (`docs: specify incremental feed refresh behavior`).
- Son HEAD: aynı commit. Commit, push, merge veya branch değişikliği yapılmadı.
- Flutter: **3.47.6 stable**, framework `5fc346839b`; Dart **3.13.5**.
- Ortam: Fedora Linux 44, Linux `7.2.11-200.fc44.x86_64`, x86_64, Intel Core i7-13650HX.

### Başlangıçtaki commit edilmemiş çalışma

Aşağıdaki dosyalar denetimden **önce** değiştirilmişti:

```text
.gitignore
docs/design/README.md
docs/design/specs/2026-10-24-incremental-feed-refresh-design.md
docs/development/architecture.md
docs/product/status.md
lib/providers/feed_provider.dart
lib/screens/desktop/desktop_article_list.dart
lib/screens/home_screen.dart
lib/services/feed_cache_policy.dart
lib/services/feed_refresh.dart
skills-lock.json
test/desktop_runtime_regressions_test.dart
test/feed_cache_policy_test.dart
test/rss_lifecycle_regression_test.dart
```

Başlangıçta izlenmeyen dosyalar/yollar:

```text
.claude/skills/brag
.devin/skills/brag
docs/design/plans/2026-10-24-incremental-feed-refresh.md
lib/widgets/anchored_feed_list.dart
test/anchored_feed_list_test.dart
```

Kademeli refresh ve anchored scrolling uygulaması mevcut çalışma ağacındaydı; HEAD tek başına güncel uygulamayı temsil etmiyordu. Remote branch üzerinden yeniden oluşturma yapılmadı. Mevcut çalışma üzerine hedefli düzeltmeler eklendi; ilgisiz değişiklikler geri alınmadı. `git diff HEAD` hem önceki çalışmayı hem bu denetimi içerir; bütün farklar denetime mal edilmemelidir.

### İncelenen uygulama haritası

- `FeedProvider`: `lib/providers/feed_provider.dart`.
- `FeedRefresher`: `lib/services/feed_refresh.dart`.
- Cache politikası: `lib/services/feed_cache_policy.dart`.
- Mobil liste: `lib/screens/home_screen.dart`, `lib/widgets/feed_list_item.dart`.
- Masaüstü liste/seçim/okuyucu: `lib/screens/desktop/desktop_article_list.dart`, `desktop_home_screen.dart`, `desktop_reader_pane.dart`.
- Anchor: `lib/widgets/anchored_feed_list.dart`.
- Tarihler: `lib/services/feed_date_groups.dart`.
- Kimlik: `lib/models/feed_item.dart`, `lib/services/article_identity.dart`.
- Yer imi: `lib/providers/bookmark_provider.dart`.
- Kalıcı kayıt/gözlem: `lib/services/article_record_store.dart`, `observed_article_store.dart`.
- Arka plan/üyelik: `lib/services/background_fetch_service.dart`, `temp_cache_membership.dart`.
- HTTP/backoff/pacing, preparation ve ilgili testler de çapraz kontrol edildi.

İlk dar baseline komutu (`anchored_feed_list`, `feed_cache_policy`, `timestamp_correctness`): **26 başarılı test**. Bu, performans baseline'ı değildir.

## 2. Executive Summary

Düzeltmeler; reset/dispose güvenliği, gözlem geçmişi, kaynak-yerel makale kimliği, yer imi korunması, mobil/masaüstü seçim, değişken yükseklikte anchor ve yerel takvim sınırlarına odaklandı. Mevcut 100 ms batching, beş fetch sınırı, refresh coalescing, lazy sliver yapısı ve nihai cache commit politikası korundu.

Önemli sonuçlar:

1. Fabrika resetinden sonra eski fetch'in gözlem geçmişini yeniden oluşturması deterministik testle doğrulandı ve düzeltildi.
2. Cache temizleme/reset depolamayı beklerken dispose edilince oluşan `ChangeNotifier` hataları doğrulandı ve düzeltildi.
3. Aynı GUID'yi kullanan farklı feed'lerin yer imleri artık birbirini silmiyor; liste birleştirme ve linksiz makale filtreleme kaynak kimliğini koruyor.
4. Aynı satır kimlikleriyle yükseklik, genişlik veya metin ölçeği değişince anchor yeniden yakalanıyor.
5. Gece yarısını aşan küçük gelecek sapması, DST ve kaynaklar arası sıralama eşitlikleri düzeltildi.

Son doğrulama: **557/557 test başarılı**, hedefli koşuda **91/91**, New York timezone koşusunda **20/20**. Analyze temiz. Linux ve Android debug build başarılı. Ancak tüm depo format kontrolü, denetimde değiştirilmemiş 13 dosyanın mevcut biçimi nedeniyle başarısız.

**Tamamlanmamış sınır:** kalıcı arşiv/medya üyeliği ve okundu durumu hâlâ legacy global ID kullanıyor. Bu denetim Hive/equality migration'ı yapmadı. Aynı ID'li farklı makalelerin bağımsız kalıcı gövde/sahiplik gereksinimi bütünüyle çözülmüş değildir. Ayrıca refresh kesilirse henüz nihai commit yapılmamış başarılı yanıtlar kaybolabilir.

## 3. Confirmed Bugs

### B1 — Reset sonrası eski refresh gözlem geçmişini geri yazıyor

- **Önem:** P0, silinen kişisel metadata'nın yeniden oluşması.
- **Konum:** `FeedRefresher.refresh`, `ObservedArticleStore.claimFeedBatch`; provider apply fence tek başına yeterli değildi.
- **Kök neden:** HTTP işleri bittikten sonra observation claim'leri provider generation kontrolünden bağımsız çalışıyordu. Reset geçmişi siliyor, gecikmiş fetch daha sonra aynı namespace'i tekrar initialize ediyordu.
- **Üretim:** iki kontrollü istek beklerken `factoryReset()`; reset bittikten sonra eski istekleri tamamla. Sonraki claim'in namespace'i yeni initialize etmesi gerekirken mevcut bulması.
- **Düzeltme:** provider, reset generation ve canlı subscription epoch kontrolünü `canObserve` ile geçiriyor. Store, `claimCheck` kontrolünü kilit içinde, disk okumasından sonra yapıyor. Kilit öncesi tek kontrolle yetinilmiyor. Cache temizleme observation'ı geçersiz kılmıyor; gözlem geçmişinin cache'ten bağımsızlığı korunuyor.
- **Kaynak:** `lib/providers/feed_provider.dart:1211-1223`, `lib/services/feed_refresh.dart:94-105,277-294`, `lib/services/observed_article_store.dart:54-79`.
- **Test:** `test/incremental_refresh_scheduler_test.dart:241-266`; `test/observed_article_store_test.dart:49-72`. İlk test düzeltme öncesinde `Expected: true / Actual: false` ile başarısızdı.

### B2 — Reset/cache clear sırasında dispose, son notify'da hata veriyor

- **Önem:** P0, yaşam döngüsü exception'ı.
- **Konum:** `FeedProvider.clearCache`, `factoryReset`.
- **Kök neden:** async depolama işlemlerinden sonraki `notifyListeners()` dispose kontrolü taşımıyordu.
- **Üretim:** temizliği başlat; ilk await sırasında provider'ı dispose et; depolama işlemlerini tamamla.
- **Düzeltme:** son bildirimler `_disposed` ile korunuyor. Filtre invalidation microtask'ı da korunuyor. Dispose, cache/refresh generation'larını artırıyor. Refresh initialization sonrası dispose kontrolü ve final async aşamalar arasında geçerlilik kontrolleri eklendi.
- **Kaynak:** `lib/providers/feed_provider.dart:475-481,1095-1103,1309-1338,1703-1834`.
- **Test:** `test/incremental_refresh_scheduler_test.dart:268-285`. Her iki varyant düzeltme öncesinde `A FeedProvider was used after being disposed.` ile başarısızdı.

### B3 — Aynı ID'li farklı feed yer imleri düşüyor veya birbirini kaldırıyor

- **Önem:** P1, yer iminin kaybolması/yanlış öğenin kaldırılması.
- **Konum:** `FeedCachePolicy.mergeVisibleFeeds`, `BookmarkProvider.toggleBookmark/removeBookmark`, background snapshot ekleme.
- **Kök neden:** normal öğeler composite kimlikle işlenirken yer imi ekleme, toggle ve removal yalnız `id` kullanıyordu.
- **Üretim:** A/B feed'lerinde aynı GUID; A aboneliğini kaldır; A'nın yer imini B yenilenirken birleştir. İkinci senaryo: A ve B'yi ayrı ayrı kaydet.
- **Düzeltme:** görünür instance ve tam JSON yer imi işlemleri `(feedUrl,id)` kullanıyor. Legacy ID kümesi herhangi bir kaynak hâlâ kayıtlıysa korunuyor. O(1) kaynak üyeliği indeksi eklendi. İkinci kaynağın kaydı global ID kümesini değiştirmese de provider filtre cache'i invalid ediliyor. UI bookmark kontrolüne feed URL geçiriliyor. Background bookmark ekleme composite kimlik kullanıyor.
- **Kaynak:** `lib/services/feed_cache_policy.dart:9-32`; `lib/providers/bookmark_provider.dart:14-25,198-310`; `lib/providers/feed_provider.dart:423-447,804-815`; `lib/services/background_fetch_service.dart:466-479`.
- **Test:** `test/feed_cache_policy_test.dart:56-79`; `test/rss_lifecycle_regression_test.dart:222-248`; `test/incremental_refresh_scheduler_test.dart:287-323`.
- **Kanıt:** ilk merge testi eksik `(removed,shared-guid)` kaydıyla; toggle/restart testi boş listeyle başarısızdı. Restart testi Hive JSON snapshot'larını doğrular; ayrı kalıcı arşiv gövdelerinin ayrıştırıldığını **kanıtlamaz** (bölüm 10).

### B4 — Linksiz farklı makaleler GUID fallback dedup'ında birleşiyor

- **Önem:** P1, görünür makale kaybı.
- **Konum:** `deduplicateByLink`.
- **Kök neden:** GUID'lerin global benzersiz olduğu varsayılmıştı. Geçersiz/boş link durumunda farklı kaynakların aynı GUID'si aynı dedup anahtarını üretiyordu.
- **Düzeltme:** kullanılabilir HTTP(S) linkleri hâlâ global tekilleştiriliyor; linksiz/geçersiz linkli instance fallback'i `(feedUrl,id)`. Legacy offline-membership `dedupeKey` API'si değiştirilmedi.
- **Kaynak:** `lib/services/feed_list_filter.dart:66-93`.
- **Test:** `test/incremental_refresh_scheduler_test.dart:287-323`. Düzeltmeden önce beklenen iki görünür/kayıtlı kaynak yerine bir kaynak vardı. Aynı gerçek URL'nin normal görünümde tek gösterilmesi korunuyor.

### B5 — Mobil/masaüstü seçim farklı kaynağın aynı ID'sine gidiyor

- **Önem:** P1, yanlış makalenin açılması/seçilmesi.
- **Kök neden:** mobile navigation window, desktop shell çözümleme ve ok tuşu seçimi `id` bazlıydı. `ensureVisible` callback'i seçimden sonra değişebilen index'i tekrar okuyordu.
- **Düzeltme:** mobil pencere ve desktop shell composite kimlik kullanıyor. Pane'e geriye uyumlu optional `selectedFeedUrl` eklendi. Post-frame callback row kimliğini yakalıyor; güncel index'i yeniden yorumlamıyor. Reader key'leri ve seçili öğe değişim kontrolü de kaynak içeriyor.
- **Kaynak:** `lib/widgets/feed_list_item.dart:39-46`; `lib/screens/desktop/desktop_article_list.dart:33-38,84-118,345-354`; `desktop_home_screen.dart:77,112-140,160-166,224-231,303-307`; `desktop_reader_pane.dart:53-62,197-211` (son iki yol `lib/screens/desktop/` altında).
- **Test:** `test/desktop_runtime_regressions_test.dart:118-159`; `test/s1_a11y_consistency_test.dart:369-375`. Linux varyantı, aynı GUID'den sonraki satıra ArrowDown ve geri ArrowUp seçimini doğrular.

### B6 — Aynı row ID'leriyle yükseklik değişince anchor kayıyor

- **Önem:** P1, okuma konumunun kayması.
- **Kök neden:** `didUpdateWidget`, ID listesi eşitse erken dönüyordu. Yeni başlık/yükseklik veya geometri değişimi anchor yakalamıyordu.
- **Üretim:** 100 px satırlarla 1050 px kaydır; ID'leri değiştirmeden yüksekliği 160 px yap.
- **Düzeltme:** anchor yakalama ayrı metoda alındı; widget güncellemelerinde ve viewport/metin ölçeği dependency değişimlerinde çalışıyor. Eski layout geometrisi yeni layout'tan önce ölçülüyor. Detached viewport ve sonlu olmayan yükseklikler de reddediliyor.
- **Kaynak:** `lib/widgets/anchored_feed_list.dart:70-143`.
- **Test:** `test/anchored_feed_list_test.dart:250-335`; yükseklik testi düzeltme öncesinde başarısız, sonrasında başarılı. Genişlik 800'den 390'a, text scale 1'den 1.4'e değişirken ilk görünür satır korunuyor.

### B7 — Gelecek gün, DST ve sıralama eşitlikleri

- **Önem:** P2, yanlış tarih grubu/kararsız kaynak sıralaması.
- **Kök neden:** 23:50'de ertesi gün 00:05 tarihli, tolerans içindeki öğe hiçbir gün grubuna uymayıp `older` oluyordu. `Duration(days:1)` DST'de önceki takvim gününü garanti etmiyordu. Eşit ID ve tarihte kaynak tie-break yoktu.
- **Düzeltme:** tolerans içindeki gelecek instant `today`; dün yerel `DateTime(year,month,day-1)` ile hesaplanıyor; sıralama tarih, ID, feed URL kullanıyor. Orijinal `pubDate` değişmiyor, 30 dakika politikası korunuyor.
- **Kaynak:** `lib/services/feed_date_groups.dart:38-101`.
- **Test:** `test/timestamp_correctness_test.dart:151-196`; `TZ=America/New_York` ile 25 saatlik ve 23 saatlik günler ayrıca çalıştırıldı. İlk gelecek/DST/tie-break testleri düzeltmeden önce başarısızdı.

### B8 — Full-text composite anahtarının ayraç çakışması; bookmark-only gövde kaybı

- **Önem:** P2 kimlik eşleştirmesi; P1 görünür offline gövde kaybı.
- **Kök neden:** tam metin eşleştirme anahtarı boşlukla birleştirilmiş String idi. Ayrıca aynı makalenin tek full-text kopyası bookmark snapshot'ındaysa yeni HTTP 200 instance'ına aktarılmıyordu.
- **Düzeltme:** tuple map anahtarı; görünür merge sonunda yer imindeki eksik full-text kopyası da aktarılıyor. Fresh öğede zaten gövde varsa üzerine yazılmıyor.
- **Kaynak:** `lib/services/feed_cache_policy.dart:26-32,68-89`.
- **Test:** `test/feed_cache_policy_test.dart:81-103` ve mevcut carry-over testleri. Ayraç testi düzeltmeden önce `Actual: 'wrong body'` veriyordu. Bu test saf helper'ın çakışmasını kanıtlar; aynı girdilerin gerçek bir geçerli abonelik URL'sinden geldiği iddia edilmiyor.

### B9 — Background merge duplicate feed/item girdilerini çoğaltıyor

- **Önem:** P2, redundant snapshot kayıtları.
- **Kök neden:** `mergeFreshFeeds` tekrarlanan abonelik URL'sini tekrar açıyor; feed içi duplicate GUID'ler foreground görünür merge dışında elenmiyordu.
- **Düzeltme:** abonelik URL'leri küme; çıktı `(feedUrl,id)` ile tekilleştirilmiş. Farklı kaynakların aynı ID'li öğeleri korunuyor.
- **Kaynak:** `lib/services/feed_cache_policy.dart:36-63`.
- **Test:** `test/feed_cache_policy_test.dart:105-121`.

## 4. Investigated but Unconfirmed Risks

- **Normal Timer'ın final veriyi ezmesi:** başlangıç kodunda zaten `finally` iptali ve cache/reset/dispose fence'leri vardı. Gerçek Dart Timer iptalinden sonra callback çalışması yeniden üretilemedi. Mevcut koruma yanlışlıkla kaldırılmadı. Ek savunma olarak her refresh'e generation, publication kabul bayrağı ve callback başında kontrol eklendi. Test scheduler'ı iptal edilmiş callback'i sözleşme dışı doğrudan çağırarak sonraki pass'in timer slot'unun ve verisinin bozulmadığını doğruluyor; bu, gerçek Timer'da böyle bir hata görüldüğü anlamına gelmez.
- **Post-frame `correctBy()` crash'i:** checkout'ta böyle bir çağrı yoktu. Çağrı `LayoutBuilder` layout aşamasında, viewport offset'i okumadan önce. Flutter SDK `scroll_position.dart:405-465` ve viewport correction akışı incelendi. Single-viewport bağlamı korunuyor; bunu post-frame `jumpTo` ile değiştirmek için kanıt yoktu.
- **Duplicate GlobalKey crash'i:** pane-local composite/occurrence anahtarları ve tile key'inin iç Material'a tekrar verilmemesi başlangıç çalışmasında zaten vardı. Yeni bir duplicate mount üretilemedi. Mevcut duplicate, reordering, resize, hızlı scroll testleri başarılı.
- **Fling'in bozulması:** kontrollü 16 ms frame testinde prepend sonrası aynı anchor korunuyor, sonraki frame'de hareket devam ediyor ve offset sonlu. Test düzeltme öncesinde de başarılıydı; fling için spekülatif scroll activity rewrite'ı yapılmadı.
- **304/ETag/Last-Modified, redirect, Retry-After, backoff/pacing:** HTTP fetch algoritması değiştirilmedi. Mevcut yaşam döngüsü testleri 200/304/failed-cache koruma, canonical subscription identity, cooldown sonrası pacing recheck ve progress sayaçlarını doğruluyor. Ara publish yalnız başarılı fresh body callback'inden geliyor; skipped feed success sayılmıyor.
- **Cache generation ve enqueue fence:** `_saveChain` seri yazım ve enqueue anında generation yakalama zaten vardı; reset fence'i geçersizleştirilmedi. Yeni intermediate durable writer eklenmedi.
- **Hazırlık ve background reset sınırları:** foreground observation için kilit içi check eklendi. Workmanager isolate'ının tüm reset yarışlarını veya mevcut full-text prefetch'in bütün clear/reset/dispose interleaving'lerini doğrulayan yeni cihaz/isolate testi yapılmadı. Bunlar tamamen güvenli ilan edilmiyor.

## 5. Code Changes

### Denetimin düzenlediği kaynaklar

```text
lib/providers/bookmark_provider.dart
lib/providers/feed_provider.dart
lib/screens/desktop/desktop_article_list.dart
lib/screens/desktop/desktop_home_screen.dart
lib/screens/desktop/desktop_reader_pane.dart
lib/services/background_fetch_service.dart
lib/services/feed_cache_policy.dart
lib/services/feed_date_groups.dart
lib/services/feed_list_filter.dart
lib/services/feed_refresh.dart
lib/services/observed_article_store.dart
lib/widgets/anchored_feed_list.dart  # başlangıçta zaten izlenmeyen dosya
lib/widgets/feed_list_item.dart
```

Düzenlenen testler:

```text
test/anchored_feed_list_test.dart  # başlangıçta zaten izlenmeyen dosya
test/desktop_runtime_regressions_test.dart
test/feed_cache_policy_test.dart
test/observed_article_store_test.dart
test/perf_baseline_test.dart
test/rss_lifecycle_regression_test.dart
test/s1_a11y_consistency_test.dart
test/timestamp_correctness_test.dart
```

Yeni dosyalar: `test/incremental_refresh_scheduler_test.dart`, bu rapor.

Test seam'leri: `FeedProvider` constructor'ı kontrollü `FeedService` ve batching scheduler kabul ediyor. Varsayılanlar mevcut servis ve `Timer.new`. Provider servis ömrünü dispose ile sonlandırmaya devam ediyor. Test scheduler'ı 100 ms isteğini, tek aktif timer'ı ve iptalleri kontrol ediyor; yeni scheduler testleri keyfi sleep kullanmıyor.

Yeni paket/dependency, Hive key, schema migration veya `FeedItem.operator ==/hashCode` değişikliği yok. Lokalizasyon kaynakları, OPML, backup ve release workflow'ları değiştirilmedi. Material 3 stilleri ve görsel ölçüler değiştirilmedi. Bazı düzenlenen dosyalardaki mevcut satırlar `dart format` tarafından yeniden biçimlendirildi.

## 6. Scroll Architecture Review

- Tek `CustomScrollView`, merkezden önce ters indeksli ve merkezden sonra ileri indeksli iki lazy `SliverList` var.
- `center: _centerKey`, **uygun merkez SliverList'in** key'i; makale satırının key'i değil.
- Anchor, eski görünümde kalan ve yeni kimlik kümesinde bulunan ilk görünür makale. Header/footer aday değil. Kısmen görünen ilk makale de geçerli anchor.
- `GlobalKey.currentContext` senkron okunuyor; detached/unlaid-out row atlanıyor. `localToGlobal` sonucunda NaN/Infinity reddediliyor. Historical keep-alive NaN regresyonu başarılı.
- `correctBy()` `LayoutBuilder` sırasında tek viewport'tan önce uygulanıyor; post-frame correction yok. Bekleyen correction bir kez tüketiliyor. Normal drag/ballistic activity elle durdurulmuyor.
- Anahtarlar `(feedUrl,id,occurrence)`; pane başına ayrı GlobalKey instance'ları. Eski kimlikler map'ten temizleniyor; reorder index anahtarıyla başka makaleye bağlanmıyor.
- ScrollController: liste dış controller'ı dispose etmiyor; kendi controller'ını dispose ediyor. Desktop Scrollbar aynı controller'a bağlı.
- Widget instance'ları topluca saklanmıyor; lazy rendering korunuyor. Mevcut virtualization testinde görünen Text sayısı 30'un altında.
- **Sınır:** key map'i ziyaret edilen ve hâlâ listede bulunan satırlar kadar büyüyebilir; görünür satır sayısıyla sınırlı değildir. İki desktop key katmanı da mevcut. Heap/GC profili yapılmadı.
- **Sınır:** widget veya MediaQuery güncellemesi olmadan yalnız descendant render yüksekliğinin değişmesi için genel bir render-level anchor garantisi eklenmedi. Üretim thumbnail'ları mobilde 72 px, desktop'ta 52 px sabit; gerçek image-load/device testi yine gerekli.
- Tüm görünür anchor'lar silinirse eski head mesafesine fallback ve layout clamp mevcut. Değişken yükseklikte bu fallback kesin piksel garantisi değildir.

## 7. Cache and Data Integrity Review

### Kimlik sözleşmesi

1. **Feed instance / satır / seçim / JSON bookmark:** `(feedUrl,id)`.
2. **Normal görünümde aynı gerçek HTTP(S) linki:** global dedup; farklı feed instance'ları ham cache'te bulunabilir, aynı gerçek makale görünümde bir kez gösterilir.
3. **Aynı feed'deki tekrarlı GUID:** merge tek instance tutar; widget occurrence discriminator'ı kötü/legacy liste girdileri için ek emniyet sağlar.
4. **Legacy read ID kümesi ve durable ArticleRecordStore:** global normalize ID; bu denetimde değişmedi. Dolayısıyla aynı raw ID'nin okundu durumu kaynaklar arasında paylaşılmaya devam eder. Bu mevcut veriyi korur ama bağımsız kaynak okundu durumu sağlamaz.
5. **Observation:** feed URL + subscription notification epoch namespace'i içinde normalize ID. Cache eviction bu geçmişi silmez.

Yer imi JSON snapshot'ları kaynaklar arasında korunur; birini kaldırmak diğerinin ID kümesini veya durable ortak bookmark sahibini yanlışlıkla düşürmez. Eski ID-only kayıtlar kaynak bilgisi olmadığından legacy global üyelik fallback'ini kullanır. Full JSON ve feedUrl boş eski kayıtlar erişilebilir kalır; eksik kaynak bilgisi tahminle doldurulmadı.

Fresh 200, yalnız ilgili feed grubunu değiştirir; mevcut full-text ve bookmark-only full-text korunur. 304, failure ve cooldown grupları eski öğelerini korur. Filter/category girdileri publication anında canlı provider üzerinden değerlendirilir. Cache/reset/dispose sonrası callback'ler hem generation hem publication kabul kontrolünden geçer. Final apply öncesi timer iptal edilir; queued pass önceki publication yetkisini devralmaz.

### Kesinti ve durable commit kararı

`docs/development/architecture.md` başlangıçta açıkça ara publication'da persistence/preparation yapılmadığını belirtiyordu. Bu **mevcut ve kasıtlı trade-off** olarak korundu:

- Hızlı feed UI'da görünebilir; slow feed bitmeden `cachedItemsJson` değişmez.
- Süreç bu arada öldürülürse yeni body kaybolur; restart eski snapshot'ı yükler.
- Sonraki fetch yeniden getirebilir; henüz nihai validator commit edilmediği için yeni body yalnız erken ETag yazımı yüzünden 304 arkasında kaybolmaz.
- HTTP header/body timeout'ları var; çok sayıda feed'in bounded kuyruğu toplam pencereyi uzatabilir.
- Ara UI publication bildirim delivery, full-text extraction, owner reconciliation veya widget persistence başlatmıyor. Durably-ready etiketi yalnız listede görünmeye dayanılarak verilmedi.

Yeni ara writer eklenmedi: her 100 ms'de `_saveCachedItems()` çağırmak sahiplik uzlaştırma/cleanup maliyetini artırır; ayrı checkpoint şeması da yeni atomicity/reset protokolü gerektirir. İşletim sistemi kill garantisi çözülmüş olarak sunulmuyor. Deterministik scheduler testi erken persistence olmadığını, mevcut lifecycle restart testi eski Hive snapshot'ının yüklenmesini doğrular; gerçek process-kill testi yok.

## 8. Performance Results

Başlangıç uygulamasına ait karşılaştırılabilir performans baseline'ı alınmadı. **Önce/sonra hızlanma iddiası yok.** Aşağıdaki sayılar yalnız son kodun Linux Flutter test/debug-JIT micro-benchmark ölçümleridir; cihaz frame benchmark'ı değildir.

Komut: `flutter test test/perf_baseline_test.dart`.

Üç ısınma + 15 koşunun medyanı; her feed 50 makale, beş feed fresh body:

- 30 feed / 1.500 öğe: merge + sort **567 µs**.
- 100 feed / 5.000 öğe: **2.075 µs**.
- 200 feed / 10.000 öğe: **4.103 µs**.

Mevcut 10k benchmark'ı: filter **9.957 µs**, group **20.716 µs**, shuffle dahil sort **5.520 µs**, JSON encode **59.547 µs**, decode **50.877 µs**, decode+fromJson **140.122 µs**, 100 RSS öğesi parse **47.638 µs**. Bu ikinci benchmark değişken çalışma zamanı/shuffle maliyeti içerir; sert performans eşiği değildir.

Aynı kodun paralel full-suite koşularında daha yüksek sonuçlar verdiği gözlendi; mutlak sayılar ortam yüküne hassas. Merge `O(N)` gruplama/tekilleştirme + `O(N log N)` sort; her publication snapshot tahsisi yapar. 100 ms batching ve progress için ayrı ValueNotifier korunuyor. Bütün listeyi yeniden filtreleme/birleştirme maliyeti tamamen kaldırılmadı.

Anchor artık eşit ID'li widget güncellemelerinde de taranıyor; doğruluk için ek maliyet var. Başlangıçtan beri tarama `O(N)` ve key map büyümesi ziyaret edilen satırlar kadar olabilir. Gerçek cihaz scroll frame timing, heap allocation, image-load frame ve OS memory-pressure profili **yapılmadı**; güvenilir cihaz performans karşılaştırması yok.

## 9. Test Results

### Son doğrulama komutları

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter test test/incremental_refresh_scheduler_test.dart test/anchored_feed_list_test.dart test/feed_cache_policy_test.dart test/timestamp_correctness_test.dart test/desktop_runtime_regressions_test.dart test/observed_article_store_test.dart test/s1_a11y_consistency_test.dart
TZ=America/New_York flutter test test/timestamp_correctness_test.dart
flutter test test/perf_baseline_test.dart
flutter build linux --debug
flutter build apk --debug
git diff --check
```

- `flutter pub get`: başarılı; dependency sürümü/lock değişikliği yok.
- `flutter test`: **557 başarılı, 0 başarısız**, framework tarafından raporlanan skip yok; yaklaşık 28 saniye.
- Son hedefli yedi dosya koşusu: **91 başarılı, 0 başarısız**.
- DST/New York: **20 başarılı, 0 başarısız**.
- Benchmark testleri: **2 başarılı**.
- Analyze: **No issues found!**
- `git diff --check`: başarılı.
- Linux debug build: başarılı, `build/linux/x64/debug/bundle/dondurma`.
- Android debug build: başarılı, `build/app/outputs/flutter-apk/app-debug.apk`.
- Android build uyarısı: bazı plugin'ler eski Kotlin Gradle Plugin uygulama biçimini kullanıyor; gelecekteki Flutter sürümleri için Built-in Kotlin geçişi öneriliyor. Paket sürümü bu görevde değiştirilmedi.
- iOS/macOS/Windows build veya native çalışma testi: **yapılmadı**. Linux widget testlerinin geçmesi bu platformların doğrulandığı anlamına gelmez. Android'de APK derlendi; cihazda çalıştırılmadı. Linux binary derlendi; manuel UI smoke/profiling yapılmadı.

### Format kontrolü: mevcut depo başarısızlığı

Komut exit **1** verdi; `--output=none` dosyaları değiştirmedi. Aşağıdaki 13 dosya başlangıçta clean idi ve denetimde düzenlenmedi; formatter bunların biçimini değiştirmek istiyor:

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

İlgisiz dosyaları değiştirmeme şartı nedeniyle bunlar formatlanmadı. Denetimin düzenlediği 22 Dart dosyasına ayrıca `dart format --output=none --set-exit-if-changed` uygulandı: 22 dosya, 0 değişiklik, başarılı. Dolayısıyla **bütün testler geçti**, fakat **bütün doğrulama kapıları geçmedi**.

### Red/green kanıtları ve diğer çalıştırmalar

- İlk baseline: `flutter test test/anchored_feed_list_test.dart test/feed_cache_policy_test.dart test/timestamp_correctness_test.dart` — 26 başarılı.
- `TZ=America/New_York flutter test test/feed_cache_policy_test.dart test/timestamp_correctness_test.dart` — ilk yeni testlerde 6 beklenen hata (bookmark GUID/URL, full-text delimiter, gece yarısı, DST, kaynak tie-break); düzeltmelerden sonra final koşular yeşil.
- `flutter test test/rss_lifecycle_regression_test.dart --plain-name 'bookmarks with shared GUID'` — düzeltme öncesi boş bookmark listesiyle hata; full suite'te başarılı.
- `flutter test test/anchored_feed_list_test.dart --plain-name 'same identities'` — önce anchor konumu hatası; son 8 anchor testi başarılı.
- `flutter test test/incremental_refresh_scheduler_test.dart --plain-name 'stale observation'` — önce reset geçmişi geri oluşuyordu; son suite'te başarılı.
- Scheduler ara koşusunda cache clear/reset sırasında dispose testleri iki `ChangeNotifier` hatası verdi; guard düzeltmesinden sonra başarılı.
- Bir ara resize testinde ilk *tam* görünür ikinci satır assert edilmişti; algoritmanın sözleşmesi ilk *kısmen de* görünür anchor olduğundan test doğru adaya düzeltildi. Başarısızlık gizlenmedi; test kaldırılmadı.
- `flutter doctor -v` — Linux ve Android toolchain hazır, bağlı native test cihazı yok.

Mevcut loopback lifecycle suite'i polling/backoff süreleri içeriyor; bunlar tümüyle yeniden yazılmadı. Yeni scheduler testleri HTTP sonuçlarını Completer, publication zamanını kontrollü Timer ile yönetir. Fling testi `WidgetTester.pump(16 ms)` sanal frame zamanını kullanır.

## 10. Remaining Risks

1. **P1 — Legacy durable archive aliasing (çözülmedi).** `ArticleRecordStore` yalnız normalize ID ile saklıyor (`lib/services/article_record_store.dart:283,339-340,442-458`); membership adayları da global ID ile map'leniyor (`lib/services/temp_cache_membership.dart:66-105`). `ArticlePreparationService._registerArticle` aynı ID'nin mevcut gövde/link/media'sını birleştiriyor (`lib/services/article_preparation_service.dart:279-378`). Farklı feed'lerde aynı GUID ama farklı gerçek makaleler, ayrı bookmark JSON'larına rağmen ortak archive record kullanabilir. Yanlış offline gövde/status veya metadata birleşmesi mümkündür. Bu sınıra kalıcı bağımsızlık kazandırmak için feed-scoped archive kimliği ve legacy lookup/ownership/read uyumluluk tasarımı gerekir; testlerin yeşil olması çözüm kanıtı değildir. Eşitlik sessizce değiştirilmedi, geniş migration yapılmadı.
2. **P1/P2 — Kesinti öncesi başarılı feed body'lerinin kaybı.** Final-commit politikası kasıtlı olarak korundu. Ürün gereksinimi “UI'da gördüğün her yeni öğe slow feed'den bağımsız restart'ta kalır” ise karşılanmıyor. Öneri: ayrı, sınırlı checkpoint tasarımını kill/reset/unsubscribe testleriyle değerlendirin; her UI publication'da pahalı membership çalıştırmayın.
3. **P1 araştırma — Tüm background/preparation reset interleaving'leri kapsanmadı.** Foreground observation düzeltmesi Workmanager isolate'ına otomatik process-wide cancellation sağlamaz. Özellikle geç background claim ve eski full-text prefetch continuation'ları kontrollü ayrı isolate/device testleriyle incelenmeli; bu rapor bunlarda doğrulanmış çözüm iddia etmez.
4. **P2 — Saf descendant image relayout ve native input.** Parent/dependency güncellemesiz keyfi row yüksekliği, iOS bounce overscroll, desktop keyboard repeat ve trackpad/scrollbar sürükleme sırasında canlı refresh gerçek cihazda denenmeli. Yeni test normal ballistic prepend ve width/text-scale değişimini kapsar; bütün kombinasyonları değil.
5. **P2 — Performans/anahtar belleği.** GlobalKey map'i görünür pencereye değil, ziyaret edilen canlı kimliklere kadar büyür. 10k cihaz scroll/heap profili yok. Mevcut sonlu liste sınırı dışında sızıntı kanıtlanmadı.
6. **P2 — Format kapısı.** 13 ilgisiz dosyanın format uyumsuzluğu ayrı değişiklikte giderilmeli.
7. **P2 — Native doğrulama eksikliği.** iOS/macOS/Windows ve Android/Linux gerçek etkileşim smoke testleri tamamlanmalı; Android plugin Kotlin uyarısı ayrıca takip edilmeli.

## 11. Release Recommendation

**NOT READY FOR RELEASE**

Bu karar test başarısızlığına değil, görevde istenen kaynaklar arası kimlik güvenliğinin durable archive katmanında tamamlanmamış olmasına dayanıyor. Görünür liste/yer imi kaybı ve doğrulanan foreground lifecycle hataları düzeltildi; 557 test ve iki debug build başarılı. Ancak farklı makalelerin ortak GUID nedeniyle tek archive record'da birleşmesi, “bütün kalıcı metadata korunur” garantisine engel. Bu sınır için bağımsız değerlendirme/uyumluluk kararı alınmadan tam güvenli release önerilmiyor. Format kapısı ve gerçek cihaz doğrulaması da açık.

## 12. Independent Reviewer Handoff

Öncelik sırası:

1. **Reset observation fence:** `feed_provider.dart:1211-1223`, `feed_refresh.dart:277-294`, `observed_article_store.dart:54-79`. Kilit içi kontrolün factory reset ve subscription epoch değişimini gerçekten gördüğünü; cache eviction'ın history'yi susturmadığını kontrol edin. Testler: `test/incremental_refresh_scheduler_test.dart`, `test/observed_article_store_test.dart`.
2. **Timer/final sınırı:** `lib/providers/feed_provider.dart:1150-1270,1309-1367,1824-1834`. `acceptingPublications`, refresh/cache/reset generation'ları, final öncesi cancellation, queued pass ve dispose sonrası devam noktalarını inceleyin. Normal Timer bug'ı ile doğrudan çağrılmış stale test callback'ini karıştırmayın.
3. **Kimlik:** `lib/services/feed_cache_policy.dart`, `feed_list_filter.dart`, `lib/providers/bookmark_provider.dart`, `lib/services/background_fetch_service.dart:466-479`. Tam bookmark snapshot ile legacy global ID set'inin farklı sözleşmelerini ve filtre invalidation'ını kontrol edin. Testler: `feed_cache_policy_test.dart`, `rss_lifecycle_regression_test.dart:222-248`, scheduler read/bookmark testi.
4. **Açık archive sorunu:** `lib/services/article_record_store.dart:283,339-340,442-458`, `article_preparation_service.dart:279-378`, `temp_cache_membership.dart:66-105`. İki farklı kaynak, ortak GUID, farklı body/link ile gerçek preparation + offline restart testi eklemek sonraki en önemli adımdır. Bu denetimdeki bookmark restart testi yalnız Hive snapshot korumasını doğrular.
5. **Scroll lifecycle:** `lib/widgets/anchored_feed_list.dart:70-205`; `test/anchored_feed_list_test.dart` ve `test/desktop_runtime_regressions_test.dart`. Layout-time correction, center sliver, keep-alive singular transform, değişken yükseklik ve GlobalKey reparenting'i Flutter SDK davranışıyla karşılaştırın.
6. **Navigation:** `lib/widgets/feed_list_item.dart:39-46`, desktop list/shell/reader composite selection değişiklikleri. Testler: `test/s1_a11y_consistency_test.dart:369-375`, `test/desktop_runtime_regressions_test.dart:118-159`.
7. **Tarih:** `lib/services/feed_date_groups.dart`; `TZ=America/New_York flutter test test/timestamp_correctness_test.dart` ile tekrar kontrol edin.

Yeniden çalıştırılabilir temel kanıt: bölüm 9'daki tam komutlar. Son sonuçlar 557 genel, 91 hedefli, 20 timezone testi; analyze temiz; Linux/Android debug build başarılı; format kontrolü başarısız. Beklenen follow-up'lar archive kimliği, süreç öldürme/checkpoint kararı, Workmanager reset yarışları ve gerçek cihaz input/image-load testleri. Hiçbir değişiklik commit edilmedi; bütün başlangıç çalışması ve denetim düzeltmeleri çalışma ağacında duruyor.
