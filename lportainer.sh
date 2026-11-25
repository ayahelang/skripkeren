#!/usr/bin/env bash
# Silverhawk Portainer Setup (lportainer.sh)
# GUI manajemen Docker
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lportainer.sh)
set -u
set -o pipefail

APP="Silverhawk Portainer"
VER="1.0.0"
INSTALL_DIR="/opt/portainer"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-portainer-$$"
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
    - Sangat ringan

    ${C_BOLD}YANG HARUS SUDAH SIAP:${C_RESET}
    - Docker sudah terinstall dan berjalan
      (kalau belum, pakai menu 1 atau script lain yang sudah install Docker)

    ${C_BOLD}Script ini TIDAK:${C_RESET}
    - Menginstall aplikasi di dalam Docker (hanya memasang Portainer sendiri)
    - Mengatur domain/SSL (bisa digabung dengan Cloudflare Tunnel atau NPM)
EOF
  pause
}

do_docker(){
  title
  echo "    ${C_BOLD}1. Install Docker (jika belum)${C_RESET}"
  hr
  if ! need_root; then return; fi
  if command -v docker >/dev/null 2>&1; then msg_ok "Docker sudah ada: $(docker --version)"
  else
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    [ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER" || true
    msg_ok "Docker terpasang."
  fi
  pause
}

do_install(){
  title
  echo "    ${C_BOLD}2. Install Portainer CE${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v docker >/dev/null 2>&1; then msg_err "Docker belum ada."; pause; return; fi

  docker volume create portainer_data 2>/dev/null || true

  # Hapus container lama jika ada
  docker rm -f portainer 2>/dev/null || true

  docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest

  msg_ok "Portainer berjalan."
  echo "    UI  : https://IP-SERVER:9443"
  echo "    (atau http://IP-SERVER:9000 pada versi lama)"
  echo "    Buat user admin saat pertama kali buka."
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}3. Status${C_RESET}"
  hr
  docker ps --filter name=portainer --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}4. Panduan singkat${C_RESET}"
  hr
  cat <<EOF
    Portainer = dashboard visual untuk Docker.

    Kegunaan:
    - Lihat container, log, stats
    - Deploy stack (compose)
    - Manage volume & network

    Setelah install, amankan:
    - Jangan expose port 9443 ke internet tanpa autentikasi kuat / Tunnel
    - Bisa diarahkan lewat Cloudflare Tunnel atau Nginx Proxy Manager
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — Portainer${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install Docker (jika belum)"
    echo "    ${C_CYAN}2${C_RESET}. Install Portainer CE"
    echo "    ${C_CYAN}3${C_RESET}. Status"
    echo "    ${C_CYAN}4${C_RESET}. Panduan singkat"
    echo "    ${C_CYAN}q${C_RESET}. Keluar"
    local p; p=$(ask "    Pilih: ")
    case "$p" in
      0) show_prereq ;; 1) do_docker ;; 2) do_install ;;
      3) do_status ;; 4) do_guide ;;
      q|Q) exit 0 ;; *) msg_warn "Tidak dikenal."; sleep 1 ;;
    esac
  done
}

echo; msg_info "Portainer Setup"; main_menu
