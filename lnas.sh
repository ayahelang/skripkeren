#!/usr/bin/env bash
# Silverhawk Home NAS Setup (lnas.sh)
# Setup NAS rumahan berbasis CasaOS di Ubuntu Server
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lnas.sh)
# Bisa digabung dengan lserver.sh (subdomain terpisah, contoh: nas.silverhawk.web.id)
set -u
set -o pipefail

APP="Silverhawk Home NAS"
VER="1.0.0"
NAS_DOMAIN_DEFAULT="nas.silverhawk.web.id"
CASA_PORT="80"          # CasaOS default web UI

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-lnas-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ---------- TTY-safe input ----------
TTY=/dev/tty
if [ ! -c "$TTY" ] || [ ! -r "$TTY" ] || [ ! -w "$TTY" ]; then
  TTY=/dev/stdin
fi
ask(){ local _a; printf "%s" "$1" >"$TTY"; IFS= read -r _a <"$TTY" || true; printf "%s" "$_a"; }
ask_secret(){ local _a; printf "%s" "$1" >"$TTY"; IFS= read -r -s _a <"$TTY" || true; printf "\n" >"$TTY"; printf "%s" "$_a"; }

# ---------- Terminal UI ----------
if [ -t 1 ] || [ -t 2 ]; then
  C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_WHITE=$'\033[97m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_CYAN=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_WHITE=""; C_DIM=""; C_BOLD=""
fi
beep(){ printf '\a' 2>/dev/null || true; }
msg_ok(){ echo "${C_GREEN}✔ $*${C_RESET}"; }
msg_warn(){ echo "${C_YELLOW}⚠ $*${C_RESET}"; }
msg_err(){ echo "${C_RED}✖ $*${C_RESET}" >&2; beep; }
msg_info(){ echo "${C_CYAN}ℹ $*${C_RESET}"; }
hr(){ printf '%s\n' "${C_DIM}    ────────────────────────────────────────────────────────────────────────────────${C_RESET}"; }
pause(){ echo; ask "    Tekan Enter untuk melanjutkan... " >/dev/null; }

title(){
  clear 2>/dev/null || true
  echo
  echo "    ${C_CYAN}${C_BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
  printf "    ${C_CYAN}${C_BOLD}║ %-76s ║${C_RESET}\n" "$APP v$VER"
  echo "    ${C_CYAN}${C_BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo "    ${C_DIM}Target contoh : ${NAS_DOMAIN_DEFAULT}    OS: $(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release 2>/dev/null | tr -d '"' || uname -s)${C_RESET}"
  hr
}

need_root(){
  if [ "$(id -u)" -ne 0 ]; then
    msg_err "Menu ini membutuhkan akses root/sudo."
    echo "    Jalankan: sudo bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lnas.sh)"
    pause
    return 1
  fi
  return 0
}

confirm(){
  local q="${1:-Lanjut?}"
  local a
  a=$(ask "    $q [y/N]: ")
  [[ "$a" =~ ^[Yy]$ ]]
}

# ---------- 1. Persiapan sistem ----------
do_prepare(){
  title
  echo "    ${C_BOLD}1. Persiapan Sistem (update + tools)${C_RESET}"
  hr
  if ! need_root; then return; fi

  msg_info "Update & upgrade..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  msg_info "Install paket pendukung..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git unzip jq htop net-tools ufw fail2ban \
    ca-certificates gnupg lsb-release smartmontools ntfs-3g \
    samba samba-common-bin cifs-utils

  msg_ok "Persiapan selesai."
  pause
}

# ---------- 2. Firewall dasar ----------
do_firewall(){
  title
  echo "    ${C_BOLD}2. Firewall (UFW) untuk NAS${C_RESET}"
  hr
  if ! need_root; then return; fi

  ufw allow OpenSSH
  ufw allow 80/tcp          # CasaOS web UI
  ufw allow 443/tcp
  ufw allow 445/tcp         # Samba
  ufw allow 139/tcp         # Samba
  # Port tambahan CasaOS / Docker biasanya internal

  echo "y" | ufw enable || true
  ufw status verbose

  systemctl enable --now fail2ban 2>/dev/null || true
  msg_ok "Firewall siap (SSH, HTTP/HTTPS, Samba)."
  msg_warn "Kalau pakai Cloudflare Tunnel, port 80/443 bisa ditutup dari luar nanti."
  pause
}

# ---------- 3. Install Docker (wajib untuk CasaOS) ----------
do_docker(){
  title
  echo "    ${C_BOLD}3. Install Docker${C_RESET}"
  hr
  if ! need_root; then return; fi

  if command -v docker >/dev/null 2>&1; then
    msg_ok "Docker sudah terpasang: $(docker --version)"
  else
    msg_info "Menginstall Docker resmi..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    if [ -n "${SUDO_USER:-}" ]; then
      usermod -aG docker "$SUDO_USER" || true
      msg_info "User $SUDO_USER ditambahkan ke grup docker."
    fi
    msg_ok "Docker terpasang."
  fi
  docker --version || true
  pause
}

