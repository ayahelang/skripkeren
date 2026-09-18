#!/usr/bin/env bash
# Silverhawk AutoCLI v0.1
# GitHub repository manager — online execution:
# sh <(curl -fsSL https://silverhawk.web.id/skripkeren/t-rm.sh)
set -u
set -o pipefail

APP="Silverhawk AutoCLI"
VER="0.1.0"
API="https://api.github.com"
TOKEN="${GITHUB_TOKEN:-}"
GH_USER="${GITHUB_USER:-}"
REPO_OWNER=""
REPO_NAME=""
BRANCH=""

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-autocli-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

die(){ echo; echo "ERROR: $*" >&2; pause; }
pause(){ echo; read -r -p "Tekan Enter untuk lanjut..." _ || true; }
hr(){ printf '%*s\n' 72 '' | tr ' ' '-'; }
title(){ clear 2>/dev/null || true; hr; echo "  $APP v$VER"; hr; }

need_cmd(){
  command -v "$1" >/dev/null 2>&1 || { echo "Perintah '$1' tidak ditemukan."; return 1; }
}
urlenc(){
  # Good enough for GitHub owner/repo/path segments.
  printf '%s' "$1" | sed 's/%/%25/g;s/ /%20/g;s/#/%23/g;s/?/%3F/g;s/&/%26/g;s/+/%2B/g'
}
api(){
  local method="$1" endpoint="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -fsS -X "$method" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      "$API$endpoint" --data "$data"
  else
    curl -fsS -X "$method" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$API$endpoint"
  fi
}
json_field(){
  # Extract a simple JSON string field without jq. Prefer jq when available.
  local field="$1"
  if command -v jq >/dev/null 2>&1; then jq -r --arg f "$field" '.[$f] // ""'; else
    sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}
