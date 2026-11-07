# ==============================================
#  Reveal Password WiFi (Lengkap) — Windows
#  Skripkeren by Ted
#
#  Cara jalankan (PowerShell as Administrator):
#    irm https://skripkeren.silverhawk.web.id/wifi-pass.ps1 | iex
#
#  Dari CMD (as Administrator):
#    powershell -ExecutionPolicy Bypass -File wifi-pass.ps1
# ==============================================

$ErrorActionPreference = "Stop"

function Write-Title {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║          Reveal Password WiFi — Skripkeren         ║" -ForegroundColor Cyan
    Write-Host "  ║                    (Windows)                       ║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Get-CurrentSSID {
    $interface = netsh wlan show interfaces 2>$null
    if (-not $interface) { return $null }
    $ssidLine = $interface | Select-String '^\s*SSID\s+:\s+(.+)$'
    if ($ssidLine) {
        return $ssidLine.Matches.Groups[1].Value.Trim()
    }
    return $null
}

function Get-WifiPassword {
    param([string]$ProfileName)

    $profile = netsh wlan show profile name="$ProfileName" key=clear 2>$null
    if (-not $profile) { return $null }

    $keyLine = $profile | Select-String 'Key Content\s+:\s+(.+)$'
    if ($keyLine) {
        return $keyLine.Matches.Groups[1].Value.Trim()
    }
    return $null
}

function Get-AllWifiProfiles {
    $raw = netsh wlan show profiles 2>$null
    if (-not $raw) { return @() }

    $profiles = @()
    $raw | Select-String 'All User Profile\s+:\s+(.+)$' | ForEach-Object {
        $profiles += $_.Matches.Groups[1].Value.Trim()
    }
    return $profiles
}

# ---------- Main ----------
Write-Title

# Cek Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  ⚠  Disarankan jalankan sebagai Administrator agar semua password terbaca." -ForegroundColor Yellow
    Write-Host ""
}

# Tampilkan WiFi yang sedang terhubung
$currentSSID = Get-CurrentSSID
if ($currentSSID) {
    Write-Host "  ▶ WiFi yang sedang terhubung" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────────────────"
    Write-Host "  SSID     : " -NoNewline
    Write-Host $currentSSID -ForegroundColor Green

    $pass = Get-WifiPassword -ProfileName $currentSSID
    if ($pass) {
        Write-Host "  Password : " -NoNewline
        Write-Host $pass -ForegroundColor Yellow
    } else {
        Write-Host "  Password : " -NoNewline
        Write-Host "(tidak ditemukan / open network)" -ForegroundColor DarkGray
    }
    Write-Host ""
} else {
    Write-Host "  ℹ  Tidak ada WiFi yang sedang terhubung." -ForegroundColor DarkGray
    Write-Host ""
}

# Ambil semua profil
$allProfiles = Get-AllWifiProfiles
if ($allProfiles.Count -eq 0) {
    Write-Host "  ✖ Tidak ada profil WiFi tersimpan di komputer ini." -ForegroundColor Red
    Write-Host ""
    exit 0
}

Write-Host "  ▶ Daftar semua profil WiFi tersimpan ($($allProfiles.Count))" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────────────────────"

for ($i = 0; $i -lt $allProfiles.Count; $i++) {
    $num = $i + 1
    $name = $allProfiles[$i]
    $marker = if ($name -eq $currentSSID) { " ← sedang terhubung" } else { "" }
    Write-Host ("  {0,2}. {1}{2}" -f $num, $name, $marker)
}

Write-Host ""
Write-Host "  Ketik nomor profil untuk lihat password-nya" -ForegroundColor DarkGray
Write-Host "  atau tekan Enter untuk keluar." -ForegroundColor DarkGray
Write-Host ""

$choice = Read-Host "  Pilih nomor"

if ([string]::IsNullOrWhiteSpace($choice)) {
    Write-Host ""
    Write-Host "  Selesai." -ForegroundColor DarkGray
    exit 0
}

if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $allProfiles.Count) {
    Write-Host ""
    Write-Host "  ✖ Pilihan tidak valid." -ForegroundColor Red
    exit 1
}

$selected = $allProfiles[[int]$choice - 1]
Write-Host ""
Write-Host "  ────────────────────────────────────────────────────"
Write-Host "  SSID     : " -NoNewline
Write-Host $selected -ForegroundColor Green

$password = Get-WifiPassword -ProfileName $selected
if ($password) {
    Write-Host "  Password : " -NoNewline
    Write-Host $password -ForegroundColor Yellow
} else {
    Write-Host "  Password : " -NoNewline
    Write-Host "(tidak ditemukan / open network / butuh Admin)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  ────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