# ---------- 4. Install CasaOS ----------
do_install_casaos(){
  title
  echo "    ${C_BOLD}4. Install CasaOS${C_RESET}"
  hr
  if ! need_root; then return; fi

  if [ -d /var/lib/casaos ] || command -v casaos >/dev/null 2>&1 || docker ps -a 2>/dev/null | grep -qi casa; then
    msg_warn "CasaOS sepertinya sudah terpasang / pernah diinstall."
    if ! confirm "Tetap jalankan installer resmi?"; then
      pause
      return
    fi
  fi

  msg_info "Menjalankan installer resmi CasaOS..."
  echo "    Sumber: https://get.casaos.io"
  echo
  # Installer resmi CasaOS
  curl -fsSL https://get.casaos.io | bash

  echo
  msg_ok "Installer CasaOS selesai."
  echo "    Web UI biasanya di: http://IP-LOKAL:80  atau  http://IP-LOKAL"
  echo "    Buat akun admin saat pertama kali buka."
  echo
  msg_info "Cek status container:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -20 || true
  pause
}

# ---------- 5. Storage & disk ----------
do_storage_info(){
  title
  echo "    ${C_BOLD}5. Info Storage & Disk${C_RESET}"
  hr

  echo "    ${C_BOLD}Disk & partisi${C_RESET}"
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL,SERIAL 2>/dev/null || lsblk
  echo
  echo "    ${C_BOLD}Penggunaan ruang${C_RESET}"
  df -hT | grep -E 'Filesystem|/dev/'
  echo
  echo "    ${C_BOLD}Saran untuk NAS rumahan${C_RESET}"
  echo "    - Pakai disk terpisah (HDD/SSD eksternal atau internal tambahan) untuk data."
  echo "    - Format ext4 (Linux native) atau NTFS jika sering diakses Windows."
  echo "    - Mount permanen lewat /etc/fstab."
  echo "    - Di CasaOS: Storage → mount disk → buat share."
  echo
  msg_info "Perintah berguna:"
  echo "      lsblk -f"
  echo "      blkid"
  echo "      smartctl -a /dev/sdX    (butuh smartmontools)"
  echo
  pause
}

# ---------- 6. Samba cepat (opsional, di luar CasaOS) ----------
do_samba_basic(){
  title
  echo "    ${C_BOLD}6. Samba Share Cepat (opsional)${C_RESET}"
  hr
  if ! need_root; then return; fi

  local share_path share_name
  share_path=$(ask "    Path folder yang mau di-share [/srv/nas]: ")
  [ -z "$share_path" ] && share_path="/srv/nas"
  share_name=$(ask "    Nama share [nas]: ")
  [ -z "$share_name" ] && share_name="nas"

  mkdir -p "$share_path"
  chmod 2775 "$share_path"

  if ! grep -q "\[$share_name\]" /etc/samba/smb.conf 2>/dev/null; then
    cat >> /etc/samba/smb.conf <<EOF

[$share_name]
   path = $share_path
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0664
   directory mask = 0775
EOF
    msg_ok "Share [$share_name] ditambahkan."
  else
    msg_warn "Share [$share_name] sudah ada di smb.conf."
  fi

  echo
  msg_info "Buat user Samba (bisa sama dengan user Linux):"
  local smbuser
  smbuser=$(ask "    Username Samba [${SUDO_USER:-nasuser}]: ")
  [ -z "$smbuser" ] && smbuser="${SUDO_USER:-nasuser}"
  if id "$smbuser" >/dev/null 2>&1; then
    smbpasswd -a "$smbuser" || true
  else
    msg_warn "User $smbuser belum ada di sistem. Buat dulu dengan: adduser $smbuser"
  fi

  systemctl enable --now smbd nmbd
  systemctl restart smbd
  msg_ok "Samba aktif. Akses dari Windows: \\\\IP-SERVER\\$share_name"
  pause
}

# ---------- 7. Cloudflare Tunnel untuk NAS ----------
do_cloudflare_nas(){
  title
  echo "    ${C_BOLD}7. Cloudflare Tunnel untuk NAS${C_RESET}"
  echo "    Contoh subdomain: ${C_CYAN}${NAS_DOMAIN_DEFAULT}${C_RESET}"
  hr
  if ! need_root; then return; fi

  if ! command -v cloudflared >/dev/null 2>&1; then
    msg_info "cloudflared belum ada. Menginstall..."
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y
    apt-get install -y cloudflared
  fi

  echo
  echo "    Panduan singkat (Nameserver tetap di Domainesia):"
  echo "    1. Cloudflare Zero Trust → Networks → Tunnels → Create"
  echo "    2. Public Hostname:"
  echo "       - Subdomain : nas   (atau sesuai keinginan)"
  echo "       - Domain    : silverhawk.web.id"
  echo "       - Service   : http://localhost:80   (CasaOS)"
  echo "    3. Di Domainesia → DNS → CNAME:"
  echo "       Name   : nas"
  echo "       Target : xxxxx.cfargotunnel.com  (dari Cloudflare)"
  echo
  echo "    [1] Install / update service cloudflared dari token"
  echo "    [2] Hanya lihat panduan"
  echo "    [0] Kembali"
  local c
  c=$(ask "    Pilihan: ")
  case "$c" in
    1)
      local token_cmd
      token_cmd=$(ask "    Tempel perintah 'cloudflared service install ...' atau token saja: ")
      if [ -z "$token_cmd" ]; then
        msg_err "Kosong."; pause; return
      fi
      if echo "$token_cmd" | grep -q "cloudflared service install"; then
        eval "$token_cmd"
      else
        cloudflared service install "$token_cmd"
      fi
      systemctl enable --now cloudflared || true
      systemctl status cloudflared --no-pager || true
      msg_ok "Service cloudflared dipasang."
      ;;
    2) msg_info "OK, ikuti panduan di atas." ;;
    *) return ;;
  esac
  pause
}

