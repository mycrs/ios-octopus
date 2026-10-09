# 🧠 OCTOPUS — BEYİN HARİTASI

> Bu dosya projenin **anayasasıdır**. Kod ile doküman çelişirse, önce burayı güncelle, sonra kodu yaz.
> Her yeni özellik "bu haritada nereye oturuyor?" sorusuna cevap veremiyorsa **yazılmaz**.

---

## 1. NE İNŞA EDİYORUZ

iOS için IPTV istemcisi. Kullanıcı bir **kaynak** ekler (Xtream hesabı, M3U linki
veya aktivasyon kodu), uygulama o kaynaktan **Canlı TV / Film / Dizi** içeriğini
çeker, yerel veritabanına yazar, offline-first gösterir ve uygun motorla oynatır.

Ayrıca bir **bayi (reseller) altyapısına** bağlanır: marka rengi, duyurular,
yedek sunucu listesi ve bakım/güncelleme kapısı panelden gelir.

> 📐 Tasarım ve özellik hedefi Android sürümünden alınıyor —
> ayrıntı ve sahada öğrenilmiş dersler: [`REFERANS-ANALIZI.md`](REFERANS-ANALIZI.md)

---

## 2. KİLİTLENMİŞ KARARLAR

| Konu | Karar | Neden |
|---|---|---|
| İçerik kaynağı | Xtream **+** M3U/M3U8 **+** aktivasyon kodu | Üçü de tek `ContentProvider` protokolü arkasında. Yeni kaynak = yeni dosya, sıfır refactor |
| Bayi altyapısı | Panel API (`/api/app-config`, `/api/activation/redeem`, `/api/dns-list`) | Marka, duyuru, failover uzaktan yönetilir |
| Görsel dil | Android sürümüyle aynı kimlik, iOS'a özgü cila | Marka `#00B0FF`; PC/Android/iOS ortak lacivert palet (`#091525`, `#11263B`, `#19374F`); kullanıcının 03.10.2026 talebiyle şeffaf mavi/turkuaz ahtapot logosu, yalnızca mavi ailesinden vurgu seçenekleri. Panel renkleri ve logoları ürün kimliğini değiştirmez, okunaklı metin; SF Symbols + iOS tipografisi + haptik. Büyük yazılar sınırlandırılmaz; düzen dikeyleşir. |
| Dil | Türkçe + İngilizce | Varsayılan cihaz dili; Ayarlar'da Sistem/Türkçe/English seçimi anında ve kalıcı uygulanır |
| Oynatma | AVPlayer **+** VLCKit | HLS → AVPlayer (canlı/film/bölümde yalnızca düğmeyle PiP, AirPlay, arka plan). MPEG-TS/RTSP → VLCKit fallback |
| Tam ekran ve dönüş | Oynatıcı kendi window scene'inde yatay; kapatınca önceki yön ve gezinme yolu korunur | Gerçek tam ekran UIKit hosting denetleyicisi, iOS 16 public geometry API ve iOS 26+ public orientation lock; görünür Live alıcısı varsa aynı oturum mini yüzeye devredilir, alıcı yoksa ses gecikmeden durur. Kanal paneli cached yerel sol overlay; video üstünde Material blur yok. |
| Min. platform | **iOS 16.0**, iPhone + iPad | Kapsam geniş |
| Proje üretimi | **XcodeGen** (`project.yml`) | `.xcodeproj` git'e girmez → merge conflict yok, Windows'ta düzenlenebilir |
| UI | SwiftUI, `NavigationStack` | iOS 16'da mevcut |
| State | `ObservableObject` + `@Published` | `@Observable` iOS 17+, bize kapalı |
| Veritabanı | **GRDB.swift** (SQLite) | SwiftData iOS 17+. 50.000 kanal bulk-insert + FTS5 arama gerekiyor |
| Görsel cache | **Nuke** | `AsyncImage`'ın cache'i poster grid'lerinde çöküyor |
| Eşzamanlılık | `async/await` + Actor | Combine sadece player state stream'i için |
| DI | Elle yazılan Composition Root | Runtime DI (Swinject vb.) derleme-zamanı güvenliği öldürür |

> ⚠️ **iOS 16 tuzakları:** `@Observable` ❌ · `SwiftData` ❌ · `@Bindable` ❌ ·
> `NavigationStack` ✅ · `.searchable` ✅ · `Charts` ✅ · async/await ✅

---

## 3. MODÜL GRAFİĞİ

```mermaid
graph TD
    App["🎬 App<br/>(Composition Root)"]

    subgraph FEAT["Features — birbirini GÖRMEZ"]
        FO[FeatureOnboarding]
        FH[FeatureHome]
        FL[FeatureLive]
        FV[FeatureVOD]
        FS[FeatureSeries]
        FR[FeatureSearch]
        FP[FeaturePlayer]
        FSet[FeatureSettings]
    end

    NAV["🧭 Navigation<br/>Route + Router"]
    DS["🎨 DesignSystem"]
    DOM["💎 Domain<br/>Entity · Repo Protokol · UseCase<br/>SIFIR BAĞIMLILIK"]
    DATA["🗄️ Data<br/>Xtream · M3U · XMLTV · GRDB"]
    PB["▶️ Playback<br/>Protokol + AVPlayerEngine"]
    PBV["📼 PlaybackVLC<br/>izole"]
    CORE["🔧 Core<br/>Log · Error · Keychain"]

    App --> FEAT
    App --> DATA
    App --> PB
    App --> PBV
    App --> NAV

    FEAT --> DOM
    FEAT --> DS
    FEAT --> NAV
    FEAT --> PB

    DATA --> DOM
    PB --> DOM
    PBV --> PB
    NAV --> DOM
    DS --> DOM
    DS --> CORE
    DATA --> CORE
    PB --> CORE

    style DOM fill:#1a4d2e,stroke:#4ade80,color:#fff
    style App fill:#4d1a1a,stroke:#f87171,color:#fff
    style DATA fill:#1a3a4d,stroke:#60a5fa,color:#fff
```

---

## 4. DEMİR KURALLAR (ihlal = derleme hatası)

1. **Domain hiçbir şeyi import etmez.** Sadece `Foundation`. UIKit/SwiftUI/GRDB **yasak**.
2. **Feature → Data import edemez.** Feature sadece Domain protokolünü bilir.
   Somut `XtreamContentProvider`'ı sadece App tanır.
3. **Feature → Feature import edemez.** Geçiş `Navigation.Route` üzerinden olur.
4. **Data → SwiftUI import edemez.** Data, ekranın var olduğunu bilmez.
5. **Bağımlılıklar yukarı akmaz.** Ok yönü tek taraflıdır; döngü olursa mimari bozulmuştur.
6. **3rd-party bağımlılık tek modülde hapsedilir.** GRDB sadece Data'da, VLCKit sadece PlaybackVLC'de.
7. **Singleton yasak.** Her şey `init` ile enjekte edilir. (`Log` istisna.)

---

## 5. MODÜL SORUMLULUKLARI

### 💎 OctopusDomain — *merkez*
**Yapar:** Entity (`Channel`, `Movie`, `Series`, `EPGProgram`, `Playlist`), Repository **protokolleri**, UseCase'ler, iş kuralları.
**ASLA yapmaz:** Ağ isteği, disk yazma, UI, tarih formatlama.
> Bu modül 10 yıl sonra da aynen durabilmeli. Buraya `import` eklemek istiyorsan dur ve düşün.

### 🗄️ OctopusData
**Yapar:** `XtreamContentProvider`, `M3UContentProvider`, XMLTV parser, GRDB şeması/migration, Repository **implementasyonları**, senkronizasyon.
**ASLA yapmaz:** Ekran bilmez, `Color`/`View` döndürmez.

### ▶️ OctopusPlayback / 📼 OctopusPlaybackVLC
**Yapar:** `PlaybackEngine` protokolü, `AVPlayerEngine`, `EngineResolver` (URL/format → motor seçimi), `PlayerController`, `NowPlayingCenter`, `AudioSessionController`.
VLC ayrı target: VLCKit patlarsa çekirdek etkilenmez.
**ASLA yapmaz:** Player **UI**'ı çizmez — o `FeaturePlayer`'ın işi.

> **Motor mu, koordinatör mü?** Motor tek bir işi bilir: verilen adresi
> açmak. Şu üçü onun işi **değil**, `PlayerController`'ın işidir:
> hangi motor (açamazsa yedeğe geçmek), nerede kalmıştı (devam konumu),
> SwiftUI'a nasıl anlatılır (`AsyncStream` → `@Published`).
> Bunlar motora konsaydı her yeni motor aynı mantığı baştan yazardı.

### 🧭 OctopusNavigation
`AppRoute` enum + `Router`. Route'lar **sadece ID taşır**, entity taşımaz (deeplink/state-restore için).

### 🎨 OctopusDesignSystem
Renk, tipografi, spacing, `PosterCard`, `ChannelRow`, `LoadingView`, `ErrorStateView`.
**ASLA yapmaz:** İş mantığı, ağ, ViewModel bilmez.

### 🔧 OctopusCore
`Log`, `AppError`, `KeychainStore`, `Reachability`, `Debouncer`. İş mantığı **yok**.

### 🎬 App — *ince olmak zorunda*
Sadece: container kurulumu + kök view + lifecycle. **Hedef: `OctopusApp.swift` ≤ 40 satır.**

---

## 6. VERİ AKIŞI — "Kanal listesi ekrana nasıl gelir?"

```
FeatureLive/LiveChannelsView
   └─ @StateObject LiveChannelsViewModel
        └─ ChannelRepository   ← PROTOKOL (Domain)
              ▲
              │ App tarafından bağlanır
              │
        ChannelRepositoryImpl (Data)
              ├─ ChannelDAO (GRDB)      → önce yereli döndür  ⚡ anında UI
              └─ ContentProvider        → arka planda tazele
                    ├─ XtreamContentProvider  (player_api.php)
                    └─ M3UContentProvider     (#EXTINF parser)
```

**Offline-first:** Repository **her zaman** önce SQLite'ı döndürür, ağ sonucu geldikçe günceller.
Kullanıcı boş ekran görmez.

---

## 7. OYNATMA AKIŞI — motor nasıl seçilir?

```
PlaybackItem(url, format)
        │
   EngineResolver
        ├─ .hls (.m3u8)          → AVPlayerEngine   ✅ AirPlay, arka plan ses
        ├─ .mp4 / .mov           → AVPlayerEngine
        ├─ .mpegTS (.ts) / rtsp  → VLCPlaybackEngine
        └─ bilinmiyor            → AVPlayer dene → hata → VLC'ye düş 🔁
```

`FeaturePlayer` **hangi motorun** çalıştığını bilmez; sadece `PlaybackEngine` protokolüne bakar.

Çalışma zamanı zinciri:

```
PlayerScreen ─── PlayerViewModel ──→ StreamResolving      "hangi adres?"
      │                                    ↓
      └───────── PlayerController ──→ PlaybackEngine      "aç ve çal"
                        ├──→ PlaybackProgressRepository   "nerede kalmıştı"
                        ├──→ WatchHistoryRepository       "izlendi"
                        └──→ NowPlayingCenter             "kilit ekranı"
```

⚠️ Yedeğe **yalnızca bir kez** düşülür (`didAttemptFallback`); ikisi de
açamazsa hata kullanıcıya gider. Aksi hâlde iki motor birbirini sonsuza
kadar tetikleyebilirdi.

⚠️ Video yüzeyine `.id(engineIdentifier)` verilir. Motor değişince SwiftUI
aynı `UIViewRepresentable`'ı yeniden kullanır; yeni motorun katmanı hiç
eklenmez ve **ekran siyah kalır**.

---

## 8. DOSYA HARİTASI

```
ios-octopus/
├── project.yml                      # XcodeGen — TEK proje tanımı
├── CLAUDE.md                        # kod kuralları
├── Docs/
│   ├── BRAIN.md                     # ← buradasın
│   └── ROADMAP.md
├── App/                             # İNCE kabuk
│   ├── Sources/
│   │   ├── OctopusApp.swift         # @main  (≤40 satır)
│   │   └── Composition/
│   │       ├── AppContainer.swift   # tüm bağlantılar burada
│   │       └── RootView.swift
│   └── Info.plist                   # `info:` DEĞİL, INFOPLIST_FILE ile bağlanır
└── Packages/
    ├── OctopusCore/
    ├── OctopusDomain/               # ⭐ saf Swift
    ├── OctopusData/
    ├── OctopusNavigation/
    ├── OctopusDesignSystem/
    ├── OctopusPlayback/
    ├── OctopusPlaybackVLC/
    └── OctopusFeatures/             # her feature ayrı target
        ├── FeatureOnboarding/       # kaynak ekleme, doğrulama
        ├── FeatureHome/             # raflar
        ├── FeatureLive/             # kanal listesi + EPG şeridi
        ├── FeatureVOD/              # film kataloğu + detay
        ├── FeatureSeries/           # dizi kataloğu + sezon/bölüm
        ├── FeatureSearch/           # birleşik arama
        ├── FeatureFavorites/        # favoriler
        ├── FeaturePlayer/           # oynatıcı (Faz 6)
        └── FeatureSettings/         # ayarlar, kaynak yönetimi
```

---

## 9. KOD KURALLARI

- Dosya adı = içindeki ana tipin adı. `LiveChannelsViewModel.swift` → `LiveChannelsViewModel`.
- View dosyası **200 satırı** geçerse alt bileşene böl.
- ViewModel `@MainActor`, `final class`, `ObservableObject`.
- Her ViewModel bağımlılığını **protokol** olarak alır → test'te sahte (mock) verilir.
- `try!` · `as!` · `force unwrap` **yasak** (test kodu hariç).
- Public API'ye `public` yazmayı unutma — modüller arası varsayılan `internal`.
- Kullanıcıya gösterilen metin doğrudan yazılmaz → `Localizable.strings`.

---

## 10. TEST STRATEJİSİ

Testin **nerede koştuğu** mimariden çıkar. Yanlış yere yazılan test ya hiç
çalışmaz ya da gereksiz yavaş çalışır.

| Test | Nerede koşar | Süre | Neden orada |
|---|---|---|---|
| `OctopusDomainTests` | Linux, `swift test` | saniyeler | Saf Swift — macOS/simülatör gerekmez |
| `OctopusDataTests` | Simülatör, `xcodebuild test` | ~1 dk | Core üzerinden `Security`/`os`'a bağlı |
| `OctopusPlaybackTests` | Simülatör, `xcodebuild test` | ~1 dk | `UIKit` bağımlı |
| `OctopusTests` (smoke) | Simülatör, `-scheme Octopus` | ~1 dk | Composition root'u kurar |

> ⚠️ **Paket test hedefleri ana şemaya dahil değildir.**
> `xcodebuild test -scheme Octopus` yalnızca `OctopusTests`'i koşar.
> Paket testleri CI'da her paketin kendi dizininde ayrıca çalıştırılır
> (bkz. `.github/workflows/ci.yml` → "Paket testleri").
> Yeni bir pakete test eklersen **o listeye de eklemeyi unutma** —
> yoksa test yazılmış ama hiç koşmamış olur ki bu, testsiz olmaktan
> daha tehlikelidir: koruman var sanırsın.

**Kural:** İş kuralını Domain'e yaz → testi ücretsiz ve anında koşar.
Test yazmak için simülatör gerekiyorsa, muhtemelen mantığı yanlış katmana koydun.

---

## 11. YOL HARİTASI

