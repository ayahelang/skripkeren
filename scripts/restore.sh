#!/usr/bin/env bash
# ==============================================
#  Universal Git Restore Tool (Skripkeren)
#  Bekerja di: Git Bash (Windows), Linux, macOS, Codespaces
#  Cara pakai:
#    curl -fsSL https://skripkeren.silverhawk.web.id/scripts/restore.sh | bash
#    atau: bash restore.sh   (dari dalam folder repo)
# ==============================================

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

# Jangan langsung set -e agar dependency check lebih ramah
set +e

# Warna (aman di Git Bash Windows)
if [[ -t 1 ]] || [[ -n "${MSYSTEM:-}" ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'
  BLUE=$'\033[0;34m'
  NC=$'\033[0m'
else
  RED=; GREEN=; YELLOW=; CYAN=; BLUE=; NC=
fi

# TTY yang andal di Git Bash, Codespaces, Linux, macOS
_setup_tty() {
  TTY=/dev/tty
  if [[ -c "$TTY" && -r "$TTY" && -w "$TTY" ]]; then
    return 0
  fi
  # Fallback Git Bash / MSYS
  if [[ -n "${MSYSTEM:-}" || "$(uname -s 2>/dev/null)" == MINGW* ]]; then
    if [[ -c /dev/tty ]]; then
      TTY=/dev/tty
      return 0
    fi
  fi
  TTY=/dev/stdin
}
_setup_tty

ask() {
  local _ans
  # Tulis prompt ke terminal asli (penting saat curl | bash)
  printf "%s" "$1" >"$TTY" 2>/dev/null || printf "%s" "$1"
  if ! IFS= read -r _ans <"$TTY" 2>/dev/null; then
    printf "\n" >"$TTY" 2>/dev/null || true
    printf "%s" "0"
    return
  fi
  printf "%s" "$_ans"
}

# ---------- Cek & bantu dependency ----------
_check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

_report_missing() {
  local missing=()
  _check_cmd curl || missing+=("curl")
  _check_cmd git  || missing+=("git")
  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi
  echo -e "${YELLOW}Dependency belum lengkap: ${missing[*]}${NC}"
  return 1
}

_try_install_deps() {
  echo ""
  echo -e "${CYAN}Mencoba memenuhi dependency...${NC}"
  if declare -F sk_ensure_basic >/dev/null 2>&1; then
    sk_ensure_basic curl git
    return $?
  fi
  # Fallback sederhana jika sk-deps gagal di-load
  if _check_cmd apt-get; then
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo apt-get install -y curl git 2>/dev/null && return 0
  fi
  if _check_cmd brew; then
    brew install curl git 2>/dev/null && return 0
  fi
  if [[ -n "${MSYSTEM:-}" || -n "${WINDIR:-}" ]] && _check_cmd winget; then
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements 2>/dev/null || true
    winget install --id curl.curl -e --accept-package-agreements --accept-source-agreements 2>/dev/null || true
  fi
  _check_cmd curl && _check_cmd git
}

show_deps_menu() {
  echo ""
  echo -e "${CYAN}┌────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}│  Dependency Check                          │${NC}"
  echo -e "${CYAN}└────────────────────────────────────────────┘${NC}"
  local ok=1
  if _check_cmd curl; then
    echo -e "  curl  ${GREEN}OK${NC}  ($(_check_cmd curl && command -v curl))"
  else
    echo -e "  curl  ${RED}BELUM${NC}"
    ok=0
  fi
  if _check_cmd git; then
    echo -e "  git   ${GREEN}OK${NC}  ($(git --version 2>/dev/null | head -1))"
  else
    echo -e "  git   ${RED}BELUM${NC}"
    ok=0
  fi
  echo ""
  if [[ $ok -eq 1 ]]; then
    echo -e "${GREEN}Semua dependency inti siap.${NC}"
    return 0
  fi
  echo -e "${YELLOW}Ada dependency yang kurang.${NC}"
  echo "  1) Coba install otomatis (via sk-deps / winget / apt / brew)"
  echo "  2) Lanjut saja (jika kamu yakin sudah ada)"
  echo "  0) Keluar"
  local c
  c=$(ask "Pilih: ")
  c=$(printf '%s' "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$c" in
    1)
      if _try_install_deps; then
        echo -e "${GREEN}Dependency siap. Lanjut.${NC}"
        return 0
      else
        echo -e "${RED}Gagal memenuhi dependency otomatis.${NC}"
        echo "Install manual lalu jalankan ulang:"
        echo "  - Windows (Git Bash): pastikan Git for Windows terpasang"
        echo "  - Linux: sudo apt install curl git"
        echo "  - macOS: brew install curl git"
        exit 1
      fi
      ;;
    2)
      echo -e "${YELLOW}Melanjutkan tanpa jaminan dependency...${NC}"
      return 0
      ;;
    *)
      echo "Keluar."
      exit 0
      ;;
  esac
}

