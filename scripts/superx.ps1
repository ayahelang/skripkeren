#Requires -Version 5.1
# SuperX - multi-app uninstaller (Windows PowerShell native)
# Skripkeren - ASCII-safe for Windows PowerShell 5.1
#
# Run:
#   irm https://skripkeren.silverhawk.web.id/scripts/superx.ps1 | iex
#   curl.exe -fsSL ... -o $env:TEMP\superx.ps1
#   powershell -ExecutionPolicy Bypass -File $env:TEMP\superx.ps1

$ErrorActionPreference = 'Continue'

function Write-Info([string]$m) { Write-Host ("-> " + $m) -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host ("OK " + $m) -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host ("!  " + $m) -ForegroundColor Yellow }
function Write-Err([string]$m)  { Write-Host ("X  " + $m) -ForegroundColor Red }

function Test-IsAdmin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Get-WinVersionInfo {
  try {
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $name = [string]$cv.ProductName
    $disp = [string]$cv.DisplayVersion
    if ([string]::IsNullOrWhiteSpace($disp)) { $disp = [string]$cv.ReleaseId }
    $build = [string]$cv.CurrentBuild
    $caption = "$name $disp (build $build)"
    return [PSCustomObject]@{ Caption = $caption }
  } catch {
    return [PSCustomObject]@{ Caption = 'Windows (unknown)' }
  }
}

function Test-IsSystemApp {
  param([string]$Name, [string]$Publisher, [string]$SignatureKind)
  if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
  if ($SignatureKind -eq 'System') { return $true }

  $patterns = @(
    '^Microsoft Edge',
    '^Microsoft Windows',
    '^Microsoft Visual C',
    '^Microsoft .NET',
    '^Microsoft OneDrive',
    '^Microsoft Teams',
    '^Microsoft Office',
    '^Microsoft Update',
    '^Windows ',
    '^NVIDIA',
    '^Intel ',
    '^AMD ',
    '^Realtek',
    'Microsoft\.Windows\.',
    'Microsoft\.Office\.',
    'Microsoft\.Xbox',
    'Microsoft\.Bing',
    'Microsoft\.UI\.Xaml',
    'Microsoft\.VCLibs',
    'Microsoft\.NET\.',
    'Microsoft\.DesktopAppInstaller',
    'Microsoft\.StorePurchaseApp',
    'Microsoft\.WindowsStore',
    'Microsoft\.AAD\.BrokerPlugin',
    'Microsoft\.AccountsControl',
    'Microsoft\.CredDialogHost',
    'Microsoft\.LockApp',
    'Microsoft\.Win32WebViewHost',
    'Microsoft\.MicrosoftEdge',
    'windows\.immersivecontrolpanel'
  )
  foreach ($pat in $patterns) {
    if ($Name -match $pat) { return $true }
  }
  if ($Publisher -match 'Microsoft Windows') { return $true }
  if ($Name -match 'Windows|Defender|Security|Update' -and $Publisher -match 'Microsoft') { return $true }
  return $false
}

function Get-InstalledApps {
  $bag = @()

  $regPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )

  foreach ($path in $regPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and $_.UninstallString } |
      ForEach-Object {
        $sys = Test-IsSystemApp -Name ([string]$_.DisplayName) -Publisher ([string]$_.Publisher) -SignatureKind ''
        $bag += [PSCustomObject]@{
          Kind      = 'WIN32'
          Name      = [string]$_.DisplayName
          Version   = [string]$_.DisplayVersion
          Publisher = [string]$_.Publisher
          Id        = [string]$_.PSChildName
          Uninstall = [string]$_.UninstallString
          Quiet     = [string]$_.QuietUninstallString
          IsSystem  = [bool]$sys
        }
      }
  }

  try {
    Get-AppxPackage -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -and (-not $_.IsFramework) } |
      ForEach-Object {
        $sk = [string]$_.SignatureKind
        $sys = Test-IsSystemApp -Name ([string]$_.Name) -Publisher ([string]$_.Publisher) -SignatureKind $sk
        $bag += [PSCustomObject]@{
          Kind      = 'APPX'
          Name      = [string]$_.Name
          Version   = [string]$_.Version
          Publisher = [string]$_.Publisher
          Id        = [string]$_.PackageFullName
          Uninstall = ''
          Quiet     = ''
          IsSystem  = [bool]$sys
        }
      }
  } catch {
    Write-Warn ("AppX listing terbatas: " + $_.Exception.Message)
  }

  $seen = @{}
  $out = @()
  foreach ($a in ($bag | Sort-Object Name)) {
    $k = $a.Kind + '|' + $a.Name + '|' + $a.Id
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = $true
    $out += $a
  }
  return $out
}

function Parse-Selection {
  param([string]$Raw, [int]$Max)
  $set = @{}
  if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }

  # split on comma, semicolon, whitespace
  $parts = $Raw -split '[,; ]+' | Where-Object { $_ -ne '' }
  foreach ($p in $parts) {
    if ($p -match '^([0-9]+)-([0-9]+)$') {
      $a = [int]$Matches[1]
      $b = [int]$Matches[2]
      if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
      for ($i = $a; $i -le $b; $i++) {
        if ($i -ge 1 -and $i -le $Max) { $set[$i] = $true }
      }
    }
    elseif ($p -match '^[0-9]+$') {
      $n = [int]$p
      if ($n -ge 1 -and $n -le $Max) { $set[$n] = $true }
    }
  }
  return @($set.Keys | Sort-Object)
}

