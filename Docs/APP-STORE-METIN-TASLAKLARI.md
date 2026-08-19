# ✍️ App Store Connect — Metin Taslakları

> Buraya App Store Connect'e giriş yapamadığım için kopyala-yapıştır
> yapabileceğin hazır metinleri bırakıyorum. Hepsi **gerçek** uygulama
> davranışını anlatıyor — hiçbir özellik uydurulmadı.

---

## 1. Ekran görüntüleri — HAZIR

`~/Desktop/AppStoreScreenshots/` altında, Apple'ın istediği çözünürlükte
(ek kırpma/küçültme gerekmez):

| Cihaz | Klasör | Çözünürlük | Apple'ın istediği |
|---|---|---|---|
| iPhone 6.9" | `iPhone/` (3 görsel) | 1320×2868 | ✅ birebir uyuyor |
| iPad 13" | `iPad/` (4 görsel) | 2064×2752 | ✅ birebir uyuyor |

İçerik `octopusplayer.com/google-review/test.m3u` ile — Blender Foundation'ın
açık lisanslı filmleri (Big Buck Bunny, Sintel, Elephants Dream, Tears of
Steel). Telif riski yok, tamamen güvenli.

Screenshot'lar: karşılama (içerik sağlamama notu görünür), ana sayfa
(gerçek kaynak + senkron durumu), Canlı TV (gerçek kanal listesi), Ayarlar
(gerçek oynatıcı/gizlilik ayarları).

---

## 2. Açıklama (Description)

### Türkçe

```
Octopus, kendi IPTV aboneliğini tek bir uygulamada izlemeni sağlayan
sade bir oynatıcıdır.

Xtream Codes hesabını, M3U bağlantını ya da hizmet sağlayıcından
aldığın aktivasyon kodunu ekle — canlı yayınların, filmlerin ve
dizilerin birkaç saniyede karşında olsun.

ÖNE ÇIKANLAR
• Canlı TV: kategoriler, favoriler, yayın akışı (EPG)
• Film ve dizi: kaldığın yerden devam et
• Kesintisiz oynatma: yayın koparsa kendiliğinden yeniden bağlanır
• Resimde resim (PiP) ve AirPlay desteği
• Ebeveyn kilidi: hassas içerikleri PIN ile gizle
• Sesli ve altyazılı içerik desteği
• iPhone ve iPad'de eksiksiz deneyim

Octopus içerik sağlamaz ya da barındırmaz — yalnızca bir oynatıcıdır.
Yayınlar tamamen senin eklediğin, kendi aboneliğine ait kaynaktan gelir.
```

### English

```
Octopus is a clean, focused player for your own IPTV subscription.

Add your Xtream Codes account, M3U playlist, or the activation code
from your provider — your live channels, movies, and series are ready
in seconds.

HIGHLIGHTS
• Live TV: categories, favorites, TV guide (EPG)
• Movies & series: continue right where you left off
• Uninterrupted playback: reconnects on its own if a stream drops
• Picture in Picture and AirPlay support
• Parental lock: hide sensitive content behind a PIN
• Audio track and subtitle support
• Full iPhone and iPad experience

Octopus does not provide or host any content — it is only a player.
Streams come entirely from the subscription you add yourself.
```

⚠️ **"IPTV" kelimesini başlığa/alt başlığa koyma.** Apple incelemesinde
bu kelime tek başına IPTV kategorisine dair otomatik bir alarm
oluşturmuyor ama açıklamada "kendi aboneliğin" vurgusunun her yerde
tekrar etmesi 5.2.3 savunmasını güçlendiriyor — yukarıdaki taslak buna
göre yazıldı.

---

## 3. Alt başlık (Subtitle, 30 karakter)

- TR: `Kendi IPTV aboneliğin` (21 karakter)
- EN: `Your own IPTV player` (21 karakter)

## 4. Tanıtım metni (Promotional text, 170 karakter — istediğin zaman değişebilir)

