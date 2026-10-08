# Windows üzerinden Octopus iOS logları

Bu araç iOS uygulamasını derlemez. USB üzerinden bağlı cihazdaki **kurulu
Octopus sürümünün** loglarını okur. Yeni yerel değişiklikler ancak bunları
içeren ayrı bir iOS build kurulduğunda cihazda denenebilir.

8 Ekim 2026'da Apple Devices kurulu, Python 3.12 ortamında
`pymobiledevice3 11.26.0` hazır ve bağlantı kontrolü **0 cihaz** döndü.
Bu ilk hazırlık kontrolünden sonra kullanıcı cihazı bağladı; gerçek
bağlantı ve ölçüm sonuçları aşağıdadır.

## Güncel durum — build 8 kuruldu

8 Ekim 2026'da `88fc529112e52eb6174d3a0de007c20ecad73f31` kaynak commit'i
GitHub macOS runner'ında derlendi. [37776653115 numaralı iş akışı](https://github.com/mycrs/ios-octopus/actions/runs/37776653115)
başarılı: mimari, Domain, DesignSystem, Data, Features, Playback ve iOS
uygulama derleme/test işleri geçti. Playback **57**, Data **264**, Features
**194** XCTest geçti; ses/overlay ve M3U cache regresyonları bunlara dahil.
Yerel cihaz araçlarının **20 Python testi** de geçti.

Release arşivi, kayıtlı hedef cihazı içeren `release-testing` profiliyle
imzalandı. Şifreli artifact yerelde açılıp IPA'nın SHA-256 değeri, kaynak
commit'i, bundle ID'si ve build numarası doğrulandı. TestFlight/App Store'a
yükleme yapılmadı. Cihazın kayıt durumu zaten `ENABLED` idi; yeni cihaz
kaydı veya güvenlik ayarı değişikliği gerekmedi.

İlk kurulum komutu zaman aşımına uğradı. Alternatif streaming aktarımı
tamamlandı, ancak iOS önceki installation-proxy işleminin coordinator'ını
tuttuğundan kurulumu reddetti. Aynı bundle ID'ye güncelleme tekrar denendi;
çalışan Octopus süreci DVT ile kapatıldı. İlerleme callback'inde yerel araç
hatası oluşmasına rağmen **bağımsız USB uygulama sorgusu `1.0.0 (8)`
kurulumunu doğruladı**. Başarı, installer'ın çıkış koduna dayanmaz.
Uygulama kaldırılmadı veya verileri silinmedi.

Build 8 açıldı ve 16:01 İstanbul'da başlayan 240 saniyelik yeni kayıt
tamamlandı: **2.915 olay**, uygulamaya özel 3 açılış olayı. `AppContainer`
logu yedek motorun **VLC** olduğunu doğruladı. Bu örnekte **0 oynatma
olayı**, 0 SQL trace, 0 ses hang uyarısı ve 0 SwiftUI yayın uyarısı var.
Kanal açılmadığından son üç sıfır değer, eski UHD denemesindeki uyarıların
giderildiğini kanıtlamaz. Tekrar Octopus adına crash kontrolü: **0 dosya**
(Jetsam hariç). UHD ve normal kanalın görüntü/ses sonucu kullanıcı
denemesiyle ayrıca doğrulanmalı; aşağıdaki build 2 bulguları yeni sürümün
sonucu değildir. Aktif kayıt kalmadı; kanal denemesinden önce yeni kayıt
başlatılmalı.

Yeni kayıt ve özeti `.artifacts/device-logs/20261008T130116109955Z/`
altında; crash kontrolü `20261008T130432075797Z/crashes/` altında.
Kurulu sürüm/kaynak eşleşmesi `.artifacts/device-builds/build8/installed-context.json`
dosyasında yereldir.

## 8 Ekim gerçek bağlantı doğrulaması

- USB ve eşleştirme erişimi başarılı: tek cihaz, ürün tipi `iPhone18,2`,
  cihazın bildirdiği iOS sürümü `27.0`.
- Kurulu Octopus **1.0.0 (2)**. Apple'ın incelediği build 7 ve yeni yerel
  değişikliklerle aynı binary değildir.
- `usbmux list --simple` JSON dizi döndürüyor. İlk araç bu çıktıyı satır
  listesi sanıyordu ve bağlı cihazı 0 sayıyordu; JSON ayrıştırması düzeltildi.
  Bozuk çıktı artık sessizce boş liste sayılmıyor. Araçta **12 test geçti**.
- Octopus mevcut geliştirme servisi üzerinden açıldı. Cihaz güvenliği veya
  Developer Mode ayarı değiştirilmedi.
- İlk 120 saniyelik kayıt uygulama çalışmadığı sırada 0 kayıt üretti ve
  başarısız sayıldı. Uygulama açıldıktan sonraki 180 saniyede **93 kayıt**
  alındı. Süreç filtresi yalnızca Octopus'un ürettiği sistem loglarını tuttu.
