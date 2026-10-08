# Octopus — Apple incelemesine hazırlık araştırması

Araştırma tarihi: **8 Ekim 2026**. Apple'ın resmî belgeleri ve bu depodaki
kaynak kod incelendi. App Store Connect'e bu araştırma sırasında yazı,
metadata, build veya yeniden inceleme gönderilmedi. Aşağıdaki başlangıç
bulguları, sonraki kod değişikliklerinden önceki durumu anlatır; gönderilen
Release sürümü için kontrol tablosu ayrıca doldurulmalıdır.

Sonraki hazırlık kararı: kullanıcı yalnızca M3U sağladı, Xtream inceleme
hesabı yok. Hedef build 9'a karşılama ve Ayarlar'dan tüm kullanıcılara
sunulan isteğe bağlı örnek kitaplığı ekleniyor. İki açık lisanslı kısa film,
açıkça örnek diye etiketlenen kanal/rehber ve film seçkisiyle bölüm akışı
uygulama kontrollerini incelemeyi kolaylaştırır. Bu, gerçek Xtream servisi,
operatör EPG'si veya UHD uyumluluğu testinin yerine geçmez. Son build'in
uygulama/oynatma testi tamamlandı iddiası bu araştırmadan çıkarılmaz.

Son durum güncellemesi: build 9 CI, derleme hataları düzeltildikten sonra
`dd3eae2` kaynağıyla yeniden başlatıldı; build 9 upload ve App Review
submission henüz doğrulanmadı. Canlı App Store Connect'te İngilizce
**Your playlists, organized** alt başlığı ve aşağıdaki yaş anketi kaydedildi.
Araştırma ajanı hesapta değişiklik yapmadı; kaydedilen işlemleri ana
ajanın gözlemi ve yaş sonucu görüntüsü üzerinden belgeler.

## Ret hakkında bildiğimiz

`APP-STORE-INCELEME-2026-10-08.md` kayıtlarına göre son mesaj 7 Ekim'de
**1.0 (7)** için, **iPad Air 11-inch (M3)** üzerinde **4.3(a)** gerekçesiyle
geldi. Apple binary, metadata ve/veya kavram benzerliğinden söz etti;
karşılaştırma uygulaması veya belirli dosya vermedi. UHD arızasının bu
ret nedeni olduğu, ortak VLCKit kullanımının tek başına ret ürettiği veya
başlıktaki IPTV kelimesinin yasak olduğu kanıtlanmadı.

8 Ekim'deki build 8 macOS CI'da derlendi, paket testleri geçti ve USB
sorgusu telefonda **1.0.0 (8)** olduğunu doğruladı. Kanal oynatma olayı
içermeyen açılış kaydı, UHD sorununun düzeldiği anlamına gelmez. Apple'ın
build 8'i incelediği de söylenemez.

