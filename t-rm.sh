#!/usr/bin/env bash
# Silverhawk AutoCLI v0.2
# GitHub repository/file manager
# Online: sh <(curl -fsSL https://silverhawk.web.id/skripkeren/t-rm.sh)
set -u
set -o pipefail

APP="Silverhawk AutoCLI"
VER="0.2.0"
API="https://api.github.com"
TOKEN="${GITHUB_TOKEN:-}"
GH_USER="${GITHUB_USER:-}"
REPO_OWNER=""
REPO_NAME=""
BRANCH=""
CURRENT_PATH=""

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-autocli-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ---------- Terminal UI ----------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_WHITE=$'\033[97m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_CYAN=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_WHITE=""; C_DIM=""; C_BOLD=""
fi
beep(){ printf '\a' 2>/dev/null || true; }
msg_ok(){ echo "${C_GREEN}✔ $*${C_RESET}"; }
msg_warn(){ echo "${C_YELLOW}⚠ $*${C_RESET}"; }
msg_err(){ echo "${C_RED}✖ $*${C_RESET}" >&2; beep; }
msg_info(){ echo "${C_CYAN}ℹ $*${C_RESET}"; }
hr(){ printf '%s\n' "${C_DIM}    ────────────────────────────────────────────────────────────────────────────────${C_RESET}"; }
pause(){ echo; read -r -p "    Tekan Enter untuk melanjutkan... " _ || true; }
title(){
  clear 2>/dev/null || true
  echo
  echo "    ${C_CYAN}${C_BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
  printf "    ${C_CYAN}${C_BOLD}║ %-76s ║${C_RESET}\n" "$APP v$VER"
  echo "    ${C_CYAN}${C_BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo "    ${C_DIM}Account : ${GH_USER:-belum login}    Repo: ${REPO_NAME:--}    Branch: ${BRANCH:--}    Path: /${CURRENT_PATH}${C_RESET}"
  hr
}

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { msg_err "Perintah '$1' tidak ditemukan."; return 1; }; }
urlenc(){
  if command -v jq >/dev/null 2>&1; then jq -nr --arg x "$1" '$x|@uri';
  else printf '%s' "$1" | sed 's/%/%25/g;s/ /%20/g;s/#/%23/g;s/?/%3F/g;s/&/%26/g;s/+/%2B/g'; fi
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
  local field="$1"
  if command -v jq >/dev/null 2>&1; then jq -r --arg f "$field" '.[$f] // ""';
  else sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; fi
}
json_escape(){
  if command -v jq >/dev/null 2>&1; then jq -Rn --arg x "$1" '$x';
  elif command -v python3 >/dev/null 2>&1; then printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))';
  elif command -v python >/dev/null 2>&1; then printf '%s' "$1" | python -c 'import sys,json; print(json.dumps(sys.stdin.read()))';
  else printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\r/\\r/g;s/\n/\\n/g;s/^/"/;s/$/"/'; fi
}

parse_selection(){
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
    elif [[ "$part" =~ ^[0-9]+$ ]]; then SELECTED+=("$part")
    else return 1; fi
  done
  local out=() x seen
  for x in "${SELECTED[@]}"; do
    seen=0; for i in "${out[@]:-}"; do [ "$i" = "$x" ] && seen=1; done
    [ "$seen" -eq 0 ] && out+=("$x")
  done
  SELECTED=("${out[@]}")
}

check_tools(){
  need_cmd curl || exit 1
  if ! command -v jq >/dev/null 2>&1; then
    msg_warn "jq tidak ditemukan. Beberapa fitur memakai parser fallback; install jq untuk hasil paling stabil."
  fi
}

