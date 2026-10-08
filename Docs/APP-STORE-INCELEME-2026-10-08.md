# Octopus — 8 Ekim 2026 inceleme ve cihaz testi

Son kullanıcı düzeltmesi: mağaza hazırlığı korunur; yatay tam ekran,
Android referansına uygun kanal paneli, blur temizliği ve tam ekrandan
dönüşte yüzey/ses ömrü düzeltilip yeni build doğrulanmadan son inceleme
gönderimi yapılmaz. Aşağıdaki build 9 kanıtı bu ek değişikliklerin testi değildir.

Güncel doğrulanan kaynak `9c0e98a2b9f09140a062c90eaf7bd7c3010ae299`,
[yayın çalışması 37808603564](https://github.com/mycrs/ios-octopus/actions/runs/37808603564).
694 Swift testi, iPhone/iPad Release kullanıcı akışları ve imzalı Apple
yüklemesi başarılı. iPhone'a **1.0.0 (9)** kuruldu; kullanıcı sorunlu UHD
kanalda görüntü ve sesi, ardından normal kanalın çalıştığını doğruladı.
Bu UHD sonucu **VLC** içindir. Apple işlemden geçirme, build seçimi,
ekran görüntüsü değişimi ve gerçek App Review gönderimi ayrı adımlardır;
aşağıdaki son durum tablosunda tamamlanmamış olanlar belirtilir.

## Son reddin anlamı

App Store Connect'teki son Apple mesajı 7 Ekim 2026 tarihli. İncelenen
sürüm **1.0 (7)**, cihaz **iPad Air 11-inch (M3)**. Gerekçe
**4.3(a), Design / Spam**: başka geliştiricilerin uygulamalarıyla binary,
metadata ve/veya kavram benzerliği. Mesaj belirli bir karşılaştırma
uygulaması veya dosya göstermiyor. Buradan belirli bir kod parçasını
reddin kesin nedeni olarak çıkarmak mümkün değil.

27 Eylül'deki **2.3.6** mesajı ebeveyn kontrollerinin bulunamamasıyla ilgili;
29 Eylül'de build 7 için yeni adımlar iletilmiş. Önceki **5.6** konusu için
Apple'ın 3 Eylül mesajında giderildiği belirtilmiş. Son 4.3 reddini bu eski
konularla veya UHD decoder sorunuyla eşitlememek gerekir.

Uygulamanın amacı IPTV oynatıcısı olarak kalır. Kaynak kontrolü ve destek
raporu bu deneyime yardımcıdır. Bu özellik, performans düzeltmeleri veya
yeni mağaza metni tek başına 4.3 kabulünü garanti etmez. Apple'ın
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#spam)
kuralları ve gözlenen Release davranışı birlikte değerlendirilmelidir.

İlk cihaz güncellemesi **1.0.0 (8)** idi; açılış kaydı oynatma içermedi.
Sonraki düzeltmelerle **1.0.0 (9)** derlendi, kuruldu ve Apple'a yüklendi.
**Apple'ın incelediği build 7'nin içinde bu değişiklikler bulunduğu
varsayılmamalıdır**. Mağaza metni/yaş cevapları ve son Review Notes
kaydedildi; build yüklemesi gerçek App Review başvurusu değildir.

## Doğrudan bulunan eksikler

| Bulgu | Sonuç / yapılacak iş |
|---|---|
| Mağaza açıklaması canlı TV, film ve dizi için genel bir medya oynatıcısı anlatıyor; inceleme notunda VLC benzetmesi var. | Gerçek kullanıcı akışlarını anlatan metin hazırlamak daha açıklayıcıdır. Bunun 4.3'ün kesin nedeni olduğu kanıtlanmadı. |
| İnceleme notundaki `https://octopusplayer.com/google-review/test.m3u` 8 Ekim'de HTTP 200 döndü; 11 MP4 kaydı ve `Google Play Review` grup adı içeriyor. | Adresin erişilebilir olması oynatmanın geçtiği anlamına gelmez. Bu M3U, mevcut parser'da canlı kanal listesine gider. |
| M3U provider film ve dizi listelerini boş döndürüyor; bu test listesi EPG sunmuyor. | Kullanıcı Xtream test hesabı sağlayamadı. Build 9'da bütün kullanıcılara açık, isteğe bağlı lisanslı örnek kitaplık film/bölüm/yerel örnek rehber akışlarını gösterir; gerçek Xtream/operatör EPG uyumluluğu kanıtı değildir. |
| Bağlı iPhone'daki build 2'de UHD sesli/görüntüsüz; native dört kez denenmiş, VLC yükleme olayı yok. | Otomatik VLC korunur. Eski binary'deki fallback sorunu gözlendi; gerçek manifest/codec/container henüz alınmadı. |
| Windows'ta USB log/DVT erişimi doğrulandı; başlangıçta sürüm 1.0.0 (2) idi. | Bağımsız InstallationProxy sorgusu son build 9 kurulumunu doğruladı. Kullanıcı UHD görüntü+ses ve normal kanal başarısını bildirdi; aşağıdaki VLC tanı kayıtları bu denemeye aittir. |

İnceleme için farklı davranan gizli bir mod eklenmedi. Kısa aktivasyon kodunu
Release'e yeniden açmak bu çalışmanın parçası değil. Yeni kaynak kontrolü
normal Ayarlar akışında erişilir; debug demo verileri Release test kaynağı
olarak sunulmamalıdır.

## Kod değişiklikleri

- **Ayarlar > Kaynak kontrolü ve destek raporu:** yalnızca etkin kaynağın
  yerel kanal/film/dizi/kategori sayılarını, tekrarlanan yayın anahtarlarını,
  eksik rehber kimliği ve logo bilgisini gösterir. Yayınlara toplu istek
  göndermez ve büyük katalogları Swift nesne listesi olarak yüklemez.
- **Paylaşılabilir JSON raporu:** açıkça seçilmiş katalog sayıları,
  uygulama/iOS sürümü ve oynatıcı anlık durumu. Kaynak adı/adresi,
  kullanıcı adı, parola, PIN, içerik adı, cihaz kimliği ve ham hata metni
  modele dahil edilmez. Paylaşımı kullanıcı iOS paylaşım ekranında başlatır.
- **Log gizliliği:** parametreleri açığa çıkarabilen DEBUG SQL trace kaldırıldı.
- **Ses ve çizim akışı:** cihazda görülen ana thread ses oturumu ve
  SwiftUI çizim sırasında yayın uyarılarını üreten yollar değiştirildi.
  Ses işlemleri iki motorun paylaştığı seri arka plan kuyruğunda çalışır;
  bekleyen yüklemeler iptal/nesil kontrolüyle korunur. Hosted overlay
  güncellemeleri çizim turundan sonraya taşınır ve son değerle birleştirilir.
- **Motor teşhisi:** güvenli seçim logu yedeğin mevcut/izinli olmasını
  gösterir; destek raporu `fallbackAvailable` alanını içerir.
- **Yayın doğrulaması:** imzalı TestFlight yükleme işi mevcut CI derleme ve
  paket testlerinin başarılı olmasına bağlandı. Windows log aracının
  gizlilik testleri de CI'a eklendi. Ayrı `device` hedefi CI kontrollerinden
  sonra şifreli, cihaz profiliyle imzalı IPA üretir; bu hedef başarıyla
  çalıştırıldı. Son 37808603564 çalışmasında imzalı Apple yüklemesi de
  başarılı; Apple'ın işlemden geçirmesi ve App Review gönderimi ayrıca izlenir.
- **Windows cihaz teşhisi:** yalnızca Octopus işlemine ait logları ve
  Octopus adına uyan crash raporlarını yerel olarak toplama aracı hazırlandı.
  Cihazdaki crash kopyaları silinmez; otomatik yükleme/paylaşım yoktur.

Önceki oynatıcı çalışması da korunuyor: UHD/fallback motor kararının
uygulanması, eski kanal seçimlerinin yeni yayını ezmemesi, kapanış sırasında
yeni oynatıcı oturumunun korunması, detay isteklerinin birleştirilmesi,
M3U yenilemesinde tek taze indirme ve gerçek ilk video karesiyle native
oynatıcının izlenmesi. Detaylar `BRAIN.md` 3 Ekim notlarında.

## UHD doğrulama yöntemi

Apple'ın [HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/)
HEVC için fMP4 segment ister. `.m3u8` uzantısı veya iPhone'un HEVC
donanım desteği tek başına yayının native uyumluluğunu kanıtlamaz.
HEVC'nin MPEG-TS segmentlerde bulunması olası bir açıklamadır; mevcut
kullanıcı yayını alınmadığı için kök neden doğrulanmış değildir.

Gerçek cihazda aynı sorunlu UHD kanal için zaman damgası, native/VLC
tercihi, video/ses codec'i, çözünürlük, segment container'ı, ilk kare,
tamponlama, sistem hata domain/kodu ve aynı kaynağın VLC sonucu birlikte
incelenmeli. Kimlik bilgisi içeren yayın adresi çıktılara veya repoya
konmamalı. Native uyumluluğu doğrulanmadan otomatik VLC kaldırılmamalı.

## Gerçek cihaz denemeleri

1. Kurulu uygulamanın sürüm/build numarasını kaydet; yerel kodla build 7'yi
   karıştırma. Yeni Ayarlar özelliği ancak bu değişiklikleri içeren build'de vardır.
2. Aynı kaynakta standart ve UHD kanalı aç; ilk görüntü/ses sürelerini ve
   kullanılan motoru kaydet. UHD için native denemeyi ayrıca ölç.
3. Art arda hızlı kanal değiştir; eski seçimin görüntü/hatasının geri dönmediğini
   ve çıkıp tekrar açmanın yeni oturumu durdurmadığını kontrol et.
4. Film detayı ve aynı dizinin bölümlerini tekrar aç; ağ kaydında aynı anda
   yinelenen detay isteği olmamalı. Kaynağı yenile; M3U tek kez indirilmeli.
5. Mini/tam ekran, arka plan/ön plan, PiP, AirPlay, ses/altyazı değişimi ve
   bağlantı kopması/geri gelmesini ayrı ayrı dene.
6. iPhone ve iPad'de ebeveyn kontrolleri, kategori gizleme ve liste PIN'ini
   kilitli/açık durumda doğrula. Büyük yazı boyutunda Ayarlar/oynatıcıyı kontrol et.
7. Yeni kaynak raporunu dışa aktar; URL/hesap/içerik adı taşımadığını,
   kaynak yokken yanlış rapor üretmediğini doğrula.

Bir senaryo başarısızsa o denemenin saatini, beklenen/gerçek davranışı ve
ilgili yerel log klasörünü birlikte kaydet. Tek bir başarılı açılış, tüm
formatların veya tüm cihazların doğrulandığı anlamına gelmez.

## İlk Apple yanıt taslağı — tarihsel kayıt

Bu metin son reddin hangi kısmına yönelik somut bilgi istendiğini anlatır;
yerel değişikliklerin build 7'de bulunduğunu veya özgünlüğün kanıtlandığını
iddia etmez. Bu ilk yanıt taslağı, daha sonra mağazaya kaydedilen
3.492 karakterlik Review Notes ile aynı alan veya metin değildir.

> Hello App Review Team,
>
> Octopus is intended to remain a player for IPTV playlists supplied by the
> user. We understand the concern that the current submission may not
> demonstrate sufficiently distinct user value.
>
> Your message refers to similarities in binary, metadata and/or concept.
> Could you clarify which of these applies to this submission and provide
> actionable details about the observed similarity, if you are able to share
> them? This would help us address the specific issue.
>
> We are reviewing the full Release experience and its metadata. Any revised
> submission will describe the actual implemented and tested functionality
> and include accurate instructions for the supported content types.
>
> Thank you.

## Mağaza açıklaması için örnek metin — son kayıtlı metin değildir

> Octopus organizes IPTV playlists you add through an M3U address, a local
> M3U file, or an Xtream account. Browse live channels and, when your Xtream
> source provides them, movies and series. Use favorites, playback history
> and viewing progress to return to your content. Program information is
> available when supplied by your source. Manage protected content and
> category visibility through Parental Controls in Settings.
>
> Octopus does not include a channel subscription. An optional sample
> library contains credited open-license films and clearly marked sample
> interfaces. You are responsible for providing personal sources you are
> authorized to use. Availability, program information and playback
> compatibility depend on the source and your device.

Son mağaza metni ve Review Notes gerçek Release örnek kitaplığı/kaynak
kontrolü akışlarını anlatır. M3U kapsamı, gerçek Xtream hesabının bulunmaması
ve örnek rehber/bölüm seçkisinin niteliği ayrı açıklanır. Kaydedilen Review
Notes kabul garantisi veya incelemeye gönderim kanıtı değildir.

## İlk build 8 hazırlığının yerel ve Mac doğrulama kaydı

8 Ekim'de yerelde tamamlanan kontroller:

- `Scripts/check-architecture.sh`: tüm mimari kuralları geçti.
- Değişen ve yeni **50 Swift dosyası** tree-sitter ile sözdizimi kontrolünü
  geçti. Bu tip denetimi veya Swift derlemesi değildir.
- Kaynak okuyucusunun gerçek SQL metni SQLite üzerinde denendi: farklı
  kaynakların ayrılması, boş katalog, boş anahtarların tekrar sayılmaması,
  eksik alan sayıları ve **50.000 kanallı sentetik katalog** doğru sonuç verdi.
  Bu ölçüm iOS cihaz performansı veya GRDB migration testi değildir.
- Yeni ekranın **42 İngilizce metin anahtarı** bulundu; dil dosyalarında
  yinelenen anahtar yok. Türkçe kaynak metinleri yerel dil düzenine uygun.
- Log aracının **12 Python testi** geçti: USB JSON keşfi, bozuk keşif
  çıktısının reddi, URL/kimlik bilgisi maskeleme,
  escaped JSON ve Authorization token'ı, başka uygulama/metadata filtresi,
  çoklu cihaz seçimi, timeout'ta cihaz kimliği ve erken biten kısmi yakalama.
- CI/release YAML ayrıştırması ve `upload -> verify -> ci.yml` bağı geçti.
  Sonrasında [37776653115 numaralı GitHub işi](https://github.com/mycrs/ios-octopus/actions/runs/37776653115)
  bütün doğrulama ve cihaz paketi adımlarını başarıyla tamamladı.
- `git diff --check` temiz. Ayarlar'ın değişen görünüm dosyaları 200 satırın
  altında olacak şekilde ayrıldı; taşınan ebeveyn kontrolü davranışı korundu.
- İlk hazırlık kontrolünde cihaz bağlı değildi. Kullanıcı cihazı
  bağladıktan sonra USB keşfindeki JSON ayrıştırma hatası düzeltildi;
  tek cihaz ve log servisine erişim doğrulandı. Kurulu sürüm **1.0.0 (2)**.
  İlk 180 saniyede 93 süreç kaydı; ayrı UHD denemesinde **31.152 kayıt**
  alındı. Kullanıcı UHD'de ses olduğunu, görüntü olmadığını ve normal
  kanalda görüntü geldiğini doğruladı. Native dört kez denendi, VLC yükleme olayı yok; codec/container
  nedeni kesinleşmedi. 16.989 SQL logu, 12 ses ve 10 SwiftUI uyarısı
  gözlendi. Tek DVT bellek örneği ve sonraki 15 örnek alındı; tam oynatma
  durumu/sızıntı sonucu çıkarılmadı. UHD sonrası da Octopus adına crash
  sayısı 0 (Jetsam hariç). Ayrıntılar `IOS-CIHAZ-LOG.md` içinde.

Kaynak raporu için **7 yeni XCTest** (Data 3, Playback 1, Settings 3),
cihazda görülen ses/çizim yolları için **5 yeni XCTest** (ses 3, overlay 2)
eklendi. Windows'ta Swift/Xcode bulunmadığından ilk yerel kontrolde bunlar
çalıştırılamadı. macOS runner'ında sonradan çalıştırıldı ve geçti:
Playback 57, Data 264, Features
194 XCTest; Domain, DesignSystem ve iOS uygulama işleri de başarılı.
İlk CI'da bulunan açık `self` derleme hatası ve M3U'nun somut nesne üzerinde
async varsayılan metodu seçmesi düzeltildi. Kaynak commit'i `88fc529` olan
imzalı build 8 üretildi; USB sorgusu `1.0.0 (8)` kurulumunu doğruladı.
Gerçek UHD görüntüsü ve normal kanal denemesi ayrıca doğrulanmalıdır.
Apple'ın bu yeni değişiklikleri incelediği iddia edilmemelidir.

Build 8'in açılış denemesinde 240 saniyede 2.915 süreç kaydı alındı;
AppContainer logu VLC yedek motorunu doğruladı. Oynatma olayı yok; bu
örnek UHD başarısı veya ses/çizim uyarılarının giderildiği şeklinde
sunulamaz. Octopus adına crash sayısı tekrar 0 (Jetsam hariç).

Cihaz aracı komutları ve sınırlamalar: [IOS-CIHAZ-LOG.md](IOS-CIHAZ-LOG.md).

## Son build 9 için Release ve fiziksel cihaz doğrulaması

Kaynak `9c0e98a2b9f09140a062c90eaf7bd7c3010ae299`,
[37808603564 numaralı yayın çalışması](https://github.com/mycrs/ios-octopus/actions/runs/37808603564)
başarılı. 694 Swift testi geçti: Domain 84, Features 219, Data 295,
Playback 71, DesignSystem 11 ve uygulama 14. Ana sayfa regresyonları ilk
M3U kaynağını, tarihsiz film/dizi kataloglarını, ebeveyn filtresini ve
geç kalan kaynak sonuçlarını kapsar. Katalog rafları kaynak bazlı SQL
sayfalaması kullanır; ek HTTP isteği oluşturmaz.

Her iki **iPhone ve iPad Release kullanıcı akışı** geçti: normal kullanıcıya
açık örnek kitaplık kurulumu, ana sayfa/film/bölüm/ayar/kaynak kontrolü ve
gerçek `AVPlayerLayer` video karesi. Önceki `b861665` turundaki iPad kapatma
dokunuşu yarışı giderildi; son turda oyuncu yüzeyinin kapanışı ve sonraki
bölüm adımı doğrulandı. Bu örnek video sonucu, bütün sağlayıcı/formatların
doğrulanması değildir.

İmzalı Apple yükleme işi başarılı. Aynı kaynak/build numarasıyla hazırlanan
USB paketi telefona güncelleme olarak kuruldu; ilerleme %100'e ulaştı ve
bağımsız InstallationProxy `get_apps` sorgusu **1.0.0 (9)** sonucunu verdi.
Yerel kayıt `.artifacts/device-builds/build9/installed-context.json` içinde
sürüm/build/kaynak commit'ini tutar; doğrulama scripti build 9 koşulunu
kontrol ettikten sonra bu kaydı yazar. Kişisel uygulama verileri silinmedi.

Kullanıcı yeni build 9'da önceki sorunlu UHD kanalında **görüntü ve sesin
geldiğini**, ardından **normal kanalın da çalıştığını** doğruladı. Denenen
UHD **VLC ile çalıştı**; native UHD başarısı iddia edilmez. 300 saniyelik
yakalama için `.artifacts/device-logs/20261008T165908300786Z` klasöründe
41.897 süreç olayı kaydedildi; ilk/son olay zaman aralığı yaklaşık 259
saniyedir. Yerel saatli gecikmeli VLC tanıları:

| Zaman | Yükleme nesli | Sayısal sonuç |
|---|---:|---|
| 20:01:14.896 | 1 | 8 sn; 2 video izi; seçili iz 0; video çıkışı var; 3840×2160; drawable ve pencere bağlı. |
| 20:02:02.712 | 2 | 8 sn; 2 video izi; seçili iz 0; video çıkışı var; 1920×1080; drawable ve pencere bağlı. |

Bu kayıtlar video izi/çıktı/yüzey metaverisidir; görünür ilk kare kanıtı
olarak sunulmaz. Görüntü/ses sonucu kullanıcının gözlemidir. Gerçek
codec/container kök nedeni veya tüm UHD/native kaynak uyumluluğu bu
denemeyle kesinleşmez.

Son UHD denemesini tanılamak için VLC motoruna yükleme başına en fazla
iki sayısal kayıt eklendi: ilk `.playing` olayı ve sekiz saniye sonrası.
Video izi/seçimi, video çıkışı/boyutu ve yüzeyin pencere/ölçü durumu
kaydedilir; adres veya hesap bilgisi yazılmaz. Bekleyen kayıt yükleme
nesliyle korunur ve duraklatma/durdurma/hata sırasında iptal edilir.
Bu metaveri görünür kare kanıtı değildir ve oynatma/fallback kararını değiştirmez.

## Apple'da kaydedilenler ve henüz tamamlanmayanlar

| Adım | Bu güncellemedeki durum |
|---|---|
| İngilizce mağaza metni ve yaş anketi | Kaydedildi; genel 13+ ve bölgesel/eski sistem sonuçları hazırlık belgesinde. |
| Review Notes | Son sürümün akışlarını anlatan 3.492 karakterlik not kaydedildi. Bu, App Review mesajı veya başvuru gönderimi değildir. |
| Apple'a 4.3 yanıtı | 8 Ekim 20:15 (GMT+3) itibarıyla 1.187 karakterlik yanıt gönderildi; konuşmada 8 mesaj görüldüğü doğrulandı. Bu, Submit for Review değildir. |
| Yeni ekran görüntüleri | CI Release artifact'ından iPhone 6 + iPad 6 olmak üzere 12 gerçek PNG seçildi. İlk görsel ilk 120 sn içinde `UPLOAD_COMPLETE` idi; sonra hatasız `PREPARE_FOR_SUBMISSION` ve doğru 1206×2622 spec doğrulandı. Diğer 11 görsel/yerleşim henüz tamamlanmadı. |
| Eski ekran ilişkileri | 21 mevcut placement ilişkisi bu noktada korunuyor. 12 yeni görsel işlenmeden eski ilişkiler kaldırılmaz; image asset silinmez. |
| Apple build 9 | İmzalı yükleme başarılı. Build 9 mevcut App Store sürümüne seçildi ve UI'da Save sonrası `Prepare for Submission` görüldü. Save öncesindeki API `Rejected` sonucu bu yeni durumun kanıtı sayılmaz; güncel API ilişkisi ayrıca okunur. |
| Gizlilik beyanı | Mevcut `Data Not Collected`/boş collected-data manifest'i ile canlı sunucunun gerçek saklama davranışı eşleştirilmeli. Yerel backend IP saklıyor; canlı sürüm eşitliği kullanıcı yanıtı/dağıtım kanıtı bekliyor. |
| Yayın tercihi | App Store Connect'teki mevcut onay sonrası otomatik yayın tercihi korunuyor; manuel yayına çevrilmedi. |
| App Review gönderimi | Gerçek `Submit for Review` ve `Waiting for Review` sonucu henüz yok. Yükleme veya TestFlight processing incelemeye gönderim değildir. |

Yerel backend'de aktivasyon rate limit'i IP/sayaç/pencere sonunu SQLite'a,
yavaş config/DNS/bayi istekleri IP ve teşhis bilgilerini diske yazar.
Bu kodun canlı backend ile eşitliği kanıtlanmadı; public cache başlıkları
aynı kaynak sürümünü veya saklama süresini ispatlamaz. Eşitse `Data Not
Collected` beyanı yeniden düzenlenmelidir; yalnızca işlev için saklanan
veri de kullanımına uygun tür/amaçla açıklanır. [Apple — App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
Bilinen dört backend dosyasını canlıda hash ile karşılaştırmak için
incelenen kapsamda güvenilir FTP/SSH erişimi ve doğrulanmış uzak document
root eşlemesi bulunmadı; uzaktan bağlantı denenmedi.

Ekran işlemesi, gizlilik eşleştirmesi, build ilişkisinin son kontrolü ve gönderim sonucu
tamamlandıktan sonra bu tablo gerçek Apple durumuyla güncellenir. Apple
4.3 kabulü veya onayı henüz alınmadı; bu çalışma kabul garantisi vermez.

Son iletişim kanıtı: 8 Ekim **20:15 (GMT+3)** App Review yanıtı gerçekten
gönderildi; `.artifacts/apple-review-reply-sent.jpg` yerel görüntüsü ve
konuşmadaki 8 mesaj sonucu ana ajan tarafından doğrulandı. Gönderilen
1.187 karakterlik yanıt, yukarıdaki ilk taslak ve kaydedilen 3.492
karakterlik Review Notes'tan ayrı tutulur. İncelemeye yeni başvuru ve
Apple onayı bu mesajdan çıkarılmaz.