function Uninstall-Win32App {
  param($App)
  Write-Info ("Uninstall WIN32: " + $App.Name)
  $cmd = $App.Quiet
  if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = $App.Uninstall }
  if ([string]::IsNullOrWhiteSpace($cmd)) {
    Write-Err 'Tidak ada UninstallString'
    return $false
  }

  try {
    # MSI: MsiExec.exe /X{GUID}
    if ($cmd -match 'MsiExec\.exe.*\{([0-9A-Fa-f\-]+)\}') {
      $guid = $Matches[1]
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/X{' + $guid + '}', '/qn', '/norestart') -Wait -PassThru
      if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { return $true }
      Write-Warn ("msiexec exit " + $p.ExitCode)
      return $false
    }

    if ($cmd.StartsWith('"')) {
      $parts = $cmd.Split('"')
      $exe = $parts[1]
      $rest = ''
      if ($parts.Count -gt 2) { $rest = ($parts[2..($parts.Count-1)] -join '"').Trim() }
      if ([string]::IsNullOrWhiteSpace($rest)) {
        $p = Start-Process -FilePath $exe -Wait -PassThru
      } else {
        $p = Start-Process -FilePath $exe -ArgumentList $rest -Wait -PassThru
      }
      return $true
    }

    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $cmd) -Wait -PassThru
    return $true
  } catch {
    Write-Err $_.Exception.Message
    return $false
  }
}

function Uninstall-AppxApp {
  param($App)
  Write-Info ("Uninstall APPX: " + $App.Name)
  try {
    Remove-AppxPackage -Package $App.Id -ErrorAction Stop
    Write-Ok ("Dihapus (user): " + $App.Name)
    return $true
  } catch {
    try {
      Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageFullName -eq $App.Id } |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop }
      Write-Ok ("Dihapus (all users): " + $App.Name)
      return $true
    } catch {
      Write-Err $_.Exception.Message
      return $false
    }
  }
}

# ---- main ----
Clear-Host
Write-Host ''
Write-Host '  ======================================================' -ForegroundColor Cyan
Write-Host '   SuperX - Multi-App Uninstaller' -ForegroundColor Cyan
Write-Host '   Windows PowerShell native - Skripkeren' -ForegroundColor Cyan
Write-Host '  ======================================================' -ForegroundColor Cyan
Write-Host ''

$ver = Get-WinVersionInfo
Write-Ok ('OS: ' + $ver.Caption)
if (-not (Test-IsAdmin)) {
  Write-Warn 'Tidak berjalan sebagai Administrator. Beberapa uninstall AppX/system mungkin gagal.'
  Write-Host '  Saran: klik kanan PowerShell -> Run as administrator, lalu ulangi.' -ForegroundColor DarkYellow
}
Write-Host ''

Write-Info 'Memuat daftar aplikasi (Win32 + AppX)...'
$apps = @(Get-InstalledApps)
if ($apps.Count -eq 0) {
  Write-Err 'Tidak ada aplikasi terdeteksi.'
  return
}

Write-Host ''
Write-Host ('{0,4}  {1,-6}  {2,-8}  {3}' -f 'No', 'Jenis', 'Sistem?', 'Nama') -ForegroundColor DarkGray
Write-Host ('{0,4}  {1,-6}  {2,-8}  {3}' -f '----', '------', '--------', '----') -ForegroundColor DarkGray

for ($i = 0; $i -lt $apps.Count; $i++) {
  $a = $apps[$i]
  $flag = 'tidak'
  if ($a.IsSystem) { $flag = 'YA*' }
  $color = 'White'
  if ($a.IsSystem) { $color = 'DarkYellow' }
  $nm = $a.Name
  if ($nm.Length -gt 70) { $nm = $nm.Substring(0, 67) + '...' }
  Write-Host ('{0,4}  {1,-6}  {2,-8}  {3}' -f ($i + 1), $a.Kind, $flag, $nm) -ForegroundColor $color
}

Write-Host ''
Write-Warn 'YA* = kemungkinan bawaan/sistem - uninstall berisiko. Hindari kecuali yakin.'
Write-Host 'Format pilih: 1 3 5-8,12   atau  1,2,3   (Enter kosong = batal)' -ForegroundColor DarkGray
$sel = Read-Host 'Nomor aplikasi yang di-uninstall'

$idxs = Parse-Selection -Raw $sel -Max $apps.Count
if ($idxs.Count -eq 0) {
  Write-Warn 'Dibatalkan / pilihan kosong.'
  return
}

Write-Host ''
Write-Host 'Akan di-uninstall:' -ForegroundColor Cyan
foreach ($n in $idxs) {
  $a = $apps[$n - 1]
  $tag = ''
  if ($a.IsSystem) { $tag = ' [SISTEM]' }
  Write-Host ('  - [' + $n + '] ' + $a.Name + $tag)
}

$confirm = Read-Host ('Lanjut uninstall ' + $idxs.Count + ' item? [y/N]')
if ($confirm -notmatch '^[Yy]') {
  Write-Warn 'Dibatalkan.'
  return
}

$ok = 0
$fail = 0
foreach ($n in $idxs) {
  $a = $apps[$n - 1]
  if ($a.IsSystem) {
    $c2 = Read-Host ("  '" + $a.Name + "' ditandai sistem. Tetap hapus? [y/N]")
    if ($c2 -notmatch '^[Yy]') {
      Write-Warn ('Skip: ' + $a.Name)
      continue
    }
  }
  $r = $false
  if ($a.Kind -eq 'WIN32') {
    $r = Uninstall-Win32App -App $a
  } else {
    $r = Uninstall-AppxApp -App $a
  }
  if ($r) { $ok++ } else { $fail++ }
}

Write-Host ''
Write-Ok ('Selesai. Berhasil: ' + $ok + '  Gagal: ' + $fail)
Write-Host 'Skripkeren SuperX' -ForegroundColor DarkGray