- Bu örnekte 88 `com.apple.network`, 5 `com.apple.CFNetwork` kaydı var.
  Üç TCP reset/hata seviyeli kayıt bağlantı kapanışında görülüyor. Aynı
  anda TLS `close notify` ve bağlantı temizliği mesajları var; bu veriden
  UHD/codec hatası veya gereksiz HTTP istek sayısı çıkarılamaz.
- Bu 3 dakikalık örnekte uygulamaya özel `com.octopus.iptv` / oynatıcı
  teşhis kaydı yok. UHD kanalının gerçekten denendiği doğrulanmadı.
- Octopus adına uyan crash raporu bulunmadı; Jetsam raporları taranmadı.
- DVT sysmon tek anlık ölçümü (14:36 İstanbul): `cpuUsage: 0.0`,
  `physFootprint: 28.690.248` bayt (~27,4 MiB),
  `memResidentSize: 75.055.104` bayt (~71,6 MiB). Bu oynatma yükü, uzun
  süreli sızıntı veya pil profili testi değildir.

Kayıtlar yerelde `.artifacts/device-logs/20261008T113122973638Z/`
altında (`octopus.ndjson`, `process-snapshot.json`). Cihaz kimliği ve
hesap bilgileri bu belgeye yazılmadı. Bu ilk örnek UHD denemesinden önceydi.

## UHD denemesi — kurulu 1.0.0 (2)

Kullanıcı **UHD'de ses var, görüntü yok; normal kanalda görüntü var**
diye doğruladı. UHD denemesi sırasında 180 saniyede **31.152 kayıt**
alındı. İstanbul saatiyle gözlenen sıra:

| Saat | Uygulama logu |
|---|---|
| 14:38:50 | AVPlayer HLS yükledi. |
| 14:38:52 | Video izi yok uyarısı; yeniden bağlantı 1. |
| 14:38:54–14:39:01 | İki native yükleme daha; video izi yok; yeniden bağlantı 2 ve 3. |
| 14:39:07–14:39:09 | Dördüncü native yükleme; video izi yok; yeniden bağlantılar tükenmiş. |
| 14:39:34–14:39:40 | Yeni seçim/yeniden bağlantı sonrası native oynatma; açılış logu 2868 ms. |

İlk hata dizisinde **4 native yükleme, 3 yeniden bağlantı ve 0 VLC yükleme
olayı** var. Eski binary'nin bu denemede fallback'e geçemediği görülüyor;
VLC'nin binary'de bulunmaması, ayarın kapalı olması veya eski motor seçim
kodunun etkisi bu kayıtla birbirinden ayrılamıyor. Kullanıcı normal kanalda
görüntüyü doğruladı; eski açılış logundaki 2868 ms gerçek ilk kare ölçümü
olarak kullanılmamalı.

Loglarda codec/segment container bilgisi yok. HEVC'nin MPEG-TS ile
paketlenmesi hâlâ yalnızca olası açıklama; native UHD kök nedeni
**doğrulanmadı**. Aynı kanalın VLC'de başarılı olduğu da bu kayıtla
kanıtlanmadı.

Ek bulgular ve yerel düzeltmeler:

- **16.989 SQL debug logu** EPG senkronizasyonu sırasında üretildi;
  parser 66.439 program bildirdi. Bunlar HTTP istek sayısı değildir.
  Parametreleri loglayabilen SQL trace yerel kaynakta kaldırıldı.
- **12 AVAudioSession Hang Risk** uyarısı: ses oturumu işlemleri ana
  iş parçacığını bekletebilir. Aktivasyon/deaktivasyon ortak seri arka
  plan kuyruğuna taşındı; aynı kategori tekrar ayarlanmıyor. Yüklemeler
  aktivasyonu bekledikten sonra iptal/nesil kontrolü yapıyor.
- **10 SwiftUI yayın uyarısı**: hosted overlay çizim sırasında senkron
  durum yayınlıyordu. Güncelleme çizim turundan sonraya taşındı, son değer
  birleştiriliyor ve ayrılan görünümün bekleyen güncellemesi iptal ediliyor.
- Yeni güvenli motor logu ve destek raporundaki `fallbackAvailable`,
  sonraki build'de motor seçimini ve yedeğin bulunup bulunmadığını gösterir.
  Kanal adı veya yayın adresi bu alanlara yazılmaz.
- UHD sonrası tekrar Octopus adına crash kontrolü yapıldı: **0 dosya**.
  Jetsam raporları bu kontrole dahil değildir.

Sonraki 15 saniyelik sysmon örneği **15 ölçüm** verdi: CPU `cpuUsage`
2,514–2,884; footprint 88.606.824–88.688.744 bayt (~84,5 MiB); resident
358.219.776 bayt (~341,6 MiB). Bu örneğin tam oynatma durumu doğrulanmadı;
UHD yükü, sızıntı veya pil testi sonucu olarak sunulmamalı. Önceki geçici
izleme komutu pretty-JSON çıktısını satır bazlı okuyup 0 örnek bildirmişti;
bu boş çıktı ölçüm sayılmadı. NDJSON dosya çıktısıyla tekrar ölçüldü.

