#!/usr/bin/env bash
# Silverhawk Immich Setup (limmich.sh)
# Google Photos alternatif — self-hosted photo & video backup
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/limmich.sh)
set -u
set -o pipefail

APP="Silverhawk Immich"
VER="1.0.0"
DOMAIN_DEFAULT="foto.silverhawk.web.id"
INSTALL_DIR="/opt/immich"
UPLOAD_DIR="/srv/immich/upload"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-immich-$$"
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
    msg_err "Butuh root/sudo."
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
    - RAM minimal 4 GB (disarankan 8 GB) — Immich memakai model ML untuk face/search
    - CPU multi-core (transcoding & machine learning)
    - Storage BESAR dan cepat (SSD lebih baik) untuk foto/video library
    - Opsional: GPU (NVIDIA) jika ingin percepat ML (tidak wajib)

    ${C_BOLD}YANG HARUS SUDAH SIAP (tidak otomatis oleh script):${C_RESET}
    - Ubuntu Server 22.04 / 24.04 LTS
    - Docker + Docker Compose (bisa diinstall lewat menu 1)
    - Domain/subdomain (contoh: foto.silverhawk.web.id)
    - Akun Cloudflare untuk Tunnel (disarankan)
    - Folder upload permanen di disk yang cukup besar (contoh /srv/immich/upload)
    - HP Android/iOS nanti install app Immich resmi untuk auto-backup

    ${C_BOLD}Peringatan:${C_RESET}
    Immich cukup lapar resource. Jangan dipaksa di laptop 2GB RAM.
EOF
  pause
}

do_docker(){
  title
  echo "    ${C_BOLD}1. Install Docker + Compose${C_RESET}"
  hr
  if ! need_root; then return; fi
  if command -v docker >/dev/null 2>&1; then
    msg_ok "Docker sudah ada."
  else
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    [ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER" || true
  fi
  msg_ok "$(docker --version 2>/dev/null || true)"
  pause
}

do_install(){
  title
  echo "    ${C_BOLD}2. Install Immich (Docker Compose resmi)${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v docker >/dev/null 2>&1; then
    msg_err "Docker belum ada. Menu 1 dulu."; pause; return
  fi

  mkdir -p "$INSTALL_DIR" "$UPLOAD_DIR"
  cd "$INSTALL_DIR"

  if [ ! -f docker-compose.yml ]; then
    msg_info "Mengunduh konfigurasi resmi Immich..."
    curl -fsSL -o docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
    curl -fsSL -o .env https://github.com/immich-app/immich/releases/latest/download/example.env
    # Sesuaikan path upload
    sed -i "s|UPLOAD_LOCATION=.*|UPLOAD_LOCATION=$UPLOAD_DIR|" .env 2>/dev/null || true
    # Generate DB password sederhana jika masih default
    if grep -q "DB_PASSWORD=postgres" .env 2>/dev/null; then
      DBPASS=$(openssl rand -hex 12 2>/dev/null || echo "immich_change_me_$(date +%s)")
      sed -i "s|DB_PASSWORD=postgres|DB_PASSWORD=$DBPASS|" .env
      msg_info "DB_PASSWORD diganti otomatis (cek file .env)."
    fi
  else
    msg_warn "docker-compose.yml sudah ada. Menggunakan yang existing."
  fi

  msg_info "Pull & start Immich (bisa lama pertama kali)..."
  docker compose pull
  docker compose up -d

  msg_ok "Immich dijalankan."
  echo "    Web UI  : http://IP-SERVER:2283"
  echo "    Data    : $UPLOAD_DIR"
  echo "    Domain  : https://${DOMAIN_DEFAULT} (setelah Tunnel)"
  echo
  msg_warn "Pertama kali buka web → buat akun admin. Lalu install app di HP."
  pause
}

do_tunnel_info(){
  title
  echo "    ${C_BOLD}3. Cloudflare Tunnel${C_RESET}"
  hr
  cat <<EOF
    Public Hostname di Cloudflare Tunnel:
    - Subdomain : foto
    - Domain    : silverhawk.web.id
    - Service   : http://localhost:2283

    Domainesia → CNAME foto → xxxxx.cfargotunnel.com

    Setelah domain aktif, di Immich Settings set Server URL ke https://foto.silverhawk.web.id
EOF
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}4. Status${C_RESET}"
  hr
  if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cd "$INSTALL_DIR" && docker compose ps
  else
    msg_warn "Belum terinstall."
  fi
  echo
  df -h "$UPLOAD_DIR" 2>/dev/null || true
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}5. Panduan singkat${C_RESET}"
  hr
  cat <<EOF
    Immich ≈ Google Photos self-hosted (backup otomatis, face recognition, search).

    Alur: 0 → 1 → 2 → 3

    Tips:
    - Biarkan machine learning selesai index dulu (bisa berjam-jam di library besar)
    - Backup folder $UPLOAD_DIR secara rutin
    - App resmi Android/iOS ada di GitHub Immich / Play Store (cek rilis)
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — Immich (Google Photos alternatif)${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan hardware & aplikasi (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install Docker"
    echo "    ${C_CYAN}2${C_RESET}. Install / Jalankan Immich"
    echo "    ${C_CYAN}3${C_RESET}. Panduan Cloudflare Tunnel"
    echo "    ${C_CYAN}4${C_RESET}. Status"
    echo "    ${C_CYAN}5${C_RESET}. Panduan singkat"
    echo "    ${C_CYAN}q${C_RESET}. Keluar"
    local p; p=$(ask "    Pilih: ")
    case "$p" in
      0) show_prereq ;;
      1) do_docker ;;
      2) do_install ;;
      3) do_tunnel_info ;;
      4) do_status ;;
      5) do_guide ;;
      q|Q) exit 0 ;;
      *) msg_warn "Tidak dikenal."; sleep 1 ;;
    esac
  done
}

echo; msg_info "Immich Setup — baca menu 0 (hardware) dulu"; main_menu
