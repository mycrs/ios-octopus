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

Sonra GitHub'da **Actions → App Store Release → Run workflow** seç. Akış:

1. Xcode projesini üretir.
2. Apple'ın otomatik imzalamasıyla Release arşivi ve IPA üretir.
3. IPA'yı TestFlight'a yükler.

Bu aşama uygulamayı doğrudan herkese yayınlamaz. Apple'ın işlemeyi bitirmesini
bekledikten sonra App Store Connect'te build'i seç, zorunlu mağaza alanlarını
doldur ve incelemeye gönder. İnceleme notunda çalışan ve telif izni olan demo
hesabını mutlaka ver; ayrıntılı metin taslakları `APP-STORE-METIN-TASLAKLARI.md`
dosyasındadır.
