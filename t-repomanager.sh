#!/bin/bash
# ==============================================
# 🚀 GitHub Repo Manager - by Teddy (versi gabungan)
# ==============================================

BASE_DIR=$(pwd)

# --- Fungsi tampilkan menu utama ---
show_menu() {
    clear
    echo "=============================================="
    echo "   🚀 GitHub Repo Manager - by Teddy "
    echo "=============================================="
    echo "📂 PWD aktif: $(pwd)"
    echo
    echo "1) Upload folder ke repo"
    echo "2) Lihat file & folder di repo online"
    echo "3) Aktifkan / buat repo + GitHub Pages"
    echo "0) Keluar"
    echo
    read -p "👉 Pilih menu: " menu_choice
}

# --- Fungsi pilih folder lokal ---
choose_local_folder() {
    echo
    echo "📋 Daftar folder di direktori ini:"
    i=1
    folders=()
    for d in */ ; do
      echo "  $i) ${d%/}"
      folders[$i]="${d%/}"
      ((i++))
    done
    echo
    read -p "👉 Masukkan nomor folder atau path relatif: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -lt $i ]; then
      local_folder="${folders[$choice]}"
    else
      local_folder="$choice"
    fi
    if [ ! -d "$local_folder" ]; then
      echo "❌ Folder '$local_folder' tidak ditemukan!"
      read -p "👉 Tekan ENTER untuk kembali..."
      return 1
    fi
    src_path="$(realpath "$local_folder")"
}

