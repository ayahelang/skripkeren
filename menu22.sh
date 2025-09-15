#!/bin/bash
# ==============================================
# 🚀 GitHub Repo Manager - by Teddy (multi akun otomatis + Windows fix)
# ==============================================

BASE_DIR=$(pwd)

# --- Cari file hosts.yml di berbagai OS ---
find_hosts_file() {
  local candidates=()

  # Prioritas: override via env
  if [ -n "$GH_HOSTS_FILE" ]; then
    candidates+=("$GH_HOSTS_FILE")
  fi

  # XDG (Linux/modern)
  if [ -n "$XDG_CONFIG_HOME" ]; then
    candidates+=("$XDG_CONFIG_HOME/gh/hosts.yml")
  fi

  # Linux/mac klasik
  if [ -n "$HOME" ]; then
    candidates+=("$HOME/.config/gh/hosts.yml")
  fi

  # Windows (Git Bash): %APPDATA%\GitHub CLI\hosts.yml
  if [ -n "$APPDATA" ]; then
    candidates+=("$APPDATA/GitHub CLI/hosts.yml")
  fi

  # Windows fallback pakai USERPROFILE
  if [ -n "$USERPROFILE" ]; then
    candidates+=("$USERPROFILE/AppData/Roaming/GitHub CLI/hosts.yml")
  fi

  for f in "${candidates[@]}"; do
    if [ -f "$f" ]; then
      HOSTS_FILE="$f"
      return 0
    fi
  done
  return 1
}

# --- Tampilkan menu utama ---
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

# --- Pilih folder lokal ---
choose_local_folder() {
    echo
    echo "📋 Daftar folder di direktori ini:"
    i=1
    folders=()
    shopt -s nullglob
    for d in */ ; do
      echo "  $i) ${d%/}"
      folders[$i]="${d%/}"
      ((i++))
    done
    shopt -u nullglob
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
    # realpath di Git Bash kadang tidak ada; fallback
    if command -v realpath >/dev/null 2>&1; then
      src_path="$(realpath "$local_folder")"
    else
      pushd "$local_folder" >/dev/null || return 1
      src_path="$(pwd)"
      popd >/dev/null
    fi
}

