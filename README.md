# 🐙 Octopus — iOS IPTV

Xtream Codes ve M3U kaynaklarını destekleyen, modüler mimarili iOS IPTV istemcisi.

📖 **Mimariyi anlamak için önce [`Docs/BRAIN.md`](Docs/BRAIN.md) oku.**

---

## 🪟 Mac'in yoksa

Bu proje Windows'ta geliştirilip bulut Mac'te derleniyor.
Kurulum ve günlük akış: **[`Docs/WINDOWS-SETUP.md`](Docs/WINDOWS-SETUP.md)**

```powershell
# Domain testleri — Windows'ta, saniyeler içinde, Mac gerekmez
.\Scripts\test-domain.ps1
```

```bash
# Mimari denetimi (Git Bash)
bash Scripts/check-architecture.sh
```

Gerçek iOS derlemesi her `git push`'ta GitHub Actions'ta macOS runner'da çalışır →
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Mac'te ilk kurulum

```bash
# 1) XcodeGen kur (tek seferlik)
brew install xcodegen

# 2) Xcode projesini üret
xcodegen generate

# 3) Aç
open Octopus.xcodeproj
```

`Octopus.xcodeproj` **git'e girmez** — proje tanımı tek yerde: [`project.yml`](project.yml).
`project.yml` değiştiğinde `xcodegen generate` komutunu tekrar çalıştır.

## Testler

Mantık testleri simülatör gerektirmez, saniyeler içinde koşar:

```bash
swift test --package-path Packages/OctopusDomain
swift test --package-path Packages/OctopusPlayback
```

Tam test (simülatörle):

```bash
xcodebuild test -scheme Octopus -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Durum

| | |
|---|---|
| Hedef | iOS 16.0+, iPhone + iPad |
| UI | SwiftUI (`NavigationStack`, `ObservableObject`) |
| Kaynak | Xtream Codes + M3U/M3U8 |
| Oynatma | AVPlayer (+ VLCKit yedek, Faz 5) |
| Faz | **0 — iskelet tamam, uygulama açılıyor** |

Faz listesi ve her fazın "bitti" tanımı: [`Docs/ROADMAP.md`](Docs/ROADMAP.md)

---

## Modüller

| Modül | Sorumluluk |
|---|---|
| `OctopusDomain` | Entity + protokol + iş kuralları. **Sıfır bağımlılık.** |
| `OctopusData` | Xtream/M3U provider, parser, kalıcılık, repository impl |
| `OctopusPlayback` | Motor protokolü + AVPlayer + motor seçici |
| `OctopusPlaybackVLC` | VLCKit motoru (izole — opsiyonel) |
| `OctopusNavigation` | Route + Router |
| `OctopusDesignSystem` | Tema + ortak bileşenler |
| `OctopusCore` | Log, Keychain, altyapı |
| `OctopusFeatures` | 8 ayrı ekran modülü |
| `App` | Composition root (ince) |

## Katkı kuralları

Kod yazmadan önce [`CLAUDE.md`](CLAUDE.md) içindeki demir kurallara bak. Özeti:

1. `OctopusDomain` yalnızca `Foundation` import eder.
2. Feature modülleri `OctopusData`'yı import **edemez**.
3. Feature → Feature import **yok**.
4. Somut tipler yalnızca `AppContainer` içinde birleşir.
5. `OctopusApp.swift` 40 satırı geçmez.
