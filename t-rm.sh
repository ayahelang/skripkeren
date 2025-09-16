#!/bin/bash

APP_NAME="Repo Manager v5 by Ted"

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

function pilih_akun() {
    echo
    accounts=($(gh auth status 2>/dev/null | grep "Logged in to github.com account" | sed -E 's/.*account ([^ ]+).*/\1/'))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo -e "${RED}❌ Tidak ada akun login. Silakan login dulu (menu 2).${NC}"
        pause
        return
    fi
    
    echo -e "${CYAN}=== Daftar akun GitHub terdeteksi login ===${NC}"
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
        echo -e "✅ Akun aktif sekarang: ${GREEN}$username ${NC}"
        gh auth status --hostname github.com
    else
        echo -e "${RED}❌ Gagal mengaktifkan akun.${NC}"
    fi
    pause
}

function login_github() {
    echo
    echo -e "${YELLOW}🔑 Login akun GitHub...${NC}"
    gh auth login -w --scopes "repo,workflow,gist,read:org"
    pause
}

function upload_folder() {
    echo
    echo -e "📂 Working directory: ${CYAN}$(pwd)${NC}"
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
    active_user=$(gh api user --jq .login)
    echo -e "📡 Daftar repo dari GitHub ${GREEN}$active_user${NC}"
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
    echo -e "🚀 Upload folder ${YELLOW}'$folder'${NC} ke repo ${GREEN}'$repo'...${NC}"
    
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
    active_user=$(gh api user --jq .login)
    echo -e "🔄 Repo yang ada di akun ${YELLOW}$active_user${NC} :"
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

function delete_repo() {
    active_user=$(gh api user --jq .login)
    echo -e "${CYAN}=== Daftar repo GitHub (akun: $active_user) ===${NC}"
    repos=$(gh repo list --limit 50 --json name --jq '.[].name')
    echo "$repos" | nl
    
    read -p "👉 Nomor repo untuk dihapus: " repo_number
    repo_name=$(echo "$repos" | sed -n "${repo_number}p")
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        pause
        return
    fi
    
    echo -e "${YELLOW}⚠️ Anda akan menghapus repo: $active_user/$repo_name${NC}"
    read -p "Apakah Anda yakin? (ketik 'yes' untuk konfirmasi): " confirm
    
    if [ "$confirm" = "yes" ]; then
        if gh repo delete "$active_user/$repo_name" --yes; then
            echo -e "${GREEN}✅ Repo '$repo_name' berhasil dihapus${NC}"
        else
            echo -e "${RED}❌ Gagal menghapus repo.${NC}"
        fi
    else
        echo -e "${CYAN}ℹ️ Batal menghapus repo.${NC}"
    fi
    pause
}

manage_scopes() {
  echo
  echo "🔎 Mengecek token scopes akun aktif..."
  TOKEN=$(gh auth token 2>/dev/null)
  if [[ -z "$TOKEN" ]]; then
    echo "⚠️ Belum ada token. Silakan login dulu."
    read -p "Tekan [Enter] untuk kembali..."
    return
  fi

  # Ambil scopes via header response
  SCOPES=$(curl -s -I -H "Authorization: token $TOKEN" https://api.github.com/user | grep "X-OAuth-Scopes:" | sed 's/X-OAuth-Scopes: //')
  echo "✅ Scopes aktif saat ini: ${SCOPES:-<tidak ada>}"
  echo

  # Daftar scopes populer & sering dipakai
  AVAILABLE_SCOPES=(
    "repo"
    "workflow"
    "gist"
    "notifications"
    "read:user"
    "user:email"
    "user:follow"
    "admin:repo_hook"
    "write:repo_hook"
    "read:repo_hook"
    "delete_repo"
    "packages"
    "write:packages"
    "read:packages"
    "project"
    "admin:org"
    "write:org"
    "read:org"
    "discussion"
    "codespace"
    "security_events"
  )

  echo "📋 Daftar scopes populer:"
  i=1
  for s in "${AVAILABLE_SCOPES[@]}"; do
    if [[ "$SCOPES" == *"$s"* ]]; then
      echo "  $i) $s ✅"
    else
      echo "  $i) $s ❌"
    fi
    ((i++))
  done
  echo "  0) Batal"
  echo "--------------------------------------------"
  read -p "👉 Masukkan nomor scope yang ingin diaktifkan (pisahkan dengan spasi): " INPUT

  if [[ "$INPUT" == "0" ]]; then
    echo "Batal menambah scope."
  else
    # Gabungkan scope lama + baru
    NEW_SCOPES=($SCOPES)
    for num in $INPUT; do
      idx=$((num-1))
      if [[ $idx -ge 0 && $idx -lt ${#AVAILABLE_SCOPES[@]} ]]; then
        NEW_SCOPES+=("${AVAILABLE_SCOPES[$idx]}")
      fi
    done
    # Hilangkan duplikat
    UNIQUE_SCOPES=$(echo "${NEW_SCOPES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    echo "⚡ Login ulang untuk mengaktifkan scopes: $UNIQUE_SCOPES"
    gh auth login -w --scopes "$UNIQUE_SCOPES"
  fi

  read -p "Tekan [Enter] untuk kembali ke menu..."
}

# --- Kelola Kolaborator Repo ---
function manage_collaborators() {
    active_user=$(gh api user --jq .login 2>/dev/null)
    echo -e "${CYAN}=== Daftar repo GitHub (akun: $active_user) ===${NC}"
    repos=$(gh repo list --limit 50 --json name --jq '.[].name')
    echo "$repos" | nl

    read -p "👉 Nomor repo untuk kelola kolaborator: " repo_number
    repo_name=$(echo "$repos" | sed -n "${repo_number}p")
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Nomor repo tidak valid.${NC}"
        pause
        return
    fi

    while true; do
        clear
        echo -e "${BLUE}=== Kelola Kolaborator Repo: $repo_name ===${NC}"
        echo "1) Lihat daftar kolaborator"
        echo "2) Tambah kolaborator"
        echo "3) Hapus kolaborator"
        echo "4) Lihat undangan tertunda (invitations)"
        echo "0) Kembali"
        echo
        read -p "👉 Pilih menu: " sub_choice

        case $sub_choice in
            1)
                echo -e "${CYAN}📜 Daftar kolaborator untuk repo $repo_name:${NC}"
                gh api repos/$active_user/$repo_name/collaborators --jq '.[].login' 2>/dev/null || \
                  echo -e "${YELLOW}⚠️ Belum ada kolaborator atau tidak punya akses melihatnya.${NC}"
                pause
                ;;
            2)
                read -p "👤 Masukkan username GitHub kolaborator: " collab_user
                echo "Pilih permission: 1) pull (read)  2) push (write)  3) admin"
                read -p "👉 Nomor permission: " perm_choice
                case $perm_choice in
                    1) perm="pull" ;;
                    2) perm="push" ;;
                    3) perm="admin" ;;
                    *) echo -e "${RED}❌ Pilihan tidak valid.${NC}" ; pause ; continue ;;
                esac

                TOKEN=$(gh auth token 2>/dev/null)
                if [[ -z "$TOKEN" ]]; then
                    echo -e "${RED}⚠️ Token tidak ditemukan. Login dulu (menu Login).${NC}"
                    pause
                    continue
                fi

                payload="{\"permission\":\"$perm\"}"
                resp_file=$(mktemp)
                http_code=$(curl -s -o "$resp_file" -w "%{http_code}" -X PUT \
                  -H "Authorization: token $TOKEN" \
                  -H "Accept: application/vnd.github+json" \
                  -d "$payload" \
                  "https://api.github.com/repos/$active_user/$repo_name/collaborators/$collab_user")

                if [[ "$http_code" == "201" ]]; then
                    echo -e "${GREEN}✅ Undangan dikirim ke $collab_user (201). Mereka harus menerima undangan untuk menjadi kolaborator.${NC}"
                    echo "📌 Cek undangan tertunda dengan menu -> Lihat undangan tertunda, atau periksa: gh api repos/$active_user/$repo_name/invitations"
                elif [[ "$http_code" == "204" ]]; then
                    echo -e "${GREEN}✅ $collab_user sudah menjadi kolaborator (204).${NC}"
                else
                    echo -e "${RED}❌ Gagal menambahkan kolaborator. HTTP $http_code${NC}"
                    echo "Respons server:"
                    cat "$resp_file"
                fi
                rm -f "$resp_file"
                pause
                ;;           
            3)
                echo -e "${CYAN}📜 Daftar kolaborator untuk repo $repo_name:${NC}"
                collabs=$(gh api repos/$active_user/$repo_name/collaborators --jq '.[].login' 2>/dev/null)

                if [[ -z "$collabs" ]]; then
                    echo -e "${YELLOW}⚠️ Tidak ada kolaborator.${NC}"
                    pause
                    continue
                fi

                            echo "$collabs" | nl
                echo
                read -p "👉 Masukkan nomor kolaborator yang ingin dihapus (bisa lebih dari satu, pisahkan spasi): " nums

                TOKEN=$(gh auth token 2>/dev/null)
                if [[ -z "$TOKEN" ]]; then
                    echo -e "${RED}⚠️ Token tidak ditemukan. Login dulu (menu Login).${NC}"
                    pause
                    continue
                fi

                for n in $nums; do
                    collab_user=$(echo "$collabs" | sed -n "${n}p")
                    if [[ -z "$collab_user" ]]; then
                        echo -e "${RED}❌ Nomor $n tidak valid.${NC}"
                        continue
                    fi

                    resp_file=$(mktemp)
                    http_code=$(curl -s -o "$resp_file" -w "%{http_code}" -X DELETE \
                    -H "Authorization: token $TOKEN" \
                    -H "Accept: application/vnd.github+json" \
                    "https://api.github.com/repos/$active_user/$repo_name/collaborators/$collab_user")

                    if [[ "$http_code" == "204" ]]; then
                        echo -e "${GREEN}✅ Kolaborator $collab_user berhasil dihapus.${NC}"
                    elif [[ "$http_code" == "404" ]]; then
                        echo -e "${YELLOW}⚠️ $collab_user tidak ditemukan atau Anda tidak punya izin.${NC}"
                    else
                        echo -e "${RED}❌ Gagal menghapus $collab_user (HTTP $http_code).${NC}"
                        cat "$resp_file"
                    fi
                    rm -f "$resp_file"
                done
                pause
                ;;
            4)
                echo -e "${CYAN}📨 Undangan tertunda untuk repo $repo_name:${NC}"
                gh api repos/$active_user/$repo_name/invitations --jq '.[] | "\(.id)\t\(.invitee.login)\t\(.permissions)"' 2>/dev/null || \
                  echo -e "${YELLOW}⚠️ Tidak ada undangan tertunda atau tidak punya akses melihatnya.${NC}"
                echo
                echo "📌 Catatan: undangan harus diterima oleh invitee sebelum mereka tampil di daftar kolaborator."
                pause
                ;;
            0) break ;;
            *) echo -e "${RED}❌ Pilihan tidak valid.${NC}" ; pause ;;
        esac
    done
}

# === Main Menu ===
while true; do
    clear
    echo -e "${BLUE}=== $APP_NAME ===${NC}"
    echo
    echo "Menu:"
    echo " 1. Pilih akun aktif"
    echo " 2. Login akun GitHub"
    echo " 3. Upload folder ke repo"
    echo " 4. Tampilkan isi repo"
    echo " 5. Aktifkan GitHub Pages"
    echo " 6. Ubah nama repo"
    echo " 7. Ubah deskripsi repo"
    echo " 8. Hapus repo"
    echo " 9. Lihat & aktifkan token scopes"
    echo "10. Atur Collaborator"
    echo " 0. Keluar"
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
        8) delete_repo ;;
        9) manage_scopes ;;
        10) manage_collaborators ;;
        0) break ;;
        *) echo -e "${RED}❌ Pilihan tidak valid.${NC}" ; pause ;;
    esac
done
