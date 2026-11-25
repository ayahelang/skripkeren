#!/usr/bin/env bash
# Silverhawk Home Server Setup (lserver.sh)
# Setup Ubuntu Server rumahan + Cloudflare Tunnel + PocketBase + tools
# Online: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lserver.sh)
# Target subdomain: lserver.silverhawk.web.id
set -u
set -o pipefail

APP="Silverhawk Home Server"
VER="1.0.0"
DOMAIN_DEFAULT="lserver.silverhawk.web.id"
PB_DIR="/opt/pocketbase"
PB_DATA="/var/lib/pocketbase/pb_data"
CF_CONFIG_DIR="/etc/cloudflared"

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-lserver-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ---------- TTY-safe input (aman di curl|bash) ----------
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
  echo "    ${C_DIM}Target : ${DOMAIN_DEFAULT}    OS: $(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release 2>/dev/null | tr -d '"' || uname -s)${C_RESET}"
  hr
}

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { msg_err "Perintah '$1' tidak ditemukan."; return 1; }; }
need_root(){
  if [ "$(id -u)" -ne 0 ]; then
    msg_err "Menu ini membutuhkan akses root/sudo."
    echo "    Jalankan ulang dengan: sudo bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lserver.sh)"
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

# ---------- Deteksi lingkungan ----------
detect_os(){
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VER="${VERSION_ID:-}"
  else
    OS_ID="unknown"
    OS_VER=""
  fi
}

# ---------- Menu 1: Update sistem + tools dasar ----------
do_update_system(){
  title
  echo "    ${C_BOLD}1. Update Sistem + Install Tools Dasar${C_RESET}"
  hr
  if ! need_root; then return; fi

  msg_info "Menjalankan apt update & upgrade..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  msg_info "Menginstall paket dasar..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git unzip jq htop net-tools ufw fail2ban \
    ca-certificates gnupg lsb-release software-properties-common \
    openssh-server

  msg_ok "Update sistem dan tools dasar selesai."
  pause
}

# ---------- Menu 2: Firewall + Fail2ban ----------
do_firewall(){
  title
  echo "    ${C_BOLD}2. Setup Firewall (UFW) + Fail2ban${C_RESET}"
  hr
  if ! need_root; then return; fi

  msg_info "Mengaktifkan UFW..."
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  # Jangan buka port lain kecuali memang dibutuhkan
  echo "y" | ufw enable || true
  ufw status verbose

  msg_info "Mengaktifkan Fail2ban..."
  systemctl enable --now fail2ban
  systemctl status fail2ban --no-pager || true

  msg_ok "Firewall & Fail2ban aktif."
  msg_warn "Port 80/443 dibuka. Jika pakai Cloudflare Tunnel, bisa ditutup lagi nanti."
  pause
}

# ---------- Menu 3: Install Docker ----------
do_install_docker(){
  title
  echo "    ${C_BOLD}3. Install Docker${C_RESET}"
  hr
  if ! need_root; then return; fi

  if command -v docker >/dev/null 2>&1; then
    msg_ok "Docker sudah terpasang: $(docker --version)"
    pause
    return
  fi

  msg_info "Menginstall Docker resmi..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker

  # Tambah user saat ini ke grup docker (jika bukan root murni)
  if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "$SUDO_USER" || true
    msg_info "User $SUDO_USER ditambahkan ke grup docker (logout/login agar aktif)."
  fi

  msg_ok "Docker terpasang."
  docker --version || true
  pause
}

# ---------- Menu 4: Cloudflare Tunnel ----------
do_cloudflare_tunnel(){
  title
  echo "    ${C_BOLD}4. Setup Cloudflare Tunnel${C_RESET}"
  echo "    Target subdomain: ${C_CYAN}${DOMAIN_DEFAULT}${C_RESET}"
  hr
  if ! need_root; then return; fi

  msg_info "Langkah ini membutuhkan akun Cloudflare + domain sudah di-DNS Domainesia."
  echo
  echo "    Ringkasan cara yang benar (tanpa ubah Nameserver):"
  echo "    1. Buat Tunnel di dashboard Cloudflare → Zero Trust → Networks → Tunnels"
  echo "    2. Beri nama misalnya: silverhawk-lserver"
  echo "    3. Cloudflare akan kasih perintah install cloudflared + token"
  echo "    4. Setelah tunnel jalan, buat Public Hostname:"
  echo "       - Subdomain : lserver"
  echo "       - Domain    : silverhawk.web.id"
  echo "       - Service   : http://localhost:8090   (untuk PocketBase)"
  echo "                     atau http://localhost:80 (untuk Nginx)"
  echo "    5. Di Domainesia → DNS → tambah CNAME:"
  echo "       Name: lserver"
  echo "       Target: (hostname yang diberikan Cloudflare, biasanya xxx.cfargotunnel.com)"
  echo
  echo "    ${C_YELLOW}Catatan:${C_RESET} Nameserver tetap di Domainesia. Jangan diganti ke Cloudflare"
  echo "    supaya subdomain GitHub Pages lain tidak terganggu."
  echo

  if ! command -v cloudflared >/dev/null 2>&1; then
    msg_info "Menginstall cloudflared..."
    # Cara resmi via apt repo Cloudflare
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y
    apt-get install -y cloudflared
    msg_ok "cloudflared terpasang: $(cloudflared --version 2>/dev/null || true)"
  else
    msg_ok "cloudflared sudah ada: $(cloudflared --version 2>/dev/null || true)"
  fi

  echo
  echo "    Pilihan selanjutnya:"
  echo "    [1] Install service dari token (paling mudah - copy dari dashboard Cloudflare)"
  echo "    [2] Hanya tampilkan panduan (saya sudah punya tunnel)"
  echo "    [0] Kembali"
  local c
  c=$(ask "    Pilihan: ")

  case "$c" in
    1)
      echo
      msg_info "Di dashboard Cloudflare → Tunnel → Install connector → copy perintah yang ada token-nya."
      echo "    Contoh bentuknya:"
      echo "    sudo cloudflared service install eyJhIjoi....token...."
      echo
      local token_cmd
      token_cmd=$(ask "    Tempel perintah lengkap (atau hanya token-nya): ")
      if [ -z "$token_cmd" ]; then
        msg_err "Kosong. Dibatalkan."
        pause
        return
      fi
      # Jika user tempel full command
      if echo "$token_cmd" | grep -q "cloudflared service install"; then
        eval "$token_cmd"
      else
        cloudflared service install "$token_cmd"
      fi
      systemctl enable --now cloudflared || true
      systemctl status cloudflared --no-pager || true
      msg_ok "Service cloudflared dipasang. Lanjut buat Public Hostname di dashboard."
      ;;
    2)
      msg_info "OK. Pastikan Public Hostname mengarah ke service lokal yang benar."
      ;;
    *)
      return
      ;;
  esac
  pause
}

