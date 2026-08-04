# CLAUDE.md — Octopus IPTV

**Her oturumda önce [`Docs/BRAIN.md`](Docs/BRAIN.md) oku.** Orası mimarinin anayasasıdır.

## Ortam
- Geliştirme **Windows**'ta yapılıyor; Swift/Xcode yok → **burada derleme yapılamaz**.
- Derleme/çalıştırma Mac'te: `xcodegen generate && open Octopus.xcodeproj`
- `.xcodeproj` git'e **girmez**. Proje tanımı tek yerde: `project.yml`

## Hedef
- iOS **16.0+**, iPhone + iPad, SwiftUI

## Yazmadan önce kontrol et
- `@Observable`, `SwiftData`, `@Bindable` → **iOS 17+, kullanma.**
  Yerine `ObservableObject` + `@Published` + GRDB.
- `NavigationStack`, `.searchable`, async/await → iOS 16'da ✅

## Değişmez kurallar
1. `OctopusDomain` sadece `Foundation` import eder. Başka hiçbir şey.
2. Feature modülleri `OctopusData`'yı import **edemez** — sadece Domain protokollerini görür.
3. Feature → Feature import **yok**. Geçiş `OctopusNavigation.AppRoute` ile.
4. 3rd-party bağımlılık tek modülde hapsedilir (GRDB→Data, VLCKit→PlaybackVLC, Nuke→DesignSystem).
5. Somut tipler yalnızca `App/Sources/Composition/AppContainer.swift` içinde birleşir.
6. Singleton yok. Bağımlılık `init` ile enjekte edilir.
7. `try!` / `as!` / force unwrap yasak.

## Yeni kod nereye?
| Ne yazıyorsun | Nereye |
|---|---|
| Yeni veri tipi / iş kuralı | `OctopusDomain` |
| API çağrısı, parser, SQL | `OctopusData` |
| Ekran + ViewModel | `Packages/OctopusFeatures/Sources/FeatureXxx` |
| Tekrar eden UI parçası | `OctopusDesignSystem` |
| Oynatıcı motoru davranışı | `OctopusPlayback` |
| Bağlantı/kurulum | `AppContainer` |

## Modül eklerken
1. `Packages/<Ad>/Package.swift` oluştur
2. `project.yml` → `packages:` ve ilgili target'ın `dependencies:` bölümüne ekle
3. `Docs/BRAIN.md` modül grafiğini güncelle

## Her değişiklikten sonra
```bash
bash Scripts/check-architecture.sh
```
Demir kuralları otomatik denetler. Windows'ta Git Bash ile de çalışır.
Kırmızı görürsen devam etme — mimari bozulmuş demektir.

## Stil
- ViewModel: `@MainActor final class XxxViewModel: ObservableObject`
- Modüller arası görünürlük için `public` gerekir — unutma
- View 200 satırı geçerse böl
- Kullanıcı metni → `Localizable.strings`