# ---------- Authentication ----------
token_help(){
  title
  echo "    ${C_BOLD}CARA MEMBUAT GITHUB TOKEN${C_RESET}"
  echo
  echo "    1. Buka GitHub dan masuk ke akun Anda."
  echo "    2. Buka: https://github.com/settings/personal-access-tokens"
  echo "    3. Pilih ${C_BOLD}Fine-grained tokens${C_RESET} → Generate new token."
  echo "    4. Beri nama, tentukan masa berlaku, dan pilih repository yang boleh diakses."
  echo "    5. Untuk Silverhawk AutoCLI, aktifkan minimal:"
  echo "       • Repository permissions → Contents: Read and write"
  echo "       • Repository permissions → Metadata: Read-only"
  echo "       • Administration: Read and write   (rename/delete/create repo & sebagian Pages)"
  echo "       • Pages: Read and write             (fitur GitHub Pages)"
  echo "    6. Generate token, lalu COPY token saat ditampilkan."
  echo
  msg_warn "GitHub biasanya hanya menampilkan nilai token lengkap sekali. Jangan kirim token kepada orang lain."
  echo "    Token Silverhawk AutoCLI hanya dipakai selama sesi dan tidak disimpan ke disk oleh script."
  echo
  echo "    Jika browser tidak terbuka otomatis, copy alamat di atas ke browser."
  read -r -p "    Tekan O untuk mencoba membuka halaman token, atau Enter untuk kembali: " c
  if [[ "$c" =~ ^[Oo]$ ]]; then
    if command -v start >/dev/null 2>&1; then start "" "https://github.com/settings/personal-access-tokens" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "https://github.com/settings/personal-access-tokens" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then open "https://github.com/settings/personal-access-tokens" >/dev/null 2>&1 || true
    else msg_warn "Tidak menemukan perintah pembuka browser otomatis."; fi
  fi
}
login(){
  title
  echo "    ${C_BOLD}LOGIN GITHUB${C_RESET}"
  echo
  echo "    Username diperlukan sebagai informasi akun."
  echo "    Token digunakan untuk mengakses GitHub API sesuai izin yang Anda berikan."
  echo
  echo "    ${C_CYAN}[T]${C_RESET} Cara membuat / melihat petunjuk token"
  echo "    ${C_CYAN}[L]${C_RESET} Lanjut login"
  echo "    ${C_CYAN}[M]${C_RESET} Menu utama"
  echo
  read -r -p "    Pilihan: " start
  case "$start" in
    [Tt]) token_help; login; return;;
    [Mm]) return;;
    *) :;;
  esac
  echo
  read -r -p "    GitHub username (opsional, identitas tampilan): " GH_USER
  if [ -z "$TOKEN" ]; then
    read -r -s -p "    GitHub Fine-grained token: " TOKEN; echo
  else
    echo "    Token sudah tersedia dari environment GITHUB_TOKEN."
  fi
  [ -z "$TOKEN" ] && { msg_err "Token kosong."; pause; return; }
  local me login_name
  me=$(api GET "/user" 2>/dev/null) || { TOKEN=""; msg_err "Login gagal. Token salah/kedaluwarsa atau koneksi bermasalah."; pause; return; }
  login_name=$(printf '%s' "$me" | json_field login)
  [ -z "$login_name" ] && { TOKEN=""; msg_err "GitHub tidak mengembalikan username."; pause; return; }
  GH_USER="$login_name"
  msg_ok "Login berhasil sebagai: $GH_USER"
  pause
}

