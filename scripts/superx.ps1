#Requires -Version 5.1
<#
.SYNOPSIS
  SuperX — multi-app uninstaller (Windows PowerShell native)
  Skripkeren by Ted

.DESCRIPTION
  Tidak butuh Git Bash / WSL.
  - Deteksi versi Windows
  - List aplikasi Win32 + AppX
  - Tandai bawaan sistem
  - Pilih nomor: 1 3 5-8,12
  - Uninstall massal

.EXAMPLE
  irm https://skripkeren.silverhawk.web.id/scripts/superx.ps1 | iex
  # atau:
  curl.exe -fsSL https://skripkeren.silverhawk.web.id/scripts/superx.ps1 -o $env:TEMP\superx.ps1
  powershell -ExecutionPolicy Bypass -File $env:TEMP\superx.ps1
#>

$ErrorActionPreference = 'Continue'

function Write-Info($m) { Write-Host "➜ $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "✓ $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "! $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "✗ $m" -ForegroundColor Red }

function Ensure-AdminHint {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warn "Tidak berjalan sebagai Administrator. Beberapa uninstall AppX/system mungkin gagal."
    Write-Host "  Saran: klik kanan PowerShell → Run as administrator, lalu ulangi." -ForegroundColor DarkYellow
  }
}

function Get-WinVersionInfo {
  try {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $name = $cv.ProductName
    $disp = $cv.DisplayVersion
    if (-not $disp) { $disp = $cv.ReleaseId }
    $build = $cv.CurrentBuild
    return [PSCustomObject]@{ Name = $name; Display = $disp; Build = $build; Caption = "$name $disp (build $build)" }
  } catch {
    return [PSCustomObject]@{ Name = 'Windows'; Display = '?'; Build = '?'; Caption = 'Windows (unknown)' }
  }
}

# Pola nama yang dianggap bawaan / hati-hati
$Script:SystemPatterns = @(
  '^Microsoft (Edge|Windows|Visual C\+\+|.NET|OneDrive|Teams|Office|Update)',
  '^Windows ',
  '^NVIDIA',
  '^Intel ',
  '^AMD ',
  '^Realtek',
  '^Microsoft Corporation',
  'Microsoft\.Windows\.',
  'Microsoft\.Office\.',
  'Microsoft\.Xbox',
  'Microsoft\.Bing',
  'Microsoft\.XboxIdentityProvider',
  'windows\.immersivecontrolpanel',
  'Microsoft\.UI\.Xaml',
  'Microsoft\.VCLibs',
  'Microsoft\.NET\.',
  'Microsoft\.DesktopAppInstaller',
  'Microsoft\.StorePurchaseApp',
  'Microsoft\.WindowsStore',
  'Microsoft\.Windows\.ShellExperienceHost',
  'Microsoft\.AAD\.BrokerPlugin',
  'Microsoft\.AccountsControl',
  'Microsoft\.BioEnrollment',
  'Microsoft\.CredDialogHost',
  'Microsoft\.LockApp',
  'Microsoft\.Win32WebViewHost',
  'Microsoft\.MicrosoftEdge'
)

function Test-IsSystemApp([string]$name, [string]$publisher) {
  if ([string]::IsNullOrWhiteSpace($name)) { return $true }
  foreach ($pat in $Script:SystemPatterns) {
    if ($name -match $pat) { return $true }
  }
  if ($publisher -match 'Microsoft Corporation|Microsoft Windows') {
    # bukan semua Microsoft = sistem, tapi flag hati-hati
    if ($name -match 'Windows|Edge|Defender|Security|Update|\.NET|Visual C') { return $true }
  }
  return $false
}

function Get-InstalledApps {
  $list = New-Object System.Collections.Generic.List[object]

  $regPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($path in $regPaths) {
    Get-ItemProperty $path -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and $_.UninstallString } |
      ForEach-Object {
        $sys = Test-IsSystemApp $_.DisplayName $_.Publisher
        $list.Add([PSCustomObject]@{
          Kind        = 'WIN32'
          Name        = [string]$_.DisplayName
          Version     = [string]$_.DisplayVersion
          Publisher   = [string]$_.Publisher
          Id          = [string]$_.PSChildName
          Uninstall   = [string]$_.UninstallString
          Quiet       = [string]$_.QuietUninstallString
          IsSystem    = $sys
        }) | Out-Null
      }
  }

  try {
    Get-AppxPackage -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -and -not $_.IsFramework } |
      ForEach-Object {
        $sys = Test-IsSystemApp $_.Name $_.Publisher
        if (-not $sys) { $sys = [bool]$_.SignatureKind -eq 'System' -or $_.SignatureKind -eq 'System' }
        # SignatureKind: System / Store / Developer
        $sk = [string]$_.SignatureKind
        if ($sk -eq 'System') { $sys = $true }
        $list.Add([PSCustomObject]@{
          Kind        = 'APPX'
          Name        = [string]$_.Name
          Version     = [string]$_.Version
          Publisher   = [string]$_.Publisher
          Id          = [string]$_.PackageFullName
          Uninstall   = ''
          Quiet       = ''
          IsSystem    = $sys
        }) | Out-Null
      }
  } catch {
    Write-Warn "AppX listing terbatas: $($_.Exception.Message)"
  }

  # dedupe by Kind+Name+Id
  $seen = @{}
  $out = @()
  foreach ($a in ($list | Sort-Object Name)) {
    $k = "$($a.Kind)|$($a.Name)|$($a.Id)"
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = $true
    $out += $a
  }
  return $out
}

