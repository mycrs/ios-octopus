# 🗺️ YOL HARİTASI

Kural: **her faz derlenebilir ve çalışır halde biter.** Yarım bırakılmış,
derlenmeyen ara durum olmaz. Bir faz bitmeden sonrakine geçilmez.

> Kapsam, Android sürümünün özellik setine göre genişletildi —
> bkz. [`REFERANS-ANALIZI.md`](REFERANS-ANALIZI.md)

---

## ✅ Faz 0 — İskelet *(tamam)*

- [x] Beyin haritası ve demir kurallar
- [x] 9 modüllük paket grafiği + `project.yml`
- [x] Domain entity'leri, repository protokolleri, `AppError`
- [x] `PlaybackEngine` protokolü + motor seçici + testleri
- [x] Router + tema + durum bileşenleri
- [x] 8 feature modülü (yer tutucu ekranlar)
- [x] `AppContainer` composition root, `OctopusApp.swift` 28 satır
- [x] CI: mimari + Domain (Linux) + iOS derleme/test + paket testleri

**Bitti tanımı:** ✅ **Doğrulandı** — 2026-08-04, CI run `30926392775`.
`xcodegen generate` → `BUILD SUCCEEDED` → `TEST SUCCEEDED` (iPhone 17 Pro).

| Test hedefi | Nerede | Adet |
|---|---|---|
| `OctopusDomainTests` | Linux | 11 ✅ |
| `OctopusPlaybackTests` | Simülatör | 4 ✅ |
| `OctopusDataTests` | Simülatör | 1 ✅ |
| `OctopusTests` (smoke) | Simülatör | 3 ✅ |

> Not: Uygulamanın ekranda açılışı **görsel olarak** doğrulanmadı (Mac yok).
> İlk görsel teyit Faz 3'te ekran görüntüsüyle yapılacak.

---

## ✅ Faz 1 — Kalıcılık *(tamam)*

