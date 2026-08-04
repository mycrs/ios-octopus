# 🪟 Mac Olmadan Geliştirme

Bu proje Windows'ta yazılıp bulut Mac'te derleniyor. Kurulum ve günlük akış burada.

---

## Neden işe yarıyor?

Demir kural #1 — `OctopusDomain` yalnızca `Foundation` import eder — sadece
mimari temizliği için değil, **pratik bir kazanç** için de var:
UIKit/SwiftUI olmayan kod Windows'ta derlenir ve test edilir.

| Katman | Windows'ta | Neden |
|---|---|---|
| `OctopusDomain` | ✅ derlenir + test edilir | Yalnızca Foundation |
| `OctopusCore` | ❌ | `os.Logger`, `Security` (Apple API) |
| `OctopusData` | ⚠️ kısmen (Faz 2'de parser'lar test edilebilir) | GRDB iOS'a bağlı değil ama Core'a bağlı |
| `OctopusPlayback` | ❌ | UIKit |
| `OctopusDesignSystem`, Features, App | ❌ | SwiftUI |

Faz 1-2'nin ağırlığı (veritabanı mantığı, Xtream/M3U parser'ları, iş kuralları)
Domain ve saf yardımcı tiplerde. Bunları burada anında doğrulayabilirsin.

---

## 1) Swift toolchain kurulumu (tek seferlik)

Swift Windows'ta C++ derleyicisine ihtiyaç duyar. Sırayla:

```powershell
# Visual Studio Build Tools + C++ iş yükü (yaklaşık 3-5 GB)
winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
  --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.22621"

# Swift toolchain (yaklaşık 1 GB)
winget install --id Swift.Toolchain -e
```

Kurulum sonrası **yeni bir terminal aç** ve doğrula:

```powershell
swift --version
```

> ⚠️ Paket kimlikleri ve gereksinimler değişebilir.
> Sorun çıkarsa güncel resmi rehber: <https://www.swift.org/install/windows/>

---

## 2) Günlük akış

```powershell
# Domain testleri — saniyeler içinde, simülatör yok
.\Scripts\test-domain.ps1
```

veya doğrudan:

```powershell
swift test --package-path Packages\OctopusDomain
```

Mimari denetimi (Git Bash ile):

```bash
bash Scripts/check-architecture.sh
```

---

## 3) Gerçek iOS derlemesi — GitHub Actions

Yerelde iOS derlemesi mümkün değil. Onu bulut Mac yapıyor:

1. Değişiklikleri commit'le ve `git push`
2. GitHub → **Actions** sekmesi
3. `iOS derleme` işi macOS runner'da `xcodegen generate` + `xcodebuild` çalıştırır
4. Kırmızıysa günlüğü aç — hata satırı doğrudan görünür

Yapılandırma: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

**Kota:** Genel (public) depolarda macOS runner ücretsizdir. Özel (private)
depoda aylık dakika kotası vardır ve macOS dakikaları 10x katsayıyla sayılır.
Güncel kotayı GitHub → Settings → Billing altından kontrol et.

---

## 4) Ne zaman gerçek Mac gerekir?

| Faz | Mac gerekir mi? |
|---|---|
| 1 — Kalıcılık (GRDB) | Hayır — CI yeter |
| 2 — Xtream/M3U parser | Hayır — CI yeter |
| 3 — Onboarding UI | Tercihen — ekranı görmek işi hızlandırır |
| 4 — Kanal listeleri | Tercihen |
| **5 — Oynatıcı** | **Evet** — video oynatma simülatörde bile elle test ister |
| 9 — PiP / AirPlay | **Evet** — gerçek cihaz gerekir |
| 10 — App Store yayını | **Evet** — arşivleme ve yükleme macOS ister |

Faz 5'e kadar CI yeterli. O noktada saatlik bulut Mac (Scaleway, MacinCloud vb.)
veya ikinci el bir Mac mini devreye alınabilir.

---

## 5) Yayın için ayrıca gerekenler

- **Apple Developer Program** üyeliği — yıllık ücretli, App Store'a yükleme için zorunlu
- İmzalama sertifikaları ve provisioning profilleri (CI'dan da yönetilebilir)
- ATS gerekçesi: IPTV yayınları HTTP üzerinden geldiği için inceleme sırasında
  açıklama istenir — bkz. [`App/Info.plist`](../App/Info.plist) içindeki not