| Faz | İçerik | Durum |
|---|---|---|
| **0** | Beyin haritası + modül iskeleti + protokoller | ✅ |
| **1** | Domain entity'leri + GRDB şema/migration | ✅ |
| **2** | Xtream + M3U provider, Repository impl | ✅ |
| **3** | Onboarding: kaynak ekle → senkronize et | ✅ |
| **4** | Canlı TV listesi + kategori + arama | ✅ |
| **5** | Player (AVPlayer → VLC fallback) | ✅ AVPlayer · ✅ VLC · 🐞 VLC'de denetimler görünmüyor |
| **6** | EPG (XMLTV + Xtream short_epg) + rehber ekranı | ✅ |
| **7** | VOD + Dizi (sezon/bölüm) | ✅ |
| **8** | Favoriler, izleme geçmişi, kaldığın yerden devam | ✅ |
| **9** | Arka plan sesi ✅ · Now Playing ✅ · AirPlay ✅ · PiP ✅* | ✅ |
| **10** | Ebeveyn kilidi ✅ · tema ✅ · çoklu profil ⏳ | 🔨 |

> ✅ **Faz 5 neden artık beklemiyor:** "gerçek cihaz gerekiyor" varsayımı
> yanlıştı. AVFoundation bir **sistem çerçevesi**; CI'daki macOS runner
> onu derliyor, test ediyor ve simülatörde çalıştırıp kare alıyor. Cihaz
> gerçekten gereken tek parça VLCKit (~60 MB binary, SPM entegrasyonu
> kırılgan) — o hâlâ Mac'i bekliyor.
>
> Bu, projenin en pahalı yanlış varsayımıydı: fazlarca "cihaz yok" diye
> ertelendi. **Dersi:** "yapamayız" demeden önce hangi parçanın gerçekten
> engellendiğini ayrıştır.