- TR: `Canlı TV, film ve diziler kaldığın yerden devam eder. Yayın koparsa kendiliğinden yeniden bağlanır.`
- EN: `Live TV, movies, and series — pick up right where you left off. Reconnects automatically if a stream drops.`

## 5. Anahtar kelimeler (Keywords, 100 karakter, virgülle ayrılmış boşluksuz)

```
iptv,xtream,m3u,canlı tv,oynatıcı,player,live tv,playlist,streaming,epg
```

---

## 6. App Review Notes (İnceleme notları)

`Docs/YAYIN-KONTROL.md` §2'de zaten var, buraya kısaca özet:

```
Octopus is a generic IPTV player, comparable to VLC or IPTV Smarters —
it ships with zero content. Users connect their own legally licensed
Xtream Codes or M3U subscription. No content is hosted, proxied, or
endorsed by this app.

Third-party IPTV providers deliver streams over plain HTTP and are
outside our control; the app cannot require HTTPS for user-supplied
sources (see NSAppTransportSecurity justification in Info.plist).

Test credentials:
[BURAYA ÇALIŞAN BİR AKTİVASYON KODU VEYA XTREAM HESABI YAZ]
```

⚠️ **Bu alanı boş bırakma** — inceleyici çalışan bir kaynak göremezse
"Guideline 2.1: Information Needed" ile geri döner. Demo M3U'yu
(`google-review/test.m3u`) da verebilirsin, ama Xtream/aktivasyon
akışının da çalıştığını göstermek daha güvenli.

---

## 7. Zorunlu URL'ler

| Alan | Değer |
|---|---|
| Gizlilik politikası (zorunlu) | `https://octopusplayer.com/privacy-policy/` ✅ verdin |
| Destek URL'i (zorunlu) | ⚠️ **eksik** — `octopusplayer.com` üzerinde ayrı bir destek/iletişim sayfası var mı? Yoksa aynı domain'in ana sayfasını kullanabiliriz |
| Pazarlama URL'i (isteğe bağlı) | `https://octopusplayer.com` önerilir |

---

## 8. Yaş sınırı anketi — önerilen cevaplar

Uygulamada gerçek bir ebeveyn kilidi var (`AdultContentDetector` +
7 ekranda uygulanan kilit, bkz. `BRAIN.md`), ama kaynağın ne
göstereceği kontrol edilemediği için:

- **Unrestricted Web Access**: Hayır (uygulama tarayıcı değil, sadece
  kullanıcının eklediği yayını oynatıyor)
- **Realistic/Prolonged Graphic Violence, Sexual Content vb.**:
  kaynak bağımlı olduğu için **"Infrequent/Mild"** yerine gerçekçi
  olan — Apple'ın IPTV oynatıcılarına genelde uyguladığı gibi
  **17+** dereceye çıkması bekleniyor. Düşük seçip sonra
  yükseltmek yeni bir inceleme turu demek — baştan 17+ seçmek
  daha az sürtünmeli.

## 9. App Privacy (Gizlilik Etiketi) anketi — önerilen cevaplar

`PrivacyInfo.xcprivacy` bunun **yerine geçmez**, App Store Connect'te
ayrıca doldurulmalı:

- **Veri toplanıyor mu?**: Hayır (uygulamanın kendi sunucusuna kimliğe
  bağlı veri gitmiyor — yalnızca kullanıcının girdiği IPTV kaynağı
  cihazda/Keychain'de tutuluyor, panelin kendi sunucusuna değil)
- Eğer bayi paneli (aktivasyon kodu, `octopusdocumentary.com`)
  herhangi bir analitik/IP kaydı tutuyorsa, o ayrı bir soru grubunda
  ("Data Not Linked to You" gibi) işaretlenmeli — panelin kendi
  gizlilik politikasına bakılmalı.

---

## 10. "What's New" (İlk sürüm için)

İlk sürümde bu alan genelde boş bırakılır ya da:

- TR: `İlk sürüm.`
- EN: `Initial release.`
