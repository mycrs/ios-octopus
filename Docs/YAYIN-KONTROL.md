# 🚀 YAYIN KONTROL LİSTESİ

> Hazırlanma tarihi: **2026-08-17**. İlk başvuru (`1.0.0`, build `1`).
> Kodda yapılabilecekler yapıldı ve CI'da doğrulandı. Bu belge **senin
> yapman gerekenleri** ve **doğrulanamayanları** bırakıyor.

---

## 1. KODDA ÇÖZÜLDÜ ✅

Bu ikisi derlemede değil, **App Store Connect'e yüklerken** patlıyordu —
yani ancak başvuru anında görülecekti.

| Ne | Neden önemliydi | Durum |
|---|---|---|
| `App/Resources/PrivacyInfo.xcprivacy` | Mayıs 2024'ten beri zorunlu. Eksikse yükleme **ITMS-91053** ile reddedilir | Eklendi, CI paket içinde doğruluyor |
| `ITSAppUsesNonExemptEncryption` | Yoksa her derleme **"Missing Compliance"** durumunda bekler, TestFlight'a/incelemeye gönderilemez | `false` bildirildi (yalnızca muaf şifreleme: HTTPS + Keychain + CryptoKit SHA-256) |

**Privacy manifest içeriği kod taranarak yazıldı**, tahminle değil:

- `UserDefaults` → 20 çağrı, tek "required reason" API. Sebep kodu `CA92.1`
- Takip / IDFA / `AppTrackingTransparency` → **yok**
- `identifierForVendor` veya başka cihaz tanımlayıcısı → **yok**
- Dosya zaman damgası, disk alanı, açılış zamanı, aktif klavye → **yok**
- Toplanan veri → **boş**: panele yalnızca aktivasyon kodu gidiyor,
  IPTV parolası cihazda Keychain'de kalıyor

### Ayrıca doğrulandı (sorun çıkmadı)

- **İkonlar eksiksiz**, 1024'lük dâhil, hepsi alfa kanalsız RGB
  (1024 ikonda alfa kanalı doğrudan ret sebebidir)
- **Launch screen** pakete giriyor (`UILaunchScreen` boş sözlük — kasıtlı)
- **`InfoPlist.strings` iki dilde tam** (tr + en)
- **Tüm demo/debug yolları `#if DEBUG` korumalı** — Release'te
  `-seedDemoData` ve arkadaşları ölü
- **Panel ulaşılamazsa uygulama açılıyor**: `appConfig?.gate` optional
  chaining, yapılandırma yoksa kapı kapanmıyor. İnceleyici panel
  çökmüşken bile uygulamayı kullanabilir
- **`AppError.reason` kullanıcıya hiç gösterilmiyor** — `userMessage`
  yalnızca case'e bakıyor. Koddaki "Faz 2'de eklenecek" gibi geliştirici
  metinleri yalnızca log'da kalıyor, ekrana çıkmıyor

---

## 2. SENİN YAPMAN GEREKENLER — risk sırasına göre

### 🔴 1. İnceleyiciye çalışan bir kaynak ver (Guideline 2.1)

**Bu, bu uygulamanın en olası ret sebebi ve en kolay önlenebilir olanı.**

İnceleyici uygulamayı açtığında karşılama ekranı görüyor ve bir kaynak
isteniyor. Kaynak yoksa uygulama **boş**. İnceleyici içeriği göremezse
"could not review" der ve reddeder.

**Karar verildi: demo M3U kullanılacak** (`google-review/test.m3u`) —
hesap açmaya gerek yok, tam metin `Docs/APP-STORE-METIN-TASLAKLARI.md`
§6'da hazır, App Review Notes'a olduğu gibi yapıştırılabilir.

- [x] Çalışan bir kaynak: demo M3U linki (aktivasyon kodu yerine)
- [x] Kaynak kalıcı — kendi sunucumuzdaki statik dosya, süresi dolmaz
- [x] Adım adım anlatım metne eklendi: *"Kaynak ekle → M3U sekmesi →
      linki yapıştır → Kaydet ve içeriği getir"*

### 🔴 2. İçerik sahipliğini açıkla (Guideline 5.2.3)

IPTV uygulamaları bu maddeden çok reddediliyor. Review Notes'a:

- [ ] Uygulamanın **yayın sağlamadığını**, kullanıcının **kendi mevcut
      aboneliğini** oynattığını açıkça yaz (bir medya oynatıcıdır)