function Parse-Selection([string]$raw, [int]$max) {
  $set = New-Object 'System.Collections.Generic.HashSet[int]'
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  $parts = $raw -split '[,;\s]+' | Where-Object { $_ -ne '' }
  foreach ($p in $parts) {
    if ($p -match '^(\d+)-(\d+)$') {
      $a = [int]$Matches[1]; $b = [int]$Matches[2]
      if ($a -gt $b) { $t=$a;$a=$b;$b=$t }
      for ($i=$a; $i -le $b; $i++) { if ($i -ge 1 -and $i -le $max) { [void]$set.Add($i) } }
    } elseif ($p -match '^\d+$') {
      $n = [int]$p
      if ($n -ge 1 -and $n -le $max) { [void]$set.Add($n) }
    }
  }
  return ($set | Sort-Object)
}

function Uninstall-Win32App($app) {
  Write-Info "Uninstall WIN32: $($app.Name)"
  $cmd = $app.Quiet
  if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = $app.Uninstall }
  if ([string]::IsNullOrWhiteSpace($cmd)) {
    Write-Err "Tidak ada UninstallString"
    return $false
  }
  try {
    if ($cmd -match '^\s*"?MsiExec\.exe"?\s+/X\{?([0-9A-Fa-f-]+)\}?') {
      $guid = $Matches[1]
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/X{$guid}","/qn","/norestart" -Wait -PassThru
      return ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010)
    }
    # generic
    if ($cmd.StartsWith('"')) {
      $exe = ($cmd -split '"')[1]
      $rest = $cmd.Substring($cmd.IndexOf('"', 1) + 1).Trim()
      $p = Start-Process -FilePath $exe -ArgumentList $rest -Wait -PassThru -ErrorAction Stop
    } else {
      $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -Wait -PassThru -ErrorAction Stop
    }
    return $true
  } catch {
    Write-Err $_.Exception.Message
    return $false
  }
}

function Uninstall-AppxApp($app) {
  Write-Info "Uninstall APPX: $($app.Name)"
  try {
    Remove-AppxPackage -Package $app.Id -ErrorAction Stop
    Write-Ok "Dihapus (user): $($app.Name)"
    return $true
  } catch {
    try {
      Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageFullName -eq $app.Id } |
        Remove-AppxPackage -AllUsers -ErrorAction Stop
      Write-Ok "Dihapus (all users): $($app.Name)"
      return $true
    } catch {
      Write-Err $_.Exception.Message
      return $false
    }
  }
}

# ---- main ----
Clear-Host
Write-Host ""
Write-Host "  ╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         SuperX — Multi-App Uninstaller             ║" -ForegroundColor Cyan
Write-Host "  ║         Windows PowerShell native · Skripkeren     ║" -ForegroundColor Cyan
Write-Host "  ╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$ver = Get-WinVersionInfo
Write-Ok "OS: $($ver.Caption)"
Ensure-AdminHint
Write-Host ""

Write-Info "Memuat daftar aplikasi (Win32 + AppX)…"
$apps = @(Get-InstalledApps)
if ($apps.Count -eq 0) {
  Write-Err "Tidak ada aplikasi terdeteksi."
  return
}

Write-Host ""
Write-Host ("{0,4}  {1,-6}  {2,-8}  {3}" -f 'No', 'Jenis', 'Sistem?', 'Nama') -ForegroundColor DarkGray
Write-Host ("{0,4}  {1,-6}  {2,-8}  {3}" -f '----', '------', '--------', '----') -ForegroundColor DarkGray
for ($i = 0; $i -lt $apps.Count; $i++) {
  $a = $apps[$i]
  $flag = if ($a.IsSystem) { 'YA*' } else { 'tidak' }
  $color = if ($a.IsSystem) { 'DarkYellow' } else { 'White' }
  $nm = $a.Name
  if ($nm.Length -gt 70) { $nm = $nm.Substring(0,67) + '...' }
  Write-Host ("{0,4}  {1,-6}  {2,-8}  {3}" -f ($i+1), $a.Kind, $flag, $nm) -ForegroundColor $color
}

Write-Host ""
Write-Warn "YA* = kemungkinan bawaan/sistem — uninstall berisiko. Hindari kecuali yakin."
Write-Host "Format pilih: 1 3 5-8,12   atau  1,2,3   (Enter kosong = batal)" -ForegroundColor DarkGray
$sel = Read-Host "Nomor aplikasi yang di-uninstall"

$idxs = Parse-Selection $sel $apps.Count
if ($idxs.Count -eq 0) {
  Write-Warn "Dibatalkan / pilihan kosong."
  return
}

Write-Host ""
Write-Host "Akan di-uninstall:" -ForegroundColor Cyan
foreach ($n in $idxs) {
  $a = $apps[$n-1]
  $tag = if ($a.IsSystem) { ' [SISTEM]' } else { '' }
  Write-Host "  - [$n] $($a.Name)$tag"
}
$confirm = Read-Host "Lanjut uninstall $($idxs.Count) item? [y/N]"
if ($confirm -notmatch '^[Yy]') {
  Write-Warn "Dibatalkan."
  return
}

$ok = 0; $fail = 0
foreach ($n in $idxs) {
  $a = $apps[$n-1]
  if ($a.IsSystem) {
    $c2 = Read-Host "  '$($a.Name)' ditandai sistem. Tetap hapus? [y/N]"
    if ($c2 -notmatch '^[Yy]') { Write-Warn "Skip: $($a.Name)"; continue }
  }
  $r = $false
  if ($a.Kind -eq 'WIN32') { $r = Uninstall-Win32App $a }
  else { $r = Uninstall-AppxApp $a }
  if ($r) { $ok++ } else { $fail++ }
}

Write-Host ""
Write-Ok "Selesai. Berhasil: $ok  Gagal: $fail"
Write-Host "Developed for Skripkeren · SuperX" -ForegroundColor DarkGray