# ---------- Repository ----------
choose_repo(){
  title
  [ -n "$TOKEN" ] || { msg_err "Silakan login dahulu."; pause; return; }
  echo "    ${C_BOLD}DAFTAR REPOSITORY${C_RESET}"
  echo "    Mengambil daftar repo..."
  local all="$TMP_ROOT/repos.json"
  api GET "/user/repos?per_page=100&sort=updated&direction=desc" >"$all" 2>/dev/null || { msg_err "Gagal mengambil repository. Pastikan token punya akses Metadata."; pause; return; }
  REPO_LINES=()
  if command -v jq >/dev/null 2>&1; then mapfile -t REPO_LINES < <(jq -r '.[] | [.name,.private,.default_branch,.html_url] | @tsv' "$all");
  else mapfile -t REPO_LINES < <(grep -o '"name":"[^"]*"' "$all" | sed 's/"name":"//;s/"$//' | awk '{print $0"\t?\t?\t"}'); fi
  if [ "${#REPO_LINES[@]}" -eq 0 ]; then echo "    Tidak ada repository yang dapat diakses token ini."; pause; return; fi
  local i=1 line name priv branch url
  for line in "${REPO_LINES[@]}"; do
    IFS=$'\t' read -r name priv branch url <<< "$line"
    printf "    %3d. %-38s %-8s branch: %s\n" "$i" "$name" "$([ "$priv" = true ] && echo PRIVATE || echo PUBLIC)" "$branch"
    ((i++))
  done
  echo
  echo "    ${C_DIM}M = menu utama${C_RESET}"
  read -r -p "    Pilih nomor repo: " ans
  [[ "$ans" =~ ^[Mm]$ ]] && return
  [[ "$ans" =~ ^[0-9]+$ ]] || { msg_err "Pilihan tidak valid."; pause; return; }
  (( ans>=1 && ans<=${#REPO_LINES[@]} )) || { msg_err "Nomor di luar daftar."; pause; return; }
  IFS=$'\t' read -r REPO_NAME _ BRANCH _ <<< "${REPO_LINES[$((ans-1))]}"
  REPO_OWNER="$GH_USER"; CURRENT_PATH=""
  msg_ok "Repository aktif: $REPO_OWNER/$REPO_NAME [$BRANCH]"
  pause
}

contents_list(){
  local path="${1:-}" enc
  enc=$(urlenc "$path")
  if [ -z "$path" ]; then api GET "/repos/$REPO_OWNER/$REPO_NAME/contents?ref=$(urlenc "$BRANCH")";
  else api GET "/repos/$REPO_OWNER/$REPO_NAME/contents/$enc?ref=$(urlenc "$BRANCH")"; fi
}

get_items(){
  local json="$1"
  if command -v jq >/dev/null 2>&1; then jq -r '.[] | [.name,.type,.sha,.path] | @tsv' <<< "$json";
  else
    echo "$json" | grep -o '{[^}]*}' | while IFS= read -r obj; do
      local n t s p
      n=$(printf '%s' "$obj" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p'); t=$(printf '%s' "$obj" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p'); s=$(printf '%s' "$obj" | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p'); p=$(printf '%s' "$obj" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p');
      [ -n "$n" ] && printf '%s\t%s\t%s\t%s\n' "$n" "$t" "$s" "$p"
    done
  fi
}

# ---------- File browser / navigation ----------
browse(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repository dahulu."; pause; return; }
  local json choice item name typ sha p
  while :; do
    title
    echo "    ${C_BOLD}FILE MANAGER / TELUSURI REPOSITORY${C_RESET}"
    echo "    Folder aktif: ${C_YELLOW}/${CURRENT_PATH}${C_RESET}"
    echo
    json=$(contents_list "$CURRENT_PATH" 2>/dev/null) || { msg_err "Gagal membaca folder. Path mungkin sudah berubah."; pause; return; }
    mapfile -t ITEMS < <(get_items "$json")
    if [ "${#ITEMS[@]}" -eq 0 ]; then echo "    ${C_DIM}(folder kosong)${C_RESET}"; else
      local i=1
      for item in "${ITEMS[@]}"; do
        IFS=$'\t' read -r name typ sha p <<< "$item"
        if [ "$typ" = "dir" ]; then printf "    %3d. ${C_BLUE}📁 [FOLDER]${C_RESET} %s\n" "$i" "$name";
        else printf "    %3d. ${C_WHITE}📄 [FILE]${C_RESET}   %s\n" "$i" "$name"; fi
        ((i++))
      done
    fi
    echo
    echo "    ${C_CYAN}Masukkan nomor FOLDER untuk masuk ke folder tersebut.${C_RESET}"
    echo "    B = naik satu folder   M = menu utama   U = upload ke folder aktif"
    echo "    R = refresh             Q = keluar"
    read -r -p "    Pilihan: " choice
    case "$choice" in
      [Mm]) return;; [Qq]) exit 0;; [Rr]) :;; [Uu]) upload_files;; [Bb])
        if [ -z "$CURRENT_PATH" ]; then msg_info "Anda sudah berada di root repository."; sleep 1;
        else CURRENT_PATH="${CURRENT_PATH%/*}"; fi;;
      *)
        [[ "$choice" =~ ^[0-9]+$ ]] || { msg_err "Masukkan nomor yang tersedia."; sleep 1; continue; }
        ((choice>=1 && choice<=${#ITEMS[@]})) || { msg_err "Nomor tidak valid."; sleep 1; continue; }
        IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((choice-1))]}"
        if [ "$typ" = "dir" ]; then CURRENT_PATH="$p";
        else
          title; echo "    FILE: $p"; hr
          if command -v jq >/dev/null 2>&1; then
            local dl; dl=$(printf '%s' "$json" | jq -r --arg p "$p" '.[]|select(.path==$p)|.download_url // ""')
            [ -n "$dl" ] && curl -fsSL "$dl" 2>/dev/null | head -100 || msg_warn "File tidak dapat ditampilkan.";
          else msg_warn "Install jq untuk preview file."; fi
          pause
        fi;;
    esac
  done
}

