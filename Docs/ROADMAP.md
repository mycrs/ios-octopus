# 🗺️ YOL HARİTASI

Kural: **her faz derlenebilir ve çalışır halde biter.** Yarım bırakılmış,
derlenmeyen ara durum olmaz. Bir faz bitmeden sonrakine geçilmez.

---

## ✅ Faz 0 — İskelet *(tamam)*

- [x] Beyin haritası ve demir kurallar
- [x] 9 modüllük paket grafiği + `project.yml`
- [x] Domain entity'leri, repository protokolleri, `AppError`
- [x] `PlaybackEngine` protokolü + motor seçici + testleri
- [x] Router + tema + durum bileşenleri
- [x] 8 feature modülü (yer tutucu ekranlar)
- [x] `AppContainer` composition root, `OctopusApp.swift` 26 satır

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
> Smoke test composition root'u kurup bootstrap ediyor; UI'nın gerçekten
> çizildiği ilk kez Faz 3'te ekran görüntüsüyle teyit edilecek.

---

## Faz 1 — Kalıcılık

- [ ] GRDB bağımlılığını `OctopusData/Package.swift`'te aç
- [ ] `AppDatabase` + migration zinciri (playlist, category, channel, movie, series, season, episode, epg, favorite, progress)
- [ ] Kanal ve film adlarında FTS5 sanal tablo
- [ ] Domain entity ↔ satır dönüşümleri (`FetchableRecord`/`PersistableRecord`)
- [ ] `InMemory*Repository` → `GRDB*Repository`
- [ ] Migration testleri

**Bitti tanımı:** Uygulama kapanıp açıldığında veriler duruyor.
50.000 kanallık toplu yazma < 3 sn.
`AppContainer`'da yalnızca 8 satır değişti.

---

## Faz 2 — Kaynak sağlayıcıları

- [ ] `XtreamContentProvider` — `player_api.php`: auth, kategoriler, live/vod/series, `get_short_epg`
- [ ] `M3UContentProvider` — `#EXTINF` akış parser'ı (bellek dostu, satır satır)
- [ ] `XMLTVParser` — EPG (sıkıştırılmış `.gz` desteği)
- [ ] `XtreamStreamResolver` / `M3UStreamResolver` — akış URL kurucuları
- [ ] `ContentSyncService` — aşamalı ilerleme yayını
- [ ] Gerçek panel cevaplarıyla parser testleri (sabit örnek dosyalar)

**Bitti tanımı:** Gerçek bir Xtream hesabı ve bir M3U linki senkronize olup
veritabanına yazılıyor. Bozuk/eksik alanlar çökmeye sebep olmuyor.

---

## Faz 3 — Onboarding

- [ ] Kaynak türü seçimi → form → doğrulama
- [ ] Parola Keychain'e, entity'ye değil
- [ ] Senkronizasyon ilerleme ekranı (`SyncStage`)
- [ ] Çoklu kaynak yönetimi (ekle/düzenle/sil/aktif yap)

**Bitti tanımı:** Uygulamayı ilk açan biri hesabını ekleyip içeriği görebiliyor.

---

## Faz 4 — Canlı TV + Arama

- [ ] Kategori listesi → kanal listesi (kilitlenmeyen sanal liste)
- [ ] Kanal satırında logo + "şimdi/sırada" EPG şeridi
- [ ] Nuke ile logo önbelleği
- [ ] FTS5 destekli birleşik arama
- [ ] Favori ekleme/çıkarma

**Bitti tanımı:** 20.000 kanallık listede kaydırma 60 fps.

---

## Faz 5 — Oynatıcı ⭐

- [ ] `AVPlayerEngine` — HLS/MP4, özel `User-Agent` başlığı
- [ ] VLCKit'i `OctopusPlaybackVLC`'de aç, `VLCPlaybackEngine` yaz
- [ ] `VLCEngineFactory.isAvailable` → `true`
- [ ] `PlayerController` — motor yaşam döngüsü + çalışma zamanı fallback
- [ ] Oynatıcı arayüzü: kontroller, ses/altyazı seçimi, kanal geçişi
- [ ] Ekran kapanırken `teardown()` — bağlantı kotası dolmasın

**Bitti tanımı:** HLS ve MPEG-TS yayınlar açılıyor.
AVPlayer başarısız olunca VLC devralıyor ve kullanıcı bunu fark etmiyor.

---

## Faz 6 — EPG

- [ ] Zaman çizelgeli EPG ızgarası
- [ ] Arka planda EPG tazeleme
- [ ] Eski kayıtların temizliği (`purgePrograms`)

## Faz 7 — VOD + Dizi

- [ ] Afiş ızgaraları, film/dizi detay ekranları
- [ ] Sezon → bölüm ağacı, sıradaki bölüm

## Faz 8 — Kişisel veriler

- [ ] Ana sayfa rafları: izlemeye devam et, son eklenenler, son izlenenler
- [ ] İzleme ilerlemesinin periyodik kaydı

## Faz 9 — Sistem entegrasyonu

- [ ] PiP, AirPlay, arka planda ses
- [ ] Now Playing + kilit ekranı kontrolleri

## Faz 10 — Olgunlaşma

- [ ] Çoklu profil, ebeveyn kilidi
- [ ] Lokalizasyon (`Localizable.strings`)
- [ ] Erişilebilirlik denetimi
- [ ] App Store hazırlığı (ATS gerekçesi, gizlilik beyanı)
