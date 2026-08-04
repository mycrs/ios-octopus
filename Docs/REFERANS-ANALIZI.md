# 📐 REFERANS ANALİZİ — Android Octopus Player

> Kaynak: `C:\Users\USER\Desktop\octopus--player (2)` (Kotlin/Compose, Android TV + mobil)
> Analiz tarihi: 2026-08-04
>
> **Bu belge iki amaca hizmet eder:**
> 1. Tasarım ve özellik hedefini sabitlemek
> 2. O projede **acı çekilerek öğrenilmiş** dersleri iOS tarafında tekrar keşfetmemek
>
> ⚠️ Tasarım dili ve özellik seti alınır. **Mimarisi alınmaz** — sebebi § 5'te.

---

## 1. TASARIM DİLİ

Karar: **aynı görsel dil, iOS'a özgü cila.** Android portu gibi durmayacak;
SF Symbols, iOS tipografisi, akıcı geçişler ve haptik geri bildirim kullanılacak.

### Renk paleti (referans → bizde)

| Rol | Referans | Not |
|---|---|---|
| Marka / vurgu | `#00B0FF` | Parlak mavi. Bizim ilk turkuazımız (`#00C2A8`) bununla değişti |
| Arka plan | `#1C1B1F` | |
| Yüzey | `#2B2930` | |
| Metin (birincil) | `#E6E1E5` | |
| Metin (ikincil) | `#938F99` | |
| Hata | `#F2B8B5` | |

### Tema modları
- `dark` (varsayılan) · `light` · `high_contrast` (siyah zemin, neon camgöbeği + sarı)
- Kullanıcı renk seçimi: Default · Purple `#E040FB` · Green `#00E676` · Orange `#FF9100`
- **Bayi marka rengi**: panelden gelen `primary_color` kullanıcı "Default"tayken uygulanır

> 🔎 Referanstaki incelikli kural: panelden gelen **doygun kırmızı** tonlar
> "renk seçilmemiş" sayılıp yok sayılıyor (eski panel varsayılanı kırmızıymış ve
> uygulamanın mavi kimliğini eziyormuş). Aynı korumayı biz de uygulayacağız.

---

## 2. ÖZELLİK SETİ

### Referansta var — bizim yol haritamızda **yoktu**, eklendi

| Özellik | Not |
|---|---|
| **Aktivasyon kodu ile giriş** | Xtream/M3U dışında üçüncü kaynak türü. `/api/activation/redeem` |
| **Bayi (reseller) sistemi** | Marka rengi, DNS slug, müşteri adı, PIN korumalı playlist |
| **Uzaktan duyuru** | Öncelik: bayi > admin > ipucu. Çevrimdışı önbellekli |
| **DNS failover** | `/api/dns-list` + host probe; ölü sunucuda otomatik geçiş |
| **Bakım / zorunlu güncelleme kapısı** | Panel bayrağıyla uygulamayı kilitleme |
| **Bağlantı hızı testi** | Kullanıcı "yayın donuyor" dediğinde ilk bakılan yer |
| **EPG hatırlatıcı** | Gelecek programa alarm → bildirim → kanala git |
| **Canlı/VOD için ayrı motor** | Kullanıcı canlıda VLC, filmde AVPlayer seçebilir |
| **Harici oynatıcıya gönder** | Sistem paylaş sayfası üzerinden |
| **Altyazı boyutu + stili** | 0.75 / 1.0 / 1.3 / 1.6 ölçek |
| **Yüksek kontrast teması** | Erişilebilirlik |
| **Çoklu dil** | Referansta 31 KB'lık sözlük |
| **Açılış ekranı tercihi** | Ana sayfa / Favoriler |
| **Abonelik bitiş tarihi** | Xtream `exp_date`; süre dolunca yönlendirme |

### Panel API'si

Uç noktalar (temel adres **kodda sabit değildir**, yapılandırmadan gelir):

| Uç nokta | İş |
|---|---|
| `/api/app-config` | Marka rengi, duyuru, iletişim bilgileri, bakım/güncelleme bayrakları |
| `/api/activation/redeem` | Aktivasyon kodu → hesap bilgileri |
| `/api/dns-list` | Yedek sunucu listesi (failover) |

---

## 3. SAHADA ÖĞRENİLMİŞ DERSLER

Bunlar referans projede **gerçek kullanıcı şikâyetiyle** ortaya çıkmış ve
çözülmüş sorunlar. Bizde baştan doğru yapılacak.

### 🗄️ Veri / kalıcılık — **Faz 1'i doğrudan ilgilendirir**

| Ders | Bizde nasıl uygulanacak |
|---|---|
| 14.000 kanallık hesapta katalog **tek satıra** yazılınca ~2 MB oldu ve SQLite cursor penceresi taştı — cache sessizce hiç çalışmadı | Katalog satır satır yazılır, tek blob asla kullanılmaz |
| Cache okuma/yazma hataları sessizce yutuluyordu; bug ancak log eklenince bulundu | Kalıcılık hataları **her zaman** loglanır, sessiz `try?` yok |
| Liste arka planda sayfa sayfa büyürken sıralama kayıyordu ("filmler sürekli değişiyor") | Sıralama anahtarı sabit; sayfalama sırayı değiştirmez |
| İlk açılışta tüm katalog RAM'e alınıyordu | İlk sayfa sınırlı, gerisi arka planda; arama gerektiğinde tam liste ayrı sorgulanır |