# ---------- Menu 5: Install PocketBase ----------
do_install_pocketbase(){
  title
  echo "    ${C_BOLD}5. Install PocketBase (Real-time Database / CRM)${C_RESET}"
  hr
  if ! need_root; then return; fi

  local PB_VERSION="0.22.21"   # bisa diganti versi terbaru nanti
  local ARCH="amd64"
  case "$(uname -m)" in
    aarch64|arm64) ARCH="arm64" ;;
    x86_64|amd64)  ARCH="amd64" ;;
    *) msg_warn "Arsitektur $(uname -m) belum diuji. Coba amd64." ;;
  esac

  msg_info "Membuat user & direktori..."
  id pocketbase >/dev/null 2>&1 || useradd -r -d "$PB_DIR" -s /usr/sbin/nologin pocketbase
  mkdir -p "$PB_DIR" "$PB_DATA"
  chown -R pocketbase:pocketbase "$PB_DIR" "$PB_DATA"

  if [ -x "$PB_DIR/pocketbase" ]; then
    msg_ok "PocketBase binary sudah ada."
  else
    msg_info "Mengunduh PocketBase v${PB_VERSION} (${ARCH})..."
    cd /tmp
    curl -fsSL -o pb.zip "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${ARCH}.zip"
    unzip -o pb.zip -d "$PB_DIR"
    chmod +x "$PB_DIR/pocketbase"
    chown pocketbase:pocketbase "$PB_DIR/pocketbase"
    rm -f pb.zip
    msg_ok "Binary terpasang."
  fi

  # Systemd unit
  cat > /etc/systemd/system/pocketbase.service <<EOF
