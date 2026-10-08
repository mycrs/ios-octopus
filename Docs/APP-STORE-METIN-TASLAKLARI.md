# App Store Connect — güncel metinler ve inceleme bilgisi

**8 Ekim 2026.** Önceki taslakların yerini alır. Bu dosya App Store
Connect'e gönderim kanıtı değildir. Son Release'in sürüm/build, işlev ve
test kapsamı ile karşılaştırılarak kaydedilir. **Hedef build 9:** isteğe
bağlı örnek kitaplığı uygulama/test çalışması sürüyor; aşağıdaki yeni
örnek kitaplığı metni, özellik aynı Release'te uygulanıp doğrulanmadan
gönderilmiş veya çalışmış sayılmaz. İnceleme için Xtream test hesabı yok;
eski M3U ve normal kullanıcıya açık örnek kitaplığı farklı kapsamlar sunar.
[İnceleme kaydı](APP-STORE-INCELEME-2026-10-08.md) ve
[Apple araştırması](APPLE-INCELEME-HAZIRLIK-2026-10-08.md).

## Açıklama — Türkçe

```text
Octopus, eklediğin IPTV kaynaklarını iPhone ve iPad'de düzenleyip izlemeni sağlayan bir oynatıcıdır.

Xtream hesabını, M3U bağlantını veya cihazındaki M3U dosyasını ekle. Canlı yayınları kategori ve favorilerine göre bul; kaynağın sunduğunda film, dizi ve program rehberine ulaş.

• Kaynak yönetimi: birden fazla liste ekle, kaynak değiştir ve listeni isteğe bağlı PIN ile koru.
• İzleme düzeni: favoriler, izleme geçmişi ve film/dizilerde kaldığın yer bilgisi.
• Ebeveyn kontrolleri: hassas içeriğe ve seçtiğin kategorilere erişimi PIN ile yönet.
• Oynatıcı seçenekleri: yayının ve oynatıcı motorunun desteklediği ses, altyazı ve ekran ayarları.
• Resimde resim ve AirPlay: uyumlu yayınlarda yerel iOS oynatıcısı ile kullan.
• Kaynak kontrolü: cihazındaki katalog sayılarını, tekrar eden yayın anahtarlarını ve eksik rehber/görsel alanlarını gör. Destek raporunu iOS paylaşım ekranından kendin paylaş.
• Örnek kitaplığı: kendi kaynağını eklemeden önce açık lisanslı kısa filmlerle izleme ve liste yönetimini dene. Örnek kanal, rehber ve bölüm akışları gerçek bir yayın aboneliği sunmaz.

Octopus bir kanal aboneliği veya ticari yayın kataloğu sağlamaz. Kullanım iznin olan kendi kaynağını eklemen gerekir. İçerik, rehber bilgisi ve oynatma uyumluluğu kaynağına ve cihazına bağlıdır.
```

## Description — English

```text
Octopus helps you organize and play IPTV sources you add on iPhone and iPad.

Add an Xtream account, an M3U address, or an M3U file from your device. Find live streams by category and favorites. Browse movies, series, and program information when your source provides them.

• Source management: add multiple playlists, switch sources, and protect a playlist with an optional PIN.
• Viewing history: return to favorites, recent content, and saved movie or episode progress.
• Parental Controls: manage access to sensitive content and selected categories with a PIN.
• Playback options: choose audio, subtitles, and display settings supported by your stream and playback engine.
• Picture in Picture and AirPlay: use the native iOS player with compatible streams.
• Source check: inspect local catalog counts, duplicate stream keys, and missing guide or image fields. Share a support report yourself through the iOS share sheet.
• Sample library: explore viewing and playlist controls with openly licensed short films before adding your own source. Sample channel, guide, and episode flows do not provide a broadcast subscription.

Octopus does not provide a channel subscription or a commercial content catalog. Add a source you are authorized to use. Content, program information, and playback compatibility depend on your source and device.
```