json_array_lines(){
  # Emits "name<TAB>type<TAB>sha<TAB>path" for GitHub content arrays.
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | [.name,.type,.sha,.path] | @tsv'
  else
    # Fallback is intentionally limited; jq is strongly recommended.
    echo "$1" | grep -o '{[^}]*}' | while IFS= read -r obj; do
      n=$(printf '%s' "$obj" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
      t=$(printf '%s' "$obj" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')
      s=$(printf '%s' "$obj" | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p')
      p=$(printf '%s' "$obj" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')
      [ -n "$n" ] && printf '%s\t%s\t%s\t%s\n' "$n" "$t" "$s" "$p"
    done
  fi
}
b64(){
  if command -v base64 >/dev/null 2>&1; then base64 | tr -d '\r\n'; else
    printf '%s' "$1" | python -c 'import sys,base64; print(base64.b64encode(sys.stdin.buffer.read()).decode())'
  fi
}
parse_selection(){
  # Input: 1, 3, 6-10,14-22 -> unique sorted numeric indices.
  local s="$1" part a b i
  s=$(printf '%s' "$s" | tr -d ' ')
  IFS=',' read -ra parts <<< "$s"
  SELECTED=()
  for part in "${parts[@]}"; do
    [ -z "$part" ] && continue
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
      if (( a>b )); then i=$a; a=$b; b=$i; fi
      for ((i=a;i<=b;i++)); do SELECTED+=("$i"); done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      SELECTED+=("$part")
    else
      return 1
    fi
  done
  # unique
  local out=() x seen
  for x in "${SELECTED[@]}"; do
    seen=0; for i in "${out[@]:-}"; do [ "$i" = "$x" ] && seen=1; done
    [ "$seen" -eq 0 ] && out+=("$x")
  done
  SELECTED=("${out[@]}")
}
json_escape(){
  if command -v jq >/dev/null 2>&1; then
    jq -Rn --arg x "$1" '$x'
  else
    printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\r/\\r/g;s/\n/\\n/g' | sed 's/^/"/;s/$/"/'
  fi
}
check_tools(){
  need_cmd curl || exit 1
  if ! command -v jq >/dev/null 2>&1; then
    echo "Catatan: jq tidak ditemukan. AutoCLI memakai parser fallback untuk operasi sederhana."
    echo "Untuk hasil paling stabil, install jq pada terminal Anda."
    sleep 1
  fi
}
login(){
  title
  echo "LOGIN GITHUB"
  echo "GitHub tidak lagi menerima password akun untuk API."
  echo "Gunakan Personal Access Token (PAT) / fine-grained token."
  echo "Token hanya dipakai selama sesi ini dan tidak disimpan ke file."
  echo
  read -r -p "GitHub username (untuk identitas tampilan): " GH_USER
  if [ -z "$TOKEN" ]; then
    read -r -s -p "GitHub token: " TOKEN; echo
  fi
  [ -z "$TOKEN" ] && { die "Token kosong."; return; }
  local me
  me=$(api GET "/user" 2>/dev/null) || { TOKEN=""; die "Login gagal. Periksa token dan koneksi."; return; }
  local login
  login=$(printf '%s' "$me" | json_field login)
  [ -z "$login" ] && { TOKEN=""; die "GitHub tidak mengembalikan username."; return; }
  GH_USER="$login"
  echo "Login berhasil sebagai: $GH_USER"
  pause
}
choose_repo(){
  title
  [ -n "$TOKEN" ] || { die "Silakan login dahulu."; return 1; }
  echo "DAFTAR REPOSITORY"
  echo "Mengambil daftar repo..."
  local all="$TMP_ROOT/repos.json"
  api GET "/user/repos?per_page=100&sort=updated&direction=desc" >"$all" 2>/dev/null || { die "Gagal mengambil repository."; return 1; }
  REPO_LINES=()
  if command -v jq >/dev/null 2>&1; then
    mapfile -t REPO_LINES < <(jq -r '.[] | [.name,.private,.default_branch,.html_url] | @tsv' "$all")
  else
    # fallback: names only, best-effort
    mapfile -t REPO_LINES < <(grep -o '"name":"[^"]*"' "$all" | sed 's/"name":"//;s/"$//' | awk '{print $0"\t?\t?\t"}')
  fi
  if [ "${#REPO_LINES[@]}" -eq 0 ]; then echo "Tidak ada repository."; pause; return 1; fi
  local i=1 line name priv branch url
  for line in "${REPO_LINES[@]}"; do
    IFS=$'\t' read -r name priv branch url <<< "$line"
    printf "%3d. %-35s %-8s branch: %s\n" "$i" "$name" "$([ "$priv" = true ] && echo PRIVATE || echo PUBLIC)" "$branch"
    ((i++))
  done
  echo
  echo "Ketik nomor repo. Ketik M untuk menu utama."
  read -r -p "Pilihan: " ans
  [[ "$ans" =~ ^[Mm]$ ]] && return 1
  [[ "$ans" =~ ^[0-9]+$ ]] || { die "Pilihan tidak valid."; return 1; }
  (( ans>=1 && ans<=${#REPO_LINES[@]} )) || { die "Nomor di luar daftar."; return 1; }
  IFS=$'\t' read -r REPO_NAME _ BRANCH _ <<< "${REPO_LINES[$((ans-1))]}"
  REPO_OWNER="$GH_USER"
  echo "Repository aktif: $REPO_OWNER/$REPO_NAME [$BRANCH]"
  pause
}
contents_list(){
  local path="${1:-}"
  local enc
  enc=$(urlenc "$path")
  if [ -z "$path" ]; then
    api GET "/repos/$REPO_OWNER/$REPO_NAME/contents?ref=$(urlenc "$BRANCH")"
  else
    api GET "/repos/$REPO_OWNER/$REPO_NAME/contents/$enc?ref=$(urlenc "$BRANCH")"
  fi
}
browse(){
  [ -n "$REPO_NAME" ] || { die "Pilih repository dahulu."; return; }
  local path="" json choice
  while :; do
    title
    echo "BROWSE REPOSITORY: $REPO_OWNER/$REPO_NAME"
    echo "Branch: $BRANCH"
    echo "Path : /$path"
    hr
    json=$(contents_list "$path" 2>/dev/null) || { die "Gagal membaca isi path."; return; }
    if command -v jq >/dev/null 2>&1; then
      mapfile -t ITEMS < <(printf '%s' "$json" | jq -r '.[] | [.name,.type,.sha,.path] | @tsv')
    else
      mapfile -t ITEMS < <(json_array_lines "$json")
    fi
    [ "${#ITEMS[@]}" -gt 0 ] || echo "(kosong)"
    local i=1 item name typ sha p
    for item in "${ITEMS[@]}"; do
      IFS=$'\t' read -r name typ sha p <<< "$item"
      printf "%3d. [%s] %s\n" "$i" "$typ" "$name"
      ((i++))
    done
    echo
    echo "Masukkan nomor folder untuk masuk."
    echo "B = kembali satu folder | M = menu utama | Q = keluar"
    read -r -p "Pilihan: " choice
    case "$choice" in
      [Mm]) return;;
      [Qq]) exit 0;;
      [Bb])
        if [ -z "$path" ]; then return; fi
        path="${path%/*}"; [ "$path" = "$path" ] || true
        ;;
      *)
        [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Pilihan tidak valid."; sleep 1; continue; }
        ((choice>=1 && choice<=${#ITEMS[@]})) || { echo "Nomor tidak valid."; sleep 1; continue; }
        IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((choice-1))]}"
        if [ "$typ" = "dir" ]; then path="$p"; else
          title; echo "FILE: $p"; echo
          if command -v jq >/dev/null 2>&1; then
            printf '%s' "$json" | jq -r --arg p "$p" '.[]|select(.path==$p)|.download_url' | xargs -r curl -fsSL | head -100
          else
            echo "Install jq untuk melihat isi file dari browser ini."
          fi
          pause
        fi
        ;;
    esac
  done
}
collect_files_recursive(){
  local path="$1" json item typ sha p name
  json=$(contents_list "$path" 2>/dev/null) || return 1
  if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r name typ sha p; do
      if [ "$typ" = "dir" ]; then collect_files_recursive "$p" || return 1
      elif [ "$typ" = "file" ]; then FILE_ITEMS+=("$name"$'\t'"$sha"$'\t'"$p"); fi
    done < <(printf '%s' "$json" | jq -r '.[] | [.name,.type,.sha,.path] | @tsv')
  else
    echo "Penghapusan folder membutuhkan jq agar daftar file rekursif aman." >&2
    return 2
  fi
}
delete_files(){
  [ -n "$REPO_NAME" ] || { die "Pilih repository dahulu."; return; }
  title; echo "HAPUS FILE / FOLDER"; echo "Repo: $REPO_OWNER/$REPO_NAME"; echo
  local path="" json item i name typ sha p
  json=$(contents_list "" 2>/dev/null) || { die "Gagal membaca repo."; return; }
  if command -v jq >/dev/null 2>&1; then
    mapfile -t ITEMS < <(printf '%s' "$json" | jq -r '.[] | [.name,.type,.sha,.path] | @tsv')
  else
    mapfile -t ITEMS < <(json_array_lines "$json")
  fi
  for i in "${!ITEMS[@]}"; do
    IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$i]}"
    printf "%3d. [%s] %s\n" "$((i+1))" "$typ" "$name"
  done
  echo
  echo "Contoh pilihan: 1-12"
  echo "atau: 1, 3, 6-10, 14-22"
  echo "M = menu utama"
  read -r -p "Yang akan dihapus: " sel
  [[ "$sel" =~ ^[Mm]$ ]] && return
  parse_selection "$sel" || { die "Format pilihan tidak valid."; return; }
  [ "${#SELECTED[@]}" -gt 0 ] || { die "Tidak ada item dipilih."; return; }
  echo
  echo "Item terpilih:"
  for i in "${SELECTED[@]}"; do
    ((i>=1 && i<=${#ITEMS[@]})) || { die "Nomor $i di luar daftar."; return; }
    IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((i-1))]}"
    echo " - [$typ] $p"
  done
  echo
  read -r -p "Ketik HAPUS untuk konfirmasi: " confirm
  [ "$confirm" = "HAPUS" ] || { echo "Dibatalkan."; pause; return; }

  # Files at root: delete directly. Folders: recursively delete all files.
  local deleted=0
  for i in "${SELECTED[@]}"; do
    IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((i-1))]}"
    if [ "$typ" = "file" ]; then
      local payload
      payload=$(printf '{"message":"Silverhawk AutoCLI: delete %s","sha":"%s","branch":"%s"}' "$p" "$sha" "$BRANCH")
      if api DELETE "/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$p")" "$payload" >/dev/null 2>&1; then
        echo "OK hapus file: $p"; ((deleted++))
      else echo "GAGAL: $p"; fi
    elif [ "$typ" = "dir" ]; then
      FILE_ITEMS=()
      collect_files_recursive "$p" || { echo "Gagal membaca folder: $p"; continue; }
      # Delete deepest files first. Contents API removes directory automatically when empty.
      for f in "${FILE_ITEMS[@]}"; do
        IFS=$'\t' read -r fname fsha fpath <<< "$f"
        local fpayload
        fpayload=$(printf '{"message":"Silverhawk AutoCLI: delete %s","sha":"%s","branch":"%s"}' "$fpath" "$fsha" "$BRANCH")
        if api DELETE "/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$fpath")" "$fpayload" >/dev/null 2>&1; then
          echo "OK hapus: $fpath"; ((deleted++))
        else echo "GAGAL: $fpath"; fi
      done
    fi
  done
  echo; echo "Selesai. File yang berhasil dihapus: $deleted"
  pause
}
create_repo(){
  title; echo "BUAT REPOSITORY BARU"; echo
  read -r -p "Nama repo: " name
  [ -n "$name" ] || { die "Nama repo kosong."; return; }
  read -r -p "Deskripsi (opsional): " desc
  read -r -p "Private? (y/N): " yn
  local private=false; [[ "$yn" =~ ^[Yy]$ ]] && private=true
  local payload
  payload=$(printf '{"name":"%s","description":"%s","private":%s}' "$(printf '%s' "$name" | sed 's/"/\\"/g')" "$(printf '%s' "$desc" | sed 's/"/\\"/g')" "$private")
  if api POST "/user/repos" "$payload" >/dev/null 2>&1; then
    echo "Repository berhasil dibuat: $name"
  else echo "Gagal membuat repository."; fi
  pause
}
rename_repo(){
  [ -n "$REPO_NAME" ] || { die "Pilih repo dahulu."; return; }
  title; echo "RENAME REPOSITORY: $REPO_OWNER/$REPO_NAME"; echo
  read -r -p "Nama baru: " new
  [ -n "$new" ] || { die "Nama baru kosong."; return; }
  read -r -p "Ketik RENAME untuk konfirmasi: " c
  [ "$c" = RENAME ] || { echo "Dibatalkan."; pause; return; }
  local payload
  payload=$(printf '{"name":"%s"}' "$(printf '%s' "$new" | sed 's/"/\\"/g')")
  if api PATCH "/repos/$REPO_OWNER/$REPO_NAME" "$payload" >/dev/null 2>&1; then
    echo "Berhasil. Repo sekarang: $REPO_OWNER/$new"
    REPO_NAME="$new"
  else echo "Gagal rename repo."; fi
  pause
}
delete_repo(){
  [ -n "$REPO_NAME" ] || { die "Pilih repo dahulu."; return; }
  title; echo "HAPUS REPOSITORY"; echo "Target: $REPO_OWNER/$REPO_NAME"; echo
  echo "PERINGATAN: GitHub akan menghapus seluruh isi dan riwayat repo."
  read -r -p "Ketik nama repo persis untuk konfirmasi: " c
  [ "$c" = "$REPO_NAME" ] || { echo "Dibatalkan."; pause; return; }
  if api DELETE "/repos/$REPO_OWNER/$REPO_NAME" >/dev/null 2>&1; then
    echo "Repo berhasil dihapus."
    REPO_NAME=""; BRANCH=""
  else echo "Gagal menghapus repo."; fi
  pause
}
pages_menu(){
  [ -n "$REPO_NAME" ] || { die "Pilih repo dahulu."; return; }
  title; echo "GITHUB PAGES / JEKYLL"; echo
  echo "1. Aktifkan Pages dari branch aktif ($BRANCH)"
  echo "2. Matikan Pages"
  echo "3. Kembali"
  read -r -p "Pilihan: " c
  case "$c" in
    1)
      local payload='{"source":{"branch":"'"$BRANCH"'","path":"/"}}'
      if api POST "/repos/$REPO_OWNER/$REPO_NAME/pages" "$payload" >/dev/null 2>&1; then
        echo "GitHub Pages diaktifkan dari / branch $BRANCH."
      else echo "Gagal. Repo mungkin sudah punya Pages atau konfigurasi memerlukan perubahan manual."; fi
      pause;;
    2)
      if api DELETE "/repos/$REPO_OWNER/$REPO_NAME/pages" >/dev/null 2>&1; then echo "Pages dimatikan."; else echo "Gagal mematikan Pages."; fi
      pause;;
    3|*) return;;
  esac
}
branches_menu(){
  [ -n "$REPO_NAME" ] || { die "Pilih repo dahulu."; return; }
  title; echo "BRANCH"; echo
  local j
  j=$(api GET "/repos/$REPO_OWNER/$REPO_NAME/branches?per_page=100" 2>/dev/null) || { die "Gagal membaca branch."; return; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | .name' <<< "$j" | nl -w3 -s'. '
  else echo "$j" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | nl -w3 -s'. '; fi
  echo
  echo "Catatan: pemindahan default branch dan rollback riwayat akan dibuat di versi lanjutan."
  pause
}
settings_menu(){
  while :; do
    title; echo "PENGELOLAAN REPOSITORY"; echo
    echo "Repo aktif: ${REPO_OWNER:-(-)} / ${REPO_NAME:-(-)}"
    echo "Branch    : ${BRANCH:-(-)}"; hr
    echo "1. Pilih / ganti repository"
    echo "2. Browse file & folder"
    echo "3. Hapus file / folder"
    echo "4. Buat repository baru"
    echo "5. Rename repository"
    echo "6. Hapus repository"
    echo "7. GitHub Pages"
    echo "8. Branch"
    echo "M. Menu utama"
    echo
    read -r -p "Pilihan: " c
    case "$c" in
      1) choose_repo;;
      2) browse;;
      3) delete_files;;
      4) create_repo;;
      5) rename_repo;;
      6) delete_repo;;
      7) pages_menu;;
      8) branches_menu;;
      [Mm]) return;;
      *) echo "Pilihan tidak valid."; sleep 1;;
    esac
  done
}
main_menu(){
  while :; do
    title
    echo "Status login : $([ -n "$TOKEN" ] && echo "LOGIN sebagai $GH_USER" || echo "BELUM LOGIN")"
    echo "Repo aktif   : ${REPO_OWNER:-(-)}/${REPO_NAME:-(-)}"
    echo "Branch       : ${BRANCH:-(-)}"
    hr
    echo "1. Login / ganti akun GitHub"
    echo "2. Pilih repository"
    echo "3. Lihat & telusuri file/folder"
    echo "4. Hapus file/folder (1,3,6-10,14-22)"
    echo "5. Buat repository baru"
    echo "6. Rename repository"
    echo "7. Hapus repository (termasuk isinya)"
    echo "8. GitHub Pages / Jekyll"
    echo "9. Branch & riwayat"
    echo "10. Pengaturan repository"
    echo "0. Keluar"
    echo
    read -r -p "Pilihan: " c
    case "$c" in
      1) login;;
      2) choose_repo;;
      3) browse;;
      4) delete_files;;
      5) create_repo;;
      6) rename_repo;;
      7) delete_repo;;
      8) pages_menu;;
      9) branches_menu;;
      10) settings_menu;;
      0) exit 0;;
      *) echo "Pilihan tidak valid."; sleep 1;;
    esac
  done
}
check_tools
main_menu
