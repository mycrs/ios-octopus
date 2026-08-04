# Domain testlerini Windows'ta koşar — simülatör ve Mac gerektirmez.
#
#   .\Scripts\test-domain.ps1
#
# Domain yalnızca Foundation'a bağlı olduğu için (Docs/BRAIN.md § 4, kural 1)
# bu testler Windows'ta saniyeler içinde çalışır.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$swift = Get-Command swift -ErrorAction SilentlyContinue
if (-not $swift) {
    Write-Host "Swift toolchain bulunamadi." -ForegroundColor Red
    Write-Host "Kurulum icin: Docs\WINDOWS-SETUP.md" -ForegroundColor Yellow
    exit 1
}

Write-Host "Swift: $((swift --version) -split "`n" | Select-Object -First 1)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Domain testleri kosuluyor..." -ForegroundColor Cyan

swift test --package-path (Join-Path $root "Packages\OctopusDomain")

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Domain testleri gecti." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Domain testleri basarisiz." -ForegroundColor Red
}
exit $LASTEXITCODE
