#18 Menu mengupload semua file di lokal ke repository di folder tertentu
#!/bin/bash

# simpan PWD awal
BASE_DIR=$(pwd)

# fungsi untuk tampilkan menu utama
show_menu() {
    clear
    echo "=============================================="
    echo "   🚀 GitHub Repo Manager - by Teddy "
    echo "=============================================="
    echo "📂 PWD aktif: $(pwd)"
    echo
    echo "1) Upload folder ke repo"
    echo "2) Lihat file & folder di repo online"
    echo "0) Keluar"
    echo
    read -p "👉 Pilih menu: " menu_choice
}

# fungsi pilih folder lokal
choose_local_folder() {
    echo
    echo "📋 Daftar folder di direktori ini:"
    i=1
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
      exit 1
    fi
    src_path="$(realpath "$local_folder")"
}

# fungsi pilih akun GitHub
choose_account() {
    echo
    echo "🔎 Mendeteksi akun GitHub..."
    accounts=()

    cfg_user=$(git config --global user.name 2>/dev/null)
    if [ -n "$cfg_user" ]; then
      accounts+=("$cfg_user")
    fi

    if command -v gh &>/dev/null; then
      gh_user_cli=$(gh api user --jq .login 2>/dev/null)
      if [ -n "$gh_user_cli" ]; then
        accounts+=("$gh_user_cli")
      fi
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

# fungsi pilih repo GitHub
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

# fungsi upload folder ke repo
upload_to_repo() {
    choose_local_folder
    choose_account
    choose_repo
    read -p "📂 Masukkan nama folder tujuan di repo (kosong = root repo): " repo_folder

    tmp_dir=$(mktemp -d)
    echo "⏳ Clone repo $gh_user/$gh_repo ..."
    git clone "https://github.com/$gh_user/$gh_repo.git" "$tmp_dir" || { echo "❌ Gagal clone repo"; return; }

    cd "$tmp_dir" || return

    if [ -n "$repo_folder" ]; then
      mkdir -p "$repo_folder"
      cp -r "$src_path/"* "$repo_folder/"
    else
      cp -r "$src_path/"* .
    fi

    git add .
    git commit -m "Upload isi folder $local_folder" || echo "⚠️ Tidak ada perubahan untuk di-commit"
    git push origin main

    echo
    echo "✅ Upload selesai!"
    echo "📌 Repo: https://github.com/$gh_user/$gh_repo"

    cd "$BASE_DIR"  # balik ke pwd awal
    read -p "👉 Tekan ENTER untuk kembali ke menu..."
}

# fungsi lihat isi repo online
view_repo_files() {
    choose_account
    choose_repo

    echo
    echo "📂 Daftar file & folder di repo $gh_user/$gh_repo (branch main):"
    echo "-------------------------------------------------------------"

    if command -v gh &>/dev/null; then
      gh api "repos/$gh_user/$gh_repo/contents" --jq '.[].name' || echo "❌ Tidak bisa ambil daftar file (pastikan gh login)"
    else
      echo "⚠️ GitHub CLI (gh) belum terinstal. Fitur ini butuh gh."
    fi

    echo "-------------------------------------------------------------"
    read -p "👉 Tekan ENTER untuk kembali ke menu..."
}

# loop menu
while true; do
    show_menu
    case $menu_choice in
        1) upload_to_repo ;;
        2) view_repo_files ;;
        0) echo "👋 Keluar. Bye!"; exit 0 ;;
        *) echo "❌ Pilihan tidak valid"; sleep 1 ;;
    esac
done
