# ==============================================
#  Reveal Password WiFi yang Sedang Terhubung
#  Skripkeren by Ted
#  Cara jalankan (PowerShell as Administrator):
#  irm https://skripkeren.silverhawk.web.id/wifi-pass.ps1 | iex
#  atau:
#  .\wifi-pass.ps1
# ==============================================

$ErrorActionPreference = "Stop"

function Write-Title {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     Reveal Password WiFi yang Sedang Terhubung     ║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

Write-Title

# Ambil SSID yang sedang terhubung
$interface = netsh wlan show interfaces 2>$null
if (-not $interface) {
    Write-Host "  ✖ Gagal membaca interface WiFi. Pastikan WiFi aktif." -ForegroundColor Red
    exit 1
}

$ssidLine = $interface | Select-String '^\s*SSID\s+:\s+(.+)$'
if (-not $ssidLine) {
    Write-Host "  ✖ Tidak ada WiFi yang sedang terhubung." -ForegroundColor Red
    exit 1
}

$SSID = $ssidLine.Matches.Groups[1].Value.Trim()

Write-Host "  SSID yang sedang terhubung : " -NoNewline
Write-Host $SSID -ForegroundColor Green
Write-Host ""

# Ambil detail profil termasuk Key Content
$profile = netsh wlan show profile name="$SSID" key=clear 2>$null
if (-not $profile) {
    Write-Host "  ✖ Gagal membaca profil WiFi. Coba jalankan sebagai Administrator." -ForegroundColor Red
    exit 1
}

$keyLine = $profile | Select-String 'Key Content\s+:\s+(.+)$'
if ($keyLine) {
    $password = $keyLine.Matches.Groups[1].Value.Trim()
    Write-Host "  Password                   : " -NoNewline
    Write-Host $password -ForegroundColor Yellow
} else {
    Write-Host "  ✖ Password tidak ditemukan (mungkin open network / tidak tersimpan)." -ForegroundColor Red
}

Write-Host ""
Write-Host "  ────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Tip: Jalankan PowerShell sebagai Administrator jika gagal." -ForegroundColor DarkGray
Write-Host ""