- [ ] Demo hesabında telifli/korsan görünen kanal olmamasına dikkat et —
      inceleyicinin gördüğü şey senin iddianı desteklemeli
- [ ] Bayilik modelini kısaca anlat (kod → kendi hesabı)

### 🟠 3. ATS gerekçesi

`NSAllowsArbitraryLoads` açık. `App/Info.plist` içindeki yorumda gerekçe
zaten yazılı; **aynı metni Review Notes'a da koy**:

> Third-party IPTV providers deliver streams over plain HTTP and are
> outside our control; the app cannot require HTTPS for user-supplied
> sources.

### 🟠 4. Yaş sınırı

Uygulamada yetişkin içerik tespiti var (`AdultContentDetector`), yani
kaynak yetişkin kategori içeriyorsa gösterilebiliyor.

- [ ] Yaş derecelendirmesini buna göre doldur (düşük seçip sonra
      düzeltmek yeni bir inceleme turu demek)
- [ ] Ebeveyn kilidi **varsayılan açık** geliyor — ama varsayılan PIN
      `0000`. İnceleyici sorarsa cevabın hazır olsun
- [ ] Sorulursa: kilit yedi ekranda birden uygulanıyor
      (bkz. `BRAIN.md` → "İçerik kilidi nerede uygulanır?")

### 🟠 5. App Store Connect zorunlu alanları

- [x] **Gizlilik politikası URL'i** → `https://octopusplayer.com/privacy-policy/`
- [x] **Destek URL'i** → `https://octopusplayer.com/support/`
- [ ] **App Privacy** cevapları — kodda toplanan veri yok, ama **panelinin
      sunucu tarafında** tuttukları (IP kaydı vb.) varsa cevapları ona göre
      ver. Manifest yalnızca uygulamanın kendisini kapsar. Öneri:
      `Docs/APP-STORE-METIN-TASLAKLARI.md` §9
- [x] Ekran görüntüleri: **iPhone 6.9" (1320×2868) + iPad 13" (2064×2752)**
      — `~/Desktop/AppStoreScreenshots/` altında hazır, gerçek içerikle
      (`google-review/test.m3u` — Blender Foundation açık lisanslı filmler,
      telif riski yok) çekildi. Apple'ın istediği çözünürlükle birebir
      uyuyor, ek kırpma gerekmiyor
- [x] Açıklama, alt başlık, anahtar kelimeler, review notu taslağı,
      yaş sınırı ve gizlilik anketi önerileri → `Docs/APP-STORE-METIN-TASLAKLARI.md`

---

## 3. DOĞRULAYAMADIKLARIM ⚠️

Windows'ta Swift yok; her şey CI üzerinden doğrulandı. Aşağıdakiler
**gerçek cihaz/simülatör etkileşimi** gerektiriyor ve MacBook'unda
10'ar dakika sürer.

### iPad'de hiç bakılmadı

`TARGETED_DEVICE_FAMILY: "1,2"` ile iPad desteği **beyan ediliyor**, yani
Apple hem iPad ekran görüntüsü isteyecek hem de uygulamanın iPad'de düzgün
çalışmasını bekleyecek. CI yalnızca iPhone karesi alıyor.

- [ ] iPad simülatöründe bir tur at: ana sayfa, katalog ızgarası, oynatıcı,
      ayarlar
- [ ] Bozuksa iki seçenek var: düzelt **veya** `TARGETED_DEVICE_FAMILY`'yi
      `"1"` yapıp yalnızca iPhone olarak yayınla. İkincisi ret riskini
      düşürür ve sonradan iPad eklemek serbesttir

### Ayarlar'ın alt boşluğu

Kök ekranlarda `Theme.Layout.tabBarClearance` (56pt) var, **push edilen
ekranlarda yok** (Ayarlar, detaylar, liste yöneticisi). Ekran görüntüsü
kaydırma konumunu göstermediği için sekme çubuğunun son satırı örtüp
örtmediğini çözemedim.

- [ ] Ayarlar'ı **sonuna kadar kaydır**. Son satır sekme çubuğunun altında
      kalıyorsa o ekranlara da `.padding(.bottom, Theme.Layout.tabBarClearance)`
      ekle. Kalmıyorsa dokunma

### PiP ve HEVC

`BRAIN.md`'de zaten yazılı: PiP simülatörde kurulmaz, HEVC simülatörde
çözülmez. İkisi de **gerçek iPhone** ister.