# ---------- Upload ----------
base64_file(){ base64 < "$1" 2>/dev/null | tr -d '\r\n'; }
make_upload_json(){
  local file="$1" remote="$2" msg="$3" out="$4" b64
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$remote" "$msg" "$BRANCH" >"$out" <<'PY'
import sys,json,base64
p,remote,msg,branch=sys.argv[1:]
with open(p,'rb') as f: content=base64.b64encode(f.read()).decode('ascii')
print(json.dumps({'message':msg,'content':content,'branch':branch}, separators=(',',':')))
PY
  elif command -v python >/dev/null 2>&1; then
    python - "$file" "$remote" "$msg" "$BRANCH" >"$out" <<'PY'
import sys,json,base64
p,remote,msg,branch=sys.argv[1:]
with open(p,'rb') as f: content=base64.b64encode(f.read()).decode('ascii')
print(json.dumps({'message':msg,'content':content,'branch':branch},separators=(',',':')))
PY
  elif command -v jq >/dev/null 2>&1; then
    b64=$(base64_file "$file") || return 1
    jq -n --arg message "$msg" --arg content "$b64" --arg branch "$BRANCH" '{message:$message,content:$content,branch:$branch}' >"$out"
  else return 2; fi
}
upload_one(){
  local local_file="$1" remote="$2" msg="$3" existing_sha="${4:-}" payload="$TMP_ROOT/upload.json"
  make_upload_json "$local_file" "$remote" "$msg" "$payload" || return 2
  if [ -n "$existing_sha" ]; then
    if command -v jq >/dev/null 2>&1; then jq --arg sha "$existing_sha" '.sha=$sha' "$payload" >"$payload.tmp" && mv "$payload.tmp" "$payload";
    else return 2; fi
  fi
  curl -fsS -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "$API/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$remote")" --data-binary @"$payload" >/dev/null
}
upload_files(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repository dahulu."; pause; return; }
  title
  echo "    ${C_BOLD}UPLOAD SEMUA FILE DARI FOLDER LOKAL${C_RESET}"
  echo
  echo "    Folder tujuan GitHub aktif: ${C_YELLOW}/${CURRENT_PATH}${C_RESET}"
  echo "    Pilih folder lokal yang berisi file yang ingin diupload."
  echo "    Semua file di dalamnya akan diupload secara rekursif dan struktur subfolder dipertahankan."
  echo
  read -r -p "    Path folder lokal (contoh C:/Users/Ted/Documents/web): " localdir
  [ -d "$localdir" ] || { msg_err "Folder lokal tidak ditemukan."; pause; return; }
  localdir=$(cd "$localdir" 2>/dev/null && pwd) || { msg_err "Tidak dapat membuka folder lokal."; pause; return; }
  mapfile -t LOCAL_FILES < <(find "$localdir" -type f -print 2>/dev/null)
  [ "${#LOCAL_FILES[@]}" -gt 0 ] || { msg_warn "Tidak ada file di folder tersebut."; pause; return; }
  echo
  echo "    Ditemukan ${#LOCAL_FILES[@]} file."
  echo "    Contoh tujuan: ${CURRENT_PATH:-/}"
  echo
  read -r -p "    Ketik UPLOAD untuk mulai: " confirm
  [ "$confirm" = "UPLOAD" ] || { echo "    Dibatalkan."; pause; return; }
  echo
  local count=0 fail=0 f rel remote
  for f in "${LOCAL_FILES[@]}"; do
    rel="${f#"$localdir"/}"
    remote="${CURRENT_PATH:+$CURRENT_PATH/}$rel"
    remote="${remote#/}"
    printf "    Upload: %s → /%s ... " "$rel" "$remote"
    if upload_one "$f" "$remote" "Silverhawk AutoCLI: upload $rel"; then echo "${C_GREEN}OK${C_RESET}"; ((count++)); else echo "${C_RED}GAGAL${C_RESET}"; ((fail++)); fi
  done
  echo; hr
  msg_ok "Upload selesai: $count berhasil, $fail gagal."
  pause
}