# Panggil cek dependency (dengan menu jika kurang)
if ! _report_missing; then
  show_deps_menu
elif declare -F sk_ensure_basic >/dev/null 2>&1; then
  # Masih panggil sk_ensure_basic agar path/winget dll ter-handle
  sk_ensure_basic curl git || show_deps_menu
fi

set -e

clear 2>/dev/null || true
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║          Universal Git Restore Tool                ║"
echo "║     Restore repo ke commit (snapshot) sebelumnya   ║"
echo "║     Git Bash / Linux / macOS / Codespaces          ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Folder kosong / tanpa .git BUKAN repository Git (meski namanya sama dengan repo di GitHub)
if [ ! -d ".git" ]; then
  echo -e "${YELLOW}Folder ini belum repository Git (tidak ada folder .git).${NC}"
  echo "  Path saat ini: $(pwd)"
  echo
  echo "Folder kosong di laptop TIDAK otomatis terhubung ke GitHub."
  echo "Yang dibutuhkan: hasil 'git clone' (ada folder .git di dalamnya)."
  echo
  echo "Pilih:"
  echo "  1) Clone repo dari GitHub ke folder ini / subfolder, lalu lanjut restore"
  echo "  2) Keluar (nanti clone manual)"
  _c=$(ask "Pilih [1/2]: ")
  _c=$(echo "$_c" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ "$_c" != "1" ]]; then
    echo
    echo "Contoh clone manual di Git Bash:"
    echo "  cd ~/Downloads"
    echo "  git clone https://github.com/OWNER/NAMA-REPO.git"
    echo "  cd NAMA-REPO"
    echo "  bash <(curl -fsSL https://skripkeren.silverhawk.web.id/scripts/restore.sh)"
    exit 1
  fi
  echo
  _url=$(ask "URL atau owner/repo GitHub: ")
  _url=$(echo "$_url" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\.git$//')
  if [[ -z "$_url" ]]; then
    echo -e "${RED}URL kosong.${NC}"
    exit 1
  fi
  # normalisasi ke URL https
  if [[ "$_url" =~ ^[^/]+/[^/]+$ ]]; then
    _url="https://github.com/${_url}.git"
  elif [[ "$_url" =~ github.com ]]; then
    _url="${_url%.git}.git"
    [[ "$_url" == https://* || "$_url" == git@* ]] || _url="https://${_url}"
  else
    echo -e "${RED}Format tidak dikenali. Pakai owner/repo atau URL GitHub.${NC}"
    exit 1
  fi
  _name=$(basename "${_url%.git}")
  # Jika folder saat ini kosong → clone ke . (butuh . bukan existing non-empty with junk)
  _isempty=1
  for _f in * .[!.]* ..?*; do
    [[ -e "$_f" ]] || continue
    [[ "$_f" == "." || "$_f" == ".." ]] && continue
    _isempty=0
    break
  done 2>/dev/null || true
  if [[ "$_isempty" -eq 1 ]]; then
    echo -e "${CYAN}Folder kosong — clone ke direktori saat ini...${NC}"
    git clone "$_url" . || { echo -e "${RED}Clone gagal.${NC}"; exit 1; }
  else
    echo -e "${CYAN}Clone ke subfolder: ${_name}${NC}"
    if [[ -d "$_name" ]]; then
      echo -e "${YELLOW}Folder ${_name} sudah ada.${NC}"
      if [[ -d "$_name/.git" ]]; then
        echo "Memakai folder yang sudah ada (sudah git repo)."
        cd "$_name" || exit 1
      else
        echo -e "${RED}Folder ada tapi bukan git repo. Hapus/rename dulu.${NC}"
        exit 1
      fi
    else
      git clone "$_url" "$_name" || { echo -e "${RED}Clone gagal.${NC}"; exit 1; }
      cd "$_name" || exit 1
    fi
  fi
  echo -e "${GREEN}Clone OK. Lanjut restore di: $(pwd)${NC}"
  echo
fi

if [ ! -d ".git" ]; then
  echo -e "${RED}Masih bukan repository Git setelah clone.${NC}"
  exit 1
fi

REPO_URL=$(git remote get-url origin 2>/dev/null || echo "Tidak ada remote")
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
CURRENT_MSG=$(git log -1 --pretty=format:"%s" 2>/dev/null)
CURRENT_DATE=$(git log -1 --pretty=format:"%ad" --date=short 2>/dev/null)

OWNER="?"
REPO_NAME="?"
if [[ "$REPO_URL" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO_NAME="${BASH_REMATCH[2]}"
fi

echo -e "${BLUE}Informasi Repository Saat Ini:${NC}"
echo "────────────────────────────────────────────────────"
echo -e "  Akun / Owner   : ${GREEN}$OWNER${NC}"
echo -e "  Nama Repo      : ${GREEN}$REPO_NAME${NC}"
echo -e "  Branch         : ${GREEN}$CURRENT_BRANCH${NC}"
echo -e "  Commit aktif   : ${YELLOW}$CURRENT_COMMIT${NC} ($CURRENT_DATE)"
echo -e "  Pesan commit   : $CURRENT_MSG"
echo -e "  Remote URL     : $REPO_URL"
echo "────────────────────────────────────────────────────"
echo ""

echo -e "${CYAN}Mengambil daftar 25 commit terakhir...${NC}"
echo ""

COMMITS=()
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] && COMMITS+=("$line")
done < <(git log --pretty=format:"%h|%ad|%an|%s" --date=short -n 25 && echo)

if [ ${#COMMITS[@]} -eq 0 ]; then
  echo -e "${RED}Tidak ada commit ditemukan.${NC}"
  exit 1
fi

MAX=${#COMMITS[@]}

echo -e "${GREEN}Daftar Commit (Snapshot) yang tersedia:${NC}"
echo "────────────────────────────────────────────────────────────────────────"
printf "  %2s  %-10s  %-12s  %-18s  %s\n" "No" "Tanggal" "Hash" "Author" "Pesan"
echo "────────────────────────────────────────────────────────────────────────"

for i in "${!COMMITS[@]}"; do
  IFS='|' read -r HASH DATE AUTHOR MSG <<< "${COMMITS[$i]}"
  NUM=$((i+1))
  if [ "$HASH" = "$CURRENT_COMMIT" ]; then
    printf "  %2d. %-10s  %-12s  %-18s  %s ${YELLOW}← SEKARANG${NC}\n" "$NUM" "$DATE" "$HASH" "$AUTHOR" "$MSG"
  else
    printf "  %2d. %-10s  %-12s  %-18s  %s\n" "$NUM" "$DATE" "$HASH" "$AUTHOR" "$MSG"
  fi
done

echo "────────────────────────────────────────────────────────────────────────"
echo -e "   ${CYAN}0${NC} atau ${CYAN}q${NC}  =  Batal / Keluar"
echo -e "   Pilih nomor ${GREEN}1${NC}–${GREEN}${MAX}${NC}"
echo ""

TRIES=0
while true; do
  CHOICE=$(ask "Pilih nomor commit yang ingin dikembalikan: ")
  CHOICE=$(printf '%s' "$CHOICE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  case "$CHOICE" in
    ""|0|q|Q|exit|EXIT|batal|Batal)
      echo ""
      echo -e "${CYAN}Dibatalkan. Tidak ada perubahan pada repo.${NC}"
      exit 0
      ;;
  esac

  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Input tidak valid.${NC} Ketik nomor 1–${MAX}, atau 0 / q untuk keluar."
    TRIES=$((TRIES+1))
    [ "$TRIES" -ge 5 ] && { echo -e "${YELLOW}Terlalu banyak percobaan. Keluar.${NC}"; exit 0; }
    continue
  fi

  if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$MAX" ]; then
    echo -e "${RED}Nomor di luar jangkauan (1–${MAX}).${NC} Atau ketik ${CYAN}0${NC} / ${CYAN}q${NC} untuk keluar."
    TRIES=$((TRIES+1))
    [ "$TRIES" -ge 5 ] && { echo -e "${YELLOW}Terlalu banyak percobaan. Keluar.${NC}"; exit 0; }
    continue
  fi

  break
done

INDEX=$((CHOICE-1))
IFS='|' read -r SELECTED_HASH SELECTED_DATE SELECTED_AUTHOR SELECTED_MSG <<< "${COMMITS[$INDEX]}"

echo ""
echo -e "${YELLOW}Kamu memilih commit:${NC}"
echo "  Hash     : $SELECTED_HASH"
echo "  Tanggal  : $SELECTED_DATE"
echo "  Author   : $SELECTED_AUTHOR"
echo "  Pesan    : $SELECTED_MSG"
echo ""
echo -e "${RED}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  PERINGATAN BESAR                                  ║${NC}"
echo -e "${RED}║  git reset --hard + git push --force               ║${NC}"
echo -e "${RED}║  Semua commit setelah titik ini akan HILANG.       ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
echo ""

CONFIRM=$(ask "Ketik 'YA' untuk lanjut, atau apa saja untuk batal: ")
CONFIRM=$(printf '%s' "$CONFIRM" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ "$CONFIRM" != "YA" ]; then
  echo ""
  echo -e "${CYAN}Dibatalkan. Tidak ada perubahan pada repo.${NC}"
  exit 0
fi

echo ""
echo -e "${CYAN}Melakukan restore...${NC}"

if ! git reset --hard "$SELECTED_HASH"; then
  echo -e "${RED}Gagal git reset --hard. Cek permission / status repo.${NC}"
  exit 1
fi

echo -e "${CYAN}Force push ke origin ${CURRENT_BRANCH} ...${NC}"
if ! git push origin "$CURRENT_BRANCH" --force; then
  echo -e "${YELLOW}Force push gagal.${NC}"
  echo "Kemungkinan:"
  echo "  - Belum login (Git Bash: git credential / gh auth login)"
  echo "  - Branch protected di GitHub"
  echo "  - Tidak ada akses write ke remote"
  echo ""
  echo -e "Lokal sudah di-reset ke ${GREEN}$SELECTED_HASH${NC}."
  echo "Kamu bisa push manual nanti: git push origin $CURRENT_BRANCH --force"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ BERHASIL!${NC}"
echo "Repo sudah dikembalikan ke commit:"
echo "  $SELECTED_HASH | $SELECTED_DATE | $SELECTED_MSG"
echo ""
echo -e "${YELLOW}Catatan: Jika ini GitHub Pages, tunggu 1–3 menit sampai update.${NC}"
echo ""
echo "Script ini bisa dijalankan dari Git Bash (Windows), Linux, macOS, dan Codespaces."
