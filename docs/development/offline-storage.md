# Çevrimdışı Makale Saklama

Kaynak koduyla karşılaştırma: 2026-10-11.

[Belge dizini](../README.md) · [Mimari](architecture.md)

## Kalıcı verinin sınırları

Hive `settings`, `feeds` ve `bookmarks` kutuları tercihleri, abonelikleri, liste snapshot'larını ve yer imlerini saklar. Çevrimdışı okuma için ayrıca iki alan vardır:

| Bileşen | Sorumluluk |
| --- | --- |
| [ArticleRecordStore](../../lib/services/article_record_store.dart) | Gövde snapshot'ı, medya manifest'i, sahipler, retry bilgisi, generation ve tombstone |
| [ArticleMediaStore](../../lib/services/article_media_store.dart) | Uygulama documents dizininde URL'den türetilen dosya adıyla paylaşılan `offline_media` havuzu |

`ArticleRecordStore`, `feeds` kutusunun yanında lock dosyasıyla seri hale getirilen JSON state kullanır. Foreground ve Workmanager ayrı Hive bellek görünümlerine sahip olduğundan ortak kayıtların yazımını bu kilit korur. `ImageCacheService` ve thumbnail cache'leri bu kalıcı havuzdan ayrıdır; görsel cache'inin dolu olması makalenin çevrimdışı hazır olduğunu kanıtlamaz.

Bildirimlerin `ObservedArticleStore` geçmişi de ayrı state'tir. Cache temizleme veya makale sahipliği, bir öğenin bildirim açısından yeniden yeni sayılması için gerekçe değildir.

## Sahiplik ve geçici cache

Bir makale kaydı `bookmark`, `tempCache` veya her iki sahibini taşıyabilir. Yer imi kalıcı kullanıcı talebidir. Geçici cache üyeliğini [TempCacheMembership](../../lib/services/temp_cache_membership.dart) belirler:

- Aktif aboneliklerden gelen, kalıcı keyword filtrelerine uyan, yer imi olmayan adaylar alınır.
- URL/kimlik üzerinden tekilleştirilmiş global en yeni N öğe seçilir; feed başına kota yoktur.
- Tarihsiz makalelerin sırası kalıcı ilk gözlem zamanına dayanır.
- Hazır bir makale olmak daha yeni bir adayın önüne geçme hakkı vermez.
- Feed yanıtından kaybolan mevcut üye, aboneliği sürüyorsa aday kalır; yeni makaleler tarafından sınır dışına itilince veya aboneliği kaldırılınca üyeliği biter.
- Cache sınırından çıkan kayıttan yalnız `tempCache` sahibi kaldırılır; yer imi sahipliği korunur.

Görünüm filtreleri ve arama bu üyelik seçimini daraltmaz. `offlineCacheLimit` geçici koleksiyonun sınırıdır; yer imleri bu kotaya sayılmaz.

## Hazırlık hattı

[ArticlePreparationService](../../lib/services/article_preparation_service.dart) önce kalıcı kayıt ve pending manifest oluşturur, ardından metin/görselleri hazırlar. Feed'in `fullTextEnabled ?? autoFullText` tercihi kullanılır; çıkarım başarısız olsa bile mevcut RSS gövdesi korunur.

Otomatik `preparePending` yalnız servisin unmetered kabul ettiği bağlantıda çalışır. Açık kullanıcı eylemiyle `prepareArticle` tek makale için bağlantı türünden bağımsız bir geçişe izin verir. Her parça bir geçişte en fazla bir kez denenir; hazır parçalar tekrar indirilmez. Paralel transfer sınırı servis instance'ı başınadır, isolate'ler arasında global bir indirme kotası değildir.

`pending`, `ready`, `failed`, `gone` durumları gövde/medya hazırlığını belirtir. Geçici hata retry planlar; kalıcı olarak kullanılamayan medya `gone` olur. Cooldown yüzünden hiç çıkılmayan istek pending kalır ve hata denemesi sayılmaz.

Hazırlık servisi dışarıdan `HostPacer` ve `FeedBackoff` alabilir. Background akışı bunları feed/extraction hattıyla paylaşır; uygulama kökünde enjekte edilen hazırlık servisi ise ayrı pacer ile, ortak backoff verilmeden oluşturulur. Bu bağlantı farkı [mimari rehberinde](architecture.md) açıklanır. Manuel retry yerel tahmini beklemeyi atlayabilir; sunucunun etkin `Retry-After` beklemesini atlayamaz. Ön plan ve arka plan cooldown snapshot'ları ayrı Hive anahtarlarına yazılır ve birlikte okunur; bu düzen anlık process-wide koordinasyon garantisi vermez.

## Temizleme ve reset

[ArticleCleanupService](../../lib/services/article_cleanup_service.dart) sahipsiz kaydı tombstone yapar, hiçbir canlı manifest'in kullanmadığı medya dosyalarını koruma süresinden sonra bırakır. Paylaşılan görseli başka bir makale kullanıyorsa dosya kalır. Kayıt verisi çözümlenemiyorsa dosyanın sahipsiz olduğu kanıtlanamaz; temizleme dosya silmeden durur.

Generation, tombstone ve persisted epoch kontrolleri eski async işlerin silinen kayıtları diriltmesini önler. `ArticlePreparationService.resetFence()` kuyruktaki eski mutasyonları sınırlar; `cacheEpoch` cache temizliğiyle yarışan background yazılarına karşı kullanılır. Fabrika sıfırlaması ve cache temizleme aynı yaşam döngüsü değildir: cache temizliği yer imlerini korur.

## UI durumu ve testler

[ArticleStatus](../../lib/services/article_status.dart) okunabilir gövdeyi, tamamlanmış medyayı, sahipliği ve bekleme nedenini kalıcı kayıttan türetir. Metnin okunabilir olması tüm görsellerin hazır olmasıyla aynı şey değildir; UI bu ayrımı saklama/önbellek etiketlerine yansıtır.

İlgili regresyonlar: [saklama](../../test/s2_storage_foundation_test.dart), [hazırlık](../../test/s3_preparation_engine_test.dart), [cache seçimi](../../test/s4_temp_cache_selection_test.dart), [temizleme](../../test/s5_cleanup_lifecycle_test.dart), [makale durumu](../../test/s6_article_status_test.dart) ve [RSS yaşam döngüsü](../../test/rss_lifecycle_regression_test.dart).
