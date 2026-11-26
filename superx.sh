#!/usr/bin/env bash
# ==============================================
#  superx.sh — Multi-App Uninstaller (Skripkeren)
#  Fokus: Windows (Git Bash / CMD / PowerShell)
#  Adaptif: macOS, Linux, Termux/Android
#
#  Fitur Windows:
#    1. Deteksi versi Windows
#    2. List aplikasi terinstall (Win32 + AppX/UWP)
#    3. Tandai aplikasi sistem / bawaan (jangan sembarangan dihapus)
#    4. Pilih banyak via nomor: 1 3 5-8,12  atau 1,2,3
#    5. Uninstall massal
#
#  Cara pakai:
#    bash superx.sh
#    curl -fsSL https://skripkeren.silverhawk.web.id/superx.sh | bash
# ==============================================

set +e

# --- Skripkeren auto-deps (opsional) ---
_SK_DEPS_URL="${SK_DEPS_URL:-https://skripkeren.silverhawk.web.id/sk-deps.sh}"
_sk_load_deps() {
  if [[ -n "${_SK_DEPS_LOADED:-}" ]]; then return 0; fi
  local _dir _f _tmp
  _dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || _dir="."
  for _f in "$_dir/sk-deps.sh" "./sk-deps.sh"; do
    if [[ -f "$_f" ]]; then
      # shellcheck source=/dev/null
      source "$_f"
      return 0
    fi
  done
  _tmp="$(mktemp 2>/dev/null || echo /tmp/sk-deps-$$.sh)"
  if command -v curl >/dev/null 2>&1 && curl -fsSL "$_SK_DEPS_URL" -o "$_tmp" 2>/dev/null; then
    # shellcheck source=/dev/null
    source "$_tmp"
    rm -f "$_tmp"
    return 0
  fi
  rm -f "$_tmp" 2>/dev/null || true
  return 1
}
_sk_load_deps 2>/dev/null || true