[Unit]
Description=PocketBase (Silverhawk Home Server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pocketbase
Group=pocketbase
WorkingDirectory=$PB_DIR
ExecStart=$PB_DIR/pocketbase serve --http=127.0.0.1:8090 --dir=$PB_DATA
Restart=on-failure
RestartSec=5
LimitNOFILE=4096
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now pocketbase
  sleep 1
  systemctl status pocketbase --no-pager || true

  echo
  msg_ok "PocketBase berjalan di http://127.0.0.1:8090"
  echo "    Dashboard admin : http://127.0.0.1:8090/_/"
  echo "    Setelah Cloudflare Tunnel + Public Hostname aktif,"
  echo "    akses dari luar  : https://${DOMAIN_DEFAULT}/_/"
  echo
  msg_info "Pertama kali buka dashboard, buat akun Superuser."
  pause
}

# ---------- Menu 6: Nginx reverse proxy (opsional) ----------
do_nginx(){
  title
  echo "    ${C_BOLD}6. Install Nginx (opsional reverse proxy)${C_RESET}"
  hr
  if ! need_root; then return; fi

  if ! command -v nginx >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  fi

  cat > /etc/nginx/sites-available/pocketbase <<'EOF'
server {
    listen 80;
    server_name lserver.silverhawk.web.id;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/pocketbase /etc/nginx/sites-enabled/pocketbase
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
  systemctl enable nginx

  msg_ok "Nginx siap sebagai reverse proxy ke PocketBase (port 80)."
  msg_info "Jika pakai Cloudflare Tunnel, arahkan Public Hostname ke http://localhost:80"
  pause
}

# ---------- Menu 7: Status ----------
do_status(){
  title
  echo "    ${C_BOLD}7. Status Layanan${C_RESET}"
  hr

  echo "    ${C_BOLD}Sistem${C_RESET}"
  echo "    Hostname : $(hostname)"
  echo "    Uptime   : $(uptime -p 2>/dev/null || uptime)"
  echo "    Disk     : $(df -h / | awk 'NR==2{print $3" dipakai / "$2" total ("$5")"}')"
  echo

  echo "    ${C_BOLD}Layanan${C_RESET}"
  for svc in ssh ufw fail2ban docker cloudflared pocketbase nginx; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      echo "    ${C_GREEN}●${C_RESET} $svc  (active)"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
      echo "    ${C_YELLOW}○${C_RESET} $svc  (installed, not active)"
    else
      echo "    ${C_DIM}○${C_RESET} $svc  (not installed)"
    fi
  done
  echo

  if command -v cloudflared >/dev/null 2>&1; then
    echo "    cloudflared : $(cloudflared --version 2>/dev/null | head -1)"
  fi
  if [ -x "$PB_DIR/pocketbase" ]; then
    echo "    PocketBase  : $($PB_DIR/pocketbase --version 2>/dev/null || echo 'binary ada')"
  fi
  echo
  pause
}

# ---------- Menu 8: Info CRM + PocketBase ----------
do_crm_info(){
  title
  echo "    ${C_BOLD}8. Info CRM & Contoh Collection PocketBase${C_RESET}"
  hr
  cat <<EOF
    CRM = Customer Relationship Management
    Sistem untuk mengelola hubungan dengan pelanggan/pembeli.

    Untuk Facebook Marketplace, contoh collection di PocketBase:

    1. collection: listings
       - title (text)
       - price (number)
       - status (select: draft, active, reserved, sold)
       - fb_url (url)
       - notes (text)
       - photos (file, multiple)

    2. collection: customers
       - name (text)
       - phone (text)
       - fb_profile (url)
       - notes (text)

    3. collection: deals
       - listing (relation → listings)
       - customer (relation → customers)
       - agreed_price (number)
       - status (select: negotiating, agreed, paid, done, cancelled)
       - chat_log (text)
       - meetup_date (date)

    Setelah PocketBase jalan:
    - Buka https://${DOMAIN_DEFAULT}/_/
    - Buat Superuser
    - Buat collection di atas sesuai kebutuhan
    - Atur API Rules (siapa yang boleh baca/tulis)

EOF
  pause
}

# ---------- Menu 9: Panduan Domain (Domainesia) ----------
do_domain_guide(){
  title
  echo "    ${C_BOLD}9. Panduan DNS Domainesia (tanpa ubah Nameserver)${C_RESET}"
  hr
  cat <<EOF
    Domain kamu: silverhawk.web.id (sewa di Domainesia)
    Sudah dipakai banyak subdomain GitHub Pages.

    CARA AMAN menambahkan lserver.silverhawk.web.id:

    1. Jangan ubah Nameserver domain.
    2. Login Domainesia → Domain → kelola silverhawk.web.id → DNS / Zone Editor.
    3. Tambah record:

       Type   : CNAME
       Name   : lserver
       Target : (hostname dari Cloudflare Tunnel, contoh: xxxxx.cfargotunnel.com)
       TTL    : Auto / 3600

    4. Di Cloudflare Zero Trust → Tunnels → Public Hostname:
       - Subdomain : lserver
       - Domain    : silverhawk.web.id
       - Service   : http://localhost:8090   (PocketBase langsung)
                     atau http://localhost:80 (kalau pakai Nginx)

    Hasilnya:
    - skripkeren.silverhawk.web.id  → tetap GitHub Pages
    - lserver.silverhawk.web.id     → server rumahan kamu
    - Subdomain lain tidak terganggu

EOF
  pause
}

# ---------- Main menu ----------
main_menu(){
  detect_os
  while true; do
    title
    echo "    ${C_BOLD}MENU UTAMA${C_RESET}"
    echo
    echo "    ${C_CYAN}1${C_RESET}. Update sistem + install tools dasar"
    echo "    ${C_CYAN}2${C_RESET}. Setup Firewall (UFW) + Fail2ban"
    echo "    ${C_CYAN}3${C_RESET}. Install Docker"
    echo "    ${C_CYAN}4${C_RESET}. Setup Cloudflare Tunnel  →  ${DOMAIN_DEFAULT}"
    echo "    ${C_CYAN}5${C_RESET}. Install PocketBase (Real-time DB / CRM)"
    echo "    ${C_CYAN}6${C_RESET}. Install Nginx (reverse proxy opsional)"
    echo "    ${C_CYAN}7${C_RESET}. Status layanan"
    echo "    ${C_CYAN}8${C_RESET}. Info CRM + contoh collection Marketplace"
    echo "    ${C_CYAN}9${C_RESET}. Panduan DNS Domainesia (tanpa ubah NS)"
    echo "    ${C_CYAN}0${C_RESET}. Keluar"
    echo
    local p
    p=$(ask "    Pilih nomor: ")
    case "$p" in
      1) do_update_system ;;
      2) do_firewall ;;
      3) do_install_docker ;;
      4) do_cloudflare_tunnel ;;
      5) do_install_pocketbase ;;
      6) do_nginx ;;
      7) do_status ;;
      8) do_crm_info ;;
      9) do_domain_guide ;;
      0) echo; msg_ok "Selesai. Semoga servernya lancar."; echo; exit 0 ;;
      *) msg_warn "Pilihan tidak dikenal."; sleep 1 ;;
    esac
  done
}

# ---------- Entry point ----------
echo
msg_info "Silverhawk Home Server Setup — cocok dijalankan di Ubuntu Server (terminal only)"
msg_info "Disarankan: sudo bash <(curl -fsSL https://skripkeren.silverhawk.web.id/lserver.sh)"
echo
main_menu
