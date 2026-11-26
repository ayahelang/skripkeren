#!/usr/bin/env bash
# Silverhawk Jellyfin Setup (ljellyfin.sh)
# Media Server open-source (film, serial, musik)
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/ljellyfin.sh)

# --- Skripkeren auto-deps ---
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

APP="Silverhawk Jellyfin"
VER="1.0.0"
DOMAIN_DEFAULT="media.silverhawk.web.id"
INSTALL_DIR="/opt/jellyfin"
MEDIA_DIR="/srv/media"
CONFIG_DIR="/srv/jellyfin/config"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-jellyfin-$$"
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
  echo "    ${C_DIM}Contoh domain : ${DOMAIN_DEFAULT}${C_RESET}"
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
    ${C_BOLD}HARDWARE yang harus disiapkan:${C_RESET}
    - RAM minimal 2 GB (4 GB lebih nyaman)
    - CPU yang cukup untuk transcoding (atau pakai client yang support direct play)
    - Storage BESAR untuk koleksi film/serial (HDD cocok)
    - Opsional: GPU (Intel QuickSync / NVIDIA) untuk hardware transcoding

    ${C_BOLD}YANG HARUS SUDAH SIAP:${C_RESET}
    - Ubuntu Server sudah terinstall
    - Folder media sudah ada dan berisi file (contoh /srv/media/movies, /srv/media/tv)
    - Struktur folder yang rapi sangat membantu library Jellyfin
    - Domain/subdomain (opsional, contoh media.silverhawk.web.id)
    - Docker (bisa diinstall menu 1)

    ${C_BOLD}Tidak dilakukan otomatis oleh script:${C_RESET}
    - Menyalin / me-rename file film
    - Hardware transcoding tuning (perlu penyesuaian manual jika pakai GPU)
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
  echo "    ${C_BOLD}2. Install Jellyfin (Docker)${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v docker >/dev/null 2>&1; then msg_err "Docker belum ada."; pause; return; fi

  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$MEDIA_DIR"
  local media
  media=$(ask "    Path folder media [${MEDIA_DIR}]: ")
  [ -z "$media" ] && media="$MEDIA_DIR"
  mkdir -p "$media"

  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "8096:8096"
    volumes:
      - ${CONFIG_DIR}:/config
      - ${media}:/media
    environment:
      - JELLYFIN_PublishedServerUrl=https://${DOMAIN_DEFAULT}
    # group_add / devices untuk hardware acceleration bisa ditambah manual nanti
EOF

  cd "$INSTALL_DIR"
  docker compose pull
  docker compose up -d

  msg_ok "Jellyfin jalan di http://IP-SERVER:8096"
  echo "    Media di-mount dari: $media"
  echo "    Config             : $CONFIG_DIR"
  pause
}

do_tunnel_info(){
  title
  echo "    ${C_BOLD}3. Cloudflare Tunnel${C_RESET}"
  hr
  cat <<EOF
    Public Hostname:
    - Subdomain : media
    - Domain    : silverhawk.web.id
    - Service   : http://localhost:8096

    Domainesia → CNAME media → xxxxx.cfargotunnel.com
EOF
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}4. Status${C_RESET}"
  hr
  docker ps --filter name=jellyfin --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  df -h "$MEDIA_DIR" 2>/dev/null || true
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}5. Panduan singkat${C_RESET}"
  hr
  cat <<EOF
    Jellyfin = media server gratis (mirip Plex, tanpa wajib akun).

    Setelah install:
    1. Buka http://IP:8096 → wizard setup
    2. Tambah library (Movies, TV Shows, dll.) mengarah ke /media/...
    3. Install app Jellyfin di HP/TV/Browser

    Tips performa:
    - Direct Play lebih hemat resource daripada Transcode
    - Hardware acceleration perlu setup tambahan (tidak otomatis)
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — Jellyfin Media Server${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan hardware & aplikasi (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install Docker"
    echo "    ${C_CYAN}2${C_RESET}. Install / Jalankan Jellyfin"
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

echo; msg_info "Jellyfin Setup — baca menu 0 dulu"; main_menu
