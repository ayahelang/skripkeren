#2 Menu deteksi akun yang aktif, pindah akun yang aktif, mengganti nama repo, mengubah deskripsi repo
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
while true; do
  clear
  echo "👤 Akun aktif terdeteksi:"
  active_user=$(gh api user --jq '.login' 2>/dev/null)
  echo -e "${YELLOW}$active_user${NC}"
  echo

  echo "📋 Daftar repository akun: $active_user"
  echo "-------------------------------------------------------------------------------"
  repos=$(gh repo list "$active_user" --limit 100 --json name,description,updatedAt \
          --jq '.[] | [.name, (.description // "-"), .updatedAt] | @tsv')

  i=1
  printf "%-3s | %-25s | %-40s | %-20s\n" "No" "Nama Repo" "Deskripsi" "Updated"
  echo "-------------------------------------------------------------------------------"
  while IFS=$'\t' read -r name desc updated; do
    short_desc=$(echo "$desc" | cut -c1-38)
    printf "%-3s | %-25s | %-40s | %-20s\n" "$i)" "$name" "$short_desc" "$updated"
    i=$((i+1))
  done <<< "$repos"
  echo "-------------------------------------------------------------------------------"

  echo
  echo "Menu Utama:"
  echo "1) Ubah akun GitHub yang aktif"
  echo "2) Ubah nama repo"
  echo "3) Ubah deskripsi repo"
  echo "0) Keluar"
  echo "-------------------------------------------------------------------------------"
  read -p "👉 Pilihan: " choice

  if [ "$choice" == "1" ]; then
    gh auth switch
    read -p "Enter untuk lanjut..."
  elif [ "$choice" == "2" ]; then
    read -p "👉 Nomor repo untuk di-rename: " repo_number
    repo_name=$(echo "$repos" | sed -n "${repo_number}p" | cut -f1)
    read -p "📝 Nama baru untuk '$repo_name': " new_name
    if gh repo rename "$new_name" --repo "$active_user/$repo_name"; then
      echo -e "${GREEN}✅ Repo berhasil di-rename menjadi $new_name${NC}"
    else
      echo -e "${RED}❌ Gagal mengubah nama.${NC}"
    fi
    read -p "Enter untuk lanjut..."
  elif [ "$choice" == "3" ]; then
    read -p "👉 Nomor repo untuk ubah deskripsi: " repo_number
    repo_name=$(echo "$repos" | sed -n "${repo_number}p" | cut -f1)
    read -e -p "📝 Deskripsi baru untuk '$repo_name': " new_desc
    new_desc=$(echo "$new_desc" | tr -d '\n\r\t')
    if gh repo edit "$active_user/$repo_name" --description "$new_desc"; then
      echo -e "${GREEN}✅ Deskripsi repo '$repo_name' berhasil diubah${NC}"
    else
      echo -e "${RED}❌ Gagal mengubah deskripsi.${NC}"
    fi
    read -p "Enter untuk lanjut..."
  elif [ "$choice" == "0" ]; then
    echo -e "${YELLOW}👋 Keluar...${NC}"
    exit 0
  else
    echo -e "${RED}❌ Pilihan tidak valid${NC}"
    read -p "Enter untuk lanjut..."
  fi
done
