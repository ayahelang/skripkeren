#!/bin/bash

APP_NAME="Repo Manager by Ted"

function list_accounts() {
    echo "=== Daftar akun GitHub login ==="
    gh auth status --show-token 2>/dev/null | grep "Logged in to" | nl
}

function pilih_akun() {
    accounts=($(gh auth status 2>/dev/null | grep "Logged in to github.com account" | sed -E 's/.*account ([^ ]+).*/\1/'))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo "❌ Tidak ada akun login. Silakan login dulu (menu 2)."
        return
    fi

    echo "=== Daftar akun GitHub login ==="
    for i in "${!accounts[@]}"; do
        echo "$((i+1))) ${accounts[$i]} (github.com)"
    done

    read -p "Pilih nomor akun: " sel
    username=${accounts[$((sel-1))]}

    if [ -z "$username" ]; then
        echo "❌ Pilihan tidak valid."
        return
    fi

    echo "🔄 Mengaktifkan akun: $username ..."
    gh auth switch -u "$username"

    if [ $? -eq 0 ]; then
        echo "✅ Akun aktif sekarang: $username (github.com)"
        echo "Verifikasi:"
        gh auth status --hostname github.com
    else
        echo "❌ Gagal mengaktifkan akun."
    fi
}

function login_github() {
    echo "🔑 Login akun GitHub..."
    gh auth login
}

function upload_folder() {
    echo "📂 Folder yang ada di direktori ini:"
    folders=($(ls -d */ 2>/dev/null))
    if [ ${#folders[@]} -eq 0 ]; then
        echo "❌ Tidak ada folder terdeteksi."
        return
    fi

    for i in "${!folders[@]}"; do
        echo "$((i+1)). ${folders[$i]}"
    done

    read -p "Pilih nomor folder: " folder_idx
    folder=${folders[$((folder_idx-1))]}
    if [ -z "$folder" ]; then
        echo "❌ Nomor folder tidak valid."
        return
    fi

    cd "$folder" || return

    echo "📡 Ambil daftar repo dari GitHub..."
    repos=($(gh repo list --limit 50 --json name --jq '.[].name'))
    if [ ${#repos[@]} -eq 0 ]; then
        echo "❌ Tidak ada repo terdeteksi."
        cd ..
        return
    fi

    for i in "${!repos[@]}"; do
        echo "$((i+1)). ${repos[$i]}"
    done

    read -p "Pilih nomor repo tujuan upload: " repo_idx
    repo=${repos[$((repo_idx-1))]}
    if [ -z "$repo" ]; then
        echo "❌ Nomor repo tidak valid."
        cd ..
        return
    fi

    echo "🚀 Upload folder '$folder' ke repo '$repo'..."

    git init
    git add .
    git commit -m "Upload via $APP_NAME"
    git branch -M main
    git remote remove origin 2>/dev/null
    git remote add origin "https://github.com/$(gh api user --jq .login)/$repo.git"
    git push -u origin main --force

    cd ..
}

function list_repo_files() {
    repos=($(gh repo list --limit 50 --json name --jq '.[].name'))
    for i in "${!repos[@]}"; do
        echo "$((i+1)). ${repos[$i]}"
    done

    read -p "Pilih nomor repo: " repo_idx
    repo=${repos[$((repo_idx-1))]}
    if [ -z "$repo" ]; then
        echo "❌ Nomor repo tidak valid."
        return
    fi

    gh repo view "$repo" --json name,url,createdAt,updatedAt --jq \
        '"Nama: \(.name)\nURL: \(.url)\nDibuat: \(.createdAt)\nUpdate: \(.updatedAt)"'
    echo
    gh api repos/$(gh api user --jq .login)/$repo/contents --jq '.[] | "\(.name)\t\(.size) bytes\t\(.path)"'
}

function activate_pages() {
    repos=($(gh repo list --limit 50 --json name --jq '.[].name'))
    for i in "${!repos[@]}"; do
        echo "$((i+1)). ${repos[$i]}"
    done

    read -p "Pilih nomor repo: " repo_idx
    repo=${repos[$((repo_idx-1))]}
    if [ -z "$repo" ]; then
        echo "❌ Nomor repo tidak valid."
        return
    fi

    gh api -X POST repos/$(gh api user --jq .login)/$repo/pages \
        -f "source[branch]=main" -f "source[path]=/" >/dev/null

    echo "⚡ GitHub Pages diaktifkan. Tunggu ±1-2 menit..."
    url="https://$(gh api user --jq .login).github.io/$repo/"
    echo "🌐 Akses di: $url"
    read -p "Buka di browser? (y/n): " ans
    if [ "$ans" = "y" ]; then
        if command -v xdg-open >/dev/null; then
            xdg-open "$url"
        else
            start "$url"
        fi
    fi
}

while true; do
    echo
    echo "=== $APP_NAME ==="
    echo "Menu:"
    echo "1. Pilih akun aktif"
    echo "2. Login akun GitHub"
    echo "3. Upload folder ke repo"
    echo "4. Tampilkan isi repo"
    echo "5. Aktifkan GitHub Pages"
    echo "0. Keluar"
    read -p "Pilih menu: " choice

    case $choice in
        1) pilih_akun ;;
        2) login_github ;;
        3) upload_folder ;;
        4) list_repo_files ;;
        5) activate_pages ;;
        0) break ;;
        *) echo "Pilihan tidak valid." ;;
    esac
done
