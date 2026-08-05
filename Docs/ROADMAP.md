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

## ✅ Faz 2 — Kaynak sağlayıcıları + ağ dayanıklılığı *(ana gövde tamam)*

- [x] **Ağ katmanı:** zaman aşımı, üstel geri çekilme, `CancellationError` ayrımı, `User-Agent`
- [x] **Tutarsızlığa dayanıklı kod çözme** (`@Lenient`) — panellerin tip tutarsızlığı
- [x] `XtreamContentProvider` — auth (`auth:0` denetimi dahil), kategoriler, live/vod/series
- [x] `M3UContentProvider` + `M3UParser` — satır satır, önbellekli
- [x] `XMLTVParser` — akış halinde, parça parça teslim, iptal denetimli
- [x] `DefaultContentProviderFactory` — kaynak türü dallanmasının tek yeri
- [x] `ProviderStreamResolver` — akış adresi + devam noktası + başlıklar
- [x] `CatalogWriter` + `ContentSyncService` — değiştir stratejisi, kısmi başarı
- [x] Sabit örnek cevaplarla 90+ test
- [ ] ~~`ActivationContentProvider`~~ → **Faz 4'e taşındı** (panel API'si orada kuruluyor)
- [ ] ~~DNS failover~~ → **Faz 4'e taşındı** (`/api/dns-list` panel ucu)
- [ ] ~~EPG senkronizasyonu~~ → **Faz 7'ye taşındı** (çözümleyici hazır, bağlanacak)

**Bitti tanımı:** ✅ Xtream ve M3U kaynakları senkronize oluyor, bozuk/eksik
alanlar çökmeye sebep olmuyor. CI run `30949745419`, 146 test.

> ⚠️ **Gerçek hesapla henüz denenmedi.** Testler sabit örneklerle çalışıyor.
> İlk gerçek sınav Faz 3'te, kendi hesabın girildiğinde olacak.

---

## Faz 3 — Onboarding *(büyük kısmı tamam)*

- [x] Kaynak türü seçimi (Xtream / M3U) → form → doğrulama
- [x] `PlaylistDraft` — form doğrulaması saf Domain mantığı olarak
- [x] `PlaylistValidating` — **kaydetmeden önce** sunucu doğrulaması
- [x] Parola Keychain'e, entity'ye değil
- [x] Senkronizasyon ilerleme ekranı (aşama adlı)
- [x] Çoklu kaynak yönetimi (ekle/sil/aktif yap/yenile)
- [x] **İlk görsel doğrulama:** CI'da simülatör ekran görüntüsü artifact'i
- [ ] ~~Dinamik tema~~ → **Faz 4'e taşındı** (bayi marka rengiyle birlikte anlamlı)
- [ ] Aktivasyon kodu ile giriş → Faz 4

> 🐞 **Görsel doğrulamanın ilk kazancı — üç turluk hata avı**
>
> İlk ekran görüntüsü uygulamanın 320×480 mantıksal boyutta (iPhone 4 gibi)
> çalıştığını, üstte ve altta siyah şeritlerle göründüğünü ortaya çıkardı.
>
> **Kök neden:** XcodeGen'in `info:` bölümü mevcut plist'i **okumaz** —
> kendisi üretip o yola **yazar**. Elle yazılan `App/Info.plist` her
> `xcodegen generate` çağrısında varsayılanlarla eziliyordu.
> `UILaunchScreen`, orientation **ve ATS ayarlarının** hiçbiri pakete
> girmiyordu. Çözüm: `info:` kaldırıldı, `INFOPLIST_FILE` doğrudan verildi.
>
> ⚠️ ATS ayarlarının da kaybolduğuna dikkat: bu fark edilmeseydi Faz 6'da
> HTTP yayınların hiçbiri açılmayacak ve sebebi kolayca bulunamayacaktı.
>
> **Ders:** İlk iki tur tahminle geçti (`UILaunchScreen` içeriği, eksik
> `ignoresSafeArea`). Üçüncüde derlenmiş paketin plist'i okununca cevap tek
> satırda çıktı. Daha erken ölçülmeliydi. Derleme geçiyor, 166 test yeşil,
> hiç uyarı yoktu — bu hata yalnızca ekrana bakılarak bulunabilirdi.

**Bitti tanımı:** Gerçek bir hesapla uçtan uca akış denenip ekran
görüntüsüyle teyit edildiğinde kapanacak.

---

## ✅ Faz 4 — Panel entegrasyonu *(tamam)*

- [x] `RemoteConfigProviding` — `/api/app-config` + çevrimdışı önbellek
- [x] **Bayi marka rengi** (doygun kırmızı = "seçilmemiş" kuralı dahil)
- [x] `ThemeController` — kullanıcı seçimi > panel > uygulama varsayılanı
- [x] **Duyuru şeridi** — kapatılan duyuru kimliğiyle hatırlanır
- [x] **Bakım kapısı** + bayinin destek kanalları
- [x] **Aktivasyon kodu ile giriş** — `/api/activation/redeem`, 7 hata durumu ayrı ayrı
- [x] **DNS failover** — `/api/dns-list`, çalışan sunucu yoklaması

**Bitti tanımı:** ✅ **Doğrulandı** — 2026-08-05, CI run `31005787630`, 239 test.

| Test hedefi | Nerede | Adet |
|---|---|---|
| `OctopusDomainTests` | Linux | 35 |
| `OctopusDataTests` | Simülatör | 168 |
| `FeatureSettingsTests` | Simülatör | 17 |
| `FeatureOnboardingTests` | Simülatör | 11 |
| `OctopusPlaybackTests` | Simülatör | 4 |
| `OctopusTests` | Simülatör | 4 |

> ⚠️ **Gerçek panelle denenmedi.** Tüm testler sabit örneklerle çalışıyor.
> Panel API'sinin şekli Android sürümünün kaynak kodundan çıkarıldı;
> canlı cevaplarda sürpriz alanlar çıkabilir.

---

## Faz 5 — Canlı TV + arama *(büyük kısmı tamam)*

- [x] Kategori şeridi → kanal listesi (`LazyVStack`, sabit sıralama)
- [x] Nuke ile logo önbelleği (`RemoteImageView`, `ChannelLogoView`, `PosterView`)
- [x] FTS5 destekli arama, 300 ms geciktirmeli
- [x] Favori ekleme/çıkarma, canlı gözlemle anında güncelleme
- [x] Kaynak yokken boş durum (hata değil)
- [ ] Kanal satırında "şimdi/sırada" EPG şeridi → **Faz 7** (EPG ile birlikte)
- [ ] Favoriler görünümü
- [ ] Kanal numarası ile hızlı geçiş

**Bitti tanımı:** 20.000 kanallık listede kaydırma 60 fps.
⚠️ **Ölçülmedi** — kaydırma performansı simülatörde anlamlı ölçülemiyor,
gerçek cihaz gerekiyor. `LazyVStack` ve sabit sıralama ile yapısal olarak
hazır; teyit TestFlight'a çıkınca yapılacak.

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
