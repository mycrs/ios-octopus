# 🖥️ Mac'e Geçiş — İlk Oturum Notları

Bu dosya Windows'tan Mac'e geçişte tek seferlik bir devir-teslim notudur.
Kalıcı mimari bilgi burada **değil**, [`Docs/BRAIN.md`](BRAIN.md)'de —
onu okumak hâlâ ilk adım. Bu dosya sadece "Mac'te ilk 10 dakika ne
yapılır" ve "şu an tam olarak nerede kaldık" sorularına cevap verir.

Claude Code'a Mac'te yeni bir oturum açtığında ilk mesaj olarak şunu
yapıştırman yeterli:

> Bu depo Windows'ta CLAUDE.md ve Docs/BRAIN.md ile geliştirildi, ilk
> defa Mac'te derleniyor. Önce Docs/BRAIN.md ve Docs/MAC-DEVIR.md'yi
> oku, sonra projeyi derle ve durumu bana özetle.

---

## 1. İlk kurulum (tek seferlik)

```bash
# Xcode Command Line Tools zaten kuruluysa atla
xcode-select --install

brew install xcodegen

git clone https://github.com/mycrs/ios-octopus.git
cd ios-octopus
xcodegen generate
open Octopus.xcodeproj
```

`.xcodeproj` bilerek git'e girmiyor — `project.yml` tek kaynak
(bkz. CLAUDE.md). Repo her çekildiğinde/değiştiğinde `xcodegen generate`
tekrar çalıştırılmalı.

**Xcode sürümü:** `project.yml` içinde `xcodeVersion: "15.0"` yazıyor,
elindeki Xcode daha yeniyse (16/26 vb.) sorun değil — XcodeGen bunu
sadece proje dosyasına metadata olarak yazıyor, build'i etkilemiyor.

**İlk build:** Sekmeler + demo veriyle gezinmeyi doğrulamak için
simülatörde şu launch argümanıyla çalıştırabilirsin (Xcode → Scheme
Edit → Arguments Passed On Launch):

```
-seedDemoData
```

Bu, `DemoCatalogSeeder`'ı (`#if DEBUG`) tetikler ve gerçek bir IPTV
kaynağı olmadan tüm ekranları (ana sayfa, canlı TV, filmler, diziler,
favoriler, "kaldığın kanal" kartı) sahte veriyle doldurur.

---

## 2. Şu an tam olarak nerede kaldık

Faz 0–4, 6–8 ve 10'un büyük kısmı **tamamlandı** (bkz. BRAIN.md §11
Yol Haritası). Tek gerçek açık iş **Faz 5: Oynatıcı motoru** —
şimdiye kadar Windows'ta derlenemediği, gerçek cihaz/Mac gerektirdiği
için bekletildi. Şu an bekleyen kesin bu:

- `OctopusPlayback/Engine/PlaybackEngineResolver.swift` yerinde ama
  `NullPlaybackEngine` ile derleniyor — gerçek oynatma yapmıyor.
- `OctopusPlaybackVLC/Package.swift` içinde VLCKit bağımlılığı
  **yorum satırı** olarak duruyor:
  ```swift
  // .package(url: "https://github.com/videolan/VLCKit", from: "4.0.0")
  ```
  Mac'te güncel sürümü doğrulayıp yorumdan çıkarman gerekiyor.
- `PlayerPreflightViewModel` şu an sadece akış adresini çözüp
  gösteren bir "ön kontrol" ekranı — gerçek `AVPlayer`/VLCKit'e
  henüz bağlı değil.
- Faz 9 (PiP, AirPlay, arka plan sesi, Now Playing) Faz 5'e bağımlı,
  o da bekliyor.

Faz 5'i tamamlarken **CLAUDE.md'nin demir kurallarına** özellikle
dikkat: 3rd-party bağımlılık (VLCKit) sadece `OctopusPlaybackVLC`
içinde kalmalı, somut motor seçimi sadece `AppContainer`'da yapılmalı.

---

## 3. Doğrulama — artık iki yolun var

Şimdiye kadar **tek** doğrulama yolu GitHub Actions CI'dı (mimari
denetim + testler + simülatör ekran görüntüleri, macOS runner
üzerinde). Bu hâlâ geçerli ve hâlâ değerli — Mac'te de aynı CI
push sonrası çalışıyor, karşılaştırma için kullanılabilir:

```bash
bash Scripts/check-architecture.sh   # her değişiklikten sonra, yerelde de çalışır
```

Ama artık Mac'te **doğrudan** simülatör/gerçek cihazda çalıştırıp
gözle de doğrulayabilirsin — CI ekran görüntüsü beklemene gerek yok.
Faz 5 gibi cihaz gerektiren işler için asıl fark burada.

**iPhone var** (gerçek cihaz testi mümkün) — ama henüz aktif bir
Apple Developer hesabı/imzalama durumu teyit edilmedi. TestFlight'a
yüklemeden önce bunu netleştirmek gerekecek.

---

## 4. Bilinen tuzaklar — tekrar keşfetme

`Docs/BRAIN.md` §11.1 "Sahada Öğrenilen Tuzaklar" tablosu bu projede
gerçekten yaşanmış, derlemenin yakalamadığı hatalar. Faz 5'e
başlamadan önce en azından şu ikisine göz at, doğrudan ilgili:

- **`.sensoryFeedback` kullanma** — iOS 17+, bizde derlenmez. Haptik
  için `UISelectionFeedbackGenerator` vb. kullan (DesignSystem/Haptics
  zaten bunu yapıyor, örnek al).
- **XcodeGen `info:` bölümünü kullanma** — `Info.plist` sessizce
  eziliyor. `App/Info.plist` zaten `INFOPLIST_FILE` ile doğru
  bağlanmış durumda, elleme.

---

## 5. Bu dosyanın ömrü

Faz 5 bittiğinde bu dosyayı silebilirsin (ya da "tamamlandı" diye
işaretleyip arşivleyebilirsin) — kalıcı bilgi zaten BRAIN.md'ye
taşınmış olacak. Bu sadece geçiş anının fotoğrafı.
