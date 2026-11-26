#!/usr/bin/env bash
# Silverhawk Uptime Kuma Setup (lkuma.sh)
# Monitoring uptime website & service + notifikasi
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lkuma.sh)

# --- Skripkeren auto-deps ---
_SK_DEPS_URL="${SK_DEPS_URL:-https://skripkeren.silverhawk.web.id/scripts/sk-deps.sh}"
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
_sk_load_deps || true

set -u

# Cek & lengkapi dependency sebelum menu utama
if declare -F sk_ensure_basic >/dev/null 2>&1; then
  sk_ensure_basic curl docker || {
    echo "Dependency belum lengkap. Selesaikan install di atas lalu jalankan ulang."
    exit 1
  }
fi

set -o pipefail

APP="Silverhawk Uptime Kuma"
VER="1.0.0"
INSTALL_DIR="/opt/uptime-kuma"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-kuma-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

TTY=/dev/tty
if [ ! -c "$TTY" ] || [ ! -r "$TTY" ] || [ ! -w "$TTY" ]; then TTY=/dev/stdin; fi
ask(){ local _a; printf "%s" "$1" >"$TTY"; IFS= read -r _a <"$TTY" || true; printf "%s" "$_a"; }

if [ -t 1 ] || [ -t 2 ]; then
  C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_BOLD=""
fi
msg_ok(){ echo "${C_GREEN}✔ $*${C_RESET}"; }
msg_warn(){ echo "${C_YELLOW}⚠ $*${C_RESET}"; }
msg_err(){ echo "${C_RED}✖ $*${C_RESET}" >&2; }
msg_info(){ echo "${C_CYAN}ℹ $*${C_RESET}"; }
hr(){ printf '%s\n' "${C_DIM}    ────────────────────────────────────────────────────────────────────────────────${C_RESET}"; }
pause(){ echo; ask "    Tekan Enter untuk melanjutkan... " >/dev/null; }

title(){
  clear 2>/dev/null || true
  echo
  echo "    ${C_CYAN}${C_BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
  printf "    ${C_CYAN}${C_BOLD}║ %-76s ║${C_RESET}\n" "$APP v$VER"
  echo "    ${C_CYAN}${C_BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
  hr
}

need_root(){
  if [ "$(id -u)" -ne 0 ]; then msg_err "Butuh root/sudo."; pause; return 1; fi
  return 0
}

show_prereq(){
  title
  echo "    ${C_BOLD}0. Persyaratan SEBELUM menjalankan menu ini${C_RESET}"
  hr
  cat <<EOF
    ${C_BOLD}HARDWARE:${C_RESET}
    - Sangat ringan (bisa jalan di 1 GB RAM)

    ${C_BOLD}YANG HARUS SUDAH SIAP:${C_RESET}
    - Docker (bisa diinstall menu 1)
    - (Opsional) Domain untuk akses dashboard dari luar
    - Akun Telegram / Discord / email jika ingin notifikasi (disetel di dalam Kuma)

    ${C_BOLD}Script ini TIDAK:${C_RESET}
    - Membuat bot Telegram / webhook Discord (kamu buat sendiri, lalu tempel di Kuma)
    - Mengatur DNS
EOF
  pause
}

do_docker(){
  title
  echo "    ${C_BOLD}1. Install Docker${C_RESET}"
  hr
  if ! need_root; then return; fi
  if command -v docker >/dev/null 2>&1; then msg_ok "Docker sudah ada."
  else
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    [ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER" || true
  fi
  pause
}

do_install(){
  title
  echo "    ${C_BOLD}2. Install Uptime Kuma${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v docker >/dev/null 2>&1; then msg_err "Docker belum ada."; pause; return; fi

  mkdir -p "$INSTALL_DIR/data"
  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/data
EOF

  cd "$INSTALL_DIR"
  docker compose pull
  docker compose up -d

  msg_ok "Uptime Kuma jalan di http://IP-SERVER:3001"
  echo "    Buat akun admin saat pertama kali buka."
  pause
}

do_tunnel_info(){
  title
  echo "    ${C_BOLD}3. Cloudflare Tunnel (opsional)${C_RESET}"
  hr
  cat <<EOF
    Public Hostname contoh:
    - Subdomain : status
    - Domain    : silverhawk.web.id
    - Service   : http://localhost:3001
EOF
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}4. Status${C_RESET}"
  hr
  docker ps --filter name=uptime-kuma --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}5. Panduan singkat${C_RESET}"
  hr
  cat <<EOF
    Uptime Kuma = pantau website, port, Docker, dll. + notifikasi.

    Setelah login:
    - Add New Monitor (HTTP, TCP, Ping, Docker, dll.)
    - Settings → Notifications → tambah Telegram / Discord / Email
    - Bisa status page publik

    Sangat berguna untuk jasa kelola server klien.
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — Uptime Kuma${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install Docker"
    echo "    ${C_CYAN}2${C_RESET}. Install Uptime Kuma"
    echo "    ${C_CYAN}3${C_RESET}. Panduan Cloudflare Tunnel"
    echo "    ${C_CYAN}4${C_RESET}. Status"
    echo "    ${C_CYAN}5${C_RESET}. Panduan singkat"
    echo "    ${C_CYAN}q${C_RESET}. Keluar"
    local p; p=$(ask "    Pilih: ")
    case "$p" in
      0) show_prereq ;; 1) do_docker ;; 2) do_install ;;
      3) do_tunnel_info ;; 4) do_status ;; 5) do_guide ;;
      q|Q) exit 0 ;; *) msg_warn "Tidak dikenal."; sleep 1 ;;
    esac
  done
}

echo; msg_info "Uptime Kuma Setup"; main_menu