# ---------- Delete ----------
collect_files_recursive(){
  local path="$1" json item typ sha p name
  json=$(contents_list "$path" 2>/dev/null) || return 1
  while IFS=$'\t' read -r name typ sha p; do
    if [ "$typ" = "dir" ]; then collect_files_recursive "$p" || return 1
    elif [ "$typ" = "file" ]; then FILE_ITEMS+=("$name"$'\t'"$sha"$'\t'"$p"); fi
  done < <(get_items "$json")
}
delete_files(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repository dahulu."; pause; return; }
  title; echo "    ${C_BOLD}HAPUS FILE / FOLDER${C_RESET}"; echo "    Folder aktif: /${CURRENT_PATH}"; echo
  local json item i name typ sha p
  json=$(contents_list "$CURRENT_PATH" 2>/dev/null) || { msg_err "Gagal membaca folder."; pause; return; }
  mapfile -t ITEMS < <(get_items "$json")
  [ "${#ITEMS[@]}" -gt 0 ] || { msg_info "Folder ini kosong."; pause; return; }
  for i in "${!ITEMS[@]}"; do IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$i]}"; printf "    %3d. [%s] %s\n" "$((i+1))" "$typ" "$name"; done
  echo
  echo "    Contoh: 1-12   atau   1, 3, 6-10, 14-22"
  echo "    M = menu utama"
  read -r -p "    Yang akan dihapus: " sel
  [[ "$sel" =~ ^[Mm]$ ]] && return
  parse_selection "$sel" || { msg_err "Format pilihan tidak valid."; pause; return; }
  [ "${#SELECTED[@]}" -gt 0 ] || { msg_err "Tidak ada item dipilih."; pause; return; }
  echo; echo "    Item terpilih:"
  for i in "${SELECTED[@]}"; do
    ((i>=1 && i<=${#ITEMS[@]})) || { msg_err "Nomor $i di luar daftar."; pause; return; }
    IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((i-1))]}"; echo "      - [$typ] $p"
  done
  echo; read -r -p "    Ketik HAPUS untuk konfirmasi: " confirm
  [ "$confirm" = "HAPUS" ] || { echo "    Dibatalkan."; pause; return; }
  local deleted=0
  for i in "${SELECTED[@]}"; do
    IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((i-1))]}"
    if [ "$typ" = "file" ]; then
      local payload; payload=$(printf '{"message":"Silverhawk AutoCLI: delete %s","sha":"%s","branch":"%s"}' "$p" "$sha" "$BRANCH")
      if api DELETE "/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$p")" "$payload" >/dev/null 2>&1; then msg_ok "Hapus: $p"; ((deleted++)); else msg_err "Gagal: $p"; fi
    else
      FILE_ITEMS=(); collect_files_recursive "$p" || { msg_err "Gagal membaca folder: $p"; continue; }
      for f in "${FILE_ITEMS[@]}"; do
        IFS=$'\t' read -r fname fsha fpath <<< "$f"
        local fpayload; fpayload=$(printf '{"message":"Silverhawk AutoCLI: delete %s","sha":"%s","branch":"%s"}' "$fpath" "$fsha" "$BRANCH")
        if api DELETE "/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$fpath")" "$fpayload" >/dev/null 2>&1; then msg_ok "Hapus: $fpath"; ((deleted++)); else msg_err "Gagal: $fpath"; fi
      done
    fi
  done
  echo; msg_ok "Selesai. File yang berhasil dihapus: $deleted"; pause
}