- [x] GRDB 7.x bağımlılığı (yalnızca `OctopusData` içinde)
- [x] `AppDatabase` + iki adımlı göç zinciri
- [x] 11 tablo: playlist, kategori, kanal, film, dizi, sezon, bölüm, epg, favori, ilerleme, geçmiş
- [x] Kanal/film/dizi adlarında FTS5 arama indeksi (trigger'larla otomatik eşitlenir)
- [x] Domain entity ↔ satır dönüşümleri (ayrı `Record` tipleri)
- [x] Sekiz depo `InMemory*` → `GRDB*`
- [x] `EntityID` — global benzersiz kimlikler
- [x] Göç, cascade, arama ve toplu yazma testleri

**Referanstan gelen zorunluluklar** *(bkz. REFERANS-ANALIZI § 3)*:
- [x] Katalog **satır satır** yazılır — şemada blob kolonu yok
- [x] Kalıcılık hataları loglanır ve `AppError.storage`'a çevrilir, sessiz `try?` yok
- [x] Sıralama sabit — sayfalı yükleme listeyi kaydırmaz

**Bitti tanımı:** ✅ **Doğrulandı** — 2026-08-04, CI run `30943353673`.

| Ölçüm | Sonuç |
|---|---|
| 10.000 kanal + FTS indeksleme, tek transaction | **0,738 sn** |
| Toplam test | 56 (Data: 37) |
| Değişen ekran dosyası sayısı | **0** |

> **Faz 1'in sınavı:** Sekiz depo bellek içinden SQLite'a taşındı ve hiçbir
> feature dosyasına dokunulmadı. Değişiklik `AppContainer` içinde kaldı —
> çünkü Feature modülleri yalnızca Domain protokollerini görüyor.

> Not: 50.000 kanal hedefi doğrudan ölçülmedi; 10.000 kanal ölçüldü.
> Gerçek katalog boyutuyla ilk teyit Faz 2'de canlı senkronizasyonla yapılacak.

---

## Faz 2 — Kaynak sağlayıcıları + ağ dayanıklılığı

- [ ] `XtreamContentProvider` — auth, kategoriler, live/vod/series, `get_short_epg`, `exp_date`
- [ ] `M3UContentProvider` — `#EXTINF` akış parser'ı (bellek dostu)
- [ ] `ActivationContentProvider` — `/api/activation/redeem` → hesap bilgisi
- [ ] `XMLTVParser` — akış halinde parse, parça parça insert, iptal kontrolü
- [ ] Akış URL kurucuları (`StreamResolving`)
- [ ] `ContentSyncService` — aşamalı ilerleme
- [ ] **Ağ katmanı:** zaman aşımı (connect ~10s / read ~15s), üstel geri çekilme, `CancellationError` ayrımı
- [ ] **DNS failover** — `/api/dns-list` + host probe
- [ ] Sabit örnek cevaplarla parser testleri

**Bitti tanımı:** Üç kaynak türü de senkronize oluyor. Ölü sunucuda yedeğe geçiliyor.
Bozuk/eksik alanlar çökmeye sebep olmuyor.

---

## Faz 3 — Onboarding + tema sistemi

- [ ] Kaynak türü seçimi (Xtream / M3U / aktivasyon kodu) → form → doğrulama
- [ ] Parola Keychain'e, entity'ye değil
- [ ] Senkronizasyon ilerleme ekranı
- [ ] Çoklu kaynak yönetimi (ekle/düzenle/sil/aktif yap)
- [ ] **Dinamik tema:** `ThemeController` — mod (dark/light/yüksek kontrast) + marka rengi seçimi
- [ ] **İlk görsel doğrulama:** CI'da simülatör ekran görüntüsü artifact'i

**Bitti tanımı:** Uygulamayı ilk açan biri hesabını ekleyip içeriği görebiliyor.
**Ekran görüntüsüyle görsel olarak teyit edilir.**

---

## Faz 4 — Panel entegrasyonu (bayi altyapısı)

- [ ] `RemoteConfigProviding` — `/api/app-config` + çevrimdışı önbellek
- [ ] **Bayi marka rengi** teması ezer (doygun kırmızı = "seçilmemiş" kuralı dahil)
- [ ] **Duyuru sistemi** — öncelik: bayi > admin > ipucu
- [ ] **Bakım modu / zorunlu güncelleme kapısı**
- [ ] Bayi bilgileri: müşteri adı, iletişim kanalları

---

## Faz 5 — Canlı TV + arama

- [ ] Kategori listesi → kanal listesi (sanal liste, sabit sıralama)
- [ ] Kanal satırında logo + "şimdi/sırada" EPG şeridi
- [ ] Nuke ile logo önbelleği
- [ ] FTS5 destekli birleşik arama + kategori içi arama
- [ ] Kanal numarası ile geçiş, favori ekleme

**Bitti tanımı:** 20.000 kanallık listede kaydırma 60 fps.

---

## Faz 6 — Oynatıcı ⭐

- [ ] `AVPlayerEngine` — HLS/MP4, özel `User-Agent`
- [ ] VLCKit'i aç, `VLCPlaybackEngine` yaz, `VLCEngineFactory.isAvailable → true`
- [ ] `PlayerController` — motor yaşam döngüsü + çalışma zamanı fallback
- [ ] Oynatıcı arayüzü, ses/altyazı seçimi, kanal zap
- [ ] **Canlı ve VOD için ayrı motor tercihi**
- [ ] **Altyazı boyutu/stili** (0.75 / 1.0 / 1.3 / 1.6)
- [ ] **Harici oynatıcıya gönder**
- [ ] Ekran kapanırken `teardown()` — bağlantı kotası dolmasın

**Bitti tanımı:** HLS ve MPEG-TS açılıyor. AVPlayer başarısız olunca VLC
devralıyor, kullanıcı fark etmiyor.

---

## Faz 7 — EPG

- [ ] Zaman çizelgeli rehber ızgarası
- [ ] Pencereli sorgu `[şimdi−3s, şimdi+36s]`
- [ ] Otomatik tazeleme + bayatlık kontrolü + kaynak başına kısıtlama
- [ ] **Program hatırlatıcı** → bildirim → kanala git
- [ ] Eski kayıtların temizliği

---

## Faz 8 — VOD + Dizi

- [ ] Afiş ızgaraları, film/dizi detay ekranları
- [ ] Sezon → bölüm ağacı, sıradaki bölüm
- [ ] Detay önbelleği (her açılışta yeniden çekme yok)

---

## Faz 9 — Kişisel veriler

- [ ] Ana sayfa rafları: izlemeye devam et, son eklenenler, son izlenenler
- [ ] İzleme ilerlemesinin periyodik kaydı + devam dialogu
- [ ] Favoriler
- [ ] **Açılış ekranı tercihi** (ana sayfa / favoriler)

---

## Faz 10 — Sistem entegrasyonu

- [ ] PiP, AirPlay, arka planda ses
- [ ] Now Playing + kilit ekranı kontrolleri

---

## Faz 11 — Olgunlaşma

- [ ] Çoklu profil, **ebeveyn kilidi** (PIN, tuzlu hash)
- [ ] **Abonelik bitiş tarihi** + süre dolunca yönlendirme
- [ ] **Bağlantı hızı testi**
- [ ] Lokalizasyon (`Localizable.strings`)
- [ ] Erişilebilirlik denetimi + yüksek kontrast teması
- [ ] App Store hazırlığı (ATS gerekçesi, gizlilik beyanı)

---

## Bilinçli olarak YAPILMAYACAKLAR

| Ne | Neden |
|---|---|
| **Demo/örnek veri modu** | Referansta sonradan tamamen kaldırıldı — kullanıcı kararı: "kesinlikle demo veriler olmasın" |
| D-pad / uzaktan kumanda focus sistemi | Hedef iPhone + iPad; tvOS'a geçilirse ayrıca ele alınır |
| Runtime DI konteyneri | Derleme zamanı güvenliğini öldürür |
