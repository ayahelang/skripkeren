#!/usr/bin/env bash
# =============================================================================
#  sk-deps.sh — helper dependency Skripkeren
#  Dipakai urusrepo.sh dan script .sh lain.
#  Bisa di-source lokal atau diunduh otomatis saat curl|bash.
# =============================================================================

# Hindari double-load
if [[ -n "${_SK_DEPS_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_SK_DEPS_LOADED=1

# Warna (jika belum di-set host script)
if [[ -z "${SK_GREEN:-}" ]]; then
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    SK_RED=$'\033[0;31m'; SK_GREEN=$'\033[0;32m'; SK_YELLOW=$'\033[1;33m'
    SK_CYAN=$'\033[0;36m'; SK_BOLD=$'\033[1m'; SK_DIM=$'\033[2m'; SK_NC=$'\033[0m'
  else
    SK_RED=; SK_GREEN=; SK_YELLOW=; SK_CYAN=; SK_BOLD=; SK_DIM=; SK_NC=
  fi
fi

sk_info()  { printf '%s➜%s %s\n' "${SK_CYAN}" "${SK_NC}" "$*"; }
sk_ok()    { printf '%s✓%s %s\n' "${SK_GREEN}" "${SK_NC}" "$*"; }
sk_warn()  { printf '%s!%s %s\n' "${SK_YELLOW}" "${SK_NC}" "$*"; }
sk_err()   { printf '%s✗%s %s\n' "${SK_RED}" "${SK_NC}" "$*"; }

sk_is_windows() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  [[ -n "${WINDIR:-}" || -n "${SystemRoot:-}" ]] && return 0
  return 1
}

sk_is_linux() {
  [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && ! sk_is_windows
}

sk_is_macos() {
  [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]
}

# --- Python (khusus Windows/Git Bash sering bermasalah) ---
sk_find_python() {
  local cmd resolved cand d home winuser
  for cmd in python python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
      resolved=$(command -v "$cmd" 2>/dev/null || true)
      [[ "$resolved" == *WindowsApps* ]] && continue
      if "$cmd" -c "import sys" >/dev/null 2>&1; then
        echo "$cmd"
        return 0
      fi
    fi
  done
  if command -v py >/dev/null 2>&1 && py -3 -c "import sys" >/dev/null 2>&1; then
    echo "py -3"
    return 0
  fi
  home="${HOME:-}"
  winuser="${USERNAME:-${USER:-}}"
  for d in \
    "$home"/AppData/Local/Programs/Python/Python3*/python.exe \
    /c/Users/"$winuser"/AppData/Local/Programs/Python/Python3*/python.exe \
    /c/Python3*/python.exe \
    "/c/Program Files/Python3"/python.exe
  do
    if [[ -f "$d" ]] && "$d" -c "import sys" >/dev/null 2>&1; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

sk_disable_python_store_alias() {
  local apps
  apps="${LOCALAPPDATA:-$HOME/AppData/Local}/Microsoft/WindowsApps"
  [[ -d "$apps" ]] || return 0
  sk_info "Menonaktifkan alias Microsoft Store (python)…"
  rm -f "$apps/python.exe" "$apps/python3.exe" "$apps/python3.11.exe" "$apps/python3.12.exe" "$apps/python3.13.exe" 2>/dev/null || true
  command -v powershell.exe >/dev/null 2>&1 && powershell.exe -NoProfile -Command '
    $dir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    @("python.exe","python3.exe") | ForEach-Object {
      $p = Join-Path $dir $_
      if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    }' 2>/dev/null || true
}

sk_install_python() {
  sk_info "Install Python 3.12 via winget…"
  if command -v winget >/dev/null 2>&1; then
    winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements && return 0
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe //c "winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements" && return 0
  fi
  if sk_is_macos && command -v brew >/dev/null 2>&1; then
    brew install python && return 0
  fi
  if sk_is_linux; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y python3 && return 0
    fi
  fi
  return 1
}

sk_refresh_python_path() {
  local home winuser d
  home="${HOME:-}"
  winuser="${USERNAME:-${USER:-}}"
  for d in "$home"/AppData/Local/Programs/Python/Python3* \
           /c/Users/"$winuser"/AppData/Local/Programs/Python/Python3*; do
    if [[ -d "$d" && -f "$d/python.exe" ]]; then
      export PATH="$d:$d/Scripts:$PATH"
      sk_info "PATH sesi ditambah: $d"
    fi
  done
}

# Set SK_PYTHON ke command yang valid, atau return 1
sk_ensure_python() {
  local found
  found=$(sk_find_python 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    SK_PYTHON="$found"
    sk_ok "Python: $SK_PYTHON ($($SK_PYTHON -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo '?'))"
    return 0
  fi
  sk_warn "Python belum siap."
  if sk_is_windows; then
    echo "  Akan dicoba: nonaktifkan alias Store → install winget → refresh PATH"
    printf "  Auto-setup Python? [Y/n] "
    local a=""; read -r a || true; a="${a:-Y}"
    if [[ "${a,,}" == "n" || "${a,,}" == "no" ]]; then
      sk_err "Python wajib. https://www.python.org/downloads/ (centang Add to PATH), restart terminal."
      return 1
    fi
    sk_disable_python_store_alias
    found=$(sk_find_python 2>/dev/null || true)
    if [[ -n "$found" ]]; then SK_PYTHON="$found"; sk_ok "Python: $SK_PYTHON"; return 0; fi
    sk_install_python || true
    sk_refresh_python_path
    sk_disable_python_store_alias
    found=$(sk_find_python 2>/dev/null || true)
    if [[ -n "$found" ]]; then SK_PYTHON="$found"; sk_ok "Python: $SK_PYTHON"; return 0; fi
    sk_err "Python masih belum terdeteksi. Tutup SEMUA terminal, buka lagi, jalankan: python --version"
    return 1
  fi
  sk_install_python || true
  found=$(sk_find_python 2>/dev/null || true)
  if [[ -n "$found" ]]; then SK_PYTHON="$found"; sk_ok "Python: $SK_PYTHON"; return 0; fi
  sk_err "Install python3 manual lalu ulangi."
  return 1
}

# --- perintah generik ---
sk_ensure_cmd() {
  # sk_ensure_cmd NAME [apt_pkg] [winget_id] [brew_pkg]
  local name="${1:-}" apt_pkg="${2:-$1}" winget_id="${3:-}" brew_pkg="${4:-$1}"
  [[ -z "$name" ]] && return 1
  if command -v "$name" >/dev/null 2>&1; then
    sk_ok "Dependency OK: $name"
    return 0
  fi
  sk_warn "Kurang: $name — mencoba install…"
  if sk_is_windows && [[ -n "$winget_id" ]]; then
    if command -v winget >/dev/null 2>&1; then
      winget install --id "$winget_id" -e --accept-package-agreements --accept-source-agreements && command -v "$name" >/dev/null 2>&1 && { sk_ok "Terpasang: $name"; return 0; }
    fi
    cmd.exe //c "winget install --id $winget_id -e --accept-package-agreements --accept-source-agreements" 2>/dev/null || true
  fi
  if sk_is_macos && command -v brew >/dev/null 2>&1; then
    brew install "$brew_pkg" && command -v "$name" >/dev/null 2>&1 && { sk_ok "Terpasang: $name"; return 0; }
  fi
  if sk_is_linux && command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo apt-get install -y "$apt_pkg" && command -v "$name" >/dev/null 2>&1 && { sk_ok "Terpasang: $name"; return 0; }
  fi
  if command -v "$name" >/dev/null 2>&1; then
    sk_ok "Dependency OK: $name"
    return 0
  fi
  sk_err "Gagal sediakan: $name — install manual lalu ulangi."
  return 1
}

sk_ensure_curl() { sk_ensure_cmd curl curl curl.curl curl; }
sk_ensure_git()  { sk_ensure_cmd git git Git.Git git; }
sk_ensure_gh()   { sk_ensure_cmd gh gh GitHub.cli gh; }

sk_ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    sk_ok "Dependency OK: docker"
    return 0
  fi
  sk_warn "Docker belum ada."
  if sk_is_linux; then
    echo "  Mencoba install docker.io via apt…"
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo apt-get install -y docker.io docker-compose-v2 2>/dev/null || sudo apt-get install -y docker.io docker-compose || true
    sudo systemctl enable --now docker 2>/dev/null || true
  fi
  if command -v docker >/dev/null 2>&1; then
    sk_ok "Docker siap"
    return 0
  fi
  sk_err "Install Docker manual: https://docs.docker.com/get-docker/"
  return 1
}

# Bootstrap loader untuk script lain
sk_load_self_note() {
  sk_info "Skripkeren deps helper aktif (sk-deps.sh)"
}

# Pastikan set dependency umum: curl + (opsional list)
# Usage: sk_ensure_basic curl git python
sk_ensure_basic() {
  local d
  sk_info "Memeriksa dependency…"
  for d in "$@"; do
    case "$d" in
      curl) sk_ensure_curl || return 1 ;;
      git)  sk_ensure_git || return 1 ;;
      gh)   sk_ensure_gh || return 1 ;;
      python|python3) sk_ensure_python || return 1 ;;
      docker) sk_ensure_docker || return 1 ;;
      *)
        if command -v "$d" >/dev/null 2>&1; then
          sk_ok "Dependency OK: $d"
        else
          sk_warn "Tidak ada helper install untuk: $d — pastikan sudah di PATH"
          command -v "$d" >/dev/null 2>&1 || return 1
        fi
        ;;
    esac
  done
  sk_ok "Semua dependency inti siap."
  return 0
}