# --- Pilih akun (auto dari hosts.yml) ---
choose_account() {
    echo
    echo "🔎 Mendeteksi akun GitHub dari gh auth login..."

    accounts=()

    if find_hosts_file; then
        # Baca YAML: host key berada di kolom 0, user diindent 2 spasi
        current_host=""
        while IFS= read -r rawline; do
            # hapus CR (Windows)
            line="${rawline%$'\r'}"

            # host baris seperti: github.com:   atau github.com-alias:
            if [[ $line =~ ^([[:alnum:].-]+):[[:space:]]*$ ]]; then
                current_host="${BASH_REMATCH[1]}"
                continue
            fi

            # user baris seperti: "  user: namauser"
            if [[ -n "$current_host" && $line =~ ^[[:space:]]*user:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
                current_user="${BASH_REMATCH[1]}"
                accounts+=("$current_user|$current_host")
                # jangan reset host; entri berikutnya (oauth_token, dll) akan di-skip otomatis
                continue
            fi
        done < "$HOSTS_FILE"
    fi

    # Fallback: coba dari gh auth status (default host)
    if [ ${#accounts[@]} -eq 0 ] && command -v gh >/dev/null 2>&1; then
        status_out="$(gh auth status 2>&1)"
        if [[ $status_out =~ Logged[[:space:]]in[[:space:]]to[[:space:]]([^[:space:]]+)[[:space:]]as[[:space:]]([^[:space:]]+) ]]; then
            accounts+=("${BASH_REMATCH[2]}|${BASH_REMATCH[1]}")
        fi
    fi

    if [ ${#accounts[@]} -eq 0 ]; then
        echo "⚠️ Tidak ada akun terdeteksi."
        echo "   Silakan login (bisa multi-akun) misal:"
        echo "   gh auth login                          # akun default"
        echo "   gh auth login --hostname github.com-kerja   # akun kedua"
        read -p "👉 Tekan ENTER untuk kembali..." _
        return 1
    fi

    echo "📋 Akun terdeteksi:"
    idx=1
    for acc in "${accounts[@]}"; do
        user="${acc%%|*}"
        host="${acc##*|}"
        echo "  $idx) $user  (host: $host)"
        ((idx++))
    done

    read -p "👉 Pilih nomor akun: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -lt $idx ]]; then
        selected="${accounts[$((choice-1))]}"
        gh_user="${selected%%|*}"
        GH_HOST="${selected##*|}"
    else
        echo "❌ Pilihan tidak valid"
        return 1
    fi

    echo "✅ Gunakan akun: $gh_user (host: $GH_HOST)"
}

# --- Pilih repo ---
choose_repo() {
    echo
    repos=()
    if command -v gh &>/dev/null; then
      echo "🔎 Mengambil daftar repo dari akun $gh_user..."
      while IFS= read -r repo; do
        repos+=("$repo")
      done < <(gh --hostname "$GH_HOST" repo list "$gh_user" --limit 30 --json name -q '.[].name' 2>/dev/null)
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
      if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -lt $idx ]]; then
        gh_repo="${repos[$((choice-1))]}"
      else
        gh_repo="$choice"
      fi
    fi
}

# --- Upload folder ---
upload_to_repo() {
    choose_local_folder || return
    choose_account || return
    choose_repo
    read -p "📂 Masukkan nama folder tujuan di repo (kosong = root repo): " repo_folder

    tmp_dir=$(mktemp -d)
    echo "⏳ Clone repo $gh_user/$gh_repo ..."

    # Ambil token dari gh auth untuk host terpilih
    if gh --hostname "$GH_HOST" auth status &>/dev/null; then
        GH_TOKEN=$(gh --hostname "$GH_HOST" auth token)
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
      rm -rf "$repo_folder"/*
      cp -r "$src_path/"* "$repo_folder/"
    else
      rm -rf ./*
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
    choose_account || return
    choose_repo
    echo
    echo "📂 Daftar file & folder di repo $gh_user/$gh_repo (branch main):"
    echo "-------------------------------------------------------------"
    if command -v gh &>/dev/null; then
      gh --hostname "$GH_HOST" api "repos/$gh_user/$gh_repo/contents" --jq '.[].name' || echo "❌ Tidak bisa ambil daftar file"
    else
      echo "⚠️ GitHub CLI (gh) belum terinstal."
    fi
    echo "-------------------------------------------------------------"
    read -p "👉 Tekan ENTER untuk kembali ke menu..."
}

# --- Aktifkan / buat repo + GitHub Pages ---
activate_repo() {
    choose_account || return
    echo "📂 Daftar Repository GitHub untuk user $gh_user:"
    echo "--------------------------------------------"
    REPOS=($(gh --hostname "$GH_HOST" repo list "$gh_user" --limit 30 --json name --jq '.[].name'))
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
      gh --hostname "$GH_HOST" repo create "$gh_user/$REPO" --public
    fi

    HTML_CONTENT="<h1>GitHub Pages <b>${REPO}</b> sudah aktif 🎉</h1><p>Silakan berkreasi dan ganti file ini</p>"
    if ! gh --hostname "$GH_HOST" api "repos/$gh_user/$REPO/contents/index.html" >/dev/null 2>&1; then
      gh --hostname "$GH_HOST" api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        "repos/$gh_user/$REPO/contents/index.html" \
        -f message="Add index.html" \
        -f content="$(echo "$HTML_CONTENT" | base64 -w 0 2>/dev/null || echo "$HTML_CONTENT" | base64)"
    fi

    echo "⚡ Mengaktifkan GitHub Pages ..."
    gh --hostname "$GH_HOST" api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      "repos/$gh_user/$REPO/pages" \
      -f "source[branch]=main" -f "source[path]=/" || true

    echo "⏳ Menunggu GitHub Pages aktif..."
    SECONDS=0
    MAX_WAIT=180   # detik
    while true; do
      STATUS=$(gh --hostname "$GH_HOST" api "repos/$gh_user/$REPO/pages" --jq .status 2>/dev/null)
      if [[ "$STATUS" == "built" ]]; then
        break
      fi
      if (( SECONDS >= MAX_WAIT )); then
        echo
        echo "⏱️ Timeout menunggu Pages. Status terakhir: ${STATUS:-unknown}"
        break
      fi
      echo -ne "⌛ Status: ${STATUS:-menunggu} | Elapsed: ${SECONDS}s\r"
      sleep 3
    done

    echo
    PAGES_URL=$(gh --hostname "$GH_HOST" api "repos/$gh_user/$REPO/pages" --jq .html_url 2>/dev/null)
    if [ -n "$PAGES_URL" ]; then
      echo "✅ GitHub Pages aktif setelah ${SECONDS}s!"
      echo "🔗 $PAGES_URL"
      # Windows Git Bash: gunakan start jika tersedia
      command -v start >/dev/null 2>&1 && start "$PAGES_URL" || xdg-open "$PAGES_URL" 2>/dev/null || open "$PAGES_URL" 2>/dev/null || true
    else
      echo "ℹ️ Cek halaman Pages di tab Settings → Pages di GitHub."
    fi
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
