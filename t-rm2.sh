#!/bin/bash
# ==============================================
# 🚀 GitHub Repo Manager - by Teddy
# ==============================================

BASE_DIR=$(pwd)

# --- Fungsi cek GitHub CLI ---
check_github_cli() {
    echo "🔎 Mengecek GitHub CLI..."
    if ! command -v gh &>/dev/null; then
        echo "❌ GitHub CLI belum terpasang."
        if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
            echo "➡️  Mencoba install via winget..."
            if command -v winget &>/dev/null; then
                winget install --id GitHub.cli -e --source winget
            else
                echo "⚠️ Winget tidak tersedia. Silakan unduh manual di https://cli.github.com/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "➡️  Mencoba install via apt..."
            if command -v apt &>/dev/null; then
                sudo apt update && sudo apt install gh -y
            else
                echo "⚠️ Silakan install manual: https://cli.github.com/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            echo "➡️  Mencoba install via brew..."
            if command -v brew &>/dev/null; then
                brew install gh
            else
                echo "⚠️ Brew tidak tersedia. Silakan unduh manual: https://cli.github.com/"
                exit 1
            fi
        else
            echo "⚠️ Sistem operasi tidak dikenali. Install manual di https://cli.github.com/"
            exit 1
        fi
    else
        echo "✅ GitHub CLI sudah terpasang."
    fi
}

# --- Fungsi cek login GitHub CLI ---
check_github_login() {
    echo "🔎 Mengecek status login GitHub..."
    if ! gh auth status &>/dev/null; then
        echo "❌ Belum login ke GitHub."
        echo "➡️  Membuka proses login..."
        gh auth login
    else
        echo "✅ Sudah login ke GitHub."
    fi
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

# --- Fungsi tunggu GitHub Pages selesai build ---
wait_for_pages() {
    echo "⏳ Menunggu GitHub Pages membangun ulang..."
    while true; do
        status=$(gh api repos/$gh_user/$repo/actions/runs --jq '.workflow_runs[0].conclusion' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            echo "✅ Build selesai."
            break
        elif [[ "$status" == "failure" ]]; then
            echo "❌ Build gagal."
            break
        else
            echo "⏳ Masih menunggu..."
            sleep 5
        fi
    done
}

# --- Fungsi menu utama ---
show_menu() {
    clear
    echo "=============================================="
    echo "   🚀 GitHub Repo Manager - by Teddy"
    echo "=============================================="
    echo "📂 PWD aktif: $(pwd)"
    echo
    echo "1) Upload folder ke repo"
    echo "2) Lihat file & folder di repo online"
    echo "3) Aktifkan / buat repo + GitHub Pages"
    echo "0) Keluar"
    echo
    read -p "👉 Pilih menu: " choice

    case $choice in
        1)
            echo "📋 Daftar folder di direktori ini:"
            select folder in */; do
                if [ -n "$folder" ]; then
                    echo "📂 Upload folder: $folder"
                    read -p "👉 Masukkan nama repo di GitHub: " repo
                    git init
                    git remote add origin https://github.com/$gh_user/$repo.git
                    git add "$folder"
                    git commit -m "Upload $folder"
                    git branch -M main
                    git push -u origin main
                    cd "$BASE_DIR"
                    echo "✅ Upload selesai!"
                    read -p "Tekan Enter untuk kembali ke menu..."
                    show_menu
                fi
                break
            done
            ;;
        2)
            read -p "👉 Masukkan nama repo di GitHub: " repo
            echo "📂 Isi repo $repo:"
            gh repo view $gh_user/$repo --web
            read -p "Tekan Enter untuk kembali ke menu..."
            show_menu
            ;;
        3)
            read -p "👉 Masukkan nama repo di GitHub: " repo
            gh repo edit $gh_user/$repo --enable-pages --branch main --path /
            wait_for_pages
            gh repo view $gh_user/$repo --web
            read -p "Tekan Enter untuk kembali ke menu..."
            show_menu
            ;;
        0)
            echo "👋 Keluar..."
            exit 0
            ;;
        *)
            echo "❌ Pilihan tidak valid."
            read -p "Tekan Enter untuk kembali ke menu..."
            show_menu
            ;;
    esac
}

# --- Eksekusi awal ---
check_github_cli
check_github_login
choose_account
show_menu
