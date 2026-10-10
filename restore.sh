#!/usr/bin/env bash
# ==============================================
#  Universal Git Restore Tool
#  curl -fsSL https://skripkeren.silverhawk.web.id/restore.sh | bash
# ==============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

TTY=/dev/tty
if [ ! -c "$TTY" ] || [ ! -r "$TTY" ] || [ ! -w "$TTY" ]; then
  TTY=/dev/stdin
fi

ask() {
  local _ans
  printf "%s" "$1" >"$TTY"
  if ! IFS= read -r _ans <"$TTY"; then
    # EOF / Ctrl+D
    printf "\n" >"$TTY"
    printf "%s" "0"
    return
  fi
  printf "%s" "$_ans"
}

clear 2>/dev/null || true
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║          Universal Git Restore Tool                ║"
echo "║     Restore repo ke commit (snapshot) sebelumnya   ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -d ".git" ]; then
  echo -e "${RED}Error: Folder ini bukan repository Git.${NC}"
  echo "Jalankan script ini dari dalam folder repository."
  exit 1
fi

REPO_URL=$(git remote get-url origin 2>/dev/null || echo "Tidak ada remote")
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
CURRENT_MSG=$(git log -1 --pretty=format:"%s" 2>/dev/null)
CURRENT_DATE=$(git log -1 --pretty=format:"%ad" --date=short 2>/dev/null)

if [[ "$REPO_URL" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO_NAME="${BASH_REMATCH[2]}"
else
  OWNER="?"
  REPO_NAME="?"
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
  # trim spasi + lowercase untuk q
  CHOICE=$(printf '%s' "$CHOICE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Keluar: kosong, 0, q, Q, exit, batal
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

git reset --hard "$SELECTED_HASH"

echo -e "${CYAN}Force push ke origin ${CURRENT_BRANCH} ...${NC}"
git push origin "$CURRENT_BRANCH" --force

echo ""
echo -e "${GREEN}✓ BERHASIL!${NC}"
echo "Repo sudah dikembalikan ke commit:"
echo "  $SELECTED_HASH | $SELECTED_DATE | $SELECTED_MSG"
echo ""
echo -e "${YELLOW}Catatan: Jika ini GitHub Pages, tunggu 1–3 menit sampai update.${NC}"