# ---------- Repository administration ----------
create_repo(){
  title; echo "    ${C_BOLD}BUAT REPOSITORY BARU${C_RESET}"; echo
  read -r -p "    Nama repo: " name; [ -n "$name" ] || { msg_err "Nama repo kosong."; pause; return; }
  read -r -p "    Deskripsi (opsional): " desc; read -r -p "    Private? (y/N): " yn
  local private=false; [[ "$yn" =~ ^[Yy]$ ]] && private=true
  local en descen payload
  en=$(json_escape "$name"); descen=$(json_escape "$desc")
  payload=$(printf '{"name":%s,"description":%s,"private":%s}' "$en" "$descen" "$private")
  if api POST "/user/repos" "$payload" >/dev/null 2>&1; then msg_ok "Repository berhasil dibuat: $name"; else msg_err "Gagal membuat repository. Token perlu Administration: write."; fi
  pause
}
rename_repo(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repo dahulu."; pause; return; }
  title; echo "    ${C_BOLD}RENAME REPOSITORY${C_RESET}"; echo
  read -r -p "    Nama baru: " new; [ -n "$new" ] || { msg_err "Nama baru kosong."; pause; return; }
  read -r -p "    Ketik RENAME untuk konfirmasi: " c; [ "$c" = RENAME ] || { echo "    Dibatalkan."; pause; return; }
  local payload; payload=$(printf '{"name":%s}' "$(json_escape "$new")")
  if api PATCH "/repos/$REPO_OWNER/$REPO_NAME" "$payload" >/dev/null 2>&1; then REPO_NAME="$new"; msg_ok "Repo sekarang: $REPO_OWNER/$new"; else msg_err "Gagal rename repo. Token perlu Administration: write."; fi
  pause
}
delete_repo(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repo dahulu."; pause; return; }
  title; echo "    ${C_BOLD}HAPUS REPOSITORY${C_RESET}"; echo "    Target: $REPO_OWNER/$REPO_NAME"; echo
  msg_warn "GitHub akan menghapus seluruh isi dan riwayat repo."
  read -r -p "    Ketik nama repo persis untuk konfirmasi: " c; [ "$c" = "$REPO_NAME" ] || { echo "    Dibatalkan."; pause; return; }
  if api DELETE "/repos/$REPO_OWNER/$REPO_NAME" >/dev/null 2>&1; then REPO_NAME=""; BRANCH=""; CURRENT_PATH=""; msg_ok "Repo berhasil dihapus."; else msg_err "Gagal menghapus repo. Token perlu Administration: write."; fi
  pause
}
pages_menu(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repo dahulu."; pause; return; }
  title; echo "    ${C_BOLD}GITHUB PAGES / JEKYLL${C_RESET}"; echo
  echo "    1. Aktifkan Pages dari branch aktif ($BRANCH)"
  echo "    2. Matikan Pages"
  echo "    B. Kembali"
  read -r -p "    Pilihan: " c
  case "$c" in
    1) local payload='{"source":{"branch":"'"$BRANCH"'","path":"/"}}'; if api POST "/repos/$REPO_OWNER/$REPO_NAME/pages" "$payload" >/dev/null 2>&1; then msg_ok "GitHub Pages diaktifkan."; else msg_err "Gagal. Periksa izin Pages/Administration atau konfigurasi Pages."; fi; pause;;
    2) if api DELETE "/repos/$REPO_OWNER/$REPO_NAME/pages" >/dev/null 2>&1; then msg_ok "Pages dimatikan."; else msg_err "Gagal mematikan Pages."; fi; pause;;
    [Bb]) return;; *) msg_warn "Pilihan tidak valid."; sleep 1;;
  esac
}
branches_menu(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repo dahulu."; pause; return; }
  title; echo "    ${C_BOLD}BRANCH${C_RESET}"; echo
  local j; j=$(api GET "/repos/$REPO_OWNER/$REPO_NAME/branches?per_page=100" 2>/dev/null) || { msg_err "Gagal membaca branch."; pause; return; }
  if command -v jq >/dev/null 2>&1; then jq -r '.[] | .name' <<< "$j" | nl -w3 -s'. ';
  else echo "$j" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | nl -w3 -s'. '; fi
  echo; echo "    Catatan: pemindahan branch dan rollback riwayat akan ditambahkan pada versi berikutnya."; pause
}

