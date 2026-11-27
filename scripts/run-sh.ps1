#Requires -Version 5.1
<#
  Skripkeren bootstrap Windows:
  - Cari Git Bash
  - Jika belum ada: winget install Git.Git
  - Jalankan script .sh yang diminta
  Usage:
    irm https://skripkeren.silverhawk.web.id/scripts/run-sh.ps1 | iex
    # atau dengan parameter:
    powershell -File run-sh.ps1 -ScriptUrl https://skripkeren.silverhawk.web.id/scripts/superx.sh
#>
param(
  [string]$ScriptUrl = 'https://skripkeren.silverhawk.web.id/scripts/superx.sh',
  [string]$ScriptName = ''
)

function Write-Info($m){ Write-Host "➜ $m" -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host "✓ $m" -ForegroundColor Green }
function Write-Warn($m){ Write-Host "! $m" -ForegroundColor Yellow }
function Write-Err($m){ Write-Host "✗ $m" -ForegroundColor Red }

function Find-GitBash {
  $candidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  # where.exe
  try {
    $w = & where.exe bash 2>$null | Select-Object -First 5
    foreach ($line in $w) {
      if ($line -match 'Git\\bin\\bash\.exe' -or $line -match 'Git\\usr\\bin\\bash\.exe') { return $line.Trim() }
    }
  } catch {}
  return $null
}

function Install-Git {
  Write-Info "Git for Windows belum ketemu. Mencoba winget install Git.Git…"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
    return $true
  }
  Write-Err "winget tidak ada. Install manual: https://git-scm.com/download/win (centang Git Bash)"
  return $false
}

Write-Host "Skripkeren run-sh · bootstrap Git Bash" -ForegroundColor Cyan
$bash = Find-GitBash
if (-not $bash) {
  Write-Warn "Git Bash tidak ditemukan (bukan WSL)."
  Write-Host "  Catatan: perintah 'bash' di PowerShell sering mengarah ke WSL, bukan Git Bash." -ForegroundColor DarkYellow
  $ans = Read-Host "Install Git for Windows sekarang via winget? [Y/n]"
  if ($ans -notmatch '^[Nn]') {
    Install-Git | Out-Null
    # refresh PATH in session
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    $bash = Find-GitBash
  }
}

if (-not $bash) {
  Write-Err "Git Bash masih belum ada. Untuk SuperX Windows, pakai native PowerShell:"
  Write-Host "  irm https://skripkeren.silverhawk.web.id/scripts/superx.ps1 | iex" -ForegroundColor Green
  return
}

Write-Ok "Git Bash: $bash"
if (-not $ScriptName) {
  $ScriptName = [IO.Path]::GetFileName( ([Uri]$ScriptUrl).AbsolutePath )
}
$dest = Join-Path $env:TEMP $ScriptName
Write-Info "Unduh $ScriptUrl"
try {
  curl.exe -fsSL $ScriptUrl -o $dest
  if (-not (Test-Path $dest)) { throw "download gagal" }
} catch {
  Write-Err "Gagal unduh: $_"
  return
}
Write-Info "Menjalankan lewat Git Bash…"
& $bash $dest
