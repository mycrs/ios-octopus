#!/usr/bin/env bash
# Demir kural denetimi — Docs/BRAIN.md § 4
#
# Her faz sonunda ve CI'da çalıştır:
#   bash Scripts/check-architecture.sh
#
# Windows'ta Git Bash ile de çalışır.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mİHLAL\033[0m %s\n' "$1"; fail=1; }

# Yorum satırlarını ele — `grep -n` çıktısı "dosya:satır:içerik" biçimindedir.
# Dokümantasyonda somut tip adı ÖRNEK olarak geçebilir; bu ihlal değildir.
strip_comments() { grep -vE ':[0-9]+:[[:space:]]*(///?|\*|/\*)' || true; }

echo "🧠 Octopus mimari denetimi"
echo

# Import satırı öneki: `@preconcurrency import X` gibi attribute'lu biçimler
# de yakalanmalı — aksi halde kurallar sessizce atlatılabilir.
IMP='^(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+'

# 1 — Domain saf kalmalı
echo "1) Domain yalnızca Foundation import eder"
leaks=$(grep -rhE "$IMP" Packages/OctopusDomain/Sources 2>/dev/null \
        | grep -vE "${IMP}Foundation[[:space:]]*$" | sort -u)
if [ -z "$leaks" ]; then ok "temiz"; else bad "fazladan import:"; echo "$leaks" | sed 's/^/         /'; fi

# 2 — Feature, Data'yı göremez
echo "2) Feature modülleri OctopusData import etmez"
hits=$(grep -rnE "${IMP}OctopusData" Packages/OctopusFeatures/Sources 2>/dev/null)
if [ -z "$hits" ]; then ok "temiz"; else bad "Data sızıntısı:"; echo "$hits" | sed 's/^/         /'; fi

# 3 — Feature → Feature import yok
echo "3) Feature modülleri birbirini import etmez"
hits=$(grep -rnE "${IMP}Feature" Packages/OctopusFeatures/Sources 2>/dev/null)
if [ -z "$hits" ]; then ok "temiz"; else bad "çapraz import:"; echo "$hits" | sed 's/^/         /'; fi

# 4 — Data, SwiftUI bilmez
echo "4) Data katmanı SwiftUI/UIKit import etmez"
hits=$(grep -rnE "${IMP}(SwiftUI|UIKit)" Packages/OctopusData/Sources 2>/dev/null)
if [ -z "$hits" ]; then ok "temiz"; else bad "UI sızıntısı:"; echo "$hits" | sed 's/^/         /'; fi

# 5 — main ince kalmalı
echo "5) OctopusApp.swift ≤ 40 satır"
lines=$(wc -l < App/Sources/OctopusApp.swift | tr -d ' ')
if [ "$lines" -le 40 ]; then ok "$lines satır"; else bad "$lines satır — mantığı AppContainer'a taşı"; fi

# 6 — Somut tipler yalnızca composition root'ta
echo "6) Somut repository tipleri yalnızca AppContainer'da geçer"
hits=$(grep -rn -E '(InMemory|GRDB|Xtream|M3U|Scaffold)[A-Za-z]*(Repository|Provider|Resolver|Sync)' \
       Packages/OctopusFeatures/Sources 2>/dev/null | strip_comments)
if [ -z "$hits" ]; then ok "temiz"; else bad "feature içinde somut tip:"; echo "$hits" | sed 's/^/         /'; fi

# 7 — Zorlama (force) kullanımı
echo "7) try! / as! / force unwrap yok (test kodu hariç)"
hits=$(grep -rn -E '(try!|as!)' Packages/*/Sources App/Sources 2>/dev/null | strip_comments)
if [ -z "$hits" ]; then ok "temiz"; else bad "zorlama kullanımı:"; echo "$hits" | sed 's/^/         /'; fi

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32m✅ Mimari sağlam.\033[0m\n'
else
  printf '\033[31m❌ Mimari ihlali var — Docs/BRAIN.md § 4'"'"'e bak.\033[0m\n'
fi
exit "$fail"