# ---------- Menus ----------
file_manager_menu(){
  while :; do
    title; echo "    ${C_BOLD}FILE MANAGER${C_RESET}"; echo
    echo "    Folder aktif: ${C_YELLOW}/${CURRENT_PATH}${C_RESET}"; echo
    echo "    1. Lihat isi folder aktif"
    echo "    2. Masuk / pindah folder"
    echo "    3. Upload semua file dari folder lokal → folder aktif"
    echo "    4. Hapus file/folder di folder aktif"
    echo "    5. Kembali ke root repository"
    echo "    M. Menu utama"
    echo
    read -r -p "    Pilihan: " c
    case "$c" in
      1|2) browse;;
      3) upload_files;;
      4) delete_files;;
      5) CURRENT_PATH="";;
      [Mm]) return;;
      *) msg_warn "Pilihan tidak valid."; sleep 1;;
    esac
  done
}
settings_menu(){
  while :; do
    title; echo "    ${C_BOLD}PENGELOLAAN REPOSITORY${C_RESET}"; echo
    echo "    1. Pilih / ganti repository"
    echo "    2. File Manager"
    echo "    3. Buat repository baru"
    echo "    4. Rename repository"
    echo "    5. Hapus repository"
    echo "    6. GitHub Pages"
    echo "    7. Branch"
    echo "    M. Menu utama"
    echo
    read -r -p "    Pilihan: " c
    case "$c" in
      1) choose_repo;; 2) file_manager_menu;; 3) create_repo;; 4) rename_repo;; 5) delete_repo;; 6) pages_menu;; 7) branches_menu;; [Mm]) return;; *) msg_warn "Pilihan tidak valid."; sleep 1;;
    esac
  done
}
main_menu(){
  while :; do
    title
    if [ -n "$TOKEN" ]; then echo "    Status: ${C_GREEN}● LOGIN${C_RESET} sebagai $GH_USER"; else echo "    Status: ${C_YELLOW}● BELUM LOGIN${C_RESET}"; fi
    echo
    echo "    ${C_BOLD}AKUN & REPOSITORY${C_RESET}"
    echo "    1. Login / ganti akun GitHub"
    echo "    2. Pilih repository"
    echo "    3. File Manager (browse / pindah folder / upload / hapus)"
    echo "    4. Hapus file/folder cepat"
    echo "    5. Buat repository baru"
    echo "    6. Rename repository"
    echo "    7. Hapus repository"
    echo "    8. GitHub Pages / Jekyll"
    echo "    9. Branch & riwayat"
    echo "    10. Pengaturan repository"
    echo "    11. Bantuan token GitHub"
    echo "    0. Keluar"
    echo
    read -r -p "    Pilihan: " c
    case "$c" in
      1) login;; 2) choose_repo;; 3) file_manager_menu;; 4) delete_files;; 5) create_repo;; 6) rename_repo;; 7) delete_repo;; 8) pages_menu;; 9) branches_menu;; 10) settings_menu;; 11) token_help;; 0) exit 0;; *) msg_warn "Pilihan tidak valid."; sleep 1;;
    esac
  done
}

check_tools
main_menu
