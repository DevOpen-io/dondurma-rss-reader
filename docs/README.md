# Dokümantasyon

Dondurma RSS Reader belgeleri konu ve kullanım amacına göre düzenlenir. Projeye giriş için [ana README](../README.md), kod üzerinde çalışmak için [geliştirme rehberi](development/README.md) ile başlayın.

## Ürün ve planlama

| Belge | İçerik |
| --- | --- |
| [Ürün rehberi](product/guide.md) | Hedef kitle, ürün ilkeleri ve görsel dil |
| [Uygulanan özellikler ve backlog](product/status.md) | Kaynak kodunda bulunan özellikler ve henüz uygulanmayan fikirler |
| [Teknik yol haritası](product/roadmap.md) | RSS denetiminden ertelenen somut iyileştirmeler |

## Geliştirme

| Belge | İçerik |
| --- | --- |
| [Kurulum ve doğrulama](development/README.md) | Bağımlılıklar, çalıştırma, test ve yerelleştirme |
| [Mimari ve çalışma zamanı](development/architecture.md) | Provider'lar, servisler, Hive, RSS hattı, bildirimler ve platform bağlantıları |
| [Çevrimdışı saklama](development/offline-storage.md) | Makale sahipliği, medya, hazırlık, cache üyeliği ve temizleme |

## Tasarım ve geçmiş uygulama planları

[Tasarım dizini](design/README.md), her konunun spesifikasyonunu ve varsa uygulama planını birlikte listeler. Tamamlanan planlardaki işaretlenmemiş kutular güncel backlog olarak değerlendirilmez.

## Denetim ve araştırma

| Belge | Kapsam |
| --- | --- |
| [RSS motoru — PR #60 denetimi](audits/rss-engine-pr-60.md) | Cooldown, pacing, extraction ve isolate yarışları hakkında tarihsel rapor |
| [iOS uygulanabilirlik araştırması — 2026-10-03](research/2026-10-03-ios-viability-audit.md) | İnceleme tarihindeki iOS yapılandırma eksikleri ve doğrulama sınırları |

Bu belgelerdeki commit, test sayısı, sürüm ve platform değerlendirmeleri kendi inceleme zamanlarına aittir.

## Yayın ve gizlilik

- [Mağaza yayın rehberi](operations/releases.md): GitHub Actions, imzalama, Fastlane, gönderim ve hata kurtarma.
- [Play sürüm notları](../fastlane/metadata/android/README.md): sürüme bağlı changelog dosyalarının biçimi.
- [Privacy policy — English](privacy-policy.en.md).
- [Gizlilik politikası — Türkçe](privacy-policy.tr.md).

Gizlilik politikaları mevcut paylaşım bağlantılarını korumak için `docs/` kökünde kalır. Metinleri bu düzenleme kapsamında değiştirilmemiştir.

## Ajanlar ve araca ait belgeler

- [AGENTS.md](../AGENTS.md): ortak proje yönergeleri ve göreve göre okunacak teknik belgeler.
- [CLAUDE.md](../CLAUDE.md): Claude Code çalışma tercihleri; ortak teknik bilgiler için AGENTS.md'ye yönlendirir.
- `.agents/skills/`: becerilerin kendi yönergeleri ve referansları.
- `.impeccable/critique/`: araca ait tarihli UI eleştirileri.
- [iOS launch-screen notları](../ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md): ilgili platform asset dizininde tutulur.

## Belge ekleme ve bakım

Yeni belgeleri konusuna uygun dizine ekleyin ve bu dizinden bağlantı verin. Güncel kullanım rehberleri `development/`, ürün kararları `product/`, tasarım kayıtları `design/specs/`, tarihli uygulama planları `design/plans/`, denetimler `audits/`, araştırmalar `research/`, yayın işlemleri `operations/` altında tutulur.

Tarihsel kayıtların sonuçlarını güncel durum gibi sunmayın; yeni bulguları güncel rehbere veya yeni bir tarihli kayda yazın. Belge taşırken göreli bağlantıları ve depo içindeki referansları birlikte güncelleyin. Otomatik keşfedilen `AGENTS.md`, `CLAUDE.md` ve beceri dosyaları kendi yerlerinde kalır.