### 📺 EPG

| Ders | Bizde |
|---|---|
| Tüm `epg_program` tablosu belleğe yükleniyordu | Pencereli sorgu: `[şimdi−3s, şimdi+36s]` |
| XMLTV tek seferde parse + tek transaction insert; iptal kontrolü yok | Akış halinde parse + parça parça insert + iptal kontrolü + hata halinde kısmi temizlik |
| EPG yalnızca Ayarlar'daki manuel butondan çekiliyordu → her yer "Bilgi yok" | Otomatik tazeleme; bayatlık kontrolü + kaynak başına kısıtlama (6 saatte 1) |
| Ad eşleştirmede her çağrıda yeni `Regex` üretiliyordu | Derlenmiş desen sabit tutulur |

### ▶️ Oynatma

| Ders | Bizde |
|---|---|
| HTTP zaman aşımı yoktu → kopuk bağlantıda sonsuz takılma | connect ~10 sn / read ~15 sn + üstel geri çekilme |
| Player teardown eksikse bağlantı kotası doluyor | `PlaybackEngine.teardown()` sözleşmede zorunlu |
| Bazı TV kutularında tek motor yetmedi | `PlaybackEngineResolver` + çalışma zamanı fallback (zaten var) |
| Kanal açılışında geri bildirim yoktu; kullanıcı "açılmıyor mu?" diye bekliyordu | Yükleme/buffer durumu her zaman görünür |

### 🌐 Ağ

- Zaman aşımsız `readText()` benzeri çağrı yok — **tüm** istekler zaman aşımlı
- `CancellationError` genel hata yakalamadan **ayrı** ele alınır (iptal yutulmamalı)
- Sunucu ölürse DNS failover devreye girer

### 🚫 Ürün kararı

> **Demo veri olmayacak.** Referansta demo modu sonradan tamamen kaldırıldı
> ("kesinlikle demo veriler olmasın"). Bizde hiç eklenmeyecek.

---

## 4. ETKİLEŞİM FARKI — DİKKAT

Referans **Android TV** odaklı: D-pad, focus halkaları, uzaktan kumanda.
Bizim hedefimiz **iPhone + iPad**: dokunma, kaydırma, haptik.

Bu yüzden referansın şu kısımları **doğrudan aktarılmaz**:
- `qruzeTvFocusable`, focus restore, D-pad seçim modeli
- TV navigasyon çubuğu (`DashboardTvNav`)
- Uzaktan kumanda tuş yakalama

Karşılığı iOS'ta: kaydırma jestleri, bağlam menüleri, haptik geri bildirim,
iPad'de klavye kısayolları.

---

## 5. ALMAYACAKLARIMIZ — mimari

Referans proje şu sorunları **yaşadı ve sonradan düzeltmek zorunda kaldı**:

| Sorun | Ölçü | Bizde neden olamaz |
|---|---|---|
| "God Screen" | `DashboardScreen.kt` **8976 satır** → 9 dosyaya bölündü | Her ekran ailesi ayrı Swift paketi; 200 satır kuralı |
| "God Object" ViewModel | `IptvViewModel.kt` **119 KB / 2456 satır** | ViewModel'ler feature'a ait, repository protokolü alır |
| Dağınık sabitler | *"900+ magic değer tek dosyada; theme sistemine taşınmalı"* | `Theme` zorunlu; ekranda ham değer yazılmaz |
| Kaynak türü dallanması | `username == "M3U_PLAYLIST" \|\| hostUrl == "ACTIVATION_CODE"` deseni **10+ yerde** | `ContentProvider` protokolü — dallanma tek yerde, App'te |
| Kopya kategori seçiciler | `selectLive/Vod/SeriesCategory` neredeyse aynı | Repository protokolleri tür bazlı ayrık |

> Bu tablo, ilk oturumdaki **"main dar şişmesin"** isteğinin nereden geldiğini
> açıklıyor. Kurduğumuz modül sınırları bu beş sorunu derleyici düzeyinde
> imkânsız kılıyor — iyi niyete veya disipline bırakmıyor.

---

## 6. MİMARİYE ETKİSİ

Bayi altyapısı kapsama girdiği için Domain'e yeni sözleşmeler gerekiyor:

```
OctopusDomain
 ├── Entities/
 │    ├── BrandConfiguration   (marka rengi, logo, iletişim)
 │    ├── Announcement         (duyuru + öncelik)
 │    ├── ServiceGate          (bakım modu / zorunlu güncelleme)
 │    └── ActivationResult
 └── Services/
      ├── RemoteConfigProviding   → /api/app-config
      ├── ActivationRedeeming     → /api/activation/redeem
      └── HostResolving           → /api/dns-list + probe
```

Ayrıca `Playlist.Kind`'a üçüncü durum eklenir:

```swift
case activationCode(code: String)
```

Bu sayede aktivasyon kodu, Xtream ve M3U ile **aynı** `ContentProvider`
soyutlamasından geçer — ekranlar farkı görmez.
