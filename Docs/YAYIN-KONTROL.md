# Octopus — iOS yayın ve yeniden inceleme kontrolü

**8 Ekim 2026.** Ağustos başvurusuna ait eski tamamlandı işaretlerini
kaldırır. Hedef 4.3(a) reddinden sonra gerçek kullanım değerini ve tam
inceleme erişimini gösteren, test edilmiş Release'i App Review'a göndermek.
IPTV oynatıcı amacı korunur; Apple'ın kabul sonucu henüz bilinmez.

## Bildiğimiz durum

| Kanıt | Durum |
|---|---|
| Apple mesajı | 7 Ekim 2026, 1.0 (7), iPad Air 11-inch (M3), 4.3(a); uzatılmış inceleme bildirimi de var. |
| Önceki sorunlar | 2.3.6 ebeveyn kontrolü için yeni adımlar iletilmiş; 5.6'nın giderildiği 3 Eylül'de belirtilmiş. Yeni ret bunlara otomatik bağlanmaz. |
| USB build | 1.0.0 (8), binary kaynak commit'i `88fc529`; sonraki commit'ler bu binary'de varsayılmaz. |
| Mac CI | [37776653115](https://github.com/mycrs/ios-octopus/actions/runs/37776653115) başarılı; Playback 57, Data 264, Features 194 XCTest ve Domain/DesignSystem/iOS işleri geçti. |
| Cihaz | Build 8 kurulu ve açılıyor; VLC yedeği bağlı. Açılış kaydı oynatma olayı içermedi; yeni UHD görüntüsü doğrulanmadı. |
| Demo / hedef build 9 | Xtream inceleme hesabı yok; kullanıcı yalnız M3U sağladı. Eski M3U canlı liste import/oynatma içindir. Normal kullanıcıya açık isteğe bağlı örnek kitaplığı film, örnek bölüm ve örnek rehber akışlarını kapsayacak; build 9 uygulama/cihaz testleri henüz kanıtlanmadı. |
| Build 9 CI | Derleme hataları düzeltildikten sonra `dd3eae2` kaynağıyla tekrar başlatıldı; başarı/dağıtım upload/submission bu kayıtla doğrulanmış sayılmaz. |
| Kaydedilen metadata | İngilizce alt başlık `Your playlists, organized` kaydedildi. Diğer taslak alanlar canlı son kontrolde doğrulanır. |
| Kaydedilen yaş | Parental Controls Present; Age Assurance No; Horror/Fear Infrequent; Cartoon/Fantasy Violence Frequent; Guns/Weapons Infrequent; diğer cevaplar değişmedi. Apple 172 ülke/bölge için 13+, Vietnam/Kore 12+, Brezilya A12, iOS 26 öncesi genel 12+ hesapladı. [Kanıt](../.artifacts/review-proof/age-rating-updated.jpg). |
| Lisans | ASC'de Standard Apple License Agreement seçili; bağlantı `https://www.apple.com/legal/itunes/appstore/dev/stdeula`. |
| Yeni App Review | Bu belgeden gönderilmiş sonucu çıkarılmaz; son canlı durum ayrıca kaydedilir. |

## Son Release kontrolü

Kutular yalnızca aynı son Release için kanıt bulunduğunda işaretlenir.
Hata varsa saat, beklenen/gerçek sonuç ve güvenli log klasörü kaydedilir.

| Alan | Kabul ölçütü | Durum |
|---|---|---|
| Kaynak ekleme | Xtream/uzak M3U/yerel M3U normal kullanıcıya açık; panel kesintisi tarif edilen yolu gizlemiyor. | [ ] |
| Kaynak yönetimi | Değiştirme, silme/yenileme ve kaynak PIN'i doğru kaynağa uygulanıyor; eski iş yeniyi ezmiyor. | [ ] |
| Katalog/istekler | Büyük listede arama/kategori; film/dizi detayları yeniden açılırken gereksiz eşzamanlı istek yok. | [ ] |
| M3U yenileme | Tek taze indirme; geçersiz kılınan iş eski önbelleği geri yazmıyor. | [ ] |
| Normal oynatma | İzinli kaynakta görüntü+ses, ilk kare ve kullanılan motor kaydı var. | [ ] |
| UHD | Eski hatalı kanal aynı cihazda görüntü+ses ve motor loguyla doğrulandı; bilinmeyen codec/container için kesin teşhis yazılmıyor. | [ ] |
| Geçişler | Hızlı kanal seçimi, çıkıp yeni oynatmaya dönme; eski görüntü/hata/stop yeniyi etkilemiyor. | [ ] |
| Oynatıcı seçenekleri | Ses/altyazı, mini/tam ekran, arka plan/ön plan; PiP/AirPlay destekleyen motor/formatlarda denendi. | [ ] |
| İzleme düzeni | Favori/geçmiş/film-bölüm ilerlemesi doğru içerik ve kaynağa ait. | [ ] |
| Koruma | Kaynak PIN'i ve ebeveyn PIN/kategorileri; arama/favori/ana sayfa/oynatıcı korumayı aşmıyor. | [ ] |
| Kaynak raporu | Yerel sayılar doğru; URL/parola/içerik adı/PIN/cihaz kimliği yok; kullanıcı kendi paylaşıyor. | [ ] |
| Gizlilik/destek | Onboarding/Ayarlar linkleri açılıyor; panel bilgisi olmadan uygulama desteğine erişim var. | [ ] |
| iPad | Kaynak/liste/detay/oynatıcı/Ayarlar/PIN/büyük yazı düzeni doğrulandı. | [ ] |
| Stabilite | Tekrarlanan crash/hang/çizim uyarısı yok; gerçek test süresi/kapsamı kayıtlı. | [ ] |
| Reviewer erişimi | Çalışan ve yeterli kapsamda test kaynağı inceleme boyunca geçerli; ilk kurulumdan tam adımlar var. | [ ] |
| Örnek kitaplığı | Karşılama ve Ayarlar'da tüm kullanıcılara isteğe bağlı; oynatma/favori/ilerleme/örnek bölüm/örnek rehber/kategori koruması aynı Release'te doğrulandı. Gerçek Xtream hesabı veya operatör EPG'si diye sunulmuyor. | [ ] |
| Hak/atıf | Dosya/görsel/screenshots izinleri doğrulandı; açık lisansın jenerik/atıf şartları uygulandı. | [ ] |
| Yaş / lisans | Yukarıdaki anket ve Apple sonuçları kaydedildi; bu bütün filmlerin izlendiği kanıtı değildir. Final içerik ve uygulama lisansı seçili Standard Apple EULA ile son kontrolde eşleşiyor. | [ ] |
| Metadata | Gerçek Release'e uygun; rakip benzetmesi, ölçülmemiş hız/uyumluluk garantisi veya unsupported özellik yok. | [ ] |

Motorun `playing` olayı görüntü kanıtı değildir. Bu tablo bütün sağlayıcıların
uyumluluğu veya kapsamlı enerji/sızıntı analizi tamamlandı şeklinde sunulmaz.

## 4.3 hazırlığı

Aynı Octopus app/bundle kaydı kullanılır. Küçük ad/ikon değişiklikleri veya
yeni bundle ID bir ret aşma yöntemi olarak sunulmaz. Kaynak yönetimi,
izleme düzeni, PIN/kategori koruması ve yerel kaynak kontrolünün birlikte
kullanımı gerçek ekranlarla gösterilir; ilk/tek uygulama iddiası yapılmaz.
Reviewer'a saklı ayrı özellik açılmaz. Apple'ın binary/metadata/concept
mesajı belirli bir SDK veya dosyanın ret nedeni olduğunu kanıtlamaz.

[Araştırma ve hazırlık](APPLE-INCELEME-HAZIRLIK-2026-10-08.md),
[yeni metinler ve reviewer bilgisi](APP-STORE-METIN-TASLAKLARI.md).

## Gizlilik, ATS ve API

- App kökündeki manifest ile üçüncü taraf manifestleri son arşivde gerçekten
  bulunmalı; gerekli neden API kullanımına göre beyanlar kontrol edilmeli.
- Mevcut **Data Not Collected** durumu transient işlemden uzun sunucu/SDK
  saklama kanıtı olmadan tahminle değiştirilmez. Manifest ve «reklam yok»
  bütün veri yollarının yerine geçmez.
- Parola Keychain'de saklanır; gerekli Xtream isteklerinde kullanıcının
  seçtiği sağlayıcıya gönderilir. Optional aktivasyon/web hızlı kurulumun
  Octopus servisinde işlemesi ayrı anlatılır.
- User-supplied HTTP hostları için ATS gerekçesi Review Notes'ta bulunur.
  Yalnızca `NSAllowsArbitraryLoadsForMedia` eklemek URLSession HTTP katalog
  desteğini korumaz; iOS 10+ alt anahtarların genel istisnayla etkileşimi
  vardır. [Apple ATS](https://developer.apple.com/documentation/security/preventing-insecure-network-connections)
- Belgelenmiş `AVURLAssetHTTPUserAgentKey` iOS 16.0'dan itibaren kullanılabilir.
  [Apple User-Agent option](https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey)
- Nuke/GRDB/VLCKit binary alt bileşenleri ve lisanslar gerçek arşive göre
  kontrol edilir. Ortak motor kullanımı tek başına 4.3 kanıtı değildir.
  [Apple SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
- `ITSAppUsesNonExemptEncryption=false` mevcut muaf sistem şifrelemesiyle
  karşılaştırılır; yeni şifreleme eklendiyse eski beyan otomatik taşınmaz.

## Build ve yükleme

Gerçek iOS derlemesi/XCTest GitHub macOS runner'da çalışır; Windows'ta
Xcode yok. Yerel mimari denetimi:

```bash
bash Scripts/check-architecture.sh
```

XcodeGen tanımı `project.yml`; sürüm/build son arşivde kontrol edilir.
`device` workflow hedefi USB test için cihaz profilli şifreli paket üretir.
`testflight` hedefi App Store Connect dağıtım arşiv/export/upload yoludur.
Son kodu içermeyen eski IPA yeni gönderim için kullanılmaz.

[İmzalı GitHub yayın yolu](GITHUB-APP-STORE-YAYIN.md),
[Windows USB log yöntemi](IOS-CIHAZ-LOG.md).

## App Store Connect gönderimi

1. Son build'in CI ve Release arşivini doğrula; dağıtım için yükle ve
   App Store Connect işlemesinin tamamlandığını gör.
2. Sürüme doğru build'i seç. Privacy/support URL, yaş, export compliance,
   içerik hakları, screenshots ve bütün lokalizasyonları denetle.
3. Çalışan reviewer kaynağı/hesabı özel Review Information alanına koy.
   Test edilen gerçek cihaz/iOS sürümleri ve yeni işlevlerin yolu Notes'ta.
   Xtream hesabı yoksa varmış gibi yazma. Her normal kullanıcıya açık
   örnek kitaplığını, M3U'nun ve örneğin ayrı kapsadığı akışları açıkla.
   Örnek kanal/rehber gerçek televizyon yayıncısı; bağımsız kısa filmler
   ticari dizi bölümü diye tarif edilmez.
4. Metadata'yı son işlevlere göre kaydet. Örnek içerik varsa açıkça örnek
   diye anlat; eski M3U'nun film/dizi/EPG sunduğu söylenmez.
5. Kullanıcının talebi inceleme/onay olduğundan **Manually release this
   version** seçeneğiyle inceleme sonrası yayın ayrı tutulabilir.
6. **Add for Review** ardından gerçek **Submit for Review** adımını tamamla.
   Yalnızca upload/TestFlight App Review başvurusu değildir.
   [Apple submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
7. Son commit, sürüm/build, CI, cihaz sonuçları, nihai Notes ve canlı
   `Waiting for Review` kanıtını kaydet. Henüz kabul yoksa onaylandı denmez.

Kararın yanlış olduğunu düşünüyorsak önce açıklama yanıtı, çözülmezse tek
ve ilgili kanıta dayalı appeal izlenir. Düzeltilip yeniden gönderilmiş
başvuru için ayrıca appeal açılması Apple'ın önerdiği yol değildir.
[Apple appeal](https://developer.apple.com/help/app-review/after-submitting-for-review/appeal-to-the-app-review-board/)