Kaynak kontrolü canlı bağlantı/codec testi değildir. UHD, PiP ve AirPlay'in
her motorda ve yayında çalışacağı söylenmez. Örnek kitaplığı normal
kullanıcıya da açıktır; reviewer'a özel veya saklı mod değildir. «Hiç
içerik yok» iddiası kullanılmaz; ticari yayın aboneliği sağlanmadığı söylenir.

## Diğer metadata alanları

| Alan | Türkçe | İngilizce |
|---|---|---|
| Alt başlık | `Listelerin, izleme düzenin` | `Your playlists, organized` |
| Tanıtım metni | `Kendi kaynaklarını ekle; favorilerini, izleme geçmişini ve kategori korumasını tek yerde yönet. Yerel kaynak kontrolüyle listeni gözden geçir.` | `Add your own sources. Manage favorites, viewing history, and category protection in one place, then inspect your playlist with the local source check.` |
| Anahtar kelimeler | `iptv,xtream,m3u,oynatıcı,canlı tv,epg,favoriler,yayın,listeler` | `iptv,xtream,m3u,player,live tv,epg,playlist,favorites,streaming` |

Mevcut Octopus marka kimliği korunur. IPTV kelimesini gizlemenin 4.3'ü
çözeceğine dair resmî dayanak yok. Rakip benzetmeleri ve ölçülmemiş
«saniyeler içinde», «kesintisiz», «bütün UHD kanalları» ifadeleri kaldırıldı.

## Review Notes — temel ürün açıklaması

Aşağıdaki blok, kaynak/test bilgileri tamamlanıp son Release'te doğrulandıktan
sonra birlikte kaydedilir. Gerekli test erişimi sonradan destekten isteme
şartına bağlanmaz.

```text
Octopus is an IPTV playlist player for users who already have a source they are authorized to use. The app does not sell a channel subscription or supply a commercial channel catalog.

Users can add an Xtream account, an M3U address, or a local M3U file. Xtream sources may provide live channels, movies, series, and guide information; availability depends on the source.

No Xtream review account is supplied for this submission. An optional Sample library is available from the welcome screen and Settings to all users. It uses openly licensed short films with attribution and preserves the film credits. Sample channel and guide entries demonstrate the app's interface; they are not a television operator's broadcasts or guide. The episode flow uses short-film selections identified as samples, rather than claiming they are episodes of a commercial series.

For a fresh installation, select Explore Sample Library on the welcome screen, read the content and license information, and select Open Sample Library. With an existing source, use Settings > Sample Library > Open Sample Library. In Movies, play a film and leave playback after a short interval to review saved progress. Add a favorite, open the sample film-selection episode list in Series, then open the clearly labelled sample guide in Live TV. The sample library demonstrates application controls; it does not certify compatibility with every Xtream provider or UHD format.

To check M3U import separately, select Start setup > M3U, enter https://octopusplayer.com/google-review/test.m3u in M3U link, give the source a name, and select Save and load content. No account credentials or activation code are needed for this M3U. Its 11 MP4 entries appear in the live-channel list; it does not supply a movie/series catalog or an external program guide.

Please also review the source-management and viewing-control flows: switching playlists, optional playlist PIN protection, favorites, saved viewing progress, and Parental Controls. In Settings, Source check shows local catalog counts and missing or duplicate catalog fields. The user can share a support report through the iOS share sheet; the report omits source URLs, credentials, content titles, PINs, and device identifiers.

Parental Controls are in Settings > Parental Controls. This section contains temporary unlocking, Change PIN, and Manage protected categories. The initial PIN is 0000 unless the user has already changed it. Unlock with the PIN, select a category in Manage protected categories, and relock to verify that protected content is hidden. The app does not perform age assurance or age verification.

Some user-supplied providers use HTTP for catalog requests and media streams. Those hosts are supplied by the user and are outside our control, so an ATS exception is required to support them. Octopus's own configured service URLs use HTTPS.

Picture in Picture and AirPlay are available through the native iOS player for compatible streams. Other formats may use the compatibility player, which has different capabilities.
```

### Test kaynağı bilgileri — gönderim öncesi tamamlanacak