# --- Fungsi pilih akun ---
choose_account() {
    echo
    echo "🔎 Mendeteksi akun GitHub..."
    accounts=()

    if command -v gh &>/dev/null; then
      gh_user_cli=$(gh api user --jq .login 2>/dev/null)
      if [ -n "$gh_user_cli" ]; then
        accounts+=("$gh_user_cli")
      fi
    fi

    cfg_user=$(git config --global user.name 2>/dev/null)
    if [ -n "$cfg_user" ]; then
      accounts+=("$cfg_user")
    fi

    accounts=($(printf "%s\n" "${accounts[@]}" | sort -u))

    if [ ${#accounts[@]} -eq 0 ]; then
      read -p "👤 Masukkan nama akun GitHub: " gh_user
    else
      echo "📋 Akun terdeteksi:"
      idx=1
      for acc in "${accounts[@]}"; do
        echo "  $idx) $acc"
        ((idx++))
      done
      read -p "👉 Pilih nomor akun atau ketik manual: " choice
      if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -lt $idx ]; then
        gh_user="${accounts[$((choice-1))]}"
      else
        gh_user="$choice"
      fi
    fi
}

# --- Fungsi pilih repo ---
choose_repo() {
    echo
    repos=()
    if command -v gh &>/dev/null; then
      echo "🔎 Mengambil daftar repo dari akun $gh_user..."
      while IFS= read -r repo; do
        repos+=("$repo")
      done < <(gh repo list "$gh_user" --limit 30 --json name -q '.[].name' 2>/dev/null)
    fi

    if [ ${#repos[@]} -eq 0 ]; then
      read -p "📦 Masukkan nama repo GitHub: " gh_repo
    else
      echo "📋 Repo terdeteksi:"
      idx=1
      for r in "${repos[@]}"; do
        echo "  $idx) $r"
        ((idx++))
      done
      read -p "👉 Pilih nomor repo atau ketik manual: " choice
      if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -lt $idx ]; then
        gh_repo="${repos[$((choice-1))]}"
      else
        gh_repo="$choice"
      fi
    fi
}

# --- Upload folder ---
upload_to_repo() {
    choose_local_folder || return
    choose_account
    choose_repo
    read -p "📂 Masukkan nama folder tujuan di repo (kosong = root repo): " repo_folder

    tmp_dir=$(mktemp -d)
    echo "⏳ Clone repo $gh_user/$gh_repo ..."

    # Ambil token dari gh auth
    if gh auth status &>/dev/null; then
        GH_TOKEN=$(gh auth token)
        GIT_URL="https://$GH_TOKEN@github.com/$gh_user/$gh_repo.git"
    else
        GIT_URL="https://github.com/$gh_user/$gh_repo.git"
    fi

    git clone "$GIT_URL" "$tmp_dir" || { echo "❌ Gagal clone repo"; return; }

    cd "$tmp_dir" || return

    if ! git rev-parse --abbrev-ref HEAD | grep -q "main"; then
        echo "⚡ Branch bukan 'main'. Reset ke branch main..."
        git checkout -B main
        git branch --set-upstream-to=origin/main main 2>/dev/null || true
    fi

    git pull origin main || git checkout -b main

    if [ -n "$repo_folder" ]; then
      mkdir -p "$repo_folder"
      rm -rf "$repo_folder"/*   # hapus isi lama
      cp -r "$src_path/"* "$repo_folder/"
    else
      rm -rf ./*                # hapus isi lama root
      cp -r "$src_path/"* .
    fi

    git add .
    git commit -m "Overwrite isi folder $local_folder" || echo "⚠️ Tidak ada perubahan untuk di-commit"

    echo "⏳ Push ke repo..."
    if git push origin main; then
        echo
        echo "✅ Upload selesai (file lama sudah diganti)!"
        echo "📌 Repo: https://github.com/$gh_user/$gh_repo"
    else
        echo "❌ Upload gagal! Cek akses token/izin repo."
    fi

    cd "$BASE_DIR"
    read -p "👉 Tekan ENTER untuk kembali ke menu..."
}

# --- Lihat isi repo ---
view_repo_files() {
    choose_account
    choose_repo
    echo
    echo "📂 Daftar file & folder di repo $gh_user/$gh_repo (branch main):"
    echo "-------------------------------------------------------------"
    if command -v gh &>/dev/null; then
      gh api "repos/$gh_user/$gh_repo/contents" --jq '.[].name' || echo "❌ Tidak bisa ambil daftar file"
    else
      echo "⚠️ GitHub CLI (gh) belum terinstal."
    fi
    echo "-------------------------------------------------------------"
    read -p "👉 Tekan ENTER untuk kembali ke menu..."
}

# --- Aktifkan / buat repo + GitHub Pages ---
activate_repo() {
    choose_account
    echo "📂 Daftar Repository GitHub untuk user $gh_user:"
    echo "--------------------------------------------"
    REPOS=($(gh repo list $gh_user --limit 30 --json name --jq '.[].name'))
    i=1
    for repo in "${REPOS[@]}"; do
      echo "  $i) $repo"
      ((i++))
    done
    echo "  0) Batal"
    echo "--------------------------------------------"
    read -p "👉 Masukkan nomor repo atau nama repo baru: " INPUT
    if [[ "$INPUT" == "0" ]]; then return; fi
    if [[ "$INPUT" =~ ^[0-9]+$ ]] && (( INPUT >= 1 && INPUT <= ${#REPOS[@]} )); then
      REPO=${REPOS[$((INPUT-1))]}
      echo "✅ Menggunakan repo yang sudah ada: $REPO"
    else
      REPO="$INPUT"
      echo "⚡ Membuat repo baru: $REPO"
      gh repo create $gh_user/$REPO --public
    fi

    HTML_CONTENT="<h1>GitHub Pages <b>${REPO}</b> sudah aktif 🎉</h1><p>Silakan berkreasi dan ganti file ini</p>"
    if ! gh api repos/$gh_user/$REPO/contents/index.html >/dev/null 2>&1; then
      gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        repos/$gh_user/$REPO/contents/index.html \
        -f message="Add index.html" \
        -f content="$(echo "$HTML_CONTENT" | base64 -w 0)"
    fi

    echo "⚡ Mengaktifkan GitHub Pages ..."
    gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      repos/$gh_user/$REPO/pages \
      -f "source[branch]=main" -f "source[path]=/" || true

    echo "⏳ Menunggu GitHub Pages aktif..."
    SECONDS=0
    while true; do
      STATUS=$(gh api repos/$gh_user/$REPO/pages --jq .status 2>/dev/null)
      if [[ "$STATUS" == "built" ]]; then
        break
      fi
      ELAPSED=$SECONDS
      echo -ne "⌛ Status: ${STATUS:-menunggu} | Elapsed: ${ELAPSED}s\r"
      sleep 3
    done

    echo
    PAGES_URL=$(gh api repos/$gh_user/$REPO/pages --jq .html_url)
    echo "✅ GitHub Pages aktif setelah ${SECONDS}s!"
    echo "🔗 $PAGES_URL"
    start "$PAGES_URL"
    read -p "👉 Tekan ENTER untuk kembali ke menu..."
}

# --- Loop utama ---
while true; do
    show_menu
    case $menu_choice in
        1) upload_to_repo ;;
        2) view_repo_files ;;
        3) activate_repo ;;
        0) echo "👋 Keluar. Bye!"; exit 0 ;;
        *) echo "❌ Pilihan tidak valid"; sleep 1 ;;
    esac
done