- [ ] Gerçek cihazda bir UHD kanal aç — yedek motora düşmemeli
- [ ] PiP düğmesi çıkıyor mu ve çalışıyor mu

---

## 4. BİLİNEN AÇIK İŞLER (yayını engellemez)

`BRAIN.md` → "Açık işler" tablosunun özeti:

| # | İş | Etki |
|---|---|---|
| 1 | Bayi kodu ucu bağlı değil | DNS yedek listesi ve bayi logosu çekilmiyor |
| 2 | `DNSFailoverService.reset()` çağrılmıyor | Yedeğe geçildiyse asıl sunucu dönse de oturum boyunca yedekte kalınır |
| 3 | Eski M3U kaynakları Xtream'e dönüşmüyor | Yalnızca yeni eklemede dönüşüyor |
| 5 | HEVC gerçek cihazda ölçülmedi | Simülatörde her UHD kanal yedeğe düşüyor; cihazda düşmemesi beklenir |

---

## 5. SON DAKİKA KONTROLÜ

Arşivlemeden hemen önce:

```bash
xcodegen generate          # .xcodeproj git'te yok, üretilmeli
bash Scripts/check-architecture.sh
```

Sonra Xcode'da **Product → Archive** (Release yapılandırması).

⚠️ Arşiv aldıktan sonra, Organizer'da paketi sağ tık → **Show in Finder** →
paket içeriğini göster ve `PrivacyInfo.xcprivacy` dosyasının **kökte**
olduğunu gözünle doğrula. CI bunu kontrol ediyor ama arşiv farklı bir
yapılandırma (Release) ile üretiliyor.

---

## 6. ARŞİV VE `.ipa` ÜRETİMİ — çalışan yol

> 2026-08-19'da bu Mac'te uçtan uca çalıştırıldı; aşağıdaki komutlar
> imzalı bir `.ipa` üretiyor.

### Neden `Product → Archive` doğrudan çalışmıyor

Otomatik imzalamada Xcode **arşivi geliştirme kimliğiyle** imzalar,
dağıtım kimliğine ancak *dışa aktarma* adımında geçer. Geliştirme profili
ise takımda **en az bir kayıtlı cihaz** ister. Cihaz kaydı yoksa arşiv
şu hatayla düşer:

```
Your team has no devices from which to generate a provisioning profile
No profiles for 'com.octopus.iptv' were found
```

⚠️ `CODE_SIGN_IDENTITY`'yi "Apple Distribution" olarak dayatmak **çözüm
değil**: otomatik imzalama bunu "çakışan, elle belirtilmiş kimlik" sayıp
reddediyor (*"automatically signed for development, but a conflicting
code signing identity ... has been manually specified"*).

### Çözüm: imzayı dışa aktarma adımına bırak

App Store profili cihaz kaydı istemez. Arşivi imzasız al, `.ipa`'yı
dışa aktarırken imzalat:

```bash
xcodegen generate

xcodebuild archive -scheme Octopus -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath ~/Desktop/Octopus.xcarchive \
  CODE_SIGNING_ALLOWED=NO

xcodebuild -exportArchive \
  -archivePath ~/Desktop/Octopus.xcarchive \
  -exportPath ~/Desktop/OctopusExport \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

`ExportOptions.plist`:

```xml
<key>method</key>            <string>app-store-connect</string>
<key>teamID</key>            <string>V5ZC6396XD</string>
<key>signingStyle</key>      <string>automatic</string>
<key>uploadSymbols</key>     <true/>
```

### Üretilen paketi doğrula

```bash
cd $(mktemp -d) && unzip -q ~/Desktop/OctopusExport/Octopus.ipa
codesign -dv --verbose=2 Payload/Octopus.app
```

Beklenen:

| Alan | Değer |
|---|---|
| `Authority` | `Apple Distribution: …` (Development **değil**) |
| `TeamIdentifier` | `V5ZC6396XD` |
| Profil adı | `iOS Team Store Provisioning Profile: com.octopus.iptv` |
| `get-task-allow` | `false` |
| `PrivacyInfo.xcprivacy` | `Payload/Octopus.app/` **kökünde** |

### Yükleme

`.ipa` hazır olduktan sonra App Store Connect'te uygulama kaydı **zaten
oluşturulmuş olmalı**, yoksa yükleme reddedilir. Sonra:

- **Transporter** uygulaması (App Store'dan ücretsiz) ile sürükle-bırak, ya da
- `xcrun altool`/`notarytool` yerine güncel yol: Xcode Organizer →
  *Distribute App*