| Test | İnceleme bilgisi | Başlangıç durumu |
|---|---|---|
| M3U import / oynatma | Karşılama → Kaynak ekle → M3U → adres → Kaydet ve içeriği getir. Mevcut kaynak varsa Ayarlar → kaynak yönetimi → yeni kaynak. | `https://octopusplayer.com/google-review/test.m3u` 8 Ekim'de erişilebilirdi; 11 MP4'ü canlı kanal listesi olarak içe alır. Son Release'te görüntü/ses denenmeli. |
| Yerel M3U | Dosyayı indir → iOS dosya seçicisinden M3U seç → içe al. | Dosya ve son Release akışı doğrulanmalı. |
| Film / dizi / bölüm | Normal kullanıcıya açık örnek kitaplığı → film ve örnek bölüm akışı; gerçek Xtream servisi için ayrı provider doğrulaması. | Xtream review hesabı yok. Bağımsız kısa filmler gerçek ticari dizi bölümü diye sunulmaz; build 9 test kanıtı beklenir. |
| EPG | Örnek kitaplığında açıkça örnek olarak etiketlenen rehber; gerçek operatör rehberiyle eşitlenmez. | Eski M3U rehber sağlamaz; örnek rehber kendi metadata'sıdır, dış EPG provider doğrulaması değildir. |
| Ebeveyn kontrolü | Ayarlar → Ebeveyn Kontrolleri → geçici aç → PIN → kategori yönetimi → tekrar kilitle. | Build 8'de ilk PIN `0000`; son sürümün temiz kurulum davranışı tekrar doğrulanır. |
| Kaynak kontrolü | Ayarlar → Kaynak kontrolü → sayılar → destek raporunu paylaş. | Yerel katalog kontrolü; toplu yayın yoklama değildir. |
| Örnek kitaplığı | Karşılama ve Ayarlar'dan isteğe bağlı; tüm kullanıcılar için aynı kaynak türü ve normal oynatma/katalog akışları. | Build 9 uygulama/test bekleniyor. Gerçek Xtream servis uyumluluğunu tek başına doğrulamaz. |

Kullanıcı yalnızca M3U sağladı; olmayan Xtream hesabı veya sahte credentials
App Store Connect'e yazılmaz. İleride özel test hesabı edinilirse host/
kullanıcı/parola repoya yazılmaz, Review Information'a girilir ve inceleme
boyunca çalışır tutulur. Adımlar son İngilizce arayüz başlıklarıyla kontrol
edilir. İlk PIN mevcut kaynak kodda `0000`; yukarıdaki önerilen Sample
Library İngilizce etiketleri ve PIN aynı final build'in arayüzüyle kontrol edilir.
Örnek kitaplığının HTTP erişimi, görüntü/ses, atıf ve bütün tarif
edilen kontrolleri build 9'da doğrulanmadan bu Notes gönderilmez.

### Açık örnek içerik kullanılırsa

