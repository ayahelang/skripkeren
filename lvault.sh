#!/usr/bin/env bash
# Silverhawk Vaultwarden Setup (lvault.sh)
# Password manager self-hosted (kompatibel Bitwarden)
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lvault.sh)
set -u
set -o pipefail

APP="Silverhawk Vaultwarden"
VER="1.0.0"
DOMAIN_DEFAULT="vault.silverhawk.web.id"
INSTALL_DIR="/opt/vaultwarden"
DATA_DIR="/srv/vaultwarden/data"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-vault-$$"
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
    ${C_BOLD}HARDWARE:${C_RESET}
    - Sangat ringan (1 GB RAM lebih dari cukup)

    ${C_BOLD}YANG HARUS SUDAH SIAP (PENTING):${C_RESET}
    - Docker
    - Domain/subdomain dengan HTTPS (Vaultwarden sangat disarankan lewat HTTPS)
      Contoh: vault.silverhawk.web.id
    - Cloudflare Tunnel atau Nginx Proxy Manager + Let's Encrypt

    ${C_BOLD}Script ini TIDAK:${C_RESET}
    - Mengatur DNS / SSL certificate (harus kamu lakukan di Tunnel atau NPM)
    - Mengaktifkan signup admin token secara permanen (keamanan)

    ${C_BOLD}Peringatan keamanan:${C_RESET}
    Password manager menyimpan data sangat sensitif.
    WAJIB pakai HTTPS. Jangan expose HTTP polos ke internet.
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
  echo "    ${C_BOLD}2. Install Vaultwarden${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v docker >/dev/null 2>&1; then msg_err "Docker belum ada."; pause; return; fi

  local domain
  domain=$(ask "    Domain Vaultwarden [${DOMAIN_DEFAULT}]: ")
  [ -z "$domain" ] && domain="$DOMAIN_DEFAULT"

  mkdir -p "$INSTALL_DIR" "$DATA_DIR"
  # Admin token sementara untuk setup awal (bisa dinonaktifkan nanti)
  local admin_token
  admin_token=$(openssl rand -hex 24 2>/dev/null || echo "ganti_admin_token_ini")

  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    ports:
      - "8082:80"
    volumes:
      - ${DATA_DIR}:/data
    environment:
      DOMAIN: "https://${domain}"
      SIGNUPS_ALLOWED: "true"
      ADMIN_TOKEN: "${admin_token}"
EOF

  cd "$INSTALL_DIR"
  docker compose pull
  docker compose up -d

  msg_ok "Vaultwarden jalan di http://IP-SERVER:8082"
  echo "    Domain target : https://${domain}"
  echo "    Admin token   : ${admin_token}"
  echo "    (simpan token ini, dipakai untuk /admin)"
  echo
  msg_warn "Setelah setup selesai, pertimbangkan SIGNUPS_ALLOWED=false"
  pause
}

do_tunnel_info(){
  title
  echo "    ${C_BOLD}3. Cloudflare Tunnel / HTTPS${C_RESET}"
  hr
  cat <<EOF
    Sangat disarankan pakai HTTPS sebelum dipakai serius.

    Cloudflare Tunnel:
    - Subdomain : vault
    - Domain    : silverhawk.web.id
    - Service   : http://localhost:8082

    Atau lewat Nginx Proxy Manager + Let's Encrypt.

    Di app Bitwarden resmi (HP/desktop):
    Settings → Self-hosted → Server URL = https://vault.silverhawk.web.id
EOF
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}4. Status${C_RESET}"
  hr
  docker ps --filter name=vaultwarden --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}5. Panduan & keamanan${C_RESET}"
  hr
  cat <<EOF
    Vaultwarden = server Bitwarden yang ringan.

    Setelah domain + HTTPS aktif:
    1. Buka https://vault... → buat akun
    2. Install app Bitwarden resmi, arahkan ke server kamu
    3. Nonaktifkan signup publik jika hanya untuk pribadi/keluarga
    4. Backup folder data ($DATA_DIR) secara rutin & aman

    Jangan lupa 2FA di akun Vaultwarden.
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — Vaultwarden (Password Manager)${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan & peringatan keamanan (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install Docker"
    echo "    ${C_CYAN}2${C_RESET}. Install Vaultwarden"
    echo "    ${C_CYAN}3${C_RESET}. Panduan HTTPS / Cloudflare Tunnel"
    echo "    ${C_CYAN}4${C_RESET}. Status"
    echo "    ${C_CYAN}5${C_RESET}. Panduan & keamanan"
    echo "    ${C_CYAN}q${C_RESET}. Keluar"
    local p; p=$(ask "    Pilih: ")
    case "$p" in
      0) show_prereq ;; 1) do_docker ;; 2) do_install ;;
      3) do_tunnel_info ;; 4) do_status ;; 5) do_guide ;;
      q|Q) exit 0 ;; *) msg_warn "Tidak dikenal."; sleep 1 ;;
    esac
  done
}

echo; msg_info "Vaultwarden Setup — WAJIB baca menu 0 (HTTPS)"; main_menu
