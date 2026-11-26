#!/usr/bin/env bash
# Silverhawk Nextcloud Setup (lnextcloud.sh)
# Personal Cloud / File Sync berbasis Nextcloud (Docker)
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lnextcloud.sh)

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

APP="Silverhawk Nextcloud"
VER="1.0.0"
DOMAIN_DEFAULT="cloud.silverhawk.web.id"
INSTALL_DIR="/opt/nextcloud"
DATA_DIR="/srv/nextcloud/data"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-nextcloud-$$"
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
  if [ "$(id -u)" -ne 0 ]; then
    msg_err "Butuh root/sudo. Jalankan: sudo bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lnextcloud.sh)"
    pause; return 1
  fi
  return 0
}

show_prereq(){
  title
  echo "    ${C_BOLD}0. Persyaratan SEBELUM menjalankan menu ini${C_RESET}"
  hr
  cat <<EOF
    ${C_BOLD}HARDWARE yang harus disiapkan:${C_RESET}
    - RAM minimal 2 GB (disarankan 4 GB ke atas jika banyak user/file)
    - Storage terpisah / partisi cukup besar untuk data file user
    - Koneksi internet stabil (upload/download file)

    ${C_BOLD}YANG HARUS SUDAH SIAP (tidak bisa dilakukan penuh oleh script ini):${C_RESET}
    - Ubuntu Server 22.04 / 24.04 LTS sudah terinstall
    - Akses SSH / terminal root atau sudo
    - Domain / subdomain sudah dimiliki (contoh: cloud.silverhawk.web.id)
    - Akun Cloudflare (disarankan) untuk Tunnel + HTTPS gratis
    - Di Domainesia: siap tambah CNAME (Nameserver JANGAN diubah)
    - Folder data permanen (contoh /srv/nextcloud/data) — sebaiknya di disk terpisah

    ${C_BOLD}Catatan:${C_RESET}
    Script ini bisa menginstall Docker & Nextcloud via Docker Compose.
    Tapi domain, DNS, dan akun Cloudflare harus kamu siapkan manual.
EOF
  pause
}

do_docker(){
  title
  echo "    ${C_BOLD}1. Install Docker + Compose${C_RESET}"
  hr
  if ! need_root; then return; fi
  if command -v docker >/dev/null 2>&1; then
    msg_ok "Docker sudah ada: $(docker --version)"
  else
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    [ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER" || true
    msg_ok "Docker terpasang."
  fi
  docker compose version 2>/dev/null || docker-compose version 2>/dev/null || true
  pause
}

do_install(){
  title
  echo "    ${C_BOLD}2. Install Nextcloud (Docker Compose)${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v docker >/dev/null 2>&1; then
    msg_err "Docker belum ada. Jalankan menu 1 dulu."; pause; return
  fi

  mkdir -p "$INSTALL_DIR" "$DATA_DIR"
  local domain
  domain=$(ask "    Domain/subdomain Nextcloud [${DOMAIN_DEFAULT}]: ")
  [ -z "$domain" ] && domain="$DOMAIN_DEFAULT"

  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  db:
    image: mariadb:11
    restart: always
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb-file-per-table=1 --skip-innodb-read-only-compressed
    volumes:
      - db_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: nextcloud_root_change_me
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud_db_change_me
    networks: [nextcloud_net]

  redis:
    image: redis:alpine
    restart: always
    networks: [nextcloud_net]

  app:
    image: nextcloud:apache
    restart: always
    ports:
      - "8081:80"
    volumes:
      - ${DATA_DIR}:/var/www/html
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud_db_change_me
      REDIS_HOST: redis
      NEXTCLOUD_TRUSTED_DOMAINS: ${domain} localhost
    depends_on: [db, redis]
    networks: [nextcloud_net]

volumes:
  db_data:

networks:
  nextcloud_net:
EOF

  cd "$INSTALL_DIR"
  docker compose pull
  docker compose up -d

  msg_ok "Nextcloud dijalankan."
  echo "    Lokal   : http://IP-SERVER:8081"
  echo "    Domain  : https://${domain}  (setelah Tunnel/Proxy aktif)"
  echo "    Data    : $DATA_DIR"
  echo
  msg_warn "Ganti password database di docker-compose.yml sebelum production!"
  pause
}

do_tunnel_info(){
  title
  echo "    ${C_BOLD}3. Cloudflare Tunnel / Reverse Proxy${C_RESET}"
  hr
  cat <<EOF
    Agar Nextcloud bisa diakses dari internet dengan HTTPS:

    Opsi A — Cloudflare Tunnel (disarankan, tidak perlu buka port):
    1. Buat Tunnel di Cloudflare Zero Trust
    2. Public Hostname:
       - Subdomain : cloud
       - Domain    : silverhawk.web.id
       - Service   : http://localhost:8081
    3. Domainesia → DNS → CNAME cloud → xxxxx.cfargotunnel.com

    Opsi B — Nginx Proxy Manager (lihat lnpm.sh)
    Arahkan domain ke http://IP:8081

    Setelah domain aktif, di Nextcloud Admin:
    Settings → Overview → pastikan tidak ada peringatan trusted domain / HTTPS.
EOF
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}4. Status${C_RESET}"
  hr
  if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cd "$INSTALL_DIR" && docker compose ps 2>/dev/null || true
  else
    msg_warn "Belum diinstall lewat script ini."
  fi
  echo
  df -h "$DATA_DIR" 2>/dev/null || df -h /
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}5. Panduan & Tips${C_RESET}"
  hr
  cat <<EOF
    Nextcloud = Google Drive + Office + Kalender + Contact self-hosted.

    Alur disarankan: 0 (baca syarat) → 1 → 2 → 3

    Setelah pertama kali buka web:
    - Buat akun admin
    - Install app resmi: Calendar, Contacts, OnlyOffice/Collabora (opsional)
    - Setup backup folder data ($DATA_DIR) secara rutin

    Keamanan:
    - Ganti password database default
    - Aktifkan 2FA
    - Jangan expose port 8081 langsung ke internet (pakai Tunnel / NPM)
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — Nextcloud${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan hardware & aplikasi (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install Docker + Compose"
    echo "    ${C_CYAN}2${C_RESET}. Install / Jalankan Nextcloud"
    echo "    ${C_CYAN}3${C_RESET}. Panduan Cloudflare Tunnel / Proxy"
    echo "    ${C_CYAN}4${C_RESET}. Status"
    echo "    ${C_CYAN}5${C_RESET}. Panduan & tips"
    echo "    ${C_CYAN}q${C_RESET}. Keluar"
    echo
    local p; p=$(ask "    Pilih: ")
    case "$p" in
      0) show_prereq ;;
      1) do_docker ;;
      2) do_install ;;
      3) do_tunnel_info ;;
      4) do_status ;;
      5) do_guide ;;
      q|Q|0) echo; msg_ok "Selesai."; exit 0 ;;
      *) msg_warn "Tidak dikenal."; sleep 1 ;;
    esac
  done
}

echo
msg_info "Nextcloud Setup — baca menu 0 dulu sebelum install"
main_menu
