#15 Menu menampilkan file2 di repository dan opsi penghapusan
#!/bin/bash
# Remote search + delete files via GitHub API (tanpa jq)
USER="teddybelajarid"

while true; do
  clear
  echo "Menampilkan file2 di repository dan opsi penghapusan"
  echo "📂 Daftar Repository GitHub untuk user $USER:"
  echo "--------------------------------------------"

  # ambil daftar repo
  REPOS=($(gh repo list "$USER" --limit 100 --json name --jq '.[].name' 2>/dev/null))
  if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "❌ Gagal mengambil daftar repo. Pastikan 'gh' terpasang & sudah login (jalankan: gh auth status)."
    exit 1
  fi

  i=1
  for repo in "${REPOS[@]}"; do
    echo "  $i) $repo"
    ((i++))
  done
  echo "  0) Keluar"
  echo "--------------------------------------------"

  read -p "👉 Pilih nomor repo: " INPUT
  if [[ "$INPUT" == "0" ]]; then
    echo "👋 Keluar dari menu. Bye!"
    break
  fi

  if [[ "$INPUT" =~ ^[0-9]+$ ]] && (( INPUT >= 1 && INPUT <= ${#REPOS[@]} )); then
    REPO=${REPOS[$((INPUT-1))]}
    echo "✅ Repo aktif: $REPO"
  else
    echo "❌ Input tidak valid!"
    read -p "Tekan [Enter] untuk kembali..."
    continue
  fi

  echo
  read -p "🔎 Masukkan kata kunci pencarian file (pisahkan spasi untuk banyak kata; kosong -> default gambar): " KEYWORDS

  echo "📥 Mengambil daftar file..."
  DEFAULT_BRANCH=$(gh api repos/"$USER"/"$REPO" --jq '.default_branch' 2>/dev/null)
  DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
  TREE_SHA=$(gh api repos/"$USER"/"$REPO"/branches/"$DEFAULT_BRANCH" --jq '.commit.commit.tree.sha' 2>/dev/null)
  if [[ -z "$TREE_SHA" ]]; then
    echo "❌ Gagal dapatkan tree SHA untuk branch $DEFAULT_BRANCH"
    read -p "Tekan [Enter] untuk kembali..."
    continue
  fi

  FILE_LIST=$(gh api repos/"$USER"/"$REPO"/git/trees/"$TREE_SHA"?recursive=1 --jq '.tree[] | select(.type=="blob") | .path' 2>/dev/null)
  if [[ -z "$FILE_LIST" ]]; then
    echo "❌ Gagal mengambil daftar file (repo kosong / akses ditolak)."
    read -p "Tekan [Enter] untuk kembali..."
    continue
  fi

  # --- Filter berdasarkan KEYWORDS ---
  MATCHED=()

  if [[ -z "$KEYWORDS" ]]; then
    REGEX="\.svg$|\.png$|\.jpg$|\.jpeg$|\.gif$"
  else
    REGEX_LIST=()
    for kw in $KEYWORDS; do
      case "$kw" in
        jpg|png|svg|jpeg|gif|html|css|js|md|wav)
          REGEX_LIST+=("\\.${kw}\$")
          ;;
        *)
          REGEX_LIST+=("$kw")
          ;;
      esac
    done
    REGEX=$(IFS='|'; echo "${REGEX_LIST[*]}")
  fi

  while IFS= read -r file; do
    if echo "$file" | grep -iE "$REGEX" >/dev/null; then
      MATCHED+=("$file")
    fi
  done <<< "$FILE_LIST"

  if [[ ${#MATCHED[@]} -eq 0 ]]; then
    echo "❌ Tidak ada file cocok dengan kata kunci."
    read -p "Tekan [Enter] untuk kembali..."
    continue
  fi

  # --- Tampilkan hasil (PAKAI PATH LENGKAP) ---
  echo "📋 File ditemukan:"
  echo "--------------------------------------------"
  i=1
  for f in "${MATCHED[@]}"; do
    SIZE=$(gh api repos/"$USER"/"$REPO"/git/trees/"$TREE_SHA"?recursive=1 --jq '.tree[] | select(.path=="'"$f"'") | .size' 2>/dev/null)
    DATE=$(gh api repos/"$USER"/"$REPO"/commits --jq ".[] | select(.files[].filename==\"$f\") | .commit.author.date" 2>/dev/null | head -n1)

    # tampilkan path lengkap
    printf " %2d) %-40s | %8s bytes | %s\n" "$i" "$f" "${SIZE:-0}" "${DATE:-unknown}"
    ((i++))
  done
  echo "--------------------------------------------"

  read -p "🗑 Masukkan nomor file yang akan dihapus (spasi/range), 0 untuk batal: " DELINPUT
  if [[ "$DELINPUT" == "0" ]]; then
    echo "↩️  Batal hapus file."
    read -p "Tekan [Enter] untuk kembali ke menu..."
    continue
  fi

  # --- Proses nomor / range ---
  TO_DELETE=()
  for token in $DELINPUT; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=${BASH_REMATCH[1]}
      end=${BASH_REMATCH[2]}
      for ((j=start; j<=end; j++)); do
        if (( j>=1 && j<=${#MATCHED[@]} )); then
          TO_DELETE+=("${MATCHED[$((j-1))]}")
        fi
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      idx=$((token-1))
      if (( idx>=0 && idx<${#MATCHED[@]} )); then
        TO_DELETE+=("${MATCHED[$idx]}")
      fi
    fi
  done

  if [[ ${#TO_DELETE[@]} -eq 0 ]]; then
    echo "❌ Tidak ada file valid dipilih."
    read -p "Tekan [Enter] untuk kembali..."
    continue
  fi

  echo "⚡ Menghapus file..."
  for f in "${TO_DELETE[@]}"; do
    SHA=$(gh api repos/"$USER"/"$REPO"/contents/"$f" --jq .sha 2>/dev/null)
    if [[ -n "$SHA" ]]; then
      gh api --method DELETE -H "Accept: application/vnd.github+json" repos/"$USER"/"$REPO"/contents/"$f" -f message="Delete $f" -f sha="$SHA" >/dev/null
      echo "✅ Terhapus: $f"
    else
      echo "❌ Gagal hapus (tidak dapat ambil sha): $f"
    fi
  done

  echo
  echo "📊 Laporan: ${#TO_DELETE[@]} file diproses."
  read -p "Tekan [Enter] untuk kembali ke menu..."
done
