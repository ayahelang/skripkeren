#!/bin/bash

USER="teddybelajarid"
LIMIT=200

clear
echo "📌 Mengambil daftar repo milik $USER..."

# Ambil daftar repo (nama + tanggal) urut paling baru
gh repo list $USER --limit $LIMIT --json name,createdAt --jq '.[] | "\(.name) \(.createdAt)"' > repos.txt

if [[ ! -s repos.txt ]]; then
  echo "❌ Tidak ada repo ditemukan."
  exit 0
fi

# Header tabel
printf "\n%-5s %-30s %-15s\n" "No." "Nama Repo" "Tanggal"
printf "%-5s %-30s %-15s\n" "-----" "------------------------------" "---------------"

# Tampilkan daftar dengan nomor urut
i=1
> mapping.txt
while read -r line; do
  NAME=$(echo $line | awk '{print $1}')
  DATE=$(echo $line | awk '{print $2}' | cut -d"T" -f1)
  printf "%-5s %-30s %-15s\n" "$i." "$NAME" "$DATE"
  echo "$i|$NAME" >> mapping.txt
  ((i++))
done < repos.txt

echo ""
read -p "👉 Masukkan nomor repo yang akan dihapus (pisahkan dengan spasi, 0 untuk keluar): " SELECTIONS

# ==== LOGIKA IF ELSE ====
if [[ "$SELECTIONS" == "0" ]]; then
  echo "❌ Tidak ada repo dihapus. Kembali ke prompt Git Bash..."
else
  echo -e "\n⚠️ Repo yang dipilih untuk dihapus:"
  for sel in $SELECTIONS; do
    NAME=$(grep "^$sel|" mapping.txt | cut -d"|" -f2)
    if [[ -n "$NAME" ]]; then
      printf "- %s\n" "$NAME"
    fi
  done

  read -p "Apakah yakin ingin menghapus repo di atas? (y/N): " confirm
  if [[ "$confirm" == "y" ]]; then
    for sel in $SELECTIONS; do
      NAME=$(grep "^$sel|" mapping.txt | cut -d"|" -f2)
      if [[ -n "$NAME" ]]; then
        echo "🗑️ Menghapus repo: $NAME ..."
        gh repo delete "$USER/$NAME" --yes
      fi
    done
    echo "✅ Selesai! Repo yang dipilih sudah dihapus."
  else
    echo "❌ Dibatalkan."
  fi
fi

# Bersihkan file sementara
# rm -f repos.txt mapping.txt