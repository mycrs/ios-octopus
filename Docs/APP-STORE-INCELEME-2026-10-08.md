# Octopus — 8 Ekim 2026 inceleme ve cihaz testi

Son kullanıcı düzeltmesi: mağaza hazırlığı korunur; yatay tam ekran,
Android referansına uygun kanal paneli, blur temizliği ve tam ekrandan
dönüşte yüzey/ses ömrü düzeltilip yeni build doğrulanmadan son inceleme
gönderimi yapılmaz. Aşağıdaki build 9 kanıtı bu ek değişikliklerin testi değildir.

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

Önceki on üçüncü build 10 kaynağı `359873a3077f4ea3deb90bfefad70e33affc6e3d`,
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

Önceki on ikinci build 10 kaynağı `53eb01efda3807d82095f1eb094a1dd60ce6c7be`,
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

Önceki on birinci build 10 kaynağı `a0d6bbb737e9443186a3a052c366bfb2e993944c`,
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

Önceki onuncu build 10 kaynağı `b96b195744cbb1331e519a94b9ae56488be40da0`,
[onuncu tur 37851820087](https://github.com/mycrs/ios-octopus/actions/runs/37851820087):
**728 Swift testi / 1 hata**; mimari ve iOS uygulama derlemesi geçti.
Tek birim hatası, tuzlu SHA-256 özetinde PIN rakamlarının tesadüfen
geçmesini yasaklayan `ParentalControlTests` kontrolüdür. Üretim PIN
saklaması değiştirilmeden testin tam özet/tuz sözleşmesi doğrulandı;
bu düzeltme yukarıdaki on birinci Mac turunda geçti.

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
uyumluluk ayarını denedi; sonucu yukarıdadır. Dört iPad yönü, uyarlanır yerleşim, mevcut dinamik
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

Önceki dokuzuncu build 10 kaynağı `4dcba17d74baa6094eda6e0faceb4997a187eaa3`,
[dokuzuncu tur 37847499591](https://github.com/mycrs/ios-octopus/actions/runs/37847499591):
**726 Swift testi / 0 hata ve mimari geçti**. iPhone Release akışının
tamamı **228,167 saniyede geçti**. iPad ilk filmde native video üretmesine
rağmen portrede kaldı; ilk yatay pencere kontrolü başarısız oldu.
17 özgün tanı eki SHA/CRC ile doğrulandı. Yön isteğinde `requested=24`,
`orientation=1`, `locked=0`, `appMask=30`, `rootMask=30`, `presentedMask=24`,
pencere 1032×1376; hemen ardından **101** hatası kaydedildi. Video ilerlerken
etkin kilit kapalıdır; erken portrait kilidi tek başına bu arızayı açıklamaz.
`appMask=30`, UIApplication'ın varsayılan Info.plist maskesi getter'ıdır;
özel AppDelegate/policy lease dönüşü değildir ve lease arızasını kanıtlamaz.

Dokuzuncu turdan sonra hazırlanan aday ilk geometry isteğini `viewDidAppear` yerine gerçek
UIKit sunumunun completion sınırına taşır. Yalnız hâlâ kendi host'u,
istenen kimliği ve geçerli sunum durumu eşleşiyorsa istek yapılır; kapanan
veya invalidated sunum istek göndermez. Bekleyen/kilitli/kapanan durumları,
geç callback koruması ve beş yön regresyon testi korunur. Bu değişiklik yukarıdaki onuncu turda Mac'te denendi; zamanlayıcı/retry eklenmez, UI doğrulamaları zayıflatılmaz.
Bu dokuzuncu/onuncu kaynaklarda `UIRequiresFullScreen` eklenmemişti. Deprecated public uyumluluk optout'u
yalnız araştırılmış yedek seçenektir: iPad çoklu görevini kısıtlar ve SDK 27+
için migration gerektirir; başarı garantisi değildir. [Apple TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key)
Dokuzuncu turun imzalı işi skipped; imzalı build 10, Apple yüklemesi ve
USB kurulumu yok. Başarı görsel klasörü oluşturulmadı. Mevcut build 9,
kaynak pinleri ve bekleyen gizlilik/inceleme kapsamı korunur. Yerel kanıt:
`.artifacts/release10-attempt9-failure-qa.json` ve `build10-attempt9-small`.

Sekizinci build 10 adayı `4983c0b08aee0b5f08e857785ba018b760749244`,
[sekizinci Mac turu 37842943490](https://github.com/mycrs/ios-octopus/actions/runs/37842943490):
**721 Swift testi / 0 hata ve mimari kapısı geçti**. iPhone Release
kullanıcı akışının tamamı **281,438 saniyede geçti**: gerçek native kare,
filmden aynı detaya dönüş, Canlı TV mini/tam ekran geçişleri, soldaki
kanal paneli, mevcut kanala dokunma, Sintel araması ve kanal değişimi,
seçilen mini oynatıcıya dönüş, bölüm ve kaynak kontrolü doğrulandı.
iPad Pro 13-inch (M5), iPadOS 26.4.1 simülatörü ilk filmde gerçek native
kareyi üretti; oynatıcı dikey kaldığı için yatay pencere kontrolü
başarısız oldu. Özgün kayıt 2064×2752 portrede ilerleyen filmi gösterir;
filtreli UIKit kaydı `Player orientation request failed; code=101` içerir.
Bu, reddedilen yön isteğinin kanıtıdır; çözümleme arızası veya testin
ekranı yanlış kırpması değildir. Kilidin portrede erken uygulanması
olasılığı, henüz sonraki gerçek Mac testiyle doğrulanmamış bir çıkarımdır.

Sekizinci turdan sonraki düzeltme kilit durumunu **bekleyen → kilitli → kapanan**
olarak ayırır. Önce yatay geometry isteği yapılır; public lock tercihi
yalnız kendi scene yönü, view ve window ölçüleri gerçekten yatay
gözlendikten sonra açılır. Kapanış durumu mühürlenir; geç kalan dönüş/layout
callback'i kilidi yeniden açamaz. Sonraki Mac sonucu yukarıdaki dokuzuncu turdadır.
Sekizinci turda imzalı iş **skipped**; imzalı build 10 üretilmedi,
Apple'a yüklenmedi veya telefona kurulmadı. Tamamlanmış yeni iPhone/iPad
görsel takımı yok; başarısız turdan görsel gönderilmez. Mevcut build 9,
mağaza kayıtları ve bekleyen gizlilik/inceleme kaynak kapsamı korunur.
Yerel kanıtlar `.artifacts/build10-attempt8-small/extraction-report.json`,
`ipad-player-ui.log` ve `video-inspection/frame-report.json` içinde aynı
kaynak/run kimliği, özgün dosya SHA/CRC'si ve video zamanlarıyla tutulur.

Build 10 düzeltmeleri `bc5ee4b2cb522075f17c4dc65709bdde7fe3f69c` kaynağında
uygulandı. [İlk Mac çalışması 37818493598](https://github.com/mycrs/ios-octopus/actions/runs/37818493598)
henüz son başarılı doğrulama değildir: Playback'te yeni bir testin escaping
closure kullanımı derlenmedi, test yerel sabit yakalayacak şekilde düzeltildi.
İkinci Mac turu `64c1849` / 37819697146'da **715 Swift testi ve mimari kapısı
geçti**. Release akışı kanal düğmesine ulaşırken 3,5 saniyelik otomatik
gizlenme süresiyle çakıştı; dokunma yardımcısı sınırlı yeniden görünür kılma
ile onarıldı. AX kanıtında pencere/video 874×402 ve ilk kare hazırdı.
Dikey cihaz duruşuyla yatay kilitli pencere ayrıştığında `app.screenshot()`
kırpıldığı için dikey kilit testi korunup tam ekran kaydı cihaz yataya
hizalandıktan sonra `XCUIScreen.main.screenshot()` ile alınır.
Üçüncü Mac turu `45ed5d0` / 37822616226'da **715 Swift testi ve mimari
kapısı geçti; iPhone Release akışının tamamı başarılı**. iPad ilk filmde
yatay yön kontrolünden geçmedi. Özgün ekran kaydı oynatmanın ilerlediğini,
oynatıcı arayüzünün ise portrede kaldığını doğruladı; bu gerçek yön hatasıdır.
SwiftUI cover'ın arka plan alt denetleyicisi yerine, kendi tam ekran UIKit
hosting denetleyicisi kullanılır. Yön tercihi, scene lease ve iOS 26+
public orientation lock gerçek sunulan denetleyiciye aittir. Kapanış
tamamlanmadan eski yön geri istenmez; eski kapanış yeni oynatıcıyı kapatamaz.
Mağaza oynatıcı karesinde normal duraklat düğmesiyle denetimler görünür
tutulur; video karesi ve PNG'nin özgün EXIF yön metaverisi korunur.
Dördüncü tur `51d2321` / 37829073111, UIKit `.fullScreen` sunumunun
arka plandaki view'ı pencereden çıkarmasının kapanış guard'ını engellediği
bulununca imzalı iş başlamadan iptal edildi. Beşinci tur `f464d83` /
37830236567'de **721 Swift testi ve mimari kapısı geçti**. iPhone filmde
yatay kilidi, tam ekran video alanını ve aynı dikey detay sayfasına dönüşü
doğruladı. Sonraki Canlı TV sekmesi seçilmedi; iPad akışı başlamadı.
Özgün kayıt Movies sekmesinde cam/ripple tepkisi gösteriyor; gerçek dokunma
koordinatı bilinmediği için neden hit-test, seçim veya animasyon hatası
olarak kesinleştirilmedi. Testin bekleme süresi artırılmaz veya adım atlanmaz.
Kapanış başlamadan görünür denetleyicinin public yön kilidi kaldırılır;
scene lease son kapanışa kadar korunur. Arka plan bridge'i SwiftUI'da
dokunma almaz. Gerçek kapanıştan iki saniye sonra yalnız sayısal UIKit
durumu, sınıf/rect ve sınırlı animasyon sayımı kaydedilir; içerik/hesap
bilgisi loglanmaz. Altıncı tur `aa73918` / 37835250387'de **721 Swift
testi ve mimari geçti**; iPhone aynı film detayına döndü, Canlı TV'ye geçti,
kanalın mini yüzeyinde ve yatay tam ekranda gerçek native kareyi gösterdi.
Kanal düğmesinde XCTest `.tap()` görünür/hittable kontrolden sonra scroll
ve yeniden sorgu yaparken düğme normal otomatik gizlenme süresine girdi.
Özgün video denetimlerin kaybolup görüntünün ilerlemeye devam ettiğini
doğruladı; çökme veya yeni yön hatası görülmedi. Düğmenin gözlenen pencere
içi merkezine normal dokunma kullanılır; sonraki panel, seçili kanal,
kanal değişimi ve dönüş doğrulamaları korunur. Önce videonun boş alanında
normal tek dokunuşla denetimler gizlenip yeniden açılır; iki ayrı dokunma
bölgesi ve gerçek gizlenme doğrulaması çift dokunmayla seek'i önler.
Canlı tam ekranın video/pencere ölçü eşitliği de kontrol edilir.
Ürün süreleri değiştirilmez.
Bu turda XCTest sonrası seçili simülatör kapalıydı; `simctl spawn` log
alamadı. Sayısal UIKit kayıtları bu yüzden runtime kanıtı sayılmaz.
Collector completed xcresult diagnostics arşivinden yalnız aynı güvenli
prefixleri çıkaracak şekilde düzeltilir; ham diagnostics yayımlanmaz.
Yedinci tur `a621e2e9846f94d970ac51afe0c29b1a20650507` /
[37838710378](https://github.com/mycrs/ios-octopus/actions/runs/37838710378)
**721 Swift testi ve mimari kapısından geçti**. iPhone gerçek filmde
yatay kilidi, tam video alanını ve aynı detay sayfasına dönüşü; Canlı TV'de
mini/tam ekran kareyi, soldaki seçili kanal panelini, mevcut kanala
dokununca panelin kapanmasını, aramayla Sintel'e geçişi ve doğru dikey
mini oynatıcıya dönüşü doğruladı. İkinci mini/tam ekran geçişi de yatay
ve native kareyle geçti. Son kapatma öncesinde test görünür düğmeyi
zorunlu gizleme varsayımında durdu; üç video dokunuşu yaptı, kapatma
düğmesine hiç basmadı. Bu başarısızlık kapatma düğmesinin bozuk olduğunu
kanıtlamaz. Görünür düğmeye doğrudan normal dokunma ve gerçek işlem
sonucunu sınırlı yeniden deneme içinde doğrulama uygulanır; ürünün
gizlenme süresi ve sonraki kontrol adımları değiştirilmez.
Bu turda collector'ın iPhone kaydı gerçekten üretildi: CRC/SHA doğrulanmış
`iphone-player-ui.log` altı güvenli olay içerir. Film ve ilk canlı kapanışı
sonrasında yön 1, pencere 402×874, public lock 0, root etkileşimi açık,
global event engeli/transition/modal kapalıdır; sekme seçimi 2→1 kaydedildi.
İkinci collector'ın «unavailable» satırı başlamamış iPad akışına aittir.
iPad ve imzalı iş çalışmadı. Yeni tam tur ve fiziksel cihaz kanıtı bekleniyor.
Başarısız çalışmalardan binary/görsel gönderilmez. App Store'daki kayıtlı build 9
ilişkisi ve mağaza alanları korunur; son başvuru yeni doğrulanmış paketi bekler.

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
