#!/bin/bash

# ==============================================
#  Universal Git Restore Tool
#  Bisa dipakai di repo mana pun
#  curl -fsSL https://silverhawk.web.id/skripkeren/restore.sh | bash
# ==============================================

set -e

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║          Universal Git Restore Tool                ║"
echo "║     Restore repo ke commit (snapshot) sebelumnya   ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---------- Cek apakah di dalam git repo ----------
if [ ! -d ".git" ]; then
  echo -e "${RED}Error: Folder ini bukan repository Git.${NC}"
  echo "Jalankan script ini dari dalam folder repository."
  exit 1
fi

# ---------- Info repo saat ini ----------
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "Tidak ada remote")
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
CURRENT_MSG=$(git log -1 --pretty=format:"%s" 2>/dev/null)
CURRENT_DATE=$(git log -1 --pretty=format:"%ad" --date=short 2>/dev/null)

# Coba deteksi username & repo name
if [[ "$REPO_URL" =~ github.com[:/](.+)/(.+)\.git$ ]] || [[ "$REPO_URL" =~ github.com[:/](.+)/(.+)$ ]]; then
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

# ---------- Ambil daftar commit ----------
echo -e "${CYAN}Mengambil daftar 25 commit terakhir...${NC}"
echo ""

mapfile -t COMMITS < <(git log --pretty=format:"%h|%ad|%an|%s" --date=short -n 25)

if [ ${#COMMITS[@]} -eq 0 ]; then
  echo -e "${RED}Tidak ada commit ditemukan.${NC}"
  exit 1
fi

echo -e "${GREEN}Daftar Commit (Snapshot) yang tersedia:${NC}"
echo "────────────────────────────────────────────────────────────────────────"
printf "  %2s  %-10s  %-12s  %-18s  %s\n" "No" "Tanggal" "Hash" "Author" "Pesan"
echo "────────────────────────────────────────────────────────────────────────"

for i in "${!COMMITS[@]}"; do
  IFS='|' read -r HASH DATE AUTHOR MSG <<< "${COMMITS[$i]}"
  NUM=$((i+1))
  
  # Tandai commit yang sedang aktif
  if [ "$HASH" = "$CURRENT_COMMIT" ]; then
    printf "  %2d. %-10s  %-12s  %-18s  %s ${YELLOW}← SEKARANG${NC}\n" "$NUM" "$DATE" "$HASH" "$AUTHOR" "$MSG"
  else
    printf "  %2d. %-10s  %-12s  %-18s  %s\n" "$NUM" "$DATE" "$HASH" "$AUTHOR" "$MSG"
  fi
done

echo "────────────────────────────────────────────────────────────────────────"
echo "   0. Batal / Keluar"
echo ""

# ---------- Pilih nomor ----------
while true; do
  read -p "Pilih nomor commit yang ingin dikembalikan: " CHOICE

  if [[ "$CHOICE" == "0" ]]; then
    echo "Dibatalkan."
    exit 0
  fi

  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#COMMITS[@]} ]; then
    echo -e "${RED}Nomor tidak valid. Coba lagi.${NC}"
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
echo -e "${RED}║  Script ini akan menjalankan:                      ║${NC}"
echo -e "${RED}║  git reset --hard + git push --force               ║${NC}"
echo -e "${RED}║  Semua commit setelah titik ini akan HILANG.       ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
echo ""

read -p "Ketik 'YA' (huruf besar semua) untuk melanjutkan: " CONFIRM

if [ "$CONFIRM" != "YA" ]; then
  echo "Dibatalkan."
  exit 0
fi

echo ""
echo -e "${CYAN}Melakukan restore...${NC}"

# Reset
git reset --hard "$SELECTED_HASH"

# Force push
echo -e "${CYAN}Force push ke origin $CURRENT_BRANCH ...${NC}"
git push origin "$CURRENT_BRANCH" --force

echo ""
echo -e "${GREEN}✓ BERHASIL!${NC}"
echo "Repo sudah dikembalikan ke commit:"
echo "  $SELECTED_HASH | $SELECTED_DATE | $SELECTED_MSG"
echo ""
echo -e "${YELLOW}Catatan: Jika ini GitHub Pages, tunggu 1–3 menit sampai update.${NC}"