# Warna
if [[ -t 1 ]] || [[ -n "${MSYSTEM:-}" ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=; GREEN=; YELLOW=; CYAN=; BLUE=; BOLD=; NC=
fi

# TTY andal
TTY=/dev/tty
if [[ ! -c "$TTY" || ! -r "$TTY" || ! -w "$TTY" ]]; then
  TTY=/dev/stdin
fi

ask() {
  local _ans
  printf "%s" "$1" >"$TTY" 2>/dev/null || printf "%s" "$1"
  if ! IFS= read -r _ans <"$TTY" 2>/dev/null; then
    printf "\n" >"$TTY" 2>/dev/null || true
    printf "%s" ""
    return
  fi
  printf "%s" "$_ans"
}

is_windows() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  [[ -n "${WINDIR:-}" || -n "${SystemRoot:-}" ]] && return 0
  return 1
}

is_macos() { [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && ! is_windows; }
is_termux() { [[ -n "${TERMUX_VERSION:-}" || -d /data/data/com.termux ]]; }

# ---------- Dependency menu ----------
check_deps() {
  echo -e "${CYAN}Memeriksa dependency...${NC}"
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  if is_windows; then
    # PowerShell hampir selalu ada di Windows modern
    if ! command -v powershell.exe >/dev/null 2>&1 && ! command -v pwsh >/dev/null 2>&1; then
      missing+=("powershell")
    fi
  fi
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo -e "${GREEN}Dependency inti siap.${NC}"
    return 0
  fi
  echo -e "${YELLOW}Kurang: ${missing[*]}${NC}"
  if declare -F sk_ensure_basic >/dev/null 2>&1; then
    sk_ensure_basic curl 2>/dev/null || true
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Beberapa fitur mungkin terbatas. Lanjut tetap bisa."
  fi
  return 0
}

# ---------- Windows helpers ----------
win_version() {
  local ver
  ver=$(powershell.exe -NoProfile -Command "[System.Environment]::OSVersion.VersionString" 2>/dev/null | tr -d '\r')
  if [[ -z "$ver" ]]; then
    ver=$(cmd.exe //c "ver" 2>/dev/null | tr -d '\r' | tail -1)
  fi
  echo "${ver:-Windows (versi tidak terdeteksi)}"
}

# Daftar aplikasi Win32 (Uninstall registry) + AppX
# Output: nomor|jenis|sistem|nama|id_atau_uninstallstring
# jenis: WIN32 / APPX
# sistem: YES / NO
list_windows_apps() {
  local tmp
  tmp="$(mktemp 2>/dev/null || echo /tmp/superx-apps-$$.txt)"
  # PowerShell: ambil Win32 + AppX, tandai sistem
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
    $ErrorActionPreference = "SilentlyContinue"
    $list = @()
    # Win32 dari registry
    $paths = @(
      "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
      "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($p in $paths) {
      Get-ItemProperty $p | Where-Object { $_.DisplayName -and $_.UninstallString } | ForEach-Object {
        $sys = "NO"
        if ($_.SystemComponent -eq 1 -or $_.ParentKeyName -or $_.WindowsInstaller -eq 1 -and $_.Publisher -match "Microsoft") {
          # Heuristik: banyak Microsoft system component
        }
        $pub = [string]$_.Publisher
        $name = [string]$_.DisplayName
        if ($pub -match "Microsoft Corporation" -and $name -match "^(Microsoft|Windows|Update|Visual C\+\+|)") {
          $sys = "YES"
        }
        if ($name -match "^(Microsoft Visual C\+\+|Microsoft .NET|Windows SDK|Update for|KB[0-9])") { $sys = "YES" }
        $list += [PSCustomObject]@{
          Kind = "WIN32"
          System = $sys
          Name = $name
          Id = $_.PSChildName
          Uninstall = [string]$_.UninstallString
          Quiet = [string]$_.QuietUninstallString
        }
      }
    }
    # AppX / UWP
    Get-AppxPackage -AllUsers | Where-Object { $_.Name -and -not $_.IsFramework } | ForEach-Object {
      $sys = "NO"
      $n = $_.Name
      if ($n -match "^(Microsoft\.(Windows|UI|VCLibs|Net|DesktopAppInstaller|StorePurchaseApp|LockApp|ShellExperienceHost|StartMenuExperienceHost|AccountsControl|AsyncTextService|BioEnrollment|CredDialogHost|ECApp|MicrosoftEdgeDevToolsClient|Win32WebViewHost|XboxGameCallableUI|AAD\.BrokerPlugin|AssignedAccessLockApp|CapturePicker|CloudExperienceHost|ContentDeliveryManager|Cortana|ParentalControls|PeopleExperienceHost|PinningConfirmationDialog|SecureAssessmentBrowser|Windows\.Apprep|Windows\.AugLoop|Windows\.CapturePicker|Windows\.CloudExperienceHost|Windows\.ContentDeliveryManager|Windows\.PeopleExperienceHost|Windows\.XGpuEjectDialog|XboxIdentityProvider))" ) {
        $sys = "YES"
      }
      # Beberapa AppX Microsoft yang umum dianggap bloat (boleh dihapus) → biarkan NO
      if ($n -match "^(Microsoft\.(Bing|GetHelp|Getstarted|Messaging|Microsoft3DViewer|MicrosoftOfficeHub|MicrosoftSolitaireCollection|MixedReality|Office\.OneNote|People|SkypeApp|WindowsAlarms|WindowsFeedbackHub|WindowsMaps|WindowsSoundRecorder|Xbox|YourPhone|ZuneMusic|ZuneVideo|Clipchamp|Teams|Todos|PowerAutomate|BingWeather|BingNews|BingSearch))") {
        $sys = "NO"
      }
      $list += [PSCustomObject]@{
        Kind = "APPX"
        System = $sys
        Name = $_.Name + " (" + $_.Version + ")"
        Id = $_.PackageFullName
        Uninstall = ""
        Quiet = ""
      }
    }
    $i = 1
    $list | Sort-Object Name | ForEach-Object {
      $sysMark = if ($_.System -eq "YES") { "SISTEM" } else { "OK" }
      # Format: nomor|KIND|SISTEM|nama|id
      "{0}|{1}|{2}|{3}|{4}" -f $i, $_.Kind, $sysMark, ($_.Name -replace "\|","/"), $_.Id
      $i++
    }
  ' 2>/dev/null | tr -d '\r' > "$tmp"
  cat "$tmp"
  rm -f "$tmp" 2>/dev/null || true
}

# Parse input user: "1 3 5-8,12" → daftar nomor unik terurut
parse_selection() {
  local input="$1"
  local -a out=()
  # Ganti koma jadi spasi
  input=$(echo "$input" | tr ',' ' ')
  for token in $input; do
    token=$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local a=${BASH_REMATCH[1]}
      local b=${BASH_REMATCH[2]}
      if (( a > b )); then local t=$a; a=$b; b=$t; fi
      local k
      for ((k=a; k<=b; k++)); do
        out+=("$k")
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      out+=("$token")
    fi
  done
  # Unik + sort
  printf '%s\n' "${out[@]}" | sort -n | uniq
}

uninstall_win32() {
  local id="$1"
  local name="$2"
  echo -e "  ${CYAN}Uninstall WIN32:${NC} $name"
  # Cari QuietUninstallString / UninstallString lewat PowerShell lalu jalankan
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    \$key = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$id','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$id','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$id' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not \$key) { Write-Host 'Key tidak ditemukan'; exit 1 }
    \$cmd = \$key.QuietUninstallString
    if (-not \$cmd) { \$cmd = \$key.UninstallString }
    if (-not \$cmd) { Write-Host 'Tidak ada UninstallString'; exit 1 }
    Write-Host \"Menjalankan: \$cmd\"
    if (\$cmd -match 'msiexec') {
      \$cmd = \$cmd -replace '/I','/X' -replace '/i','/x'
      if (\$cmd -notmatch '/quiet|/qn') { \$cmd += ' /qn /norestart' }
      Start-Process -FilePath 'cmd.exe' -ArgumentList '/c',\$cmd -Wait -NoNewWindow
    } else {
      Start-Process -FilePath 'cmd.exe' -ArgumentList '/c',\$cmd -Wait -NoNewWindow
    }
  " 2>/dev/null
}

uninstall_appx() {
  local fullname="$1"
  local name="$2"
  echo -e "  ${CYAN}Uninstall APPX:${NC} $name"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    Remove-AppxPackage -Package '$fullname' -ErrorAction SilentlyContinue
    Get-AppxPackage -AllUsers | Where-Object { \$_.PackageFullName -eq '$fullname' } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Write-Host 'Selesai (AppX).'
  " 2>/dev/null
}

# ---------- Menu Windows ----------
menu_windows() {
  echo ""
  echo -e "${BOLD}${CYAN}=== SuperX — Uninstaller Windows ===${NC}"
  echo -e "Versi OS : ${GREEN}$(win_version)${NC}"
  echo ""
  echo "Memuat daftar aplikasi (Win32 + AppX). Mohon tunggu..."
  local lines
  mapfile -t lines < <(list_windows_apps)
  if [[ ${#lines[@]} -eq 0 ]]; then
    echo -e "${RED}Gagal mengambil daftar aplikasi.${NC}"
    echo "Pastikan dijalankan di Git Bash / terminal Windows dengan PowerShell tersedia."
    return 1
  fi

  echo ""
  echo -e "${GREEN}Daftar aplikasi terinstall:${NC}"
  echo "──────────────────────────────────────────────────────────────────────────────"
  printf "  %4s  %-6s  %-7s  %s\n" "No" "Jenis" "Status" "Nama"
  echo "──────────────────────────────────────────────────────────────────────────────"
  local line no kind sys name id
  for line in "${lines[@]}"; do
    IFS='|' read -r no kind sys name id <<< "$line"
    local status_col
    if [[ "$sys" == "SISTEM" ]]; then
      status_col="${RED}SISTEM${NC}"
    else
      status_col="${GREEN}OK${NC}"
    fi
    printf "  %4s  %-6s  %-7b  %s\n" "$no" "$kind" "$status_col" "$name"
  done
  echo "──────────────────────────────────────────────────────────────────────────────"
  echo -e "  ${RED}SISTEM${NC} = aplikasi bawaan / komponen sistem (disarankan JANGAN di-uninstall)"
  echo -e "  ${GREEN}OK${NC}     = biasanya aman dihapus"
  echo ""
  echo "Contoh input:  1 3 5-8,12   atau   2,4,6"
  echo "Ketik 0 atau q untuk batal."
  echo ""

  local sel
  sel=$(ask "Pilih nomor yang akan di-uninstall: ")
  sel=$(printf '%s' "$sel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -z "$sel" || "$sel" == "0" || "$sel" == "q" || "$sel" == "Q" ]]; then
    echo "Dibatalkan."
    return 0
  fi

  local -a nums
  mapfile -t nums < <(parse_selection "$sel")
  if [[ ${#nums[@]} -eq 0 ]]; then
    echo -e "${RED}Tidak ada nomor valid.${NC}"
    return 1
  fi

  echo ""
  echo -e "${YELLOW}Yang akan di-uninstall:${NC}"
  local -a targets=()
  local n
  for n in "${nums[@]}"; do
    for line in "${lines[@]}"; do
      IFS='|' read -r no kind sys name id <<< "$line"
      if [[ "$no" == "$n" ]]; then
        if [[ "$sys" == "SISTEM" ]]; then
          echo -e "  ${RED}! $no  $name  (SISTEM — berisiko)${NC}"
        else
          echo -e "  $no  $name"
        fi
        targets+=("$line")
        break
      fi
    done
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "Tidak ada target valid."
    return 1
  fi

  echo ""
  local conf
  conf=$(ask "Ketik YA untuk uninstall semua di atas: ")
  conf=$(printf '%s' "$conf" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ "$conf" != "YA" ]]; then
    echo "Dibatalkan."
    return 0
  fi

  echo ""
  for line in "${targets[@]}"; do
    IFS='|' read -r no kind sys name id <<< "$line"
    if [[ "$kind" == "APPX" ]]; then
      uninstall_appx "$id" "$name"
    else
      uninstall_win32 "$id" "$name"
    fi
  done

  echo ""
  echo -e "${GREEN}Selesai. Beberapa aplikasi mungkin perlu restart Explorer / reboot.${NC}"
}

# ---------- Menu non-Windows (adaptif) ----------
menu_other() {
  echo ""
  echo -e "${BOLD}${CYAN}=== SuperX — Package helper (non-Windows) ===${NC}"
  if is_macos; then
    echo "Platform: macOS"
    if command -v brew >/dev/null 2>&1; then
      echo "Perintah berguna:"
      echo "  brew list"
      echo "  brew uninstall <formula>"
      echo "  brew uninstall --cask <cask>"
    else
      echo "Homebrew belum terpasang. Install: https://brew.sh"
    fi
  elif is_termux; then
    echo "Platform: Termux (Android)"
    echo "  pkg list-installed"
    echo "  pkg uninstall <paket>"
  elif is_linux; then
    echo "Platform: Linux"
    if command -v apt-get >/dev/null 2>&1; then
      echo "  apt list --installed"
      echo "  sudo apt remove <paket>"
    elif command -v dnf >/dev/null 2>&1; then
      echo "  dnf list installed"
      echo "  sudo dnf remove <paket>"
    else
      echo "Package manager tidak dikenali otomatis."
    fi
  else
    echo "Platform tidak dikenali untuk uninstall massal."
  fi
  echo ""
  echo "Fitur pilih-nomor massal saat ini dioptimalkan untuk Windows."
  echo "Di platform ini gunakan perintah package manager di atas."
}

# ---------- Main ----------
main() {
  clear 2>/dev/null || true
  echo -e "${CYAN}"
  echo "╔════════════════════════════════════════════════════╗"
  echo "║              superx.sh — Super Uninstaller         ║"
  echo "║     Multi-app uninstall · Windows + adaptif        ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  check_deps

  if is_windows; then
    menu_windows
  else
    menu_other
    echo ""
    echo "0) Keluar"
    local c
    c=$(ask "Pilih: ")
  fi

  echo ""
  echo "Selesai. Jalankan lagi kapan saja: bash superx.sh"
}

main "$@"