# ---------- 8. Status ----------
do_status(){
  title
  echo "    ${C_BOLD}8. Status NAS${C_RESET}"
  hr

  echo "    ${C_BOLD}Sistem${C_RESET}"
  echo "    Hostname : $(hostname)"
  echo "    Uptime   : $(uptime -p 2>/dev/null || uptime)"
  echo "    Disk /   : $(df -h / | awk 'NR==2{print $3" / "$2" ("$5")"}')"
  echo

  echo "    ${C_BOLD}Layanan${C_RESET}"
  for svc in docker smbd nmbd cloudflared ufw fail2ban; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      echo "    ${C_GREEN}●${C_RESET} $svc"
    else
      echo "    ${C_DIM}○${C_RESET} $svc"
    fi
  done
  echo

  if command -v docker >/dev/null 2>&1; then
    echo "    ${C_BOLD}Container Docker (CasaOS & apps)${C_RESET}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -25 || echo "    (tidak ada / docker tidak jalan)"
  fi
  echo
  pause
}

# ---------- 9. Panduan & tips ----------
do_guide(){
  title
  echo "    ${C_BOLD}9. Panduan & Tips Home NAS${C_RESET}"
  hr
  cat <<EOF
    Aplikasi yang dipilih: ${C_BOLD}CasaOS${C_RESET}

    Kenapa CasaOS?
    - UI modern, mudah dipakai
    - App Store berbasis Docker (Nextcloud, Jellyfin, PhotoPrism, dll.)
    - Cocok laptop/PC rumahan
    - Bisa digabung dengan lserver.sh (PocketBase di subdomain lain)

    Alur instalasi yang disarankan:
    1 → 2 → 3 → 4 → (5 cek disk) → 7 (kalau mau akses dari internet)

    Setelah CasaOS jalan:
    - Buka http://IP-LOKAL di browser
    - Buat akun admin
    - Storage → pasang disk data
    - App Store → install yang dibutuhkan (file browser, media, backup, dll.)

    Domain (contoh):
    - nas.silverhawk.web.id  → CasaOS (lewat Cloudflare Tunnel)
    - lserver.silverhawk.web.id → PocketBase / CRM (dari lserver.sh)

    Nameserver tetap di Domainesia. Hanya tambah CNAME per subdomain.

    Backup penting:
    - Data user (folder share)
    - Konfigurasi CasaOS (biasanya di /var/lib/casaos)
    - Jangan lupa UPS / shutdown yang benar agar disk aman

EOF
  pause
}

# ---------- Main menu ----------
main_menu(){
  while true; do
    title
    echo "    ${C_BOLD}MENU UTAMA — Home NAS (CasaOS)${C_RESET}"
    echo
    echo "    ${C_CYAN}1${C_RESET}. Persiapan sistem (update + tools)"
    echo "    ${C_CYAN}2${C_RESET}. Firewall UFW (SSH, web, Samba)"
    echo "    ${C_CYAN}3${C_RESET}. Install Docker"
    echo "    ${C_CYAN}4${C_RESET}. Install CasaOS"
    echo "    ${C_CYAN}5${C_RESET}. Info storage & disk"
    echo "    ${C_CYAN}6${C_RESET}. Samba share cepat (opsional)"
    echo "    ${C_CYAN}7${C_RESET}. Cloudflare Tunnel untuk NAS"
    echo "    ${C_CYAN}8${C_RESET}. Status layanan & container"
    echo "    ${C_CYAN}9${C_RESET}. Panduan & tips"
    echo "    ${C_CYAN}0${C_RESET}. Keluar"
    echo
    local p
    p=$(ask "    Pilih nomor: ")
    case "$p" in
      1) do_prepare ;;
      2) do_firewall ;;
      3) do_docker ;;
      4) do_install_casaos ;;
      5) do_storage_info ;;
      6) do_samba_basic ;;
      7) do_cloudflare_nas ;;
      8) do_status ;;
      9) do_guide ;;
      0) echo; msg_ok "Selesai. Selamat memakai NAS rumahan."; echo; exit 0 ;;
      *) msg_warn "Pilihan tidak dikenal."; sleep 1 ;;
    esac
  done
}

# ---------- Entry ----------
echo
msg_info "Silverhawk Home NAS — CasaOS di Ubuntu Server"
msg_info "Jalankan dengan: sudo bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lnas.sh)"
echo
main_menu
