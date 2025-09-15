#!/bin/bash

APP_NAME="Repo Manager by Ted"

# Warna ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # reset

pause() {
    echo
    read -p "Tekan [Enter] untuk kembali ke menu..."
}

function list_accounts() {
    echo
    echo -e "${CYAN}=== Daftar akun GitHub login ===${NC}"
    gh auth status --show-token 2>/dev/null | grep "Logged in to" | nl
    pause
}

function pilih_akun() {
    echo
    accounts=($(gh auth status 2>/dev/null | grep "Logged in to github.com account" | sed -E 's/.*account ([^ ]+).*/\1/'))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada akun login. Silakan login dulu (menu 2).${NC}"
        pause
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
        pause
        return
    fi
    
    echo "🔄 Mengaktifkan akun: $username ..."
    gh auth switch -u "$username"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Akun aktif sekarang: $username ${NC}"
        echo "Verifikasi:"
        gh auth status --hostname github.com
    else
        echo -e "${RED}❌ Gagal mengaktifkan akun.${NC}"
    fi
    pause
}

function login_github() {
    echo
    echo -e "${YELLOW}🔑 Login akun GitHub...${NC}"
    gh auth login
    pause
}

function upload_folder() {
    echo
    echo -e "${CYAN}📂 Folder yang ada di direktori ini:${NC}"
    folders=($(ls -d */ 2>/dev/null))
    if [ ${#folders[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada folder terdeteksi.${NC}"
        pause
        return
    fi
    
    for i in "${!folders[@]}"; do
        echo "$((i+1)). ${folders[$i]}"
    done
    
    read -p "Pilih nomor folder: " folder_idx
    folder=${folders[$((folder_idx-1))]}
    if [ -z "$folder" ]; then
        echo -e "${RED}❌ Nomor folder tidak valid.${NC}"
        pause
        return
    fi
    
    cd "$folder" || return
    
    echo
    echo -e "📡 ${GREEN}Daftar repo dari GitHub $username${NC}"
    repos=($(gh repo list --limit 50 --json name --jq '.[].name'))
    if [ ${#repos[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada repo terdeteksi.${NC}"
        cd ..
        pause
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
        pause
        return
    fi
    
    echo
    echo -e "🚀 ${YELLOW}Upload folder '$folder' ke repo '$repo'...${NC}"
    
    git init
    git add .
    git commit -m "Upload via $APP_NAME"
    git branch -M main
    git remote remove origin 2>/dev/null
    git remote add origin "https://github.com/$(gh api user --jq .login)/$repo.git"
    git push -u origin main --force
    
    cd ..
    pause
}

function list_repo_files() {
    echo -e "🔄 Repo yang ada di akun ${YELLOW}$username${NC} :"
    repos=($(gh repo list --limit 50 --json name --jq '.[].name'))
    for i in "${!repos[@]}"; do
        echo "$((i+1)). ${repos[$i]}"
    done
    
    read -p "Pilih nomor repo: " repo_idx
    repo=${repos[$((repo_idx-1))]}
    if [ -z "$repo" ]; then
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        pause
        return
    fi
    
    gh repo view "$repo" --json name,url,createdAt,updatedAt,description --jq \
    '"Nama: \(.name)\nURL: \(.url)\nDibuat: \(.createdAt)\nUpdate: \(.updatedAt)\nDeskripsi: \(.description)"'
    echo
    gh api repos/$(gh api user --jq .login)/$repo/contents --jq '.[] | "\(.name)\t\(.size) bytes\t\(.path)"'
    pause
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
        pause
        return
    fi
    
    gh api -X POST repos/$(gh api user --jq .login)/$repo/pages \
    -f "source[branch]=main" -f "source[path]=/" >/dev/null
    
    echo -e "⚡ ${GREEN}GitHub Pages diaktifkan. Tunggu ±1-2 menit...${NC}"
    url="https://$(gh api user --jq .login).github.io/$repo/"
    echo -e "🌐 ${CYAN}Akses di: $url${NC}"
    read -p "Buka di browser? (y/n): " ans
    if [ "$ans" = "y" ]; then
        if command -v xdg-open >/dev/null; then
            xdg-open "$url"
        else
            start "$url"
        fi
    fi
    pause
}


function rename_repo() {
    active_user=$(gh api user --jq .login)
    echo -e "${CYAN}=== Daftar repo GitHub (akun: $active_user) ===${NC}"
    repos=$(gh repo list --limit 50 --json name --jq '.[].name')
    echo "$repos" | nl
    
    read -p "👉 Nomor repo untuk di-rename: " repo_number
    repo_name=$(echo "$repos" | sed -n "${repo_number}p")
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        pause
        return
    fi
    
    read -p "📝 Nama baru untuk '$repo_name': " new_name
    if gh repo rename "$new_name" --repo "$active_user/$repo_name"; then
        echo -e "${GREEN}✅ Repo berhasil di-rename menjadi $new_name${NC}"
    else
        echo -e "${RED}❌ Gagal mengubah nama.${NC}"
    fi
    pause
}

function edit_description() {
    active_user=$(gh api user --jq .login)
    echo -e "${CYAN}=== Daftar repo GitHub (akun: $active_user) ===${NC}"
    repos=$(gh repo list --limit 50 --json name --jq '.[].name')
    echo "$repos" | nl
    
    read -p "👉 Nomor repo untuk ubah deskripsi: " repo_number
    repo_name=$(echo "$repos" | sed -n "${repo_number}p")
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        pause
        return
    fi
    
    read -e -p "📝 Deskripsi baru untuk '$repo_name': " new_desc
    new_desc=$(echo "$new_desc" | tr -d '\n\r\t')
    if gh repo edit "$active_user/$repo_name" --description "$new_desc"; then
        echo -e "${GREEN}✅ Deskripsi repo '$repo_name' berhasil diubah${NC}"
    else
        echo -e "${RED}❌ Gagal mengubah deskripsi.${NC}"
    fi
    pause
}

while true; do
    clear
    echo -e "${BLUE}=== $APP_NAME ===${NC}"
    echo
    echo "Menu:"
    echo "1. Pilih akun aktif"
    echo "2. Login akun GitHub"
    echo "3. Upload folder ke repo"
    echo "4. Tampilkan isi repo"
    echo "5. Aktifkan GitHub Pages"
    echo "6. Ubah nama repo"
    echo "7. Ubah deskripsi repo"
    echo "0. Keluar"
    echo
    read -p "Pilih menu: " choice
    
    case $choice in
        1) pilih_akun ;;
        2) login_github ;;
        3) upload_folder ;;
        4) list_repo_files ;;
        5) activate_pages ;;
        6) rename_repo ;;
        7) edit_description ;;
        0) break ;;
        *) echo -e "${RED}❌ Pilihan tidak valid.${NC}" ; pause ;;
    esac
done
