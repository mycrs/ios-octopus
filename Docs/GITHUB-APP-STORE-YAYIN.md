# GitHub'dan App Store yayını

Mac gerekmeden imzalı IPA üretip TestFlight'a yüklemek için GitHub
deposunda **Settings → Environments → app-store** ortamını oluştur ve aşağıdaki
üç environment secret'ı ekle:

| Secret | Değer |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect'te oluşturduğun API anahtarının Key ID'si |
| `APP_STORE_CONNECT_ISSUER_ID` | Users and Access → Integrations → Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | İndirilen `AuthKey_….p8` dosyasının tamamı |

API anahtarının rolü **App Manager** veya **Admin** olmalı. Apple Developer
hesabında `com.octopus.iptv` uygulama kimliği ve App Store Connect'te aynı
bundle ID ile uygulama kaydı mevcut olmalı. `V5ZC6396XD` takımına erişim de
zorunlu.

Sonra GitHub'da **Actions → App Store Release → Run workflow** seç.
`distribution: testflight` mevcut mağaza paketini hazırlar. Akış:

1. Xcode projesini üretir.
2. Apple'ın otomatik imzalamasıyla Release arşivi ve IPA üretir.
3. IPA'yı TestFlight'a yükler.

Bu aşama uygulamayı doğrudan herkese yayınlamaz. Apple'ın işlemeyi bitirmesini
bekledikten sonra App Store Connect'te build'i seç, zorunlu mağaza alanlarını
doldur ve incelemeye gönder. İnceleme notunda çalışan ve telif izni olan demo
hesabını mutlaka ver; ayrıntılı metin taslakları `APP-STORE-METIN-TASLAKLARI.md`
dosyasındadır.

## USB cihaz testi

`distribution: device` aynı Release kodunu kayıtlı test cihazına uygun
`release-testing` profili ile dışa aktarır. Önce aynı dalın gerçek iOS
derlemesi ve paket testleri başarılı olmalıdır. Bu hedef TestFlight'a
yükleme veya App Review gönderimi yapmaz.

`app-store` environment'ında iki ek secret kullanılır:
`OCTOPUS_TEST_DEVICE_UDID` (yalnızca hedef USB cihazı) ve
`OCTOPUS_TEST_PACKAGE_PUBLIC_KEY` (yerel alıcının Base64 Curve25519 açık
anahtarı). Cihaz Apple hesabında bulunmuyorsa bir test cihazı olarak
kaydedilir; Apple henüz etkinleştirmemişse iş durur. Devre dışı cihazın
durumu otomatik değiştirilmez.

Profil, bundle ID, takım ve build kontrolünden sonra IPA libsodium
sealed box ile şifrelenir. `Octopus-device-encrypted` artifact'ı bir gün
tutulur. İçindeki manifest yalnızca commit/build/hash ve paket türünü
taşır. Cihaz kimliği, profil içeriği veya açık IPA artifact'a konmaz.
Şifre çözme özel anahtarı yerelde git dışındaki `.artifacts` içinde kalır.
Kurulum sırasında aynı bundle ID güncellenir; uygulamayı silerek kurulmaz.
