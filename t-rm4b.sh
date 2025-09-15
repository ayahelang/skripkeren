#!/bin/bash

APP_NAME="Repo Manager by Ted"

# Warna ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # reset

function list_accounts() {
    echo -e "${CYAN}=== Daftar akun GitHub login ===${NC}"
    gh auth status --show-token 2>/dev/null | grep "Logged in to" | nl
}

function pilih_akun() {
    accounts=($(gh auth status 2>/dev/null | grep "Logged in to github.com account" | sed -E 's/.*account ([^ ]+).*/\1/'))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada akun login. Silakan login dulu (menu 2).${NC}"
        return
    fi

    echo -e "${CYAN}=== Daftar akun GitHub login ===${NC}"
    for i in "${!accounts[@]}"; do
        echo "$((i+1))) ${accounts[$i]} (github.com)"
    done

    read -p "Pilih nomor akun: " sel
    username=${accounts[$((sel-1))]}

    if [ -z "$username" ]; then
        echo -e "${RED}❌ Pilihan tidak valid.${NC}"
        return
    fi

    echo -e "${YELLOW}🔄 Mengaktifkan akun: $username ...${NC}"
    gh auth switch -u "$username"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Akun aktif sekarang: $username (github.com)${NC}"
        echo -e "${CYAN}Verifikasi:${NC}"
        gh auth status --hostname github.com
    else
        echo -e "${RED}❌ Gagal mengaktifkan akun.${NC}"
    fi
}

function login_github() {
    echo -e "${YELLOW}🔑 Login akun GitHub...${NC}"
    gh auth login
}

function upload_folder() {
    echo -e "${CYAN}📂 Folder yang ada di direktori ini:${NC}"
    folders=($(ls -d */ 2>/dev/null))
    if [ ${#folders[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada folder terdeteksi.${NC}"
        return
    fi

    for i in "${!folders[@]}"; do
        echo "$((i+1)). ${folders[$i]}"
    done

    read -p "Pilih nomor folder: " folder_idx
    folder=${folders[$((folder_idx-1))]}
    if [ -z "$folder" ]; then
        echo -e "${RED}❌ Nomor folder tidak valid.${NC}"
        return
    fi

    cd "$folder" || return

    echo -e "${YELLOW}📡 Ambil daftar repo dari GitHub...${NC}"
    repos=($(gh repo list --limit 50 --json name --jq '.[].name'))
    if [ ${#repos[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada repo terdeteksi.${NC}"
        cd ..
        return
    fi

    for i in "${!repos[@]}"; do
        echo "$((i+1)). ${repos[$i]}"
    done

    read -p "Pilih nomor repo tujuan upload: " repo_idx
    repo=${repos[$((repo_idx-1))]}
    if [ -z "$repo" ]; then
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        cd ..
        return
    fi

    echo -e "${YELLOW}🚀 Upload folder '$folder' ke repo '$repo'...${NC}"

    git init
    git add .
    git commit -m "Upload via $APP_NAME"
    git branch -M main
    git remote remove origin 2>/dev/null
    git remote add origin "https://github.com/$(gh api user --jq .login)/$repo.git"
    git push -u origin main --force

    echo -e "${GREEN}✅ Upload selesai.${NC}"
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
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        return
    fi

    echo -e "${CYAN}ℹ️ Info repo:${NC}"
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
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        return
    fi

    gh api -X POST repos/$(gh api user --jq .login)/$repo/pages \
        -f "source[branch]=main" -f "source[path]=/" >/dev/null

    echo -e "${YELLOW}⚡ GitHub Pages diaktifkan. Tunggu ±1-2 menit...${NC}"
    url="https://$(gh api user --jq .login).github.io/$repo/"
    echo -e "${GREEN}🌐 Akses di: $url${NC}"
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
    clear
    echo -e \"${BLUE}=== $APP_NAME ===${NC}\"
    echo -e \"${CYAN}Menu:${NC}\"
    echo \"1. Pilih akun aktif\"
    echo \"2. Login akun GitHub\"
    echo \"3. Upload folder ke repo\"
    echo \"4. Tampilkan isi repo\"
    echo \"5. Aktifkan GitHub Pages\"
    echo \"0. Keluar\"
    read -p \"Pilih menu: \" choice

    case $choice in
        1) pilih_akun ; read -p $'\\n[Enter untuk kembali ke menu]';;
        2) login_github ; read -p $'\\n[Enter untuk kembali ke menu]';;
        3) upload_folder ; read -p $'\\n[Enter untuk kembali ke menu]';;
        4) list_repo_files ; read -p $'\\n[Enter untuk kembali ke menu]';;
        5) activate_pages ; read -p $'\\n[Enter untuk kembali ke menu]';;
        0) break ;;
        *) echo -e \"${RED}❌ Pilihan tidak valid.${NC}\" ; sleep 1 ;;
    esac
done