Blender Foundation, Big Buck Bunny için CC BY 3.0 ve bütün filmi
gösterirken tam kapanış jeneriği şartını belirtir; logolar ve bazı
materyaller kapsam dışıdır. [Big Buck Bunny license](https://peach.blender.org/about/)
Sintel için de CC BY 3.0, uygun atıf ve filmde tam jenerik şartı vardır;
logo/trademark'lar kapsam dışıdır. [Sintel sharing](https://durian.blender.org/sharing/)

Gerçek dosyanın lisans kapsamını doğrula; jeneriği kesme ve atıf/lisans
bağlantısını uygulamada göster. Örnek film gerçek TV kanalı veya ücretli
IPTV hesabı gibi sunulmaz. Erişilebilir dosya tek başına hak kanıtı değildir.

## 4.3(a) açıklama mesajı

Yeni build değişiklikleri reddedilen build 7'de varmış gibi anlatılmaz.
Aşağıdaki gelecek zaman taslağı ancak yapılacak çalışmalar için uygundur;
gönderimde biten/test edilen değişiklikler somut yollarıyla yazılır.

```text
Hello App Review Team,

We are addressing the concern in Guideline 4.3(a). Octopus is intended to remain an IPTV playlist player. Our submission will describe the actual source-management, viewing-control, and local source-check flows and provide direct steps to review them in the updated Release build.

Your message refers to similarities in binary, metadata and/or concept. Could you clarify which observed aspect of this submission needs to change, and provide actionable details that you are able to share? We are asking about our submission so we can address the specific concern.

We are revising the metadata and review access information to match the implemented behavior. The updated review notes will distinguish the test sources and the features each one covers.

Thank you.
```

## Gizlilik, destek ve beyanlar

| Alan | Yapılandırılmış adres |
|---|---|
| Gizlilik | `https://octopusplayer.com/privacy-policy/` |
| Destek | `https://octopusplayer.com/support/` |
| Uygulama lisansı / kullanım şartları | `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` — App Store Connect'te seçili Standard Apple License Agreement |
| Web sitesi kullanım şartları | `https://octopusplayer.com/terms-of-service/` — uygulama lisansının yerine geçirilmez |
| İsteğe bağlı pazarlama | `https://octopusplayer.com/` |

Politika ve destek 8 Ekim'de canlı tarayıcıda erişilebilir görüldü.
Uygulama içi linkler son Release'te açılmalı; panel bilgisi gelmese de
Octopus desteği erişilebilir olmalı. Politika manuel kaynakların yerel
saklanması ile isteğe bağlı web hızlı kurulumunun geçici işlemeyi ayırır.

Web sözleşmesinin 10 Temmuz 2026 platform listesinde iOS bulunmuyor ve
örnek kitaplığı anlatılmıyor. Site sözleşmesi bu çalışmada değiştirilmedi.
App Store Connect'te özel EULA yoksa Apple'ın standart lisansı uygulanır;
uygulama içindeki lisans bağlantısı bu seçime uyar.
[Apple standard license](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/)

Mevcut App Store etiketi **Data Not Collected**. Kodda reklam/analitik/IDFA
entegrasyonu gözlenmedi; sunucu kayıtlarının saklanmadığı yalnızca koddan
kanıtlanamaz. Transient istek aktarımı tek başına etiketi değiştirme nedeni
sayılmaz; gerçek uzun süreli sunucu/SDK saklaması varsa tür ve amaçları
değerlendirilir. [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

Parental Controls, PIN/kategori araçları son Release'te bulunabiliyor ve
çalışıyorsa **Present**; yaş doğrulama mekanizması yoksa Age Assurance
**None** kalır. Diğer cevaplar gerçek işlev/içeriğe göre doldurulur; sırf
IPTV olduğu için otomatik yüksek yaş veya düşük yaş üretmek için yanlış
cevap verilmez. BBB/Sintel örnekleriyle tüm içerik sorularını **None**
bırakmak uygun değildir: fantezi/çizgi film şiddeti, korku ve silah
betimleri final dosyalar izlenerek değerlendirilir. **Infrequent**
şiddet/korku/silah cevapları genel 9+; **Frequent** fantezi şiddeti/korku
iOS 26+ genel 13+, eski sistemlerde 12+ üretir. Bu sonuçlar diğer cevaplara
ve bölgeye bağlıdır; HEAD veya süre metadata'sı içerik frekansını
doğrulamaz. [Apple age definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)

## Görseller ve son kayıt

Eski klasör yolları/test kareleri hazır kanıt sayılmaz. Yeni iPhone/iPad
görselleri gönderilecek arayüzü göstermeli; cihaz başına çoğunluk kullanılan
uygulamayı göstermelidir. Kaynak kontrolü, ebeveyn kontrolü ve gerçek
izleme akışları somut değeri anlatır. [Apple screenshots](https://developer.apple.com/help/app-review/guideline-reference/2-3-3-screenshots)

Son kayıtta sürüm/build, kaynak commit, test kapsamı ve Review Notes'un
nihai metni birlikte saklanır. TestFlight upload ile App Review submission
ayrı adımlardır; canlı submission durumunu görmeden gönderildi denmez.
