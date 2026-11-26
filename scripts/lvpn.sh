#!/usr/bin/env bash
# Silverhawk WireGuard VPN Setup (lvpn.sh)
# VPN server ringan untuk akses aman ke rumah/kantor
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lvpn.sh)

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
  sk_ensure_basic curl || {
    echo "Dependency belum lengkap. Selesaikan install di atas lalu jalankan ulang."
    exit 1
  }
fi

set -o pipefail

APP="Silverhawk WireGuard VPN"
VER="1.0.0"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-vpn-$$"
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
    - Hampir semua hardware cukup (WireGuard sangat ringan)
    - RAM 1 GB sudah memadai untuk VPN server sederhana

    ${C_BOLD}YANG HARUS SUDAH SIAP (penting!):${C_RESET}
    - Ubuntu Server sudah terinstall
    - Salah satu cara agar client bisa connect dari internet:

      A. Punya IP Public + bisa buka/forward port UDP 51820
         (router rumah harus support port forwarding)

      B. ATAU pakai Cloudflare Tunnel / Tunnel lain (lebih rumit untuk VPN)
         WireGuard murni lebih cocok dengan port forward klasik.

      C. ATAU pakai Tailscale / Headscale (overlay, beda pendekatan)

    - Client (HP/laptop) nanti install aplikasi WireGuard resmi

    ${C_BOLD}Script ini TIDAK bisa:${C_RESET}
    - Mengatur port forwarding di router rumah kamu
    - Memberi IP Public jika ISP kamu di belakang CGNAT
    - Menggantikan akun Cloudflare / domain (untuk kasus non-klasik)

    Jika rumah kamu di belakang CGNAT (banyak ISP Indonesia),
    pertimbangkan Tailscale (mudah) atau VPS sebagai entry point.
EOF
  pause
}

do_install_wg(){
  title
  echo "    ${C_BOLD}1. Install WireGuard${C_RESET}"
  hr
  if ! need_root; then return; fi

  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard wireguard-tools qrencode

  msg_ok "WireGuard terpasang."
  wg --version 2>/dev/null || true
  pause
}

do_quick_server(){
  title
  echo "    ${C_BOLD}2. Generate Server Config Cepat${C_RESET}"
  hr
  if ! need_root; then return; fi
  if ! command -v wg >/dev/null 2>&1; then
    msg_err "WireGuard belum terinstall. Menu 1 dulu."; pause; return
  fi

  mkdir -p /etc/wireguard
  if [ -f /etc/wireguard/wg0.conf ]; then
    msg_warn "File /etc/wireguard/wg0.conf sudah ada."
    if ! [[ "$(ask "    Timpa? [y/N]: ")" =~ ^[Yy]$ ]]; then pause; return; fi
  fi

  local priv pub
  priv=$(wg genkey)
  pub=$(printf '%s' "$priv" | wg pubkey)

  local endpoint
  endpoint=$(ask "    Endpoint publik (IP atau domain) [contoh 103.x.x.x atau vpn.domain.com]: ")
  [ -z "$endpoint" ] && endpoint="GANTI_DENGAN_IP_ATAU_DOMAIN"

  cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.10.10.1/24
ListenPort = 51820
PrivateKey = $priv
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o \$(ip route | awk '/default/ {print \$5; exit}') -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o \$(ip route | awk '/default/ {print \$5; exit}') -j MASQUERADE

# Client contoh (ganti PrivateKey client & tambah Peer di server)
# [Peer]
# PublicKey = CLIENT_PUBLIC_KEY
# AllowedIPs = 10.10.10.2/32
EOF

  chmod 600 /etc/wireguard/wg0.conf
  echo "$pub" > /etc/wireguard/server_public.key

  # Enable IP forward
  sysctl -w net.ipv4.ip_forward=1
  grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  systemctl enable --now wg-quick@wg0

  msg_ok "Interface wg0 aktif."
  echo "    Server Public Key : $pub"
  echo "    Config            : /etc/wireguard/wg0.conf"
  echo "    Endpoint          : ${endpoint}:51820"
  echo
  msg_warn "Masih perlu: buka/forward UDP 51820 di router + buat peer client."
  pause
}

do_add_client_help(){
  title
  echo "    ${C_BOLD}3. Cara menambah Client${C_RESET}"
  hr
  cat <<EOF
    1. Di server:
       wg genkey | tee client1.key | wg pubkey > client1.pub

    2. Tambah di /etc/wireguard/wg0.conf (atau lewat wg set):

       [Peer]
       PublicKey = (isi client1.pub)
       AllowedIPs = 10.10.10.2/32

    3. Buat file config untuk client (client1.conf):

       [Interface]
       PrivateKey = (isi client1.key)
       Address = 10.10.10.2/24
       DNS = 1.1.1.1

       [Peer]
       PublicKey = (server public key)
       Endpoint = IP-ATAU-DOMAIN:51820
       AllowedIPs = 0.0.0.0/0
       PersistentKeepalive = 25

    4. Import client1.conf ke aplikasi WireGuard di HP/laptop.
       Bisa juga generate QR: qrencode -t ansiutf8 < client1.conf
EOF
  pause
}

do_status(){
  title
  echo "    ${C_BOLD}4. Status WireGuard${C_RESET}"
  hr
  wg show 2>/dev/null || msg_warn "Interface belum aktif."
  echo
  systemctl status wg-quick@wg0 --no-pager 2>/dev/null | head -15 || true
  pause
}

do_guide(){
  title
  echo "    ${C_BOLD}5. Panduan & peringatan CGNAT${C_RESET}"
  hr
  cat <<EOF
    WireGuard sangat cepat & ringan.

    Masalah umum di Indonesia:
    - Banyak ISP memakai CGNAT → rumah tidak punya IP Public murni
      → port forwarding gagal.

    Solusi jika CGNAT:
    1. Pakai Tailscale (paling mudah, ada free tier)
    2. Sewa VPS murah sebagai entry, lalu site-to-site
    3. ZeroTier

    Script ini fokus WireGuard klasik (butuh IP Public + UDP 51820).
EOF
  pause
}

main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU — WireGuard VPN${C_RESET}"
    echo
    echo "    ${C_CYAN}0${C_RESET}. Persyaratan hardware & jaringan (WAJIB DIBACA)"
    echo "    ${C_CYAN}1${C_RESET}. Install WireGuard"
    echo "    ${C_CYAN}2${C_RESET}. Generate server config cepat + aktifkan"
    echo "    ${C_CYAN}3${C_RESET}. Cara menambah client"
    echo "    ${C_CYAN}4${C_RESET}. Status"
    echo "    ${C_CYAN}5${C_RESET}. Panduan & catatan CGNAT"
    echo "    ${C_CYAN}q${C_RESET}. Keluar"
    local p; p=$(ask "    Pilih: ")
    case "$p" in
      0) show_prereq ;; 1) do_install_wg ;; 2) do_quick_server ;;
      3) do_add_client_help ;; 4) do_status ;; 5) do_guide ;;
      q|Q) exit 0 ;; *) msg_warn "Tidak dikenal."; sleep 1 ;;
    esac
  done
}

echo; msg_info "WireGuard VPN — baca menu 0 (terutama soal IP Public/CGNAT)"; main_menu