UHD kayıtları yerelde `.artifacts/device-logs/20261008T113840460195Z/`
altında: `octopus.ndjson`, `summary.json`,
`followup-process-samples.ndjson`, `followup-process-summary.json`.
Yakalama tamamlandı; devam eden log kaydı yok.

Bu eski kayıt alındığında düzeltmeler **telefondaki build 2'de yoktu**.
Sonrasında build 8 macOS/Xcode ile derlenip kuruldu; XCTest sonuçları
yukarıdadır. Aynı UHD ve normal kanaldaki gerçek görüntü/ses ve motor
seçimi yeni kayıt üzerinden ayrıca doğrulanmalıdır.

## Bağlantı

Tek iPhone/iPad'i veri taşıyan USB kablosuyla bağla. Cihazın kilidini aç ve
gerekirse **Bu bilgisayara güven** sorusunu cihaz üzerinde kendin yanıtla.
Apple Devices cihazı görmeli. Octopus'u açıp hatayı yeniden oluştur.

PowerShell'de repo dizininden:

```powershell
& '.artifacts\ios-device-tools-312\Scripts\python.exe' Scripts/capture-ios-logs.py check
& '.artifacts\ios-device-tools-312\Scripts\python.exe' Scripts/capture-ios-logs.py capture --seconds 120
& '.artifacts\ios-device-tools-312\Scripts\python.exe' Scripts/capture-ios-logs.py crashes
```

`check` cihaz kimliğini yazdırmaz. Tek cihaz olduğunda `ready: true` verir;
bu henüz log servisinin veya oynatmanın geçtiği anlamına gelmez. Birden
fazla cihaz varsa otomatik seçim yapılmaz; hedefin `--udid` ile açıkça
seçilmesi gerekir. Kimliği rapora veya git'e ekleme.

`capture` yalnızca Octopus işlemini filtreler ve süre sonunda durur. Süre
1–600 saniye olabilir. Kayıt bulunmazsa veya akış istenen süreden önce
kapanırsa başarısız sonuç döner; boş/kısmi log başarılı yakalama sayılmaz.
`crashes` yalnızca Octopus adına uyan raporları
kopyalar; cihazdaki kayıtları silmez. Jetsam raporları bu filtreye dahil
değildir.

Çıktılar git dışında kalan `.artifacts/device-logs/<UTC-zaman>/` altına
yazılır. Yakalama başlangıcında ve sonunda tam çıktı yolu gösterilir.
Aktarım veya başka kişiye mesaj gönderme işlemi yoktur.

## Gizlilik ve sınırlar

Canlı log çıktısında yalnızca zaman, seviye, subsystem, kategori ve mesaj
tutulur. Diğer işlemler, süreç kimlikleri ve image UUID alanları atılır.
HTTP/RTSP/RTMP URL'leri, seçili cihaz kimliği ve bilinen kullanıcı adı,
parola, token, PIN gibi anahtarların değerleri maskelenir. Bu metin
maskelemesi serbest biçimli her hassas verinin kaldırıldığını garanti
etmez; crash metninde cihaz/app bilgileri veya içerik adları kalabilir.
Ham cihaz kayıtları yerel inceleme içindir. Dışarı paylaşmadan önce
çıktıyı kontrol et; uygulama içindeki izinli alanlardan oluşan destek
raporu daha dar kapsamlıdır.

Windows araçları Xcode Instruments'ın yerini tutmaz. Erişilebilir DVT
servisleriyle CPU/bellek örnekleri alınabildiği bu cihazda doğrulandı;
tam Instruments arayüzü, ayrıntılı GPU/enerji analizi ve iOS derlemesi
için macOS/Xcode gerekir. iOS sürümüne göre geliştirme
servisleri ek eşleştirme veya tunnel isteyebilir; bu araç Developer Mode
veya güvenlik onaylarını otomatik açmaz. Kurulum ve servis kapsamının
birincil kaynağı: [pymobiledevice3](https://github.com/doronz88/pymobiledevice3).

## Ortamı yeniden kurmak

Çalışan ortam yereldir ve git'e dahil edilmez. Windows'ta `lzfse` hazır
wheel desteği nedeniyle Python **3.12** kullanıldı; sistemdeki 3.13 ile
kurulum C++ derleyicisi istedi. Ortamı tekrar kurmak için bir Python 3.12
yorumlayıcısı ile aşağıdaki komutları çalıştır:

```powershell
& '<Python-3.12-python.exe>' -m venv .artifacts/ios-device-tools-312
& '.artifacts\ios-device-tools-312\Scripts\python.exe' -m pip install -r Scripts/device-tools-requirements.txt
python -m unittest discover -s Scripts -p test_capture_ios_logs.py
```

Güven/eşleştirme hatası olduğunda cihazı Apple Devices'ta kontrol et.
Bu araç başka uygulamaların loglarını toplayacak şekilde genişletilmemeli;
Octopus hatasının saatini ve denenen adımları çıktı klasörüyle birlikte
kaydetmek tanı için yeterlidir.
