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

## 0. ⚠️ Önce güncelle — yoksa eski sürüme bakarsın

Bu gerçekten yaşandı: depo bir kez klonlandı, sonra Windows tarafında
**Faz 5'in tamamı** (gerçek oynatıcı) push edildi. Mac'teki kopya eski
kaldığı için oynatıcı hâlâ yer tutucu ekran gösteriyordu ve "bozuk"
görünüyordu — oysa kod çoktan yazılmıştı.

Her oturuma bununla başla:

```bash
cd ios-octopus
git pull
xcodegen generate      # ← atlanırsa yeni dosyalar projeye girmez
open Octopus.xcodeproj
```

`xcodegen generate` **her `git pull` sonrası** gerekli: `.xcodeproj` git'e
girmiyor (tek kaynak `project.yml`), yeni eklenen dosyalar aksi hâlde
derlemeye dahil olmaz ve "neden değişmedi?" diye kovalarsın.

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

**Oynatıcı çalışıyor.** Sen Xcode'u indirirken Faz 5'in AVPlayer tarafı
yazıldı ve CI'da doğrulandı: `09-oynatici.png` karesi Apple'ın test
akışını 16. saniyesinde oynarken gösteriyor.

> Not: "Faz 5 gerçek cihaz bekliyor" varsayımı yanlıştı. AVFoundation
> bir sistem çerçevesi; CI'daki macOS runner derliyor, test ediyor,
> simülatörde çalıştırıp kare alıyor. Bu yüzden Mac'e geçmeyi
> beklemeden bitirildi.

Bugün çalışan: gerçek oynatma, denetimler (oynat/duraklat, ±10 sn,
sürüklenebilir ilerleme çubuğu), ses/altyazı seçimi, kaldığı yerden
devam, izleme geçmişi, arka planda ses, kilit ekranı denetimleri.

### Mac'te yapılacak tek büyük iş: VLCKit

MPEG-TS / MKV / RTSP yayınlar AVPlayer'ın açamadığı formatlar ve IPTV'de
çok yaygın. Yedek motor yolu **yazılı ve test edilmiş** durumda; eksik
olan yalnızca binary'nin kendisi (~60 MB, SPM entegrasyonu kırılgan —
bu yüzden Mac'e bırakıldı).

Adımlar:
1. `Packages/OctopusPlaybackVLC/Package.swift` içindeki yorumlu satırı aç:
   ```swift
   .package(url: "https://github.com/videolan/VLCKit", from: "4.0.0")
   ```
   Sürümü Mac'te doğrula — 4.x hâlâ ön sürüm olabilir, 3.x daha kararlı.
2. `VLCEngineFactory.makeEngine()` içine gerçek `VLCPlaybackEngine`'i yaz
   (`PlaybackEngine` protokolüne uy, `AVPlayerEngine`'i örnek al).
3. `VLCEngineFactory.isAvailable` → `true`.

**Başka hiçbir dosyaya dokunma.** Resolver zinciri, çalışma zamanı
yedeğe düşme ve "kaldığı yerden sürdür" mantığı zaten yazılı ve
`PlayerControllerTests` içinde test edilmiş durumda. VLCKit ileride
sorun çıkarırsa tek yapılacak şey `isAvailable`'ı kapatmak — uygulama
AVPlayer'la çalışmaya devam eder.

⚠️ Demir kural: VLCKit **yalnızca** `OctopusPlaybackVLC` içinde geçebilir.

### Kalan küçük işler

- **PiP** (`AVPictureInPictureController`) — simülatörde çalışmıyor,
  gerçek cihazda doğrulanmalı. `supportsPictureInPicture` şu an bilerek
  `false`.
- **Çoklu profil** (Faz 10) — başlanmadı.
- **Localizable.strings** — kullanıcı metinleri hâlâ kodun içinde.

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

**Oynatıcıyı simülatörde hızlı açmak** (kanal listesinde gezinmeden):

Xcode → şema adına tıkla → **Edit Scheme… → Run → Arguments**. Orada iki
kutu **hazır duruyor**, sadece işaretle:

```
☑ -seedDemoData     sahte katalog yazar
☑ -demoPlayer       açılışta doğrudan oynatıcıyı açar
```

Demo kaynağın ilk kanalı Apple'ın açık HLS örneğine bakar, yani oynatıcı
gerçekten video çizer. İkisi de `#if DEBUG` altında; yayın derlemesinde yok.

> ⚠️ Kutular görünmüyorsa `xcodegen generate`'i tekrar çalıştır — proje
> dosyası eski demektir.
>
> ⚠️ Argümanları **elle** yazma: bu listede boşluk içeren bir satır
> (`-startup.player live:...`) Xcode tarafından tek argüman sayılıyor ve
> sessizce hiçbir şey olmuyor. İlk kurulumda takılınan yer tam olarak burasıydı.

---

## 4. Bilinen tuzaklar — tekrar keşfetme

`Docs/BRAIN.md` §11.1 "Sahada Öğrenilen Tuzaklar" tablosu bu projede
gerçekten yaşanmış, derlemenin yakalamadığı hatalar. VLC işine
başlamadan önce şunlara göz at — hepsi doğrudan ilgili:

- **`.sensoryFeedback` kullanma** — iOS 17+, bizde derlenmez. Haptik
  için `UISelectionFeedbackGenerator` vb. kullan (DesignSystem/Haptics
  zaten bunu yapıyor, örnek al).
- **XcodeGen `info:` bölümünü kullanma** — `Info.plist` sessizce
  eziliyor. `App/Info.plist` zaten `INFOPLIST_FILE` ile doğru
  bağlanmış durumda, elleme.
- **Motor değişince video yüzeyini yenile** — VLC devreye girdiğinde
  ilk karşılaşacağın tuzak bu: ses gelir, ekran siyah kalır. Çözüm
  yazılı (`.id(engineIdentifier)`), bozmamaya dikkat et.
- **`@MainActor` izole bir tipin örneği varsayılan parametre değeri
  olamaz** — VLC motorunu yazarken üç kez karşılaşırsın. Parametreyi
  `Optional` yap, varsayılanı gövdede üret.

---

## 5. Bu dosyanın ömrü

VLCKit bağlandığında bu dosyayı silebilirsin — kalıcı bilgi zaten
BRAIN.md'ye taşınmış durumda. Bu sadece geçiş anının fotoğrafı.