Güncel 4.3(a), aynı uygulamanın birden çok bundle ID ile dağıtılmasını;
4.3(b), yaygın uygulamalardan ayırt edilemeyen deneyimleri ele alır.
Metadata gerçek davranışı göstermeli; saklı işlev olmamalı. Gizlilik
politikası hem mağazada hem uygulamada erişilebilir olmalı. Kullanılan
üçüncü taraf içerik ve servislerin hakları doğrulanmalı. [App Review
Guidelines — 4.3, 2.3, 5.1.1, 5.2](https://developer.apple.com/app-store/review/guidelines/)

4.3 yanıtını yalnızca «yeniden yazdık», «hızlandırdık» veya «yeni ikon
yaptık» etrafında kurmak yetersizdir. Octopus IPTV oynatıcısı olarak kalır;
inceleyicinin uygulamadaki somut kullanım değerini kolayca deneyebilmesi
sağlanır. Özgün arayüz ve gerçek özellikler açıklanır; rakip isimleriyle
benzetme yapılmaz. [Apple — copycat rejections](https://developer.apple.com/help/app-review/guideline-reference/4-1-prevent-copycat-rejection)

## Başlangıçta bulunan somut eksikler

| Alan | Kod / belge bulgusu | Düzeltmenin kabul ölçütü |
|---|---|---|
| Uygulama içi gizlilik | `SettingsSections.swift` içinde politika bağlantısı yok; Uygulama bölümünde sürüm ve içerik dipnotu var. | Ayarlar'da sürekli görünen bir gizlilik bağlantısı; ilk kurulumda da erişim; URL'nin açılması ve güncel iOS davranışını anlatması. |
| Destek | `SettingsScreen` destek bölümünü yalnızca panelden `contact.hasAny` gelirse gösteriyor. | Panel kapalıyken veya yeni kaynak eklenmemişken de Octopus destek adresine ulaşılabilmesi. Bayi iletişimi uygulama desteğinden ayrı anlaşılmalı. |
| Reviewer kaynak yolu | `AddPlaylistViewModel.availableSourceKinds` panel `isXtreamLoginEnabled == false` olduğunda M3U/Xtream'i gizliyor; `AppContainer` bu bayrağı gerçek açılışta uyguluyor. | Review Notes'ta tarif edilen kaynak türlerinin gönderilen Release'te her normal kullanıcı için erişilebilir olması; açılışta panel gecikmesi/hatasının kurulum akışını bozmadığının testi. |
| Kimlik ve marka | Global/reseller config uygulama adı, renk ve servis kapısını etkiliyor. `OnboardingBrandLogo` ise sabit Octopus logosu çiziyor. | Mağazadaki kimlik ile çalışan uygulamanın tutarlı olması. Kaynak sağlayıcı adının uygulama adı gibi görünmemesi. Değişiklik reviewer'a özel gizli davranış olmamalı. |
| Demo kapsamı | Eski inceleme M3U'su 11 MP4 kaydını canlı listede gösteriyor; `M3UProvider` film/dizi katalogları döndürmüyor, bu liste EPG sağlamıyor. | Canlı/film/dizi/bölüm/rehber akışları için kullanım izni olan, inceleme süresince çalışan test kaynağı; her akışın gerçek Release'te denenmesi. Sadece bu M3U'nun kapsadığı işlevler tamamlandı diye yazılmalı. |
| Eski metadata | `APP-STORE-METIN-TASLAKLARI.md` «VLC or IPTV Smarters» karşılaştırması, «ready in seconds/uninterrupted», «demo yeterli», doğrulanmamış «telif riski yok» ifadeleri içeriyor. | Rakip karşılaştırmalarının ve ölçülmeyen garantilerin kaldırılması; hangi özelliklerin sağlayıcıya veya oynatma motoruna bağlı olduğunun doğru anlatılması. |
| Gizlilik beyanı | Manifest yorumunda «IPTV parolası cihazda kalır» yazıyor; Xtream doğrulama/oynatma için kullanıcı seçtiği sunucuya hesap bilgileri gönderiliyor. | «Cihazda Keychain'de saklanır, kullanıcının seçtiği sağlayıcıya gerekli istekte gönderilir» ayrımı; Octopus sunucularına giden ayrı isteklerin açık envanteri. |
| Test kanıtı | Build 8 açılıyor ve VLC yedeği bağlı; yeni UHD görüntüsü kullanıcı tarafından henüz doğrulanmadı. | Aynı hatalı UHD kanalda görüntü+ses, kullanılan motor, hızlı kanal geçişi ve normal kanal sonucu. CI sonucu cihaz görüntüsünün yerine geçmez. |

Bu tablo eksiklikleri gösterir; her satırın 4.3 ret gerekçesi olduğu
iddia edilmez. Eski `YAYIN-KONTROL.md` ve mağaza metinleri yeni sonuçlarla
güncellenmeden yeniden kullanılmamalı.

## İnceleyicinin görebileceği kullanım değeri

Mevcut üründe gösterilebilir üç bağlantılı iş var:

1. Kullanıcı kaynaklarını kendi yönetir: Xtream, uzak M3U ve yerel M3U
   ekleme; kaynak değiştirme; isteğe bağlı kaynak PIN'i.
2. İzleme düzenini korur: favoriler, geçmiş, kaldığı yer ve kategori
   koruması birlikte çalışır. Arama, ana sayfa ve oynatıcı gezinmesinde
   korumalı içerik görünmemelidir.
3. Kaynak sorununu anlaşılır kılar: Ayarlar'da yerel katalog sayıları,
   tekrar eden yayın anahtarları, eksik rehber/logo alanları ve güvenli
   destek raporu. Kontrol yayınları topluca açmaz; rapor URL, parola,
   içerik adı, PIN veya cihaz kimliği taşımaz.

Bunlar «App Store'da ilk» veya «hiçbir rakipte yok» şeklinde sunulmaz.
İnceleyiciye aynı Release'te bu işlerin nasıl birlikte kullanıldığı
gösterilir. Özellik eklemek tek başına Apple'ın özgünlük değerlendirmesini
garanti etmez.

Önerilen kanıt seti: kaynak ekleme sonrası canlı liste, oynatma, favori
ve kaldığı yer, ebeveyn kontrolleri, kaynak kontrolü. Her kare gerçek
uygulamada çekilir; büyük metin veya splash ekranı uygulamayı gizlemez.
Her cihazın ekran görüntülerinin yarıdan fazlası kullanılan uygulamayı
göstermelidir. iPad destekleniyorsa iPad ekranları da yeni sürümden
alınmalıdır. [Apple — screenshots](https://developer.apple.com/help/app-review/guideline-reference/2-3-3-screenshots)

## Demo ve Review Notes dosyası

Apple tam inceleme için işlevleri, iş modelini, kullanılan servisleri,
test edilen cihaz/iOS sürümlerini ve çalışan hesap bilgilerini ister.
Kaynak hesabı inceleme başlamadan bitmemeli veya değişmemelidir.
Üçüncü taraf korunan içerik için hak belgesi istenebilir. [Apple — complete
review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)

Gönderim paketinde şu bilgiler açık olmalı:

- Yeni build numarası ve ilk kurulumdan başlayarak kaynak ekleme adımları.
- M3U adresi ve yalnızca test ettiği işlevler. Yerel M3U dosyası kullanılacaksa
  dosyayı indirip iOS dosya seçicisinden içe alma adımları.
- Film/bölüm/rehber arayüzleri için açık lisanslı örnek kitaplığı; örnek
  rehber ve bağımsız film seçkisi gerçek yayıncı/dizi diye sunulmaz.
  Gerçek Xtream test hesabı yoksa varmış gibi yazılmaz. İleride hesap
  sağlanırsa host/kullanıcı/parola özel Review Information'a girilir;
  GitHub veya genel ekran görüntülerine yazılmaz.
- Örnek izleme sırası: örnek kanal → film → örnek bölüm seçkisi → rehber →
  favori → uygulamaya geri dönüp kaldığı yer → kategori koruması.
- Ebeveyn kontrolü: Ayarlar → Ebeveyn Kontrolleri; PIN değiştirme, kategori
  yönetimi ve tekrar kilitleme adımları. İlk kurulum PIN'i ancak gönderilen
  sürümde gerçekten aynıysa yazılır.
- Kaynak kontrolü ve raporun yolu; yerel katalog kontrolü olduğu ve canlı
  bağlantı testi olmadığı açıklaması.
- PiP/AirPlay yalnızca gerçekten destekleyen motor ve formatlarda
  anlatılır. UHD için otomatik VLC tercihi teknik uyumluluk çözümüdür;
  bütün UHD kaynaklarında başarı garantisi verilmez.
- Kullanıcı kaynaklarının HTTP gereksinimi için ATS açıklaması; Octopus'un
  kendi servisleri için HTTPS kullanımı ve hesap bilgilerinin doğru alıcısı.
- Test içeriğinin hak durumu ve atıfları. Herhangi bir açık lisansın
  gereklerini karşılamadan «telif sorunu yok» denmez.

Yeni özellikler sadece reviewer'a açılmaz; normal kullanıcıya sunulan
aynı akış gösterilir. Gizli reviewer tespiti veya ret denetimini aşmak
için yeni bundle ID oluşturma önerilmez.

## Örnek içerik lisansı ve erişim kontrolü

BBB ve Sintel'in resmî proje siteleri filmleri ve proje materyallerini
CC BY 3.0 kapsamında yayımlar. Bütün film gösterilirken kapanış jeneriği
kesilmemelidir; uygulamada atıf göstermek jeneriğin yerine geçmez.
Logolar/trademark'lar ve ayrıca belirtilmiş kapsam dışı materyaller
kullanılmaz. [BBB lisans](https://peach.blender.org/about/),
[Sintel lisans](https://durian.blender.org/sharing/).

8 Ekim 2026'da yalnızca HTTP HEAD, HTML ve Archive metadata JSON'u
incelendi; medya indirilmedi. Aşağıdaki dosyaların görüntü/ses/codec veya
jenerikleri bu yöntemle doğrulanmış sayılmaz. Kaynaklar CC lisanslı
Archive aynalarıdır; resmî Blender stream sunucusu diye sunulmaz.

| Aday | HTTP ve dosya metadata'sı |
|---|---|
| [BBB MP4](https://archive.org/download/BigBuckBunny_328/BigBuckBunny_512kb.mp4) | 200, video/mp4, 43.315.070 bayt, byte ranges; Archive JSON 596,41 sn, BigBuckBunny.avi türevi, CC BY 3.0 US. |
| [Sintel hafif MP4](https://archive.org/download/Sintel/sintel-2048-stereo_512kb.mp4) | 200, video/mp4, 77.410.288 bayt, ranges; JSON 888,06 sn, tam MP4'ün türevi, CC BY 3.0. |
| [Sintel orijinal MP4](https://archive.org/download/Sintel/sintel-2048-stereo.mp4) | 200, video/mp4, 282.690.045 bayt, ranges; JSON creator Blender Foundation, original, 888,06 sn. |
| [Resmî Sintel MKV](https://download.blender.org/durian/movies/Sintel.2010.1080p.mkv) | 200, application/octet-stream, 1.180.090.590 bayt, ranges; MP4 değil, native-player uyumluluğu varsayılmaz. |
| [Resmî Sintel fragmanı](https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4) | 200, video/mp4, 4.372.373 bayt, ranges. Fragmandır; seçilirse başlık/Notes fragman demeli, tam film dememeli. |

Archive bilgi kaynakları: [BBB metadata](https://archive.org/metadata/BigBuckBunny_328),
[Sintel metadata](https://archive.org/metadata/Sintel). Süreler tam-film
süresiyle tutarlıdır; son jenerik final uygulamada ayrıca izlenir.
`storage.googleapis.com` ve `commondatastorage.googleapis.com` gtv örnek
BBB/Sintel URL'leri 403 verdi; erişilebilirliği doğrulanmış kabul edilmedi.
Blender'ın BBB dizinlerindeki güncel MP4 indirmeleri ZIP; eski doğrudan
MP4 adresleri 404. `demo/android/` dizini yalnız APK/ZIP içeriyor.

Resmî proje sayfasından gelen görsel adayları da HEAD 200:
[BBB film karesi](https://peach.blender.org/wp-content/uploads/bird1.jpg)
ve [Sintel film karesi](https://durian.blender.org/wp-content/uploads/2010/06/02.b_comp_000296.jpg).
Bunların site/proje CC lisans kapsamı ve Blender Foundation/site atfı
gözetilir; logo/trademark kullanımına izin varsayılmaz. HEAD incelemesi
görselin tamamını görerek kontrol etmenin yerine geçmez.

## Gizlilik ve arşiv doğrulaması

Apple'ın gizlilik etiketi, cihaz dışına gönderilen verinin isteği servis
etmekten daha uzun süre okunabilir biçimde tutulmasını esas alır.
Salt cihaz içi işlenen bilgi toplanan veri sayılmaz. Yalnızca işlev
sunmak için tutulan sunucu verisi de uygun tür ve amaçla açıklanır;
«reklam yok» bunun yerine geçmez. [Apple — App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

Koddan görülen veri yolları: kullanıcının sağlayıcısı için Xtream/M3U,
EPG ve görseller; Octopus panelinin app config/reseller/aktivasyon/DNS
servisleri; kullanıcı başlatırsa iOS paylaşım ekranıyla destek JSON'u.
Yerel geçmiş/favori/ilerleme ve parolanın cihazda saklanması ayrı
anlatılır. Panel/CDN erişim loglarının saklama süresi koddan bilinemez.
Bu nedenle sunucu davranışı doğrulanmadan App Privacy için «No Data
Collected» sonucuna otomatik olarak varılmamalıdır.

Build 8 IPA'sında görülen manifestler:

| Konum | İçerik |
|---|---|
| `Payload/Octopus.app/PrivacyInfo.xcprivacy` | Tracking false; toplanan veri listesi boş; UserDefaults `CA92.1`. |
| `GRDB_GRDB.bundle/PrivacyInfo.xcprivacy` | Tracking false; veri ve API listeleri boş. |

Bu ZIP içinde Nuke veya MobileVLCKit için ayrı manifest bulunmadı.
Build logunda Nuke **12.9.0**, GRDB **7.11.1**, vlckit-spm **3.6.0**
görülüyor. Apple'ın SDK listesinde doğrudan bu üç isim yok; alt bileşenler
ve yeniden paketlenen SDK'lar ayrıca incelenmelidir. Listelenmiş SDK'lar
ve onları yeniden paketleyen SDK'lar için manifest, binary bağımlılıklarda
imza gereksinimleri vardır. [Apple — Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)

Son Release arşivinde bütün manifestleri ve gerekli neden API kullanımını
yeniden kontrol et; yalnızca app kökünde dosya bulunduğu için tamam
sayma. Third-party lisanslarını/atıflarını da kullanılan gerçek binary
sürümüne göre paketle. Buradaki tarama App Store upload validation veya
sunucu gizlilik denetimi değildir.

## Yaş derecelendirmesi

Apple, ebeveyn kontrollerini içerik/özellik erişimini sınırlayan araçlar;
age assurance'ı ise yaşın gerekliliği karşıladığını doğrulayan ayrı
mekanizmalar olarak tanımlar. Derecelendirme, anket cevaplarına ve bölgeye
göre üretilir. [Apple — Age rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)

Mevcut PIN/kategori gizleme gerçek parental controls olabilir; yaş
doğrulaması yoksa Age Assurance var diye beyan edilmez. Reviewer için
ebeveyn kontrolü yolu görünür kalmalıdır. Özel kaynak dosyası içe alma,
tek başına sosyal paylaşım veya halka yayılan kullanıcı içeriği anlamına
gelmez. Anket tüm gerçek özelliklere göre doldurulur; «daha düşük yaş
çıksın» veya «IPTV olduğundan otomatik yüksek yaş» şeklinde değiştirilmez.

Başlangıçta canlı ASC'de 4+ ve içerik sıklıklarının None olduğu gözlendi.
8 Ekim'de anket **Parental Controls Present**, **Age Assurance No**,
**Horror/Fear Infrequent**, **Cartoon/Fantasy Violence Frequent** ve
**Guns/Weapons Infrequent** olarak kaydedildi; diğer cevaplar değişmedi.
Apple **172 ülke/bölgede 13+**, Vietnam/Kore **12+**, Brezilya **A12**,
iOS 26 öncesi genel **12+** (bölgesel istisnalarla) hesapladı.
[Kaydedilmiş sonuç](../.artifacts/review-proof/age-rating-updated.jpg)
araştırmada görüntü olarak kontrol edildi. Bu kayıt bütün filmlerin
izlendiğini göstermez; HTTP başlıkları da içerik sıklığı kanıtı değildir.
Sırf IPTV diye 13+/18+ override gerektiği sonucu çıkarılmaz.

ASC'de Standard Apple License Agreement seçili. Uygulama içindeki
Terms bağlantısı ASC'nin kullandığı [Apple standart EULA](https://www.apple.com/legal/itunes/appstore/dev/stdeula)
olabilir. Web sitesi sözleşmesinin 10 Temmuz 2026 platform listesinde
iOS ve yeni örnek kitaplığı yok; site sözleşmesi bu çalışmada değiştirilmedi.
Özel EULA tanımlanmadığında standart lisansın uygulanması Apple'ın
açıkladığı mevcut yoldur. [Apple license setup](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/)

## 4.3 mesajına yaklaşım ve gönderim sırası

İlk yanıt kısa ve somut olmalı: mevcut 4.3(a) kaygısının hangi gözlenen
benzerlikle ilgili olduğunu açıklamasını iste; uygulama işlevlerini ve
denenebilecek yolları anlat. Başka geliştiricinin özel inceleme durumu
istenmez. Daha fazla yardım gerekirse iletişim bilgileri güncel tutularak
Türkiye saat dilimi ve tercih edilen dil ile telefon görüşmesi talep
edilebilir. [Apple — contact App Review](https://developer.apple.com/help/app-review/after-submitting-for-review/contact-app-review)

Yeni build'de sorunları düzelttiğimiz durumda normal yeniden gönderim
yolunu izleriz. Karara katılmıyorsak önce açıklama yanıtı, çözülmezse
ilgili kurallara ve doğrulanabilir kanıta dayanan tek appeal gönderilir.
Apple, düzeltilip yeniden gönderilmiş başvuru için ayrıca appeal
başlatılmamasını belirtir. [Apple — appeal](https://developer.apple.com/help/app-review/after-submitting-for-review/appeal-to-the-app-review-board/)

Uygulanacak sıra:

1. Android/cihaz özelleştirmelerini iOS'un gerçek akışlarına eşleştir;
   oyuncu, kaynak, ebeveyn kontrolü ve gizlilik değişikliklerini tamamla.
2. Son kod için Release arşivi, paket testleri, cihaz testi ve iPhone/iPad
   ekran görüntülerini aynı build numarasıyla doğrula.
3. Demo kapsamını ve kullanım haklarını doğrula; privacy/support URL'lerini
   aç; metadata ve Review Notes'u son sürüm davranışına göre güncelle.
4. App Store dağıtımı için imzalı build'i yükle ve işlemden geçtiğini kontrol
   et. USB `release-testing` paketi yükleme için kullanılmaz.
5. Doğru build'i sürüme seç; metadata, screenshots, privacy, yaş, export
   compliance ve review bilgilerini kontrol et; **Add for Review** sonrası
   gerçek **Submit for Review** adımını tamamla. Yalnızca TestFlight'a
   yükleme yapmak App Review başvurusu değildir. [Apple — submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
6. Kullanıcının talebi onay almak olduğu için mağaza release seçimini
   **Manually release this version** olarak tutmak uygundur. Onay sonrası
   `Pending Developer Release` görünmesi incelemenin tamamlandığını,
   mağazaya yayınlamanın ayrı adım olduğunu gösterir. [Apple — release options](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)

Gönderim sonunda kaydedilecek kanıt: son kod commit'i, sürüm/build,
CI linki, cihaz test sonuçları, kullanılan demo kapsamı, metadata son
metni ve App Store Connect'in `Waiting for Review` durumunu gösteren
gönderim kaydı. Apple'ın kabul kararı henüz yoksa «onaylandı» denmez.

## Son gönderim için doldurulacak durum

| Kontrol | Başlangıç durumu |
|---|---|
| Güncel Release kurulu cihaz | Build 8 kurulu; sonraki değişiklikler ayrı build gerektirir. |
| UHD görüntü ve ses | Yeni build için doğrulanmadı. |
| iPad gerçek akış ve yeni görüntüler | Bu araştırmada doğrulanmadı. |
| Sürekli erişilir privacy/support | Başlangıç kodunda eksik; düzeltme gerekiyor. |
| Reviewer kaynak kapsamı | Xtream hesabı yok. M3U canlı listesini kapsıyor; build 9 normal kullanıcıya açık örnek kitaplığı/rehber/bölüm arayüzü test kanıtı bekleniyor. |
| Kaydedilen metadata / yaş | İngilizce alt başlık ve yaş anketi kaydedildi; hesaplanan 13+/bölgesel sonuçlar yukarıda. Diğer taslak alanlar son canlı kontrol bekler. |
| Review Notes ve 4.3 mesajı | Son build doğrulaması sonrası için taslak hazır; gönderilmedi. |
| Sunucu veri saklama ve privacy beyanı | Kaynak koddan teyit edilemiyor. |
| Yeni App Store dağıtım build'i ve inceleme gönderimi | Build 9 `dd3eae2` CI tekrar denemesi başlatıldı; upload/submission henüz doğrulanmadı. |