> ✅ **VLC bağlandı (2026-08-09).** `vlckit-spm` 3.6.0 (`MobileVLCKit`) —
> resmî `videolan/VLCKit` deposunda `Package.swift` yok, SPM ile
> çözülemiyor. Tahmin doğru çıktı: resolver zinciri ve `PlayerController`
> yedek yolu **hiç değişmeden** çalıştı; yalnızca motor yazıldı.
>
> ⚠️ **Beklenmeyen boşluk — "sesli körlük":** `hls` formatı
> `isNativelySupported == true` olduğu için HEVC/UHD kanallar AVPlayer'da
> kalıyordu. AVPlayer çözemediği video izini **sessizce atlıyor**: durum
> `readyToPlay`, hata yok, ses akıyor, ekran siyah. Hata düşmediği için
> yedek motor hiç denenmiyordu. Çözüm: `AVPlayerEngine` içinde gözcü —
> görünür yüzeyde 8 sn kesintisiz oynatmaya rağmen
> `AVPlayerLayer.isReadyForDisplay == false` ise başarısızlık olayı
> yayınlanır. `presentationSize` yalnızca boyut metadata'sıdır; ilk
> karenin çözüldüğünü kanıtlamaz. AirPlay'de yerel kare beklenmez.
> **Ders:** "açıldı" ile "görüntü var" aynı şey değil; motor sözleşmesi
> yalnızca hata sinyaline dayanırsa sessiz başarısızlıklar yakalanmaz.
>
> ⚡ **Zaplama maliyeti motor ömründedir (2026-08-09 incelemesi).**
> `start()` her çağrıldığında yeni motor üretiliyordu: eski motorun
> `teardown`'ı (VLC'de `stop()` ana iş parçacığını tıkar), yeni `AVPlayer`,
> ses oturumunun yeniden etkinleştirilmesi, PiP kontrolörünün yeniden
> kurulması ve `surfaceGeneration` arttığı için SwiftUI'ın video yüzeyini
> baştan yaratması — hepsi **her kanalda**. Artık resolver kararı
> değişmediyse motor korunuyor, yalnızca `load()` çağrılıyor.
> **Kural:** motor değiştirmek pahalıdır; yalnızca karar değişince yapılır.
>
> ⚠️ **Canlı yayın ≠ VOD, ayarlar da ayrı olmalı.** Canlıda
> `automaticallyWaitsToMinimizeStalling` kapalı (tampon beklemek her zapta
> gecikme demek), VOD'da açık. VLC'de `network-caching` canlıda 1500 ms —
> 3000 ms akıcıydı ama her zapta 3 saniye siyah ekrandı.
>
> ⚠️ **Sessiz başarısızlıklar iki motorda da yakalanmalı.** AVPlayer
> çözemediği videoyu sessizce atlar (bkz. "sesli körlük"); VLC ise ölü bir
> yayında `.opening`'de sonsuza kadar bekler, `.error` hiç gelmez.
> İkisinin de gözcüsü var: AVPlayer'da 3 sn (kare gelmedi), VLC'de 15 sn
> (hiç açılmadı). Motor sözleşmesi yalnızca hata sinyaline güvenemez.
>
> ⚠️ **Canlıda kopma kalıcı sayılmaz:** `PlayerController` aynı yayına
> artan gecikmeyle 3 kez sessizce yeniden bağlanır (kullanıcı spinner
> görür, hata ekranı değil). Sayaç oynatma başlayınca sıfırlanır — saatlik
> izlemede biriken kopmalar hakkı tüketmesin. VOD'da yeniden deneme **yok**:
> orada kopma genelde kalıcı bir sebeptendir ve gizlenmemeli.
>
> 🧪 **Üçüncü motor denendi: KSPlayer (2026-08-09).** `OctopusPlaybackKS`
> modülü kuruldu (KSPlayer 2.3.4 + FFmpegKit 6.1.4) ve **ilk denemede
> derlendi** — üçüncü motoru eklemek protokol + fabrika + `AppContainer`'da
> tek satırdan ibaret kaldı. Mimarinin asıl sınavı buydu ve geçti.
>
> ❌ **Ve kaldırıldı:** UHD/HEVC yayınlarında KSPlayer'ın kendi iz
> ayrıştırması çöküyordu — `FFmpegAssetTrack.init(stream:)` →
> `_assertionFailure` (EXC_BREAKPOINT), iki denemede birebir aynı yığın.
> Kütüphane içi, yamanamaz; 2.3.4 en güncel sürüm. Modül tamamen silindi
> (uygulama ~168 MB → VLC'siz hâline döndü, SPM önbelleğinden ~1 GB düştü).
> Yedek motor yine VLC.
> **Ders:** üçüncü taraf motoru "derleniyor" ile "güvenilir" aynı şey değil;
> kabul kriteri gerçek yayında çökmemektir. Eklemek de çıkarmak da tek
> modül + `AppContainer`'da tek fonksiyondan ibaret kaldı — izolasyon işe yaradı.
>
> 🐞 **Açık:** VLC motorundayken oynatıcı denetimleri ekranda görünmüyor
> (dokunma ulaşıyor, durum değişiyor, çizim olmuyor). `VLCOpenGLES2VideoView`
> SwiftUI içeriğinin önünde kompozit ediliyor. `zIndex`, `.overlay` ve
> `isUserInteractionEnabled` denendi, çözmedi. Bkz. `PlayerScreen.swift`.

> ✅* **PiP yazıldı, gerçek cihazda doğrulanmadı:** simülatörde
> `AVPictureInPictureController.isPictureInPictureSupported()` **false**
> döner; kontrolör hiç kurulmaz ve düğme çıkmaz. Kod bu durumu sessizce
> kabul ediyor — yani simülatörde "çalışmıyor" görünmesi normaldir.
> Mac'te iPhone'a kurup doğrulanması gerekiyor.
> PiP canlı yayın, film ve dizi bölümlerinde kullanıcı üst çubuktaki düğmeye
> bastığında başlar. Geri/Home hareketi otomatik PiP başlatmaz.
>
> ⚠️ İki ayrı kavram karıştırılmamalı: `supportsPictureInPicture`
> **motorun** yeteneği (VLC'de `false`), `isPictureInPicturePossible`
> ise **o an** başlatılabilirlik (video yüklenene kadar `false`).
> Düğmenin görünürlüğü ikincisine bakar; birincisine baksaydı
> simülatörde tıklanan ama hiçbir şey yapmayan bir düğme olurdu.

### Görsel dil

Android sürümüyle aynı kimlik, iOS'a özgü cila. Somut karşılıkları:

| Referanstaki | iOS karşılığı | Nerede |
|---|---|---|
| Tam ekran dönen tanıtım | Hero **kartı** (raflar kaydırılabilir kalsın) | `FeatureHome/HomeScreen` |
| Kart üstü puan | `RatingBadge` — puan yoksa hiç çizilmez | `DesignSystem` |
| Detay hero'su | `DetailHeaderView` — film **ve** dizi ortak kullanır | `DesignSystem` |
| Uzun künye satırı | Yatay kaydırılan çipler (`DetailChip`) | `DesignSystem` |
| Üstte gömülü video | `LiveMiniPlayerView` — **gerçek** oynatıcı; liste dokunuşu yayını burada başlatır, tam ekran karta dokununca | `FeatureLive` |
| — | Haptik: favori/kategori/PIN | `DesignSystem/Haptics` |

⚠️ Detay başlığı **tek** bileşen: ayrı yazılsalardı zamanla birbirinden
ayrı düşerlerdi — referans projede tam olarak bu olmuştu.

> ⚠️ **Sinematik başlık iki parçalı bir sözleşmedir.** `DetailHeaderView`
> tek başına yetmez: ekranın **`.toolbarBackground(.hidden, for: .navigationBar)`**
> demesi de gerekir. Opak çubuk zemini görselin üst ~110pt'sini ve afişin
> tepesini örtüyordu — görsel ekranın tepesinden başladığı hâlde koyu bir
> bant gibi duruyor, afiş oradan kesiliyordu. Yeni bir detay ekranı
> eklenirse bu satır unutulmamalı.
>
> ⚠️ **Oran boş kutuya uygulanır, görsele değil.** `RemoteImageView`'a
> doğrudan `.aspectRatio` verilince görsel kendi doğal genişliğini
> dayatıyor ve **tüm başlık bloğu ekrandan taşıyor** (afiş ve başlık
> soldan kesildi). Doğrusu: `Color.clear.aspectRatio(...).overlay { görsel }`.

> ✅ **Gömülü mini oynatıcı (2026-08-09).** Uzun süre "feature'lar
> birbirini import edemez, video gömülemez" diye statik bir kartla
> idare edilmişti. Yanlış teşhis: gereken şey `FeaturePlayer` **değil**,
> `OctopusPlayback`'ti. `FeatureLive` motor sözleşmesini oynatma
> modülünden görüyor, iki ekran hâlâ birbirini tanımıyor — demir kural 3
> bozulmadı. `VideoSurfaceView` bu yüzden `FeaturePlayer`'dan
> `OctopusPlayback`'e taşındı.
>
> ⚠️ **Yüzey kimliği motor adı olamaz:** her `attach` yeni bir motor
> **örneği** üretir ama kimlik dizgesi aynı kalabilir (kanal değiştirirken
> AVPlayer → AVPlayer). SwiftUI `.id` değişmeyince yüzeyi yeniden kurmaz
> ve ekranda bırakılmış eski motorun katmanı kalır: kanal değişir, ses
> gelir, görüntü donar. Çözüm `PlayerController.surfaceGeneration`
> sayacı. Aynı hata tam ekrandaki zaplamayı da vuruyordu.

#### Canlı TV yerleşimi

Referanstaki sıra birebir alındı: **video → kategoriler → arama → liste**.
Üç karar bunu mümkün kıldı:

1. **Gezinme çubuğu gizli** (`.toolbar(.hidden, for: .navigationBar)`) —
   önizleme kartı ekranın üst kenarına yapışsın, durum çubuğunun altına
   uzansın diye. Üst bardaki ayarlar ikonu da gizlendiğinden aynı erişim
   `LiveScreen` üzerinde sağ üstteki ayrı düğmeyle korunur.
2. **`.searchable` kullanılmıyor** — o değiştirici aramayı gezinme
   çubuğuna koyar, biz kategorilerin **altında** istiyoruz. Yerine
   `DesignSystem/SearchField`.
3. **Kart `ScrollView`'in dışında** — referansta video sabit, liste
   altında kayıyor.

⚠️ Video **gömülemez**: `FeaturePlayer` ayrı modül ve feature'lar
birbirini import edemez (demir kural 3). Kart aynı hissi mimariyi
bozmadan verir.

⚠️ İki tuzak: (a) kart yokken üst güvenli alan korunmalı
(`edges: showsPreview ? .top : []`), yoksa kategori şeridi durum
çubuğunun altında kalır; (b) buradan açılan ekranlara
`.toolbar(.visible)` verilmeli, yoksa geri düğmesi kaybolur.

### Bayi paneli entegrasyonu

Panel ayrı bir depoda: `qruze_player/admin-server` (Node + Express +
SQLite). Uygulama oraya **üç uçtan** bağlanır:

| Uç | Ne getirir | Ne zaman |
|---|---|---|
| `/api/app-config` | genel: sürüm, bakım, tema, duyuru | her açılış |
| `/api/public/reseller-config/<kod>` | bayiye özel: marka, duyuru, **sunucu listesi**, iOS bayrağı | kod kayıtlıysa |
| `/api/activation/redeem` | aktivasyon kodu → gerçek hesap | kullanıcı kod girince |

Sistemdeki üç **adres** karıştırılmamalı:

| Ne | Adres | Kim kullanır |
|---|---|---|
| API tabanı | `octopusdocumentary.com` | uygulama |
| Yönetim paneli | `octopusdocumentary.com/octo-control-7842` | admin, tarayıcıda |
| Hızlı kurulum | `octopusplayer.com/b/<kod>` | müşteri, tarayıcıda |

⚠️ Sonuncusu **API değil**. Uygulama oraya istek atmaz; kullanıcı o
bağlantıyı bayi kodu alanına yapıştırırsa koda çevrilir
(`ResellerConfig.normalizeCode`) — bayiler müşteriye kodu değil
bağlantıyı gönderiyor.

**Öncelik kuralı:** bayi > global. Bayi bir alanı doldurmuşsa o kazanır,
susmuşsa global değer korunur (`RemoteAppConfig.applying(_:)`).

⚠️ **Panel varsayılan kırmızısı** (`#E50914`): panel, bayi renk seçmemiş
olsa da bu değeri gönderiyor. Ham uygulanırsa her bayi kırmızı olur ve
uygulamanın kimliği kaybolur — `BrandConfiguration.effectiveColorHex`
yalnızca bu bilinen eski varsayılan değeri eler; seçilmiş diğer kırmızılar uygulanır.

⚠️ **iOS ayrı bir platform**: `platform_ios_enabled`, Android'in
`platform_mobile_enabled` bayrağından bağımsız. Bayilerin çoğu App Store
onayı çıkana kadar yalnızca Android dağıtıyor; tek bayrak paylaşsalardı
iOS'u kapatmak Android'i de kapatırdı. Kapalıyken
`ServiceGate.platformUnavailable` devreye girer — bakımdan **ayrı** bir
durum, çünkü beklemenin faydası yok, kullanıcı bayisine başvurmalı.

⚠️ **Eksik alan = açık**: sunucusu güncellenmemiş panelde
`platform_ios_enabled` hiç gelmez. `false` varsaymak o bayilerin
uygulamasını bir anda kilitlerdi.

Sözleşme `PanelResellerConfigTests` ile kilitli: içindeki JSON çalışan
panelden alınmış gerçek bir yanıt. Panel bir alan adını değiştirirse test
kırmızıya döner — aksi hâlde uygulama sessizce markasız açılır.

### İçerik kilidi nerede uygulanır?

Kilit ilk kurulumdan itibaren otomatik kapalı başlar ve **tek bir yerde
tutulup yedi yerde uygulanır**. Bir ekranı atlamak
kilidi o ekrandan atlatılabilir kılar — bu yüzden liste burada:

| Ekran | Süzülen |
|---|---|
| Canlı TV | kanal listesi **ve** arama sonuçları |
| Filmler | katalog sayfaları **ve** arama sonuçları |
| Diziler | katalog sayfaları **ve** arama sonuçları |
| Ara (birleşik) | üç türün sonucu da |
| Ana Sayfa | "kaldığın yer", "son eklenenler", "son izlenenler" |
| Favoriler | üç tür de |
| **Oynatıcı** | doğrudan açılış, kanal değiştirme sırası ve arka plan geçişi |

⚠️ Sonuncusu en kolay unutulanı: listeler süzülse bile oynatıcıda ileri
geri basan kullanıcı korumalı kanala düşebilirdi. `PlayerZappingTests`
doğrudan kimlikle açmayı ve arka plan kilidini de ayrıca doğruluyor.

⚠️ Sayfalı listelerde ofset **çekilen ham satır** sayısını takip eder,
görünen öğe sayısını değil. Aksi halde gizlenen her öğe sonraki sayfayı
geri kaydırır ve aynı içerik tekrar tekrar gelir.

---

## 11.1 SAHADA ÖĞRENİLEN TUZAKLAR

Bu proje boyunca **derleme geçtiği hâlde** yanlış olan şeyler. Hepsi
gerçekten yaşandı; tekrar keşfetmeye gerek yok.

| Tuzak | Belirti | Doğrusu |
|---|---|---|
| XcodeGen `info:` bölümü | `Info.plist` sessizce **eziliyor**; ATS ve launch screen pakete girmiyor, uygulama 320×480 boyutta açılıyor | `info:` kullanma, `INFOPLIST_FILE` build ayarını ver |
| Eksik `ignoresSafeArea()` | Arka plan durum çubuğuna uzanmıyor, ekran "kutu içinde" duruyor | Kök görünümde `ZStack` + `ignoresSafeArea()` |
| Çok ürünlü SPM paketi | `xcodebuild -scheme OctopusFeatures` diye bir şema **yok**, testler koşmuyor | `<Ad>-Package` toplu şemasını kullan |
| `XCTUnwrap(try await …)` · `XCTAssertTrue(await …)` | `'async' call in an autoclosure that does not support concurrency` | Tüm `XCTAssert…` ailesi **autoclosure** alır; içinde `await` olamaz. Önce `let x = await …`, sonra assert |
| `@MainActor` tipin örneğini varsayılan parametre değeri yapmak | `call to main actor-isolated initializer in a synchronous nonisolated context` — varsayılan ifadeler izolasyonsuz bağlamda değerlendirilir | Parametreyi `Optional` yap, varsayılanı **gövdede** üret: `self.x = x ?? X()` |
| `@MainActor` fonksiyona non-escaping closure parametresi | `escaping local function captures non-escaping value` — aktöre atlarken parametre kaçmış sayılır | Closure'ı `@escaping` işaretle |
| Motor değişince video yüzeyini yeniden kurmamak | Yedeğe düşülüyor, ses geliyor ama **ekran siyah**: SwiftUI aynı `UIViewRepresentable`'ı yeniden kullanıyor, yeni motorun katmanı hiç eklenmiyor | Yüzeye `.id(engineIdentifier)` ver |
| İzleme geçmişini adres çözülünce yazmak | Açılmayan yayınlar da "izlendi" sayılıyor; "kaldığın kanal" kartı hiç izlenmemiş kanalı gösteriyor | Kaydı `.playing` durumuna **ilk geçişte** yaz |
| Ham dizgi `#"…"#` + renk kodu | `"#00E676` dizisi dizgiyi erken kapatıyor | İki diyezli sınırlayıcı `##"…"##` |
| Feature'da `as?` ile Data protokolü | Dönüşüm **asla tutmaz** (feature Data'yı göremez), özellik sessizce çalışmaz | Sözleşmeyi Domain'e taşı |
| Domain'in iç yardımcısına uzanmak | `inaccessible due to 'internal'` | Dönüşümü sunum katmanına koy, Domain'i açma |
| `try?` + optional dönen fonksiyon | `initializer for conditional binding must have Optional type, not 'String'` — `String??` sanıp iki kez açtım | `try?` iç içe optional'ı **düzleştirir** (SE-0230); `throws -> String?` tek `if let` ile açılır |
| Testte sabit `sleep` ile geciktirme beklemek | CI **rastgele** kırmızı: yerelde geçen test yüklü koşucuda 100 ms'e sığmıyor. Kod değişmemişti | Süreyi değil **koşulu** bekle (`waitUntil { … }`). Sabit bekleme yalnızca bir şeyin *olmadığını* doğrularken doğru |
| `AsyncStream`'e abone olunmadan yayın yapmak | Yayın **sessizce kaybolur** (continuation henüz yok), test zaman aşımına düşer | Önce aboneliği bekle (`waitUntil { stub.isObserving }`), sonra yayınla. Sabit uyku bunu şans eseri örtüyordu — uyku kaldırılınca ortaya çıktı |
| `@MainActor` sınıfın statik üyesini izolasyonsuz testten çağırmak | `call to main actor-isolated static method … in a synchronous nonisolated context` | Test sınıfını da `@MainActor` yap. `actor` tiplerde sorun yok — onların statikleri zaten izolasyonsuz |
| Uyarlanır ızgarada sabit genişlikli afiş | Hücreler ekrana göre genişliyor, afiş 104pt'de kalıyor; iPad'de her hücrede boşluk | `Color.clear` + `aspectRatio` ile hücre genişliğini ölç, görseli doldur |
| Nuke'u yapılandırmadan bırakmak | Afişler **tam boyutta** çözülüyor; 1000×1500 afiş 104pt'lik küçük resim için ~6 MB. Yüz afişte bellek baskısı | `ImageProcessors.Resize(width:)` ile çözme sırasında küçült |
| Sayfalamada beraberlik bozucusuz sıralama | Aynı adlı içerik (IPTV'de aynı film farklı kalitelerde) sayfa sınırında tekrar edip kaybolur | `ORDER BY title, id` — ve `id`'yi indekse de ekle |
| Varsayılan görünümün indeksi | `(playlistId, categoryId, sortOrder)` indeksi, kategori süzülmeyince sıralamayı karşılamıyor → tam sıralama | Süzgeçsiz hâl için ayrı indeks: `(playlistId, sortOrder, name)` |
| `.sensoryFeedback` kullanmak | iOS **17+** — bizde derlenmez | UIKit üreteçleri (`UISelectionFeedbackGenerator` vb.), `prepare()` ile sakla |
| Kaynaksız uygulamanın karesini almak | Tek görülebilen ekran karşılama; ana sayfa/ızgara/detay **kör** yazılıyor | `-seedDemoData` ile sahte katalog yaz, `-startup.tab <ad>` ile her sekmenin karesini al |
| Dokunma gerektiren ekranın karesini alamamak | Oynatıcıya girmek bir kanala dokunmayı gerektiriyor, `simctl` dokunma üretmiyor → oynatıcı kör yazılıyor | `-startup.player <storageKey>` ile açılışta doğrudan sun (`#if DEBUG`). Demo kaynağın ilk kanalı gerçek bir HLS akışına bakıyor, böylece kare video çizildiğini de kanıtlıyor |

> 💡 **iOS numarası:** `xcrun simctl launch … -anahtar değer` biçimindeki
> argümanları iOS otomatik olarak `NSUserDefaults`'a yazar. Açılış sekmesi
> tercihi zaten oradan okunduğu için sekme sekme kare almak **sıfır satır**
> ek uygulama kodu gerektirdi.
| Sağlayıcının `is_adult` alanına güvenmek | Ebeveyn kilidi kuruluyor ama hiçbir şey gizlenmiyor: M3U'da alan yok, panellerin çoğu doldurmuyor | Kategori adından çıkar (`AdultContentDetector`), damgalamayı senkronizasyonda yap |
| **Panel ucuna GET atmak** | Aktivasyon kodu **hiç** çalışmıyor: uç `405 method_not_allowed` dönüyor, kullanıcı "kod geçersiz" sanıyor | `POST` + JSON gövde. Kod sorgu dizesine **konmaz** — sunucu erişim kayıtlarına düşer, kod tek kullanımlık bir sırdır |
| 4xx gövdesini atmak | Panel asıl sebebi `{"error":"invalid_code_format"}` diye **400 gövdesinde** açıklıyor; kullanıcı "Beklenmeyen durum kodu: 400" görüyor | Gövdeyi durum kodundan **önce** oku (`HTTPResponse` döndür, fırlatma) |
| Panel cevabını düz varsaymak | Kod kabul ediliyor ama "Aktivasyon bilgileri eksik": alanlar `playlist` **nesnesinin içinde** geliyordu | Okuma sırası: iç içe nesne → düz alan → yedek ad. Alan adlarını (değerleri değil) logla |
| Kullanıcı girdisini "temizlemek" | Kod büyük harfe çevriliyor + karakter süzgecinden geçiyordu; panel büyük/küçük harfe duyarlıysa **doğru kod bozuluyor** | Yalnızca boşluk kırp. Geçerliliğe **panel** karar verir; yerel süzgeç test edilemeyen bir hata sınıfı üretir |
| `playlist_type` alanına güvenmek | Panel "m3u" diyor ama adres `get.php?username=…&password=…` — yani Xtream. M3U olarak işlenince **250 MB tek dosya** iniyor, 315 bin satırın hepsi "kanal" oluyor, film/dizi **sıfır** | Bağlantı kimlik taşıyorsa Xtream kur (`XtreamLink`). Tür alanı bağlantının **biçimini** anlatır, hesabın türünü değil |
| Marka bilgisini ayrıştırıp kullanmamak | Bayinin rengi (`#E50914`) çözülüyor ama hiçbir yere uygulanmıyordu; herkes varsayılan maviyi görüyordu | Aktivasyon sonucu tema denetleyicisine bağlanmalı. Ayrıca renk `theme.primary_color`'da — düz `reseller_primary_color` hiç gelmiyor |
| Panel alan adını belgeye göre yazmak | `maintenance_mode` bekleniyordu, panel `maintenance` gönderiyor → **bakım modu hiç tetiklenmiyor** | Canlı cevabın alan adlarını listele, ikisini de oku |
| Motor kimliğini yüzey kimliği sanmak | Kanal değişince ses geliyor, görüntü **donuyor**: her `attach` yeni motor **örneği** üretiyor ama kimlik dizgesi aynı (`avplayer` → `avplayer`), SwiftUI yüzeyi yenilemiyor | `surfaceGeneration` sayacı; `.id(engineIdentifier)` yetmez |
| Her kanal değişiminde motoru yeniden kurmak | Zaplama yavaş: teardown + yeni `AVPlayer` + ses oturumu + PiP + yüzey yeniden kurulumu, **her kanalda** | Resolver kararı değişmediyse motoru koru, yalnızca `load()` çağır |
| Motorun yalnızca hata sinyaline güvenmek | AVPlayer çözemediği videoyu **sessizce atlıyor**: `readyToPlay`, hata yok, ses akıyor, ekran siyah — yedek motor hiç denenmiyor | "Oynuyor ama kare yok" gözcüsü. VLC'de tersi: ölü yayında sonsuza kadar `.opening` — orada da zaman aşımı gerekir |
| `.menu` Picker'ın etiketine güvenmek | `Form`/`List` dışında etiket **hiç çizilmiyor**, ekranda yalnızca seçili değer duruyor ("Dengeli" yazıyor, neyin dengeli olduğu yazmıyor) | Etiketi elle çiz, Picker'a `.labelsHidden()` |
| Oranı görsele uygulamak | `RemoteImageView`'a `.aspectRatio` verilince görsel kendi doğal genişliğini dayatıyor, **tüm blok ekrandan taşıyor** | Oranı boş kutuya ver: `Color.clear.aspectRatio(…).overlay { görsel }` |
| Sinematik başlığı tek bileşen sanmak | Opak gezinme çubuğu görselin üst ~110pt'sini ve afişin tepesini örtüyor | Ekran ayrıca `.toolbarBackground(.hidden, for: .navigationBar)` demeli — bu bir **iki parçalı sözleşme** |
| **Başarısızlığı önbelleğe almak** | Yedek sunucu listesi bir kez alınamayınca `cachedHosts = []` yazılıyor ve `if let cachedHosts` artık hep doğru: panele bir daha **hiç** sorulmuyor, failover oturum boyunca sessizce ölüyor. Üstelik bu kod yalnızca kayıtlı sunucu ölüyken çalışıyor — yani ağın zaten sorunlu olduğu an | Yalnızca **başarılı** sonucu önbelleğe al. Negatif önbellek gerekiyorsa süreli olsun |
| Güvenlik kontrolünde `try?` | `try? secrets.read(…)` "kayıt yok" ile "okunamadı"yı SE-0230 ile tek `nil`e düzleştiriyor; Keychain hatası kilidi **varsayılan PIN'e açıyor**. Kullanıcı kendi PIN'ini kurmuş sanarken 0000 kabul ediliyor | Hatayı `do/catch` ile ayır, şüphede **kapalı** kal. Yarım kayıt (özet var, tuz yok) da varsayılana düşmemeli |
| Çok anahtarlı Keychain yazımını atomik sanmak | Özet yazılıp tuz yazılamazsa depo kalıcı olarak tutarsız kalıyor | Hata yolunda ikisini de sil (`KeychainPlaylistAccessControl.configure` bunu baştan doğru yapıyordu) |
| **Testi olan ama çağrılmayan kod** | `DNSFailoverService.reset()` ve `DefaultContentProviderFactory.invalidate` için test **var**, üretimde call-site **yok**. Yeşil test "bu özellik çalışıyor" sanısı veriyor | Testin varlığı bağlanmışlığı kanıtlamaz. Yeni bir genel API yazınca call-site'ı da aynı commit'te bağla — **ya da** call-site'a hiç ihtiyaç bırakma: sağlayıcı önbelleğinde çözüm, `invalidate` çağrısı eklemek değil, anahtara `kind`'ı koymak oldu. Unutulabilecek adım en iyi ihtimalle **olmayan** adımdır |
| **`%ld` ile `%lld` ayrımı** | Aynı metin iki yoldan çevriliyor ve **farklı anahtar** üretiyorlar: `language.localized("%ld dk", n)` → `%ld`, SwiftUI `Text("\(n) dk")` → `%lld`. `.strings` dosyasında yalnızca biri varsa diğer yol sessizce **Türkçe kalıyor** — derleme ve test geçiyor. Dizi bölüm süreleri böyle İngilizcede "42 dk" kaldı | Sayı içeren her anahtarın **iki ikizini de** yaz. Tuzağa üç kez düşüldü: `%lld gün kaldı`, `%lld kaynak kayıtlı`, `%lld dk` |
| Denetim betiğinin adına güvenmek | Kural 7 "force unwrap yok" diyordu ama regex yalnızca `try!`/`as!` arıyordu; `URL(string:)!` yıllarca **yeşil** raporlandı ve açık iş #4 tam da bu yüzden kimsenin gözüne çarpmadı | Denetim kuralını yazarken **kırmızıya döndüğünü de** gör. Yakalamadığı bir örnek uydurup dene |

> 🔍 **Yöntem dersi:** Ekran boyutu hatası iki tur **tahminle** kovalandı,
> üçüncüde `plutil -p` ile derlenmiş plist okununca cevap tek satırda çıktı.
> Belirti tekrar ediyorsa tahmini bırak, ölç.

> 🔍 **Üçüncü yöntem dersi — en pahalısı:** Faz 5 fazlarca "gerçek cihaz
> gerekiyor" diye ertelendi. Varsayım hiç sınanmadı. Sınandığında ortaya
> çıktı ki AVFoundation bir **sistem çerçevesi**: CI'daki macOS runner onu
> derliyor, test ediyor, simülatörde çalıştırıp video karesi alıyor.
> Gerçekten engellenen tek parça VLCKit'ti (60 MB binary).
> **Dersi:** "yapamayız" demeden önce hangi parçanın gerçekten
> engellendiğini ayrıştır — engel çoğu zaman sanılandan küçüktür.

> 🔍 **İkinci yöntem dersi:** Favoriler testi "yavaş" sanılıp bekleme süresi
> uzatılabilirdi. Süre yerine **koşul** beklenince gerçek sebep ortaya çıktı:
> yayın, abone olunmadan yapılıyordu ve sessizce kayboluyordu. Sabit uyku
> hatayı düzeltmiyor, **saklıyordu**.

---

## 12. "MAIN NEDEN ŞİŞMEZ?"

Klasik IPTV projelerinde `ContentView.swift` 3000 satır olur çünkü **her şey oraya bağlanır**.
Burada üç mekanizma bunu fiziksel olarak imkânsız kılar:

1. **Fiziksel ayrım** — Her feature ayrı Swift paketi. App'e kod yazmak için önce paket eklemen gerekir; bu bir sürtünmedir ve doğru yere yazmaya iter.
2. **Tek bağlanma noktası** — Somut sınıflar sadece `AppContainer` içinde birleşir. App büyüse bile **tek bir dosya** büyür, o da sadece `let x = XImpl(y:)` satırlarıdır.
3. **Derleyici zorlaması** — `FeatureLive`, `OctopusData`'yı import **edemez**. "Şuraya hızlıca şunu yazayım" kestirmesi derlenmez.

**Sonuç:** Proje 50.000 satıra çıkar, `OctopusApp.swift` yine 40 satır kalır.

---

## 13. NEREDE KALDIK? (2026-08-11)

### Bu oturumda tamamlananlar

| Konu | Durum | Not |
|---|---|---|
| VLCKit entegrasyonu (Faz 5) | ✅ | `vlckit-spm` 3.6.0. UHD/HEVC kanallar artık görüntülü açılıyor |
| "Sesli körlük" gözcüsü | ✅ | AVPlayer sessizce video izini atlıyordu; 3 sn sonra yedeğe düşülür |
| Canlı TV gömülü mini oynatıcı | ✅ | Liste dokunuşu tam ekrana atlamıyor, yayın tepede başlıyor |
| Kanal geçiş hızı | ✅ | Motor yeniden kullanımı + tampon ayarları. Standart kanal ~1,3 sn |
| Canlıda otomatik yeniden bağlanma | ✅ | Artan gecikmeyle 3 deneme, sessiz |
| Sonraki bölüm | ✅ | 8 sn geri sayım, elle oynatma/iptal ve sezonlar arası otomatik sıra |
| Oynatıcı hareketleri + kilit | ✅ | Çift dokunma 10 sn; sol parlaklık, sağ ses; yanlış dokunmaya karşı kilit |
| Canlı oynatıcı paneli | ✅ | Oynatıcıdan çıkmadan aranabilir kanal listesi ve şimdi/sırada EPG |
| Yayın öncesi görsel kalite turu | ✅ | Kompakt oynatıcı kontrolleri/bildirim, güvenli alt boşluklar, yatay raf ipucu ve markalı logo-afiş yedekleri |
| Standart uygulama logosu | ✅ | Ahtapot oynat simgesi AppIcon oldu; bayi logosu yoksa onboarding ve ana sayfada çerçevesiz, şeffaf işaret kullanılıyor |
| Tam ekran VLC denetimleri | ✅ | Video ve SwiftUI katmanı aynı UIKit hiyerarşisinde; CI'da fallback karesi var |
| Ayarlar → Oynatıcı bölümü | ✅ | Tampon, yerleşim, yeniden bağlanma, yedek motor — hepsi gerçek etkili |
| Detay sayfası sinematik başlık | ✅ | Şeffaf çubuk + oranla ölçeklenen arka plan |
| Ana sayfa başlık kartı | ✅ | Dönen afiş kaldırıldı; marka, saat, abonelik, kullanıcı |
| Ana sayfa liste işlemleri | ✅ | Hero altında yeni liste ve aktif listeyi yenileme; Ayarlar'daki sağlayıcı bağlantısı gizlendi |
| Son eklenen diziler rafı | ✅ | `SeriesRepository.recentlyAdded` (sıralama `lastModified`) |
| Abonelik bitişi kalıcı | ✅ | `authenticate()` sonucu atılıyordu; artık `playlist.expiresAt` |
| Aktivasyon kodu | ✅ | GET→POST, iç içe cevap, normalleştirme — üç ayrı hata |
| Giriş sonrası katalog özeti | ✅ | Kanal, film ve dizi adetleri gerçek senkronizasyon sonucundan gelir; temalı kartlarda sayarak görünür ve başarı anı kısa süre korunur |
| M3U → Xtream dönüşümü | ✅ | `XtreamLink`. Kanıt: m3u'da 315k kanal/0 film · xtream'de 3k kanal/38k film/4k dizi |
| Bayi markası | ✅ | `theme.primary_color` okunuyor **ve** artık uygulanıyor |
| KSPlayer denemesi | ❌ | Entegre edildi, çalıştı, **çöktü** (kütüphane içi trap), kaldırıldı |

### Açık işler

| # | İş | Neden bekliyor |
|---|---|---|
| 1 | **Bayi kodu ucu bağlı değil** | `/api/public/reseller-config/{kod}` app_name, logo, iletişim, `minimum_version` ve **DNS yedek listesi** döndürüyor. Uygulama bu ucu hiç çağırmıyor çünkü **bayi kodunu bilmiyor** — aktivasyon cevabı kodu döndürmüyor. Seçenekler: (a) panel cevabına `reseller_code` eklesin, (b) bayi başına derleme, (c) kullanıcı girsin |
| 2 | **`DNSFailoverService.reset()` çağrılmıyor** | Üretimde call-site yok (yalnızca testi var). Sonucu küçük: ölü sunucu için bulunan yedek, asıl sunucu geri gelse de oturum boyunca kullanılmaya devam eder. Sağlayıcı önbelleğinin bayatlaması **çözüldü** — anahtar artık `id + kind`, kaynak tanımı değişince önbellek kendiliğinden ıskalıyor (bkz. `DefaultContentProviderFactory.CacheKey`) |
| 3 | Mevcut M3U kaynakları dönüşmüyor | Dönüşüm yalnızca **yeni** eklemede. Eski kayıtlar silinip yeniden eklenmeli — ya da senkronizasyonda göç yazılmalı |
| 4 | `PanelEndpoint.defaultBaseURL` force unwrap | CLAUDE.md yasaklıyor, `check-architecture.sh` yakalamıyor |
| 5 | UHD yayının native uyumluluğu doğrulanmalı | Kullanıcı UHD kanalların AVPlayer'da çalışmadığını ve otomatik VLC'nin bilinçli tercih olduğunu bildirdi. HEVC donanım desteği tek başına yeterli değil: HLS'te fMP4 paketleme gerekir. Gerçek yayın manifesti/segmenti, iPhone modeli ve iOS sürümüyle ölçülmeli; doğrulanana kadar otomatik VLC korunur |

### Doğrulanmış gerçekler (tahmin değil)

- **API adresi:** `octopusdocumentary.com` ✅ · `octopusplayer.com/api/*` → CMS 404 ❌
- Bayi sayfası `octopusplayer.com/b/{kod}` 4 haneli, 10 dakikalık kod üretir
- Aktivasyon başarı cevabı: `{ success, playlist:{…}, theme:{…}, home_theme:{…} }`
- Panel `invalid_code_format` hatasını **boş gövdeye de** döndürür — "biçim yanlış" değil, "okuyamadım" demektir
- Açılış süreleri (simülatör): standart kanal 1,3–2,4 sn · UHD (yedeğe düşerek) ~7,5 sn

### Ölçüm araçları

- `Açılış: N ms · motor X` — her yayın açılışında (kalıcı log)
- `Aktivasyon cevabı: HTTP N · <hata> · alanlar=[…]` — alan adları, **değerler asla**

### 03.10.2026 — gelecek güncelleme için oynatıcı ve istek incelemesi

- Motor kurulumu artık biçimi yeniden değerlendirip kararı kaybetmez:
  UHD ipucu ve hatırlanan fallback tercihi gerçek motor fabrikasına iletilir.
- Kapanış önce ilerleme anlık görüntüsünü alır, motoru ve ekran durumunu
  bırakır, sonra depoya yazar. Bekleyen eski kapanış yeni oturumu durduramaz.
- AVPlayer gözlem ve bitiş olayları içerik nesliyle doğrulanır; eski iz
  keşfi durdurmada da iptal edilir ve her asenkron aşamada güncel asset kontrol edilir.
- Kanal/bölüm adres çözümünde yalnızca son seçim uygulanır; geç gelen
  sonuç veya hata güncel yayını ve rehberini ezmez.
- Canlı yayın zaman olayları ve kayıt aralığı dolmamış VOD olayları için
  ilerleme yazma görevi oluşturulmaz. Yazılacak konum olay anında yakalanır.
- Film/dizi detay çağrıları kimlik başına devam eden tek isteği paylaşır.
  Film künyesi güncel katalog kimliğini, sırasını, kategorisini ve yetişkin
  işaretini koruyarak birleştirilir; eksik künye alanları liste verisini silmez.
- `ContentProvider.invalidateCache()` senkronizasyon öncesinde çağrılır.
  M3U yenilemesi taze listeyi bir kez indirir; geçersiz kılınan eski indirme
  yeni önbelleği dolduramaz.

Bu davranışlar için 19 regresyon testi eklendi. Windows'ta mimari denetimi
ve değişen Swift dosyalarının sözdizimi ayrıştırması geçti; Swift/Xcode
bulunmadığı için XCTest ve iOS derlemesi bu ortamda **çalıştırılmadı**.
Yayın doğrulaması mevcut CI'daki `OctopusData`, `OctopusPlayback` ve
`OctopusFeatures` paket testlerini, ardından gerçek iPhone'da hızlı zaplama,
mini/tam ekran geçişi, UHD yayın, arka plan, PiP ve AirPlay denemesini gerektirir.

### 03.10.2026 — UHD / AVPlayer incelemesi

- UHD için otomatik VLC bilinçli ürün kararıdır; kaldırılmadı. Kanal adı
  yalnızca koruyucu ipucudur, codec veya container kanıtı değildir.
- Apple'ın [HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/)
  §1.5'i HEVC için fMP4 ister. `.m3u8` adresi tek başına uyumluluk
  göstermez; HEVC'nin MPEG-TS parçalarında gönderilmesi olası açıklamadır.
  Kullanıcının gerçek yayını alınmadığı için kök neden henüz doğrulanmadı.
- Boyut metadata'sının ilk kare sayılması düzeltildi: görüntü gözcüsünü
  artık `AVPlayerLayer.isReadyForDisplay` kapatır. Ses akışı ayrı işaretlenir.
  Katmanın gözlemi içerik nesline bağlıdır; eski kanalın sinyali yeniye taşınmaz.
- Gözcü yalnızca görünür yüzey/PiP ve kesintisiz oynatma sırasında çalışır;
  duraklama/tamponlamada iptal edilir ve AirPlay'e yanlış fallback üretmez.
  Mevcut zaman gözlemi, sonradan ekrana takılan yüzeyi de kontrol eder.
- Aynı native arıza bir kez bildirilir. Teşhis kaydı video izi sayısı,
  boyut, ilk kare, AirPlay durumu ve sistem hata domain/kodunu içerir;
  yayın URL'si, sunucu hata metni veya kimlik bilgisi eklenmez.
- İki ilk kare regresyon testi ve ağ gerektirmeyen 3.9 KB yerel H.264 örneği
  eklendi. Windows'ta mimari/sözdizimi denetlenebilir; Xcode testleri ve
  gerçek cihaz oynatma denemesi burada çalıştırılamadı.

### 08.10.2026 — App Store 4.3(a), kaynak kontrolü ve cihaz teşhisi

Apple 07.10.2026 tarihinde 1.0 (7) sürümünü iPad Air 11-inch (M3) üzerinde
4.3(a) benzer/yeniden paketlenmiş uygulama gerekçesiyle reddetti. Önceki
5.6 konusu 03.09 mesajında giderilmiş olarak bildirilmiş; son ret özgünlük
üzerine. Performans düzeltmeleri tek başına bu gerekçenin giderildiğini
kanıtlamaz. Yeniden gönderimden önce gerçek işlevler, doğru mağaza metni
ve aynı Release sürümünden alınan iPhone/iPad kanıtları gerekir.

Kaynak kontrolü Ayarlar'dan herkes için erişilebilir olacak. Domain'deki
`SourceHealthReading` sözleşmesi üzerinden yerel katalog özetini alır;
GRDB sorguları Data'da, görünüm ve destek raporu FeatureSettings'tedir.
Kanal listesi bütünüyle belleğe alınmaz; hiçbir yayın topluca yoklanmaz.
Sayılar, tekrar eden yayın anahtarları ve eksik EPG/görsel bilgisi gösterilir.
Bu kontrol canlı bağlantı testi veya codec doğrulaması olarak sunulmaz.

Paylaşılabilir rapor yalnızca açıkça seçilmiş özet alanları ve oynatıcı
durumunu içerir: kaynak adı/adresi, kullanıcı adı, parola, içerik adı,
PIN, cihaz kimliği veya ham hata metni eklenmez. Paylaşımı kullanıcı
sistem paylaşım ekranında başlatır. SQL bağlama değerlerini açık loglayan
DEBUG trace kaldırılır. Cihazdan log toplama ayrıca yerel Windows aracıyla
yapılır; bağlanmamış cihaz veya çalıştırılmamış test başarı sayılmaz.

8 Ekim yerel doğrulaması: mimari denetimi ve `git diff --check` temiz;
42 değişen/yeni Swift dosyası sözdizimi ayrıştırmasını geçti. Kaynak
okuyucusunun SQL'i kaynak ayrımı, boş katalog ve 50 bin sentetik kanalda
doğrulandı. Log aracının 9 Python testi geçti; USB cihaz sayısı 0.
Data/Playback/Settings için 7 yeni XCTest eklendi, Windows'ta **koşulmadı**.
İmzalı yükleme işi mevcut CI'a bağlandı; CI/release YAML doğrulandı,
GitHub derleme/yükleme tetiklenmedi. Ayarlar bölümleri ve bağımlılıkları
200 satır altında ayrı dosyalara ayrıldı. Ayrıntılı bulgular, gönderilmemiş
Apple yanıtı ve metadata taslağı `APP-STORE-INCELEME-2026-10-08.md` içinde;
Windows cihaz komutları `IOS-CIHAZ-LOG.md` içinde.

8 Ekim cihaz bağlantısı sonrası: `usbmux --simple` çıktısının JSON dizi
olduğu görüldü; satır ayrıştırması bağlı cihazı yanlışlıkla 0 sayıyordu.
Keşif düzeltildi, araç testleri 12 oldu. Tek iPhone'a USB/lockdown,
os_trace ve DVT erişimi doğrulandı. Kurulu Octopus **1.0.0 (2)**;
yerel değişiklikleri veya Apple'ın build 7'sini cihazda doğrulamış değiliz.
Octopus açıldıktan sonra 180 saniyede 93 süreç logu alındı; UHD/oynatıcı
teşhis olayı yok. App adına uyan crash sayısı 0 (Jetsam hariç). Tek
CPU/bellek örneği alındı; oynatma yükü veya sızıntı sonucu değildir.
Gerçek cihaz ayrıntıları `IOS-CIHAZ-LOG.md` içinde; bütün ham kayıtlar
git dışındaki `.artifacts/device-logs/` altında tutulur.

8 Ekim UHD denemesi (cihazdaki build 2): kullanıcı görüntü olmadığını
bildirdi. Native motor dört kez yüklendi, her seferinde video izi yok
uyarısı geldi; üç yeniden bağlantı sonrası başarısız oldu. Bu kayıtta
VLC yükleme olayı yok. Sonraki normal kanal native ile 2868 ms'de açıldı.
Codec/container bu logla belirlenemedi; HEVC/TS teşhisi kesinleşmedi.
17 bine yakın SQL debug kaydı, `AVAudioSession Hang Risk` ve SwiftUI
`Publishing changes from within view updates` uyarıları görüldü.
Yerel kaynakta SQL trace zaten kaldırılmıştır. Ses oturumunun bloklayan
işlemleri ortak bir seri iş kuyruğuna alınacak; motor yüklemeleri bu
aktivasyonu beklerken nesil/iptal kontrolüyle korunacak. Hosted overlay
güncellemesi çizim turundan sonraya taşınıp son değerle birleştirilecek.

8 Ekim UHD son kullanıcı doğrulaması: UHD'de ses var, görüntü yok;
normal kanalda görüntü var. Ayrı 180 saniyelik kayıt 31.152 olay içeriyor:
16.989 SQL logu, 12 AVAudioSession ve 10 SwiftUI uyarısı. UHD sonrasında
app adına crash sayısı tekrar 0 (Jetsam hariç). Codec/container hâlâ
bilinmiyor; eski build'de VLC yükleme olayı görülmediği, yedeğin neden
devreye girmediğini tek başına açıklamaz.

Yerel ses/overlay düzeltmeleri tamamlandı: iki motor AppContainer'da
ortak AudioSessionWorker kullanır. Aktivasyon kuyruğa MainActor yaşam
döngüsü sırasıyla eklenir; bloklayan AVAudioSession işlemleri seri arka
plan kuyruğundadır. Aynı kategori tekrar kurulmaz. Her iki motor await
sonrası iptal/nesil kontrolü yapar. Overlay yayını çizim turundan sonraya
taşınır, son güncelleme birleştirilir, dismantle bekleyen işi iptal eder.
Motor seçim logu ve güvenli rapor `fallbackAvailable` alanı eklendi.

Ses için 3, overlay için 2 regresyon XCTest'i eklendi; Windows'ta
**çalıştırılmadı**. Son yerel kontrol: 50 Swift dosyasında sözdizimi hatası
yok, mimari temiz, kaynak SQL'i 50 bin sentetik kanalda doğru, 42 yeni
ekran metni/dil dosyası anahtarları kontrol edildi. Telefondaki build 2
değişmedi; bu düzeltmelerin gerçek cihaz başarısı macOS derlemesi sonrası
aynı UHD/normal kanal ve geçiş denemeleriyle doğrulanmalı. Ham loglar git
dışında, ayrıntılı sonuç `IOS-CIHAZ-LOG.md` içindedir.

8 Ekim güncel uygulamayı kurma talebi: kullanıcı yeni kodu içeren binary'nin
telefona kurulup aynı UHD kanalda denenmesini istedi. Bu test için yapı
numarası 8'e yükseltildi. Mevcut GitHub/Apple imzalama yoluyla gerçek
macOS derlemesi ve XCTest çalıştırılacak; başarılı derleme ve cihazdaki
build numarası doğrulanmadan düzeltmeler çalışmış sayılmayacak.

USB kurulum için App Store Release iş akışına ayrı `device` paket hedefi
eklenir. Seçilen cihaz kimliği GitHub environment secret üzerinden Apple
cihaz kaydı/profiline iletilir, açık workflow input veya loga yazılmaz.
Release arşivi imzasız hazırlanır, `release-testing` dışa aktarımı hedef
cihazı içeren profil ile imzalar. Cihaz profili bulunan IPA, yerel alıcının
açık anahtarıyla şifrelenmeden artifact olarak yüklenmez; özel anahtar
Windows'ta `.artifacts` içinde kalır. Bu hedef TestFlight/App Store'a yükleme
yapmaz. Aynı bundle ID ile güncelleme kurulur; eski uygulama/veri silinmez.

Mac CI ilk doğrulaması (37774933006): Domain/mimari/DesignSystem geçti;
Playback log interpolasyonunda açık `self` gerektiği için derleme durdu.
Bu hata düzeltildi. Data'da 264 testten yalnızca M3U somut nesne üzerinde
`invalidateCache` testi başarısızdı: async protokolün extension varsayılanı
sync aktör metodu yerine seçilebiliyordu. M3U metodu açıkça async yapıldı.
Device export araçlarının 8 testi ve mevcut log aracının 12 testi yerelde
geçti. Güncel kaynak için yeniden macOS CI/imzalama gerekiyor.

Reusable CI'da elle başlatılan turlar aynı concurrency kilidine takıldı:
yeni tur, eski turda tamamlanmış mimari işi için bekliyor görünüyordu.
Elle başlatılan turların grup adına run ID eklendi; otomatik push/PR
turlarında önceki işi iptal etme davranışı korundu.

8 Ekim build 8 doğrulaması: kaynak commit'i `88fc529`, GitHub Actions
`37776653115` tamamlandı ve başarılı. Mimari/Domain/DesignSystem/Data/
Features/Playback/iOS uygulama işleri geçti. Mac XCTest sayıları Playback
57, Data 264, Features 194; ses/overlay ve M3U regresyonları geçti.
Hedef cihaz Apple'da zaten ENABLED idi. `release-testing` imzalı IPA
şifreli artifact olarak üretildi; TestFlight/App Store'a yükleme yapılmadı.
Yerelde SHA-256/commit/bundle/build kontrolü sonrası USB kurulumu yapıldı.
İlk installer timeout'u ve streaming coordinator çakışması sonrası aynı
bundle ID'ye güncelleme tekrar denendi, çalışan Octopus kapatıldı.
İlerleme callback'i hata verse de bağımsız USB sorgusu **1.0.0 (8)**
kurulumunu doğruladı; uygulama/veriler silinmedi. Yeni binary açıldı,
16:01 İstanbul'da 240 saniyelik app log kaydı başlatıldı; UHD/normal
görüntü-ses sonucu ayrıca kullanıcı denemesiyle doğrulanacak.

Build 8 açılış kaydı tamamlandı: 2.915 olay, 0 oynatma olayı; AppContainer
logu VLC yedeğinin bağlı olduğunu doğruladı. SQL trace/ses hang/SwiftUI
yayın uyarısı bu örnekte yok, ancak kanal açılmadığı için UHD düzeltmesi
başarı sayılmaz. Octopus adına crash kontrolü tekrar 0 (Jetsam hariç).
Aktif kayıt yok; kullanıcının UHD/normal kanal denemesinden önce yeniden
kayıt başlatılmalı. Binary kaynak commit'i `88fc529`; sonraki belge
commit'leri bu kurulu binary'nin parçası değildir.

### 08.10.2026 — Android referansından iOS build 9 ve yeniden inceleme

Kullanıcı Android referansındaki cihaz/stabilite çalışmalarının iOS'a
uyarlanmasını ve düzeltmelerden sonra Apple'a tekrar gönderilmesini istedi.
`octopus--player (2)` salt okunur karşılaştırıldı. Android TV odak, tunneling,
Realtek ve SurfaceView kuralları iOS'a taşınmaz; ortak ürün davranışları
iOS yaşam döngüsü ve bellek sınırları üzerinden uygulanır.

- Native HTTP yetki/kaldırılmış içerik hatası VLC tercihini değiştirmez;
  geçici ağ/5xx için sınırlı aynı-motor toparlanması, decoder/ilk-kare
  hataları için uyumluluk motoru vardır. Referer gerektiren kaynak doğrudan
  VLC'ye gider. Belgelenmemiş AVURLAsset header anahtarı kaldırıldı.
- Sonraki bölüm yalnızca gerçek `.ended` olayından sonra kullanıcı seçimiyle
  ilerler. Oturumluk otomatik seçim kalıcı tercih değildir; jenerik %95
  zaman eşiğinde kesilmez. `.playing` ilk-kare ölçümü değildir.
- Katalog türlerinden biri başarısızsa diğerleri senkronize edilir;
  başarısız türün mevcut verisi korunur. Tüm türler veya yerel yazım
  başarısızsa hata gizlenmez. Hesap tarihi atomik güncellenir.
- Tamamen bozuk ama boş olmayan provider cevabı boş katalog sayılmaz;
  önceki içerik korunur. Bölüm `direct_source` adresi doğrulanıp nullable
  v6 migration ile saklanır; eksik uzantı için MP4 varsayımı üretilmez.
- Rehber satırları, okumaları, kapsamı ve indirme throttle'ı kaynağa
  ayrılır. v5 migration eski kaynağı bilinmeyen rehberi başka kaynağa
  atamaz. Rehber adresi hash ile takip edilir; yarım XML başarı sayılmaz.
- Kaynak değişimi eski oynatıcı/ekranları kapatır; eski arama sonuçları
  yeni bağlama taşınmaz. Provider kuruluşu ve senkronizasyon ortaklanır.
  Yeni kaynağın PIN durumu çözülene kadar kök ekran yükleme kapısındadır.
- Nuke thumbnail decoder tam bitmap oluşmadan boyutu sınırlar; ayrı
  bellek/disk bütçesi ve indirme eşzamanlılığı kullanılır. Nuke'nin kendi
  bellek uyarısı temizliğine ikinci gözlemci eklenmez.
- App Store'da M3U/Xtream girişini panel bayrağı gizleyemez. Gizlilik,
  destek ve mevcut Standard Apple EULA bağlantıları kurulum ve Ayarlar'dadır.

Kullanıcı Xtream inceleme hesabı sağlayamadı. Yalnız eski M3U'nun bütün
ekranları kapsadığı iddia edilmez. Herkes için isteğe bağlı `.sampleLibrary`
kaynağı iki CC BY 3.0 Blender filmi, açıkça örnek olarak açıklanan kayıtlı
kanal, bölüm seçkisi ve yerel rehber sunar. Kaynak ayrı kaydedilir; kişisel
listeler silinmez. Atıf/lisans/film ekibi bağlantıları gösterilir; film
baytları değiştirilmez. Medya oynatma kullanıcı eylemiyle başlar. Archive
MP4 aynaları kullanılır; resmî Blender MP4 adresleri artık ZIP olduğundan
doğrudan oynatma için kullanılmaz. Bu örnek gerçek Xtream/EPG/UHD servisi
uyumluluğunu kanıtlamaz. Örnekler yaş anketinde değerlendirilmelidir.

Hedef build **9**. Yeni ayrı `OctopusReview` şeması Release'i DEBUG tohumu
kullanmadan herkese açık örnek kurulumundan yürütür; gerçek native kare,
film/bölüm/ayar/kaynak kontrolü ekranlarını iPhone ve iPad'de kaydeder.
İmzalı yayın işi tüm CI kapıları sonrası aynı arşivden App Store ve
yapılandırılmış USB paketi üretir; cihaz IPA'sı şifreli saklanır.

Yerel mimari ve 89 Swift sözdizimi kontrolü temiz; 50 bin sentetik kanal
SQL kontrolü ve iki dilde tekrar eden anahtar kontrolü geçti. Log aracı
12, cihaz paketi aracı 8 Python testi doğru bağımlılık ortamında geçti.
Yeni XCTest'ler ve gerçek Release akışı henüz macOS'ta çalıştırılmadı;
TestFlight yükleme veya App Review gönderimi henüz tamamlanmadı. Sonuçlar
CI ve canlı App Store Connect durumuyla ayrıca kaydedilecek. Araştırma ve
karşılaştırma `APPLE-INCELEME-HAZIRLIK-2026-10-08.md` ve
`ANDROID-IOS-UYARLAMA-2026-10-08.md` dosyalarında.

### Build 9 — gerçek Mac doğrulamasında bulunanlar (8 Ekim)

`dd3eae2` turunda Domain 84, Playback 71, Features 211, DesignSystem 11
ve uygulama kabuğu 14 XCTest geçti. Data 294 testten birinde eski HTTP
testinin ortak yanıt kuyruğu/sayacı geç kalan iptal isteğinden etkilenebildi;
oturum başına URL ve durum ayrıldı, tam iki tekrar isteği beklentisi korunur.
Üretim HTTP istemcisi bu test düzeltmesi için değiştirilmedi.

Release akışı gerçek örnek kitaplığı kurup film listesine ulaştı. Kartların
2:3 kutusu görsel olarak doğru olsa da dolgu görüntüsünün erişilebilir ve
dokunma alanı yanındaki hücreye taşıyordu. GridPoster'ın dekoratif görüntüsü
bu alanlara katılmaz; film/dizi kartlarının dokunma şekli kendi kutusudur.
Release UI testi ekran dışına taşan veya birbirine binen film kartlarını
da denetler. Üst kapsayıcı erişilebilirlik kimlikleri düğme kimliklerini
ezdiği için kaldırıldı. CI Release simülatörü gerçek Keychain davranışını
korumak için yerel ad-hoc imzalıdır; üretimdeki hata halinde kilitleme
politikası gevşetilmedi.

App Store İngilizce alt başlığı ve açıklama/tanıtım/anahtar kelimeleri
kaydedildi. Örnek filmlere göre kaydedilen yaş cevapları genel 13+, eski
sistemlerde 12+ sonucunu verdi; bölgesel sonuçlar inceleme belgesindedir.
Build 9 yüklemesi, iPad Release akışı ve fiziksel cihaz UHD görüntüsü hâlâ
doğrulanmadı; başarısız test kapısı Apple'a paket yüklemesini durdurdu.

`3f633b3` turunda Data 294/294, Domain 84, Playback 71, Features 211
ve DesignSystem 11 test geçti. iPhone Release kullanıcı akışı 95 saniyede
tamamlandı: örnek kitaplığı, film seçimi, gerçek AVPlayerLayer video karesi,
örnek bölüm listesi, Ayarlar ve kaynak kontrolü; 10 ekran görüntüsü alındı.
Ardından CI zaten Shutdown durumundaki telefon simülatörünü yeniden
kapatmaya çalıştığı için iPad adımına geçemedi. Simülatör durumu artık
okunur; yalnız Booted ise kapatılır, beklenmeyen durum hâlâ hata verir.
iPad ve yayın yüklemesi yeni turda doğrulanacak. Mağaza metnindeki ayrı
liste PIN'i iddiası yalnız Code/Quick Setup kaynaklarıyla sınırlandırıldı;
normal M3U/örnek kitaplık için kategori ebeveyn PIN'i anlatılır.

`9111266` turunda tüm 685 Swift birim testi ile iPhone ve iPad'in iki
Release kullanıcı akışı geçti; her iki cihazda gerçek AVPlayerLayer karesi
doğrulandı. Yayın yüklemesi aşağıdaki ek üretim onarımını da kapsamak için
bu tur bitince durduruldu; eski paketin gönderilmesi hedeflenmedi.

Release ekran incelemesi Home'daki gerçek bir ilk kullanım hatasını buldu:
dolu M3U kataloğu izleme geçmişi yokken, tarihsiz film/dizi katalogları ise
"son eklenenler" sorgusundan dışlandığı için içerik yok mesajı alıyordu.
Home şimdi mevcut raflar boşken izinli katalogdan Film/Dizi veya Canlı TV
rafı sunar; tarihi olmayan öğeler son eklenen diye etiketlenmez. Okumalar
kaynak bazlı ve sınırlı sayfalıdır, ek HTTP isteği oluşturmaz; ebeveyn
filtresi ile geç kalan kaynak yüklemeleri korunur. GRDB kanal okumalarına
SQL LIMIT/OFFSET ve kararlı kimlik bağlayıcısı eklendi. Sekiz Home ve bir
kanal sayfalama regresyon testi eklendi. Release testi ana sayfadaki gerçek
örnek film kartını ekran görüntüsünden önce bekler. Bu son değişiklikler
için yeni Mac test sonucu, paket yükleme ve cihaz kurulum kanıtı beklenir.

### 08.10.2026 — build 9 son kaynak, USB UHD sonucu ve Apple'da kalan adımlar

Sonraki kullanıcı talebi son gönderimi yeni oynatıcı düzeltmelerine bağladı:
tam ekranda yatay yön, Android'deki kanal paneli, kontrol blur'unun temizliği,
tam ekrandan geri dönüşte görünür yüzey/ses ömrü. Build 9 henüz App Review'a
gönderilmedi; mevcut metadata korunup yeni binary ve gerçek cihaz akışı test edilir.

Doğrulanan binary kaynağı `9c0e98a2b9f09140a062c90eaf7bd7c3010ae299`;
[37808603564 numaralı yayın çalışması](https://github.com/mycrs/ios-octopus/actions/runs/37808603564)
başarılı. Mimari/iOS derleme kapıları ile **694 Swift testi** geçti:
Domain 84, Features 219, Data 295, Playback 71, DesignSystem 11, App 14.
Hem iPhone hem iPad Release inceleme akışı gerçek örnek kitaplık kurulumu,
ana sayfa, film, gerçek `AVPlayerLayer` video karesi, bölüm, Ayarlar ve
kaynak kontrolüyle tamamlandı. Önceki `b861665` turundaki iPad tam ekran
kapatma/test dokunuşu yarışı bu kaynakta giderildi. Native örnek video
kanıtı gerçek kullanıcı UHD kanalının native uyumluluğu anlamına gelmez.

İmzalı Apple yükleme işi geçti. Aynı kaynak/build numaralı USB güncellemesi
%100'e ulaştı; bağımsız InstallationProxy `get_apps` sorgusu telefonda
**1.0.0 (9)** olduğunu doğruladı. `.artifacts/device-builds/build9/installed-context.json`
bu sürüm/build/kaynak commit'ini kaydeder; doğrulama scripti build 9
koşulunu geçmeden kayıt yazmaz. Kişisel uygulama verileri silinmedi.

Kullanıcı build 9'da önceki sorunlu UHD kanalda **görüntü ve sesin geldiğini**,
ardından **normal kanalın çalıştığını** doğruladı. Çalışan UHD motoru **VLC**;
native UHD düzeldi veya bütün UHD formatları çalışıyor diye yazılmaz.
300 saniyelik log yakalama isteği için
`.artifacts/device-logs/20261008T165908300786Z` altında **41.897 olay** var;
ilk/son zaman damgalarının aralığı yaklaşık 259 saniye. Yerel saatle
20:01:14.896'da VLC yükleme nesli 1 / 8 saniyelik tanı: 2 video izi,
seçili iz 0, videoOut true, 3840×2160, drawable ve pencere bağlı.
20:02:02.712'de nesil 2 / 8 saniyelik tanı 1920×1080 ve aynı geçerli
iz/çıktı/yüzey durumunu verdi. Bunlar sayısal metaveridir; VLC'de
görünür ilk kare olayı üretilmez. Görüntü/ses sonucu kullanıcı gözlemidir;
codec/container kök nedeni ve genel native HEVC uyumluluğu bilinmiyor.

App Store İngilizce mağaza alanları, yaş cevapları ve **3.492 karakterlik
Review Notes** kaydedildi. Not alanını kaydetmek App Review mesajı veya
başvuru gönderimi değildir. Gerçek CI PNG'lerinden iPhone 6 + iPad 6
olarak **12 ekran görüntüsü** seçildi. İlk image asset aktarıldı;
`UPLOAD_COMPLETE` processing için ilk 120 saniyelik bekleme sınırı doldu;
sonraki kontrolde hatasız `PREPARE_FOR_SUBMISSION` ve doğru 1206×2622
spec doğrulandı. Diğer 11 görsel/yerleşim henüz tamamlanmadı.
Bu aşamada **eski 21 placement ilişkisi korunuyor**. Tüm yeni image
asset'ler hazır olup güncel sürüm/yüzey/restore kayıtları doğrulanmadan
ilişki kaldırılmaz; image asset silinmez.

Gizlilik denetimi yalnız iOS gövdesine bakarak «Data Not Collected»
sonucuna varmaz. iOS aktivasyonu yalnız `code` gönderiyor, config/DNS'te
kalıcı cihaz kimliği yok; bayi kodu kullanıcı girdisi olarak yolda gidiyor.
Android referansının işaret ettiği yerel owned-backend, rate-limit IP/sayacını
SQLite'a ve yavaş config/DNS/bayi isteklerini IP/teşhis bilgileriyle diske
yazıyor. Rate-limit 60 saniye pencere reset'i silme süresi değildir;
temizleme/rotasyon bulunmadı. Yerel backend'in canlı sürümle eşitliği ve
altyapı saklama süresi doğrulanmadı; public cache başlıkları bunu ispatlamaz.
Bilinen dört PHP dosyasının canlı hash karşılaştırması için güvenilir
FTP/SSH erişimi ve doğrulanmış uzak document root eşlemesi bulunamadı;
uzaktan bağlantı veya DB/log okuması yapılmadı.
Kullanıcı yanıtı/dağıtım kanıtı bekleniyor. Canlı kod eşitse mevcut boş
collected-data manifest'i ve ASC `Data Not Collected` cevabı gerçek
tür/amaç/bağlantı durumuna göre düzeltilmelidir. IP kendiliğinden konum
veya Device ID sayılmaz; ham IP'nin kullanıcıyla bağlantısızlığı da yalnız
IDFV yokluğundan çıkarılmaz. [Apple — App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

Build 9 mevcut App Store sürümüne seçilip UI'da Save ile kaydedildi;
sonrasında **Prepare for Submission** görüldü. Save öncesindeki API
Rejected sonucu bu yeni durumu doğrulamaz; güncel API ilişkisi ayrıca okunur.
Kalan dış adımlar: build ilişkisinin son kontrolü, 12 yeni görselin işlenip yerleştirilmesi,
gizlilik eşleştirmesi ve **gerçek Submit for Review / Waiting for Review**
kanıtı. Mevcut ASC **onay sonrası otomatik yayın** tercihi korunur;
manuel yayına çevrilmez. İmzalı yükleme/TestFlight processing, App Review
başvurusu veya Apple onayı değildir. Kabul garantisi verilmez.

Son iletişim kaydı: **8 Ekim 20:15 (GMT+3)** 1.187 karakterlik App Review
yanıtı gönderildi; ana ajan 8 mesajlı konuşmayı doğruladı. Yerel kanıt
`.artifacts/apple-review-reply-sent.jpg`. Bu mesaj, 3.492 karakterlik
Review Notes alanı ve gerçek Submit for Review ayrı adımlardır; yanıtın
gönderilmesi Waiting for Review veya Apple onayı anlamına gelmez.

Build 10 yedinci aday `a621e2e9846f94d970ac51afe0c29b1a20650507` /
37838710378: **721 Swift testi ve mimari geçti**. iPhone film/Canlı TV
yatay kilidi, sol kanal paneli ve aramayla kanal değişimi, aynı film
detayına veya seçilen kanalın mini oynatıcısına dönüşü doğruladı.
Gerçek iPhone UIKit logunda altı güvenli olay ve iki etkileşime açık
dikey dönüş var. Son tekrar kapanışında test görünür close'u zorunlu
gizleme varsayımında durdu; close'a hiç basmadı. Denetim zaten
görünürse normal merkez dokunuşu ve işlem sonucunu sınırlı yeniden
denemede kontrol et; görünürlük için zorunlu gizle/aç precondition'ı
kullanma. Ürün süresi veya sonraki akış doğrulamaları değiştirilmez.
Bu aday iPad'e veya imzalı yüke geçmedi; build 10 henüz telefonda değil.

Build 10 sekizinci aday `4983c0b08aee0b5f08e857785ba018b760749244` /
[37842943490](https://github.com/mycrs/ios-octopus/actions/runs/37842943490):
**721 Swift testi / 0 hata ve mimari geçti**. iPhone Release kullanıcı
akışının tamamı **281,438 saniyede geçti**; gerçek native film karesi,
aynı detay sayfasına dönüş, Canlı TV mini/tam ekran geçişleri, yerel sol
kanal paneli, mevcut kanala dokunma, Sintel araması/kanal değişimi,
doğru mini oynatıcıya dönüş, bölüm ve kaynak kontrolü doğrulandı.
iPad Pro 13-inch (M5), iPadOS 26.4.1 simülatörü ilk filmde native kareyi üretir
ama tam ekran portrede kalır; yatay pencere kontrolü başarısızdır.
Özgün 2064×2752 kayıt ilerleyen filmi portrede gösterir. Gerçek filtreli
UIKit kaydı `Player orientation request failed; code=101` içerir;
isteğin reddi kanıtlanmıştır, erken portrait kilidinin buna neden olduğu
yorumu ise henüz sonraki Mac testiyle doğrulanmamış bir çıkarımdır.

Sekizinci turdan sonraki onarım adayı `PlayerFullscreenOrientationLockState` ile
bekleyen → kilitli → kapanan durumlarını ayırır. Yatay geometry isteği
kilit tercihi etkinleşmeden yapılır. Public lock yalnız kendi scene yönü ile view ve
window geometrisi gerçekten yatay gözlendiğinde açılır; kapanış durumu
mühürlenir ve geç callback yeniden kilitleyemez. Sonraki Mac sonucu
aşağıdaki dokuzuncu turdadır. Sekizinci turda imzalı iş **skipped**; imzalı build 10
üretilmedi, Apple'a yüklenmedi veya telefona kurulmadı. Bu başarısız turdan
eksik görsel takımı gönderilmez. Son doğrulanmış imzalı/kurulu kaynak
build 9'dur; mağaza kayıtları, kaynak pinleri, M3U/Xtream inceleme kapsamı
ve bekleyen canlı backend gizlilik eşleştirmesi korunur. Son tur kanıtı
`.artifacts/build10-attempt8-small/extraction-report.json`, filtreli
`ipad-player-ui.log` ve `video-inspection/frame-report.json` altında
aynı kaynak/run, özgün SHA/CRC ve native video zamanlarıyla tutulur.

Build 10 dokuzuncu kaynak adayı `4dcba17d74baa6094eda6e0faceb4997a187eaa3` /
[37847499591](https://github.com/mycrs/ios-octopus/actions/runs/37847499591):
**726 Swift testi / 0 hata ve mimari geçti**. iPhone Release akışının
tamamı **228,167 saniyede geçti**. iPad ilk filmde native video üretir
ama portrede kalır; ilk yatay pencere kontrolü başarısızdır. 17 özgün
tanı eki SHA/CRC ile doğrulandı. İstek sırasında `requested=24`,
`orientation=1`, `locked=0`, `appMask=30`, `rootMask=30`, `presentedMask=24`,
pencere 1032×1376; hemen ardından code **101** gelir. Etkin kilit kapalıyken
de istek reddedilmiştir; erken portrait kilidi tek başına açıklama değildir.
`appMask` UIApplication'ın varsayılan Info.plist getter'ıdır; özel
AppDelegate/policy lease sonucunu ölçmez ve lease arızasını kanıtlamaz.

Dokuzuncu turdan sonra hazırlanan aday ilk geometry isteğini gerçek UIKit sunum completion'ına
taşır; current host/desired ID eşleşmesi ve invalidation/kapanış guard'ı
korunur. Bekleyen → kilitli → kapanan durumları ile beş regresyon testi
kalır; geç callback kapanışı yeniden kilitleyemez. Timer/retry eklenmez,
UI assertion zayıflatılmaz. Onuncu turun gerçek sonucu aşağıdadır.
Bu dokuzuncu/onuncu kaynaklarda `UIRequiresFullScreen` eklenmemişti; deprecated public uyumluluk optout'u
araştırılmış fallback'tir, iPad çoklu görevini kısıtlar ve SDK 27+ için
migration gerektirir. Çözüm garantisi değildir. [Apple TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key)
Dokuzuncu turun imzalı işi skipped; imzalı build 10/Apple yüklemesi/USB
kurulumu ve başarılı yeni görsel takımı yok. Build 9 mağaza kayıtları,
kaynak pinleri, M3U/Xtream kapsamı ve bekleyen gizlilik eşleştirmesi korunur.
Kanıt `.artifacts/release10-attempt9-failure-qa.json` ve `build10-attempt9-small`
altında tutulur; başarısız kaynak görselleri mağazaya gönderilmez.

Build 10 onuncu kaynak adayı `b96b195744cbb1331e519a94b9ae56488be40da0`,
[onuncu tur 37851820087](https://github.com/mycrs/ios-octopus/actions/runs/37851820087):
**728 Swift testi / 1 hata**; mimari ve iOS uygulama derlemesi geçti.
Tek birim hatası, tuzlu SHA-256 özetinde PIN rakamlarının tesadüfen
geçmesini yasaklayan `ParentalControlTests` kontrolüdür. Üretim PIN
saklaması değiştirilmeden testin tam özet/tuz sözleşmesi doğrulandı;
bu düzeltme sonraki on birinci Mac turunda geçti.

iPhone Release akışının tamamı **260,500 saniyede geçti**. Özgün 06-player
PNG'si SHA/CRC doğrulandı; eXIf 6, etkili 2622×1206, gerçek video karesi
ve okunur kontroller görüldü. iPad native kare aşamasını geçse de ilk
filmde portrede kaldı; `ReviewJourneyTests.swift:140` yatay kontrolü
başarısız, akış **140,261 saniyede başarısız**. İstek UIKit sunum completion'ında:
`requested=24`, `orientation=1`, `locked=0`, `defaultAppMask=30`,
`policyMask=24`, `rootMask=30`, `presentedMask=24`, `beingPresented=0`,
`coordinator=1`, 1032×1376; ardından **101**, `reportedSupported=-1`.
Coordinator'ın varlığı tek başına aktif animasyon kanıtı değildir;
desteklenen ret maskesi ayrıştırılamadı. Zamanlamayı completion'a taşımak
bu iPad arızasını çözmedi; varsayılan getter policy lease arızasını kanıtlamaz.
26 özgün ek SHA/CRC ile doğrulandı. iPad native kaydı 2064×2752,
133,972 saniye, dönüş metadatası yok; 126,017 saniyedeki BBB karesi
gerçek 0:09 ilerlemeye rağmen dikey letterbox gösterir. Video SHA-256
`20eb691342bc60e05e44ac590a542377639ae8a923df71cb5fb7fd5a7b2209d7`.
Filtreli özgün UI logu SHA-256 `86c2593448349063795d78132616ceb8f33acb3bb13b03c8d707baed263ba55c`.

On birinci aday `App/Info.plist` içinde public `UIRequiresFullScreen=YES`
uyumluluk ayarını denedi; sonucu aşağıdadır. Dört iPad yönü, uyarlanır yerleşim, mevcut dinamik
lease/kapanış korumaları ve aynı UI assertion'ları korunur. Bu ayar uygulama
genelinde iPad pencere davranışını etkiler; Windowed Apps/Stage Manager'da
yalnız mantıksal scene yönü seçimi fiziksel görüntü dönüşünü kanıtlamaz.
Apple deprecated uyumluluk davranışını SDK 27+ için değiştirmiştir;
yeni native görüntülerle doğrulanmadan çözüm veya gelecek SDK uyumluluğu
iddia edilmez. [Apple TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key)
Onuncu turun imzalı işi skipped; build 10 Apple'a yüklenmedi veya telefona
kurulmadı. Mağazadaki build 9 ve eski görsel yerleşimleri korunur.
Kanıt `.artifacts/release10-attempt10-unit-evidence` ve
`.artifacts/build10-attempt10-small/ipad-player-ui.log` altında tutulur.
Bekleyen canlı backend gizlilik eşleştirmesi ve gerçek başvuru ayrı adımlardır.

İnceleme hazırlığı API aracı ayrı workflow üzerinden yalnız Build 10
ilişkisini ve mevcut Review Notes sonuna 337 karakter oynatıcı adımını
güncelleyebilir. API yanıtındaki not/iletişim/demo metni rapora veya
işlem günlüğüne yazılmaz; yalnız ID, durum, uzunluk ve SHA raporlanır. Mevcut not
fingerprintı, sekiz CI kapısı, imzalı TestFlight adımı, geçerli build ve
taze sürüm/inceleme ilişkileri zorunludur. Belirsiz PATCH otomatik
tekrarlanmaz; GET kanıtı kaydedilip durulur. Review item çözme veya
gönderim endpointi yoktur. 18 yerel API testi ve 70 workflow mod senaryosu
geçti; canlı Apple metadata yetkisi/şeması henüz denenmedi. Mağaza sürümü
1.0 ile gerçek IPA marketing/prerelease 1.0.0 ayrı doğrulanır. Bu API
aracı değişikliği, on birinci turdaki binary kaynak
`a0d6bbb737e9443186a3a052c366bfb2e993944c` /
[37854715123](https://github.com/mycrs/ios-octopus/actions/runs/37854715123)
pinini değiştirmez; yeni binary/görsel/telefon ve gizlilik doğrulanmadan
hazırlık veya inceleme gönderimi tamamlandı denmez.

Son Mac'te denenen build 10 kaynağı `a0d6bbb737e9443186a3a052c366bfb2e993944c`,
[on birinci tur 37854715123](https://github.com/mycrs/ios-octopus/actions/runs/37854715123):
**728 Swift testi / 0 hata**; mimari ve iOS uygulama derlemesi geçti.
PIN testinin tam tuz/özet sözleşmesi de gerçek Mac testinde geçti.
iPhone Release akışının tamamı **190,574 saniyede geçti**.

iPad ilk filmdeki yatay pencere kontrolünde **103,520 saniyede başarısız**.
Bu turun kanıtı önceki portrait/101 arızasından farklıdır: filtreli
tanıda 101 yok; host 1376×1032 ile yataydır. AX snapshot yalnız Application
gösterir, Window öğesi bulunmadığından assertion fiziksel tam ekranı
doğrulayamadı. Özgün kayıt gerçek BBB görüntüsünü yatay uygulama penceresinde,
dikey masaüstü/Dock ve sistem pencere düğmeleriyle gösterir. Mantıksal
scene dönüşü gerçekleşmiştir; cihaz ekranının tamamını kaplama kanıtı yoktur.
17 özgün ek SHA/CRC doğrulandı. Kayıt 2064×2752, 99,983 saniye; video SHA-256
`727c25853405552099abefa9a88c45ebde6973dc90cecd065b11798fa2d13578`.
Filtreli log SHA-256 `cecb57f606ff5576cca0953eb56d6d4f52774bf377ab84ff188715736ed6ae5b`.

`UIRequiresFullScreen=YES` bu iPad ortamında fiziksel tam ekranı zorlamadı.
Apple TN3192'nin Windowed Apps uyumluluk davranışı mantıksal yönü fiziksel
ekranı döndürmeden değiştirebilir. Sıradaki kontrollü test simülatörde
Apple'ın public Ayarlar → Multitasking & Gestures → Full Screen Apps
arayüzünü kullanır; cihaz dikken yatay pencere, videonun pencereyi doldurması
ve kapanışta doğru ekrana dönüş assertion'ları aynen korunur. Public
Ayarlar seçimi doğrulanamazsa preflight başarısız olur; özel defaults/API,
zamanlayıcı veya assertion zayıflatması kullanılmaz. Bu preflight henüz
Mac'te denenmedi. [Apple'ın ayar adımları](https://support.apple.com/en-us/123635),
[TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

On birinci turun imzalı işi **skipped**; build 10 üretilmedi, Apple'a
yüklenmedi veya telefona kurulmadı. Eski build 9/görseller korunur.
Kanıt `.artifacts/release10-attempt11-failure-qa.json` ve
`.artifacts/release10-attempt11-unit-evidence` içindedir. Canlı backend
gizlilik eşleştirmesi ve gerçek App Review gönderimi hâlâ bekliyor.

Son Mac'te denenen build 10 kaynağı `53eb01efda3807d82095f1eb094a1dd60ce6c7be`,
[on ikinci tur 37858059958](https://github.com/mycrs/ios-octopus/actions/runs/37858059958):
**728 Swift testi / 0 hata**, mimari, işlem modu ve uygulama derlemesi geçti.
iPhone Release akışı **161,416 saniyede başarısız**; ilk film kapanışı,
Canlı TV kanal paneli/Sintel seçimi, ilk canlı kapanışta dikey Sintel
mini oynatıcı ve native kare doğrulandı. İkinci genişletmede yatay/native
kare geçti; ikinci canlı kapanış `ReviewJourneyTests.swift:236` içinde
başarısız oldu. Kapat AX alanı (78,16,44,44), dokunulan merkez (100,38)
ile eşleşir. Reveal 148,22s, synth 151,07s; ikinci dismissal kaydı yok.
Kapatma olayının gönderilmemesi ile yanlış navigasyon sonucu ayrı tutulur.
20 özgün ek SHA/ZIP CRC ile doğrulandı; 255.507.047 baytlık native kayıt
ve gerçek dokunma eki incelendi. Kapat simgesi 149,8–152,165 video
saniyelerinde basılma tepkisi göstermedi; bütün denetimler 152,213'te
solup 152,353'te kayboldu ve 153,002'de tekrar belirdi. Gerçek event
merkezi yatay kapat düğmesiyle eşleşir; ekin zamanı 152,397'ye denk gelir.
Geç dokunuşun alttaki videoya ulaşması bu kanıtla tutarlıdır; gerçek down
anı veya down-sonrası gizleme kanıtlanmadı. Kapat handler'ının bozuk
olduğu sonucu çıkarılmaz. Özgün video SHA-256
`bf543653d40f83ab19999da1b34b76a6df7215e82d86cc20b098e9fd55e7b480`;
kesin pin, zamanlar ve sınırlar özel failure QA raporunda tutulur.

iPhone ilk çalıştığı ve başarısız olduğu için iPad testi **başlamadı**.
Public Settings preflight kaydı veya iPad sonucu yok; bu tur iPad
ayar yaklaşımını doğrulamaz veya çürütmez. İmzalı iş **skipped**;
build 10 paketi, Apple yüklemesi, telefon kurulumu ve yeni mağaza
görselleri yok. Mağazadaki build 9 ve eski görsel ilişkileri korunur.
728 test kanıtı `.artifacts/release10-attempt12-unit-evidence` içindedir.

Kodda ayrıca somut risk vardır: 3,5s gizleme görevi, kontrol basılıyken
veya scrub sürüklenirken görünümü kaldırabilir. Şimdiki yerel aday public
`ButtonStyleConfiguration.isPressed` ve ayrı kontrol kimlikleriyle
bu sırada gizlemeyi iptal eder; son gerçek release normal, hâlâ kendi
oynatıcı katmanında ise süreyi yeniden başlatır. Örtüşen/birden fazla
dokunuş, tekrarlı/geç release ve görünümden ayrılma korunur. Hız seçimi
açıkken de katman tutulur; yeni gesture veya artırılmış süre kullanılmaz.
Beş yeni mantık regresyon testi ve ikinci canlı kapanışta **4s gerçek
basılı tutma** UI kontrolü eklendi. Diğer yön/kare/liste/kapanış assertion'ları
aynıdır. Windows syntax/mimari geçti; bu aday henüz Mac'te denenmedi.
Basılı tutma testine ek olarak UI yardımcısı, hazır/görünür/hittable
kontrolü hemen kullanır; 2s waiter yalnız kontrol hazır değilse çalışır.
Pencere ölçüsü reveal öncesi okunur. Böylece ilk predicate'ın gecikmesi
atılır; gerçek süre, dokunuş, hedef sınırı ve sonuç assertion'ları korunur.
PlayerScreen yaşam döngüsü ayrı uzantıya taşındı; ana View 170 satırdır.
[Apple düğme durumu](https://developer.apple.com/documentation/swiftui/buttonstyleconfiguration),
[public XCTest basılı tutma](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press%28forduration%3A%29).
Canlı backend gizlilik eşleştirmesi ve gerçek App Review gönderimi bekliyor.


## 9 Ekim 2026 — on üçüncü aday ve basılma kaydı ömrü

Son Mac'te denenen build 10 kaynağı `359873a3077f4ea3deb90bfefad70e33affc6e3d`,
[on üçüncü tur 37861193556](https://github.com/mycrs/ios-octopus/actions/runs/37861193556):
**733 gerçek Swift testi / 0 hata**; beş yeni basılma regresyonu dahil
Features **237/0**, App **31/0** tamamlanmış loglardan doğrulandı. App
job'un iptali unit adımı sonrasındadır; bütün CI gate'leri geçti denmez. iPhone Release **173,867 saniyede başarısız**;
film duraklatma/kapanış/aynı detay ve Canlı TV mini→yatay tam ekran/native
kare geçti. İlk `player.channels.open` eylemi line 237'de tamamlanmadı.
23:54:20.714 dokunuş ve 20.772 synth sonrası 21.130 idle isteğinden ilk
sonuç sorgusuna **30,64s**, ardından AX snapshot'a **30s** bekleme vardır.
Son snapshot'lar yalnız Application içerir. Kanal merkezi (480,167;340)
ve fiziksel dönüşümü doğru; bu kanıt tek başına main-thread döngüsünü
kanıtlamaz. İkinci canlı 4s basılı kapatma ve iPad/Settings preflight
**çalıştırılmadı**. 19 küçük özgün ek ve tek 307.520.539 baytlık native MP4
CRC/SHA ile doğrulandı. Video SHA-256
`7c505bcd7878c55239862825e1a315c41cb6e07b96d473725c79cf1679135e56`.
Dokunma ekinin 108,405 video saniyesi çevresinde denetimler görünmez;
110–125s içinde denetimler tekrar görünürken video ilerler ama denetim
süresi 0:11'de kalır. Son 170,872s karesinde kanal paneli BBB seçili ve
Sintel satırıyla görünür. İlk panel geçişi 140,048–140,310s aralığında,
yani dokunma ekinden yaklaşık 31,6–31,9s sonradır; ilk AX retry/snapshot
23:54:53.017 zamanı bu sınırla eşleşir. Crash/SpringBoard/yükleniyor
kesintisi görünmez. Bu nedenle panelin hiç açılmadığı veya yalnız
kaçırılmış dokunma olduğu sonucu çıkarılmaz; belirgin UI/AX gecikmesi
vardır, kesin mekanizma doğrulanmadı. Başarılı 20 PNG paketi yok.

Release zaten başarısızken kalan DEBUG görsel adımı 9 Ekim 03:03 TR'de
iptal edildi; App unit adımı daha önce başarılıydı. Run/App görsel gate
ve imzalı iş **cancelled**, Release **failure**; tamamı geçti denmez.
Yeni IPA, TestFlight yüklemesi, telefon kurulumu veya App Review gönderimi yok.

Yeni yerel düzeltme, basılma kayıtlarını non-Observable bir referansta
korur. `@State` içindeki Set değerine her disappearance cleanup'ta
mutating writeback ile dış PlayerScreen'i yeniden çizdirme kaldırıldı;
UUID/süre/örtüşen basılma ve son release sözleşmesi aynıdır. Hosted overlay
snapshot'ıyla gereksiz yeniden çizim geri besleme riski kodda somuttur;
bunun son native takılmanın kesin nedeni olduğu henüz söylenemez.
Denetim basılması ile panel request/appear/scroll begin/end için yalnız
altı sabit, kullanıcı içeriği içermeyen log eklendi. Collector fullmatch
şeması ve **28 privacy testi** geçti; adres/başlık/token/ID suffix'leri
reddedilir. Bu referans düzeltmesi henüz Mac'te denenmedi.

## 9 Ekim 2026 — on dördüncü aday: iPhone geçişi ve test senkronizasyonu

Son Mac'te denenen build 10 kaynağı `803248d30f6df0b86ed1a4639a6cfe064cedb99f`,
[on dördüncü tur 37863231559](https://github.com/mycrs/ios-octopus/actions/runs/37863231559):
**733 gerçek Swift testi / 1 hata**; Domain 84/0, Playback 75/1, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Beş basılma regresyonu, PIN ve
uygulama yön/sunum testleri geçti; App job da başarılı tamamlandı.
Playback'te `test_finish_duringLoad_doesNotRestartReleasedEngine` 0 yerine
1 play çağrısı gördü. Test motoru yüklemeyi 100ms sonra kendiliğinden
bitiriyordu; 15,451s süren test, play'in finish'ten sonra olduğunu kanıtlamaz.
Production attach/reload guard'ları kapanışta senkron geçersiz kılınır.
Yeni yerel test, gerçek yüklemeyi continuation ile finish sonrasına kadar
askıda tutar; giriş XCTest expectation ile sınırlıdır. Aynı 0-play/idle/
teardown assertion'ları ve ayrı kanal reload kapanışı korunur. Bu yeni
testler henüz Mac'te çalışmadı; production bu test hatası için değiştirilmedi.

iPhone **bütün Release akışını 172,895 saniyede geçti**: dik tutulan
cihazda yatay video/native kare, film duraklatma ve aynı detaya dönüş,
Canlı TV mini→tam ekran, sol panel/geçerli kanala tekrar dokunma/Sintel
arama ve seçim, aynı dikey Sintel mini oynatıcıya dönüş ve ikinci canlı
kapanışta **4s gerçek basılı tutma** başarılıdır. Önceki panel gecikmesinin
kesin mekanizması hâlâ çıkarım olarak ayrılır; yeni referans kaydıyla bu
somut kullanıcı akışı doğrulanmıştır.

iPad **Octopus açılmadan önce** public Settings preflight'ta 152,806s
sonunda `settings-navigation-not-ready` ile başarısız oldu. Hemen sonraki
tanı eki kategori, arama alanı ve tanınan sidebar'ın hazır/hittable olduğunu
gösterir; ilk geniş mode AX sorgusu yaklaşık 9,17s tüketmiştir. Sonraki
yerel hazırlık düzeltmesi kategori/arama/sidebar'ı önce kontrol eder ve
süre bitiminde koşulu bir kez taze okur; süreler ve gerçek Full Screen Apps
seçili doğrulaması korunur. iPad oynatıcı/yön assertion'ları çalışmadı.
Bu turdaki collector runtime kaydı bulmadı; sabit player logları başarılı
akışın kanıtı olarak gösterilmez. Whole run **failure**, imzalı job
**skipped**: yeni IPA, TestFlight yüklemesi, telefon kurulumu, yeni mağaza
görsel ilişkisi veya App Review gönderimi yok. Build 9 kanıtı ayrı kalır.

## 9 Ekim 2026 — on beşinci aday: 734 test ve gerçek iPad pencere seçimi

Son Mac'te denenen build 10 kaynağı `e784931116a1779d0ba2b4f49e26293ad04e6fc4`,
[on beşinci tur 37865437808](https://github.com/mycrs/ios-octopus/actions/runs/37865437808):
**734 gerçek Swift testi / 0 hata**; Domain 84/0, Playback 76/0, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Finish sırasında askıda tutulan load
ve kanal reload testleri sırasıyla 0,003s ve 0,004s içinde geçti. Beş
basılma regresyonu, PIN ve uygulama yön/sunum testleri de başarılıdır.

iPhone **bütün Release akışını 302,468 saniyede geçti**. Dik cihazda
yatay tam ekran/native kare, aynı film detayına dönüş, sol kanal paneli,
geçerli kanala tekrar dokunma, Sintel arama/seçim, seçili canlı kanalın
aynı dikey mini oynatıcıya dönüşü ve 4s gerçek basılı tutarak ikinci
kapanış doğrulanmıştır. Bu sonuç fiziksel cihazda yeni VLC testi değildir.

iPad public Settings hazırlığını geçti: Full Screen Apps seçili ve
hittable; Windowed Apps ve Stage Manager seçili değil. Octopus açıldı ve
gerçek native-video ready yüzeyi ile Main penceresi **1376×1032** olarak
gözlendi. Bunun önündeki yardımcı AX Window **0×0** idi. Testin
`app.windows.firstMatch` seçimi ilk yatay pencere assertion'ında
`ReviewJourneyTests.swift:141` satırında 121,090s sonunda başarısız oldu.
İki sabit güvenli UI log olayı vardır; yatay istek boyutu 1376×1032'dir,
bu kayıtta yön isteği reddi yoktur. Bu gözlem iPad yolculuğunun kalanının
geçtiğini kanıtlamaz. Sonraki test düzeltmesi sıfır alanlı yardımcı
pencereleri dışlayarak gerçek pencereyi gözlemleyecek; gerçek yön,
native yüzey sınırı, dik tutma ve geri dönüş assertion'ları korunacak.

Whole run **failure**, imzalı job **skipped**. Build 10 IPA, TestFlight
yüklemesi, telefon kurulumu ve App Review gönderimi yok. Sınırlı
çıkarılan 31 özgün ekin CRC/SHA-256 doğrulaması korunur; büyük video
indirilmedi. Ayrı read-only Apple API kontrolünde sürüm
PREPARE_FOR_SUBMISSION ve eski 21 görsel yerleşimi doğrulandı; bu işlem
görsel, not, build seçimi veya inceleme gönderimini değiştirmedi.

## 9 Ekim 2026 — on altıncı aday: pencere geometrisi ve hit-point ayrımı

Son Mac'te denenen build 10 kaynağı `f5480055fee0bbe9863c28069692c4d02672b1fe`,
[on altıncı tur 37868108461](https://github.com/mycrs/ios-octopus/actions/runs/37868108461):
**734 gerçek Swift testi / 0 hata**; Domain 84/0, Playback 76/0, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Altı job başarılıdır; askıdaki
load/reload, beş basılma regresyonu, PIN ve App yön/sunum suiteleri geçti.

iPhone kullanıcı testi **176,395s** sonunda test yardımcı fonksiyonunun
`ReviewJourneyTests.swift:323` satırındaki Window `isHittable` sorgusunda
başarısız oldu. Kayıt, ikinci canlı kapanışta 4s basılı tutmayı ve ardından
163,99s'te interface orientation'ın Portrait'e dönmesini gösterir. Son
pencere assertion'ı tamamlanmadı: pozitif frame okumasından sonraki
dokunulabilirlik sorgusu **{{inf, inf}, {0, 0}}** pencere için geçersiz
activation point XCTest hatası kaydetti. Bunun sonucu tam iPhone PASS
değildir; iPad bu turda çalışmadı. İki AX okuması arasında pencere/indeks
değişimi mekanizması çıkarımdır, gerçek hata pencere hit-point sorgusudur.

Sonraki dar test düzeltmesi `allElementsBoundByAccessibilityElement`
ile AX öğesine bağlanır ve geometry-only Window seçiminden `isHittable`
sorgusunu çıkarır. Apple belgeleri bu API'nin sonuç AX öğelerine,
`allElementsBoundByIndex` API'sinin ise sonuç indekslerine bağlandığını
açıklar. Bu seçim atomik pencere yaşam süresi garantisi değildir. Finite/
pozitif bağımsız pencere geometrisi, 1pt native yüzey sınırı, gerçek
button/mini hittability, seçili kanal, dik tutma ve geri dönüş assertion'ları
korunur; production oynatıcı bu test hatası için değiştirilmez.
[Apple query belgesi](https://developer.apple.com/documentation/xcuiautomation/xcuielementquery/allelementsboundbyaccessibilityelement)
ve [hittability belgesi](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable).

Whole run **failure**, imzalı job **skipped**. Build 10 IPA, TestFlight
yüklemesi, telefon kurulumu veya App Review gönderimi yok. Bir önceki
turun bütün iPhone PASS ve iPad native/Main yatay gözlemi ayrı kanıt olarak
korunur; yeni test kaynağı Mac doğrulaması bekler.

## 9 Ekim 2026 — on yedinci aday: mini oynatıcıda gerçek dokunuş kanıtı

Son Mac'te denenen build 10 kaynağı `a76e5e29256ba6b2a9c8f44e84d451bd6bf73244`,
[on yedinci tur 37870292518](https://github.com/mycrs/ios-octopus/actions/runs/37870292518):
**734 gerçek Swift testi / 0 hata**; Domain 84/0, Playback 76/0, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Altı unit job başarılıdır.

iPhone kullanıcı testi **192,400s** sonunda `ReviewJourneyTests.swift:254`
satırında mini oynatıcının SwiftUI kapsayıcısının `isHittable` sorgusunda
başarısız oldu. XCTest geçerli activation point hesaplayamadı. AX öğesine
bağlanan pencere seçimi geçti; gerçek hata artık mini kapsayıcının hit-point
sorgusudur. Kayıt ikinci kapanışta **4,006s** gerçek basılı tutmayı gösterir.
Kapanıştan 2s sonraki UIKit kaydı portre **402×874**, normal kullanıcı
etkileşimi, açık Live TV sekmesi ve kaldırılmış tam ekran modalını gösterir.
Bu kayıt tek başına mini oynatıcının görüntüsünü veya yeniden açılabildiğini
kanıtlamaz. Son AX dökümü yalnızca uygulama kökünü içerir; son mini frame'i
bu dökümden çıkarılamaz. Tek özgün telefon MP4 kaydı (292.350.269 bayt)
CRC/SHA doğrulamasından sonra incelendi. Gerçek basılı kapanışın ardından
182s ve 185s karelerinde portre Live TV sekmesi, Sintel mini oynatıcısı ve
ilerleyen film görüntüsü doğrudan gözlendi. Bu iki kare boş AX dökümünün
görüntü kaybını kanıtlamadığını gösterir; tekrar dokunabilme yeni testte
ayrıca doğrulanmalıdır. Tam iPhone PASS değildir; iPad bu turda çalışmadı.

Sonraki dar test düzeltmesi kapsayıcının `isHittable` sorgusu yerine
finite/pozitif, portre pencere içinde kalan mini geometrisini kullanır.
Geri dönen mini içinde hazır native video yüzeyi ve 1pt sınır eşleşmesi
doğrulanır; ardından gerçek bir dokunuşla tekrar tam ekran açılması ve
aynı Sintel kanalına yeniden portre dönüşü sınanır. Kontrol görünürlüğü,
4s basılı tutma, dik cihazda yatay kilit ve 1pt tam ekran video sınırları
korunur; timeout veya üretim oynatıcı bu XCTest hatası için değiştirilmez.

Whole run **failure**, imzalı job **skipped**. Build 10 IPA, TestFlight
yüklemesi, telefon kurulumu veya App Review gönderimi yok. Yeni test
kaynağı Mac doğrulaması bekler; önceki tam iPhone PASS ayrı kanıttır.

## 9 Ekim 2026 — on sekizinci aday: Window yaşam süresi ve örnek yayın etiketi

Son Mac'te denenen build 10 kaynağı `a13057e227dab618c50a5d9bbbf234ece47bff2a`,
[on sekizinci tur 37872902093](https://github.com/mycrs/ios-octopus/actions/runs/37872902093):
**734 gerçek Swift testi / 0 hata**; Domain 84/0, Playback 76/0, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Altı unit job başarılıdır.

iPhone kullanıcı testi **90,442s** sonunda `ReviewJourneyTests.swift:373`
satırında AX identity ile bağlı eski Window'un frame okumasında başarısız
oldu: `No matches found for Identity Binding`; mevcut snapshot'ta Main
Window vardı. Film kapatma dokunuşu 79,33s, interface Portrait gözlemi
86,11s idi. Pencerenin AX kimliği yön/sunum geçişinde kalıcı olmadı.
Bu tur canlı mini helper'ına veya 4s kapanışa ulaşmadı; iPad çalışmadı.
Sonuç uygulamada görüntü kaybı ya da ana sayfaya atma kanıtı değildir.

Sonraki dar test düzeltmesi Window öğelerini `allElementsBoundByIndex`
ile sorgular; Window `isHittable` geri eklenmez. Sıfır auxiliary pencereler
finite/pozitif bağımsız geometri ile elenir ve en büyük geçerli pencere
gözlenir. Beklenen yön veya video geometrisi pencere seçiminde kullanılmaz.
Mini içinde native-ready/1pt sınır, gerçek yeniden açma dokunuşu, aynı
kanala portre dönüşü ve 4s basılı tutma koşulları korunur. Timeout artmaz;
yeni sorgunun gerçek Mac/XCTest sonucu henüz doğrulanmamıştır.

Özgün video denetimi ayrıca kayıtlı örnek kanalda yanlış LIVE rozeti
buldu. Provider örnek kanalı `isLive=false` olarak verir; onboarding ve
rehber bunu kayıtlı film diye açıklar. Mini rozet artık controller'ın
gerçek `currentItem.isLive` değerini kullanır: kayıtlı örnekte LIVE gizlenir,
gerçek canlı kanalda ve son kanal placeholder'ında mevcut davranış korunur.

Release **failure**, imzalı job **skipped**. Build 10 IPA, TestFlight
yüklemesi, telefon kurulumu veya App Review gönderimi yok. Yeni test ve
rozet kaynağı Mac doğrulaması bekler; geçmiş gerçek PASS sonuçları korunur.

## 9 Ekim 2026 — on dokuzuncu aday: tüm iPhone PASS ve iPad transient Window

Son Mac'te denenen build 10 kaynağı `ea5d3affa18a8c74c11eb97c076f95b2505ab996`,
[on dokuzuncu tur 37874319632](https://github.com/mycrs/ios-octopus/actions/runs/37874319632):
**734 gerçek Swift testi / 0 hata**; Domain 84/0, Playback 76/0, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Altı unit job başarılıdır.

**iPhone kullanıcı akışının tamamı PASS: 271,647s**. Dik cihazda yatay
kilit ve native 1pt tam ekran sınırı, blursuz gerçek kontrol ekranı,
film kapatılınca aynı detay, canlı kanal paneli/arama/Sintel seçimi,
mini oynatıcıya aynı kanalın devri, 4s basılı kapanış ve mini kapsamındaki
hazır native video/1pt sınır doğrulamaları geçti. Gerçek üçüncü mini
dokunuşu tekrar yatay tam ekran açtı; normal kapanış yeniden portre
Sintel mini görüntüsüne döndü. Dizi/bölüm ve kaynak sağlık akışı da geçti.
Kayıtlı örnekte yanlış LIVE rozetini kaldıran üretim kodu bu kaynaktadır.

iPad preflight ve uygulama akışı çalıştı. Gerçek yatay **1376×1032**
pencere, native tam ekran sınırı, film ve Live TV/kanal paneli/Sintel
native-ready kontrolleri geçti. İlk canlı kapanış dokunuşu 293,04s,
interface Portrait 297,01s idi. Pencere listesi dört öğeden üçe inerken
298,13s'te eski index3'ün frame okuması `No matches found for Element at
index3` ile `ReviewJourneyTests.swift:373` satırında hata verdi; iPad
testi **302,668s** sonunda FAIL. Bu native geometri veya mini video
assertion hatası değildir. Hangi yardımcı pencerenin kalktığı henüz doğrulanmadı;
kaybolan index sorgusu gerçek kanıttır. Son özgün AX dökümü Main
1032×1376 içinde seçili Live TV'yi, Sintel mini (3,96,1026,577.5) ve tam
aynı bounds içinde ready native video yüzeyini gösterir. UIKit +2s kaydı
modalın kapandığını gösterirken `ignoresEvents=true` gözlemi de vardır;
bunun kalıcı dokunma sorunu olduğu bu turda doğrulanmadı. iPad'de tekrar
gerçek dokunuş ve bütün kalan akış PASS sayılmaz; yeni test bunları korur.

Sonraki dar test düzeltmesi her Window için `exists` kontrolü yapar ve
public throwing `snapshot()` üzerinden tek snapshot.frame okur. Kaybolan
öğe elenir; finite/pozitif bağımsız en büyük pencere, bütün orientation/
native/mini/gerçek dokunuş/4s koşulları ve süreler korunur. Apple API'si
öğe ve alt hiyerarşinin snapshot'ını verir. Yakalanan hatanın XCTest issue
üretmemesi Mac'te doğrulanmadan garanti sayılmaz; üretim oynatıcı bu test
hatası için değiştirilmez.
[Apple snapshot belgesi](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding).

Release **failure**; Build 10 IPA, TestFlight yüklemesi, telefon kurulumu
veya App Review gönderimi yok. Yeni test kaynağı Mac doğrulaması bekler;
gerçek tam iPhone PASS ve kısmi iPad kanıtı ayrı ayrı korunur.


## 9 Ekim 2026 — yirminci aday: gerçek pause görüntüsü ve bağımsız buffering yarışı

Son Mac'te denenen build 10 kaynağı `faf7793e9c410c74e100ff2e7ffcc4a8def1cda5`,
[yirminci tur 37877568288](https://github.com/mycrs/ios-octopus/actions/runs/37877568288):
**734 gerçek Swift testi / 0 hata**; Domain 84/0, Playback 76/0, Design 11/0,
Data 295/0, Features 237/0, App 31/0. Altı unit job başarılıdır; ham log
sayımı, tam kaynak/job kimlikleri ve hash indeksi bağımsız doğrulandı.

iPhone native-ready, dik cihazda yatay kilit ve native 1pt tam ekran
sınırlarını geçti. Test **78,787s** sonunda `ReviewJourneyTests.swift:283`
satırında `player.playPause` sonucunu okuyamadı. Gerçek düğme merkezine
dokunuldu ve UIKit logunda 63ms pressed=1→0 kaydı var. Son iki AX dump
yalnız boş Application içerir; görünür Play veya enabled bu AX'dan çıkmaz.
CRC/SHA doğrulanmış tek özgün MP4 (82.251.479 bayt) son görüntülerde
**Play üçgeni ve 0:17** gösterir. Görsel duraklama gerçekleşmiştir; bu,
başarısız XCTest assertion'ını PASS yapmaz. Kayıt 57,935s ile biter ve
son PTS kümesinde kısa geri gidiş vardır; seek hedefi kesin kare zamanı
sayılmaz. Sonraki +1/+3/+8/+12s görüntü, enabled değeri veya uzun süreli
pause bu kayıtta kanıtlanmadı. Film kapanışı, canlı mini ve iPad çalışmadı.
Window.snapshot API derlendi ve erişilen geometri kontrollerini geçti;
iPad'deki kaybolan Window yarışını çözdüğü bu turda henüz doğrulanmadı.

Yeni dar test düzenlemesi gerçek Pause dokunuşundan sonra çağıranın
mevcut 10s `Play + enabled` assertion'ını çalıştırır. Kanal/kapanış,
4s gerçek basılı tutma, mini native-ready/1pt, üçüncü gerçek mini dokunuşu
ve bütün orientation koşulları korunur; gerçek yeni Mac sonucu beklenir.

Bağımsız kod denetimi, aktif loading/buffering sırasında toggle'ın yeniden
play çağırabildiğini buldu. Üretim düzeltmesi bu durumda bekleyen oynatma
isteğini pause ile iptal eder; paused resume ve ended VOD yeniden başlatma
korunur. Üç deterministik regresyon eklendi: buffering pause/resume,
askıdaki load bitince otomatik play'in önlenmesi ve paused resume.
Bu yeni testlerin Mac sonucu henüz yoktur; beklenen sayı Playback 79 ve
toplam 737'dir. Bu ayrı yarış, 20. turdaki görsel olarak gerçekleşmiş
pause'un kök nedeni olarak sunulmaz.

Whole run ve Release **failure**, imzalı job **skipped**. Build 10 IPA,
TestFlight yüklemesi, telefon kurulumu veya App Review gönderimi yok.
19. turun tam iPhone PASS ve kısmi iPad kanıtı aşağıda korunur.
