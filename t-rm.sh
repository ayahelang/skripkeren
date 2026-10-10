#!/usr/bin/env bash
# Silverhawk AutoCLI v0.2
# GitHub repository/file manager
# Online (Codespaces OK): bash <(curl -fsSL https://skripkeren.silverhawk.web.id/t-rm.sh)
set -u
set -o pipefail

APP="Silverhawk AutoCLI"
VER="0.5.0"
API="https://api.github.com"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
GH_USER="${GITHUB_USER:-}"
REPO_OWNER=""
REPO_NAME=""
BRANCH=""
CURRENT_PATH=""

TMP_ROOT="${TMPDIR:-/tmp}/silverhawk-autocli-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ---------- TTY-safe input (aman di Codespaces & curl|bash) ----------
TTY=/dev/tty
if [ ! -c "$TTY" ] || [ ! -r "$TTY" ] || [ ! -w "$TTY" ]; then
  TTY=/dev/stdin
fi
ask(){ local _a; printf "%s" "$1" >"$TTY"; IFS= read -r _a <"$TTY" || true; printf "%s" "$_a"; }
ask_secret(){ local _a; printf "%s" "$1" >"$TTY"; IFS= read -r -s _a <"$TTY" || true; printf "\n" >"$TTY"; printf "%s" "$_a"; }

# ---------- Terminal UI ----------
if [ -t 1 ] || [ -t 2 ]; then
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
pause(){ echo; ask "    Tekan Enter untuk melanjutkan... " >/dev/null; }
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

# ---------- Environment detection ----------
detect_env(){
  ENV_KIND="desktop"
  ENV_HINT=""
  if [ -n "${CODESPACES:-}" ] || [ -n "${CODESPACE_NAME:-}" ] || [ "${GITHUB_CODESPACES:-}" = "true" ]; then
    ENV_KIND="codespaces"
    ENV_HINT="GitHub Codespaces"
  elif [ -n "${GITHUB_ACTIONS:-}" ]; then
    ENV_KIND="actions"
    ENV_HINT="GitHub Actions"
  elif [ -n "${MSYSTEM:-}" ] || [[ "${OSTYPE:-}" == msys* ]] || [[ "${OSTYPE:-}" == cygwin* ]]; then
    ENV_KIND="windows-gitbash"
    ENV_HINT="Windows Git Bash"
  elif [[ "${OSTYPE:-}" == darwin* ]]; then
    ENV_KIND="macos"
    ENV_HINT="macOS"
  elif [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
    ENV_KIND="linux"
    ENV_HINT="Linux"
  fi
  # Copilot / VS Code terminal often sets TERM_PROGRAM
  if [ -n "${TERM_PROGRAM:-}" ]; then
    ENV_HINT="${ENV_HINT:-terminal} (${TERM_PROGRAM})"
  fi
}

try_token(){
  # $1 = token value, $2 = label
  local tok="$1" label="$2" me login_name
  [ -z "$tok" ] && return 1
  TOKEN="$tok"
  me=$(api GET "/user" 2>/dev/null) || { TOKEN=""; return 1; }
  login_name=$(printf '%s' "$me" | json_field login)
  if [ -z "$login_name" ]; then TOKEN=""; return 1; fi
  GH_USER="$login_name"
  msg_ok "Login berhasil sebagai: $GH_USER  ${C_DIM}(via $label)${C_RESET}"
  return 0
}

auto_login(){
  # 1) Env tokens
  if [ -n "${GITHUB_TOKEN:-}" ] && try_token "$GITHUB_TOKEN" "GITHUB_TOKEN"; then return 0; fi
  if [ -n "${GH_TOKEN:-}" ] && try_token "$GH_TOKEN" "GH_TOKEN"; then return 0; fi
  # 2) gh CLI session
  if command -v gh >/dev/null 2>&1; then
    local t
    t=$(gh auth token 2>/dev/null || true)
    if [ -n "$t" ] && try_token "$t" "gh auth token"; then return 0; fi
  fi
  return 1
}

# ---------- Authentication ----------
token_help(){
  title
  echo "    ${C_BOLD}PANDUAN TOKEN GITHUB (PAT)${C_RESET}"
  echo
  echo "    GitHub tidak mengizinkan membuat token hanya dengan username+password."
  echo "    Yang bisa otomatis: wizard ini + browser, atau login via gh (opsi 2)."
  echo
  echo "    ${C_CYAN}[W]${C_RESET} Jalankan wizard buat PAT (disarankan)"
  echo "    ${C_CYAN}[Enter]${C_RESET} Kembali"
  local c
  c=$(ask "    Pilihan: ")
  [[ "$c" =~ ^[Ww]$ ]] && wizard_create_pat
}

open_url(){
  local url="$1"
  echo
  echo "    ┌────────────────────────────────────────────────────────────┐"
  echo "    │  BUKA LINK INI (Ctrl+klik / Cmd+klik di Codespaces):       │"
  echo "    └────────────────────────────────────────────────────────────┘"
  echo
  echo "    ${C_GREEN}${C_BOLD}${url}${C_RESET}"
  echo
  # OSC-8 hyperlink (VS Code / Windows Terminal / iTerm)
  printf "    "
  printf "\033]8;;%s\033\\" "$url"
  printf "${C_CYAN}${C_BOLD}👉 KLIK DI SINI UNTUK BUKA HALAMAN TOKEN${C_RESET}"
  printf "\033]8;;\033\\"
  printf "\n\n"
  echo "    ${C_DIM}Jika tidak bisa diklik: salin URL hijau di atas ke tab browser baru.${C_RESET}"
  echo

  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process \"$url\"" >/dev/null 2>&1 || true
  fi
  if command -v code >/dev/null 2>&1; then
    code --open-url "$url" >/dev/null 2>&1 || true
  fi
  [ -n "${BROWSER:-}" ] && "$BROWSER" "$url" >/dev/null 2>&1 || true
}

# Wizard: user isi data → buka halaman GitHub → tempel token → login
wizard_create_pat(){
  title
  echo "    ${C_BOLD}WIZARD BUAT PERSONAL ACCESS TOKEN${C_RESET}"
  echo

  # --- Link & panduan DULUAN (sebelum input) ---
  local default_url="https://github.com/settings/tokens/new?description=silverhawk-upload&scopes=repo"
  echo "    ${C_BOLD}LANGKAH CEPAT:${C_RESET}"
  echo "      1. Buka link di bawah (Ctrl+klik / Cmd+klik)"
  echo "      2. Login GitHub jika diminta"
  echo "      3. Centang scope ${C_CYAN}repo${C_RESET}"
  echo "      4. Klik ${C_BOLD}Generate token${C_RESET}"
  echo "      5. Copy token ${C_YELLOW}ghp_....${C_RESET} (hanya tampil sekali)"
  echo "      6. Kembali ke terminal ini, isi form singkat, lalu tempel token"
  echo
  open_url "$default_url"
  echo "    ${C_DIM}Link alternatif Fine-grained:${C_RESET}"
  echo "    https://github.com/settings/personal-access-tokens/new"
  echo
  echo "    ────────────────────────────────────────────────────────"
  echo "    Isi data di bawah (boleh Enter = pakai default), lalu tempel token."
  echo

  local note_name repo_hint kind
  echo "    ${C_DIM}Nama token BEBAS (hanya label di GitHub, bukan kode rahasia).${C_RESET}"
  note_name=$(ask "    1) Nama token [silverhawk-upload]: ")
  [ -z "$note_name" ] && note_name="silverhawk-upload"

  echo
  echo "    2) Jenis token:"
  echo "       [1] Classic PAT (paling mudah) ${C_DIM}— default / disarankan${C_RESET}"
  echo "       [2] Fine-grained (repo tertentu)"
  kind=$(ask "    Pilih 1 atau 2 [1]: ")
  [ -z "$kind" ] && kind="1"

  repo_hint=$(ask "    3) Repo yang perlu write [darulistiqomah]: ")
  [ -z "$repo_hint" ] && repo_hint="${REPO_NAME:-darulistiqomah}"

  echo
  echo "    ${C_BOLD}Ringkasan:${C_RESET}  $note_name  |  $([ "$kind" = "2" ] && echo Fine-grained || echo Classic)  |  repo: $repo_hint"
  echo

  # Buka ulang URL yang lebih spesifik setelah user isi nama
  if [ "$kind" = "2" ]; then
    echo "    Untuk Fine-grained, buka lagi link ini lalu atur repo + Contents: Read and write:"
    open_url "https://github.com/settings/personal-access-tokens/new"
  else
    local url
    url="https://github.com/settings/tokens/new?description=$(urlenc "$note_name")&scopes=repo"
    echo "    Link Classic dengan nama token Anda:"
    open_url "$url"
  fi

  echo "    Setelah Generate token di browser, tempel di sini:"
  echo
  local t
  t=$(ask_secret "    Tempel PAT (ghp_...) : ")
  if [ -z "$t" ]; then
    msg_err "Token kosong. Wizard dibatalkan."
    pause
    return 1
  fi
  TOKEN=""
  GH_USER=""
  if try_token "$t" "PAT wizard"; then
    msg_ok "Token aktif. Silakan pilih repo lalu upload."
    pause
    return 0
  fi
  msg_err "Token ditolak GitHub. Cek scope repo, generate ulang, coba lagi."
  pause
  return 1
}

login_via_gh(){
  if ! command -v gh >/dev/null 2>&1; then
    msg_err "GitHub CLI (gh) belum terpasang."
    echo "    Install: bash <(curl -fsSL https://skripkeren.silverhawk.web.id/installgitcli.sh)"
    pause
    return 1
  fi
  title
  echo "    ${C_BOLD}LOGIN VIA GITHUB CLI (gh auth)${C_RESET}"
  echo
  echo "    Ini cara paling nyaman: GitHub memberi kode, Anda buka browser,"
  echo "    lalu izinkan — ${C_BOLD}tanpa mengetik password di terminal${C_RESET}."
  echo
  echo "    Scope yang diminta: repo, workflow, read:org"
  echo
  local go
  go=$(ask "    Lanjut? (Y/n): ")
  [[ "$go" =~ ^[Nn]$ ]] && return 1

  # Device/web flow — works on Codespaces, desktop, remote SSH
  # stdin/stdout harus ke terminal asli
  if gh auth login -h github.com -p https -w -s repo,workflow,read:org,delete_repo <"$TTY" >"$TTY" 2>"$TTY"; then
    local t
    t=$(gh auth token 2>/dev/null || true)
    if [ -n "$t" ] && try_token "$t" "gh auth login"; then
      pause
      return 0
    fi
  fi
  # Fallback tanpa -w (device code flow)
  msg_info "Mencoba mode device code..."
  if gh auth login -h github.com -p https -s repo,workflow,read:org,delete_repo <"$TTY" >"$TTY" 2>"$TTY"; then
    local t
    t=$(gh auth token 2>/dev/null || true)
    if [ -n "$t" ] && try_token "$t" "gh auth login"; then
      pause
      return 0
    fi
  fi
  msg_err "Login gh gagal atau dibatalkan."
  pause
  return 1
}

login_manual_pat(){
  title
  echo "    ${C_BOLD}LOGIN MANUAL (tempel PAT)${C_RESET}"
  echo
  echo "    Username GitHub hanya untuk tampilan; yang menentukan akses adalah token."
  echo
  local u
  u=$(ask "    GitHub username (opsional): ")
  [ -n "$u" ] && GH_USER="$u"
  local t
  t=$(ask_secret "    Tempel PAT / Fine-grained token: ")
  [ -z "$t" ] && { msg_err "Token kosong."; pause; return 1; }
  if try_token "$t" "PAT manual"; then
    pause
    return 0
  fi
  msg_err "Token ditolak GitHub (salah, kedaluwarsa, atau scope kurang)."
  echo "    Coba buat ulang token dengan scope 'repo', lalu login lagi."
  pause
  return 1
}

login(){
  detect_env
  title
  echo "    ${C_BOLD}LOGIN GITHUB${C_RESET}"
  echo "    Lingkungan terdeteksi: ${C_CYAN}${ENV_HINT:-$ENV_KIND}${C_RESET}"
  echo
  echo "    Script memakai GitHub API. Username+password saja ${C_BOLD}tidak cukup${C_RESET}"
  echo "    (kebijakan GitHub sejak 2021)."
  echo

  # Coba deteksi sesi yang ada (tanpa menutup menu)
  local had_session=0
  if [ -n "$TOKEN" ] && [ -n "$GH_USER" ]; then
    had_session=1
  elif auto_login; then
    had_session=1
  fi

  if [ "$had_session" -eq 1 ]; then
    msg_ok "Sesi aktif: $GH_USER"
    if [ -n "${CODESPACES:-}" ] || [ -n "${CODESPACE_NAME:-}" ]; then
      msg_warn "Token Codespaces sering HANYA write ke 1 repo (tempat Codespace dibuka)."
      echo "    Untuk upload ke repo lain (mis. darulistiqomah), pilih ${C_BOLD}[3] PAT${C_RESET} atau ${C_BOLD}[2] gh auth${C_RESET}."
    fi
    echo
    echo "    ${C_CYAN}[Enter / M]${C_RESET} Pakai sesi ini, kembali ke menu utama"
  else
    msg_info "Belum ada sesi valid."
    echo
  fi

  echo "    ${C_CYAN}[1]${C_RESET} Auto-detect lagi (Codespaces token / gh session)"
  echo "    ${C_CYAN}[2]${C_RESET} Login via GitHub CLI — browser/device code ${C_DIM}(disarankan)${C_RESET}"
  echo "    ${C_CYAN}[3]${C_RESET} Tempel PAT manual ${C_DIM}(untuk write ke banyak repo)${C_RESET}"
  echo "    ${C_CYAN}[4]${C_RESET} Panduan buat PAT (+ buka browser)"
  echo "    ${C_CYAN}[M]${C_RESET} Menu utama"
  echo
  local start
  start=$(ask "    Pilihan: ")
  case "$start" in
    ""|[Mm]) return ;;
    1)
      TOKEN=""; GH_USER=""
      if auto_login; then
        msg_ok "Sesi: $GH_USER"
        echo "    Jika upload masih 403, pilih [3] PAT yang punya akses repo target."
      else
        msg_warn "Tidak ketemu token valid. Coba [2] atau [3]."
      fi
      pause
      login
      ;;
    2)
      TOKEN=""; GH_USER=""
      login_via_gh || true
      login
      ;;
    3)
      TOKEN=""; GH_USER=""
      login_manual_pat || true
      login
      ;;
    4) wizard_create_pat || true; login ;;
    *) msg_warn "Pilihan tidak valid."; sleep 1; login ;;
  esac
}

# ---------- Repository ----------
choose_repo(){
  title
  [ -n "$TOKEN" ] || { msg_err "Silakan login dahulu."; pause; return; }
  echo "    ${C_BOLD}DAFTAR REPOSITORY${C_RESET}"
  echo "    Mengambil daftar repo..."
  local all="$TMP_ROOT/repos.json" status body
  # GitHub recommends GET /user/repos for the authenticated user. It supports
  # fine-grained PATs when Repository Metadata is Read-only.
  status=$(curl -sS -o "$all" -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API/user/repos?per_page=100&sort=updated&direction=desc") || status="000"
  if [ "$status" != "200" ]; then
    echo
    msg_err "GitHub mengembalikan HTTP $status saat mengambil daftar repository."
    if command -v jq >/dev/null 2>&1; then
      body=$(jq -r '.message // empty' "$all" 2>/dev/null)
      [ -n "$body" ] && echo "    Pesan GitHub: $body"
    else
      body=$(sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$all" | head -1)
      [ -n "$body" ] && echo "    Pesan GitHub: $body"
    fi
    echo
    echo "    Saran perbaikan:"
    echo "      • Codespaces: pastikan GITHUB_TOKEN punya akses repo (Settings → Codespaces secrets)"
    echo "      • Fine-grained PAT: Metadata Read + Contents Read/Write + repo yang dituju"
    echo "      • Classic PAT: scope 'repo' (full control of private repositories)"
    echo "      • Login ulang (menu 1) dengan token yang benar"
    pause; return
  fi
  REPO_LINES=()
  if command -v jq >/dev/null 2>&1; then mapfile -t REPO_LINES < <(jq -r '.[] | [.name,.private,.default_branch,.html_url] | @tsv' "$all");
  else mapfile -t REPO_LINES < <(grep -o '"name":"[^"]*"' "$all" | sed 's/"name":"//;s/"$//' | awk '{print $0"\t?\t?\t"}'); fi
  if [ "${#REPO_LINES[@]}" -eq 0 ]; then
    echo "    Tidak ada repository yang dikembalikan oleh token ini."
    echo
    msg_warn "Kemungkinan paling umum: token Fine-grained belum diberi akses ke repository tersebut."
    echo "    Buka GitHub → Settings → Developer settings → Personal access tokens"
    echo "    → Fine-grained tokens → pilih token → pastikan Repository access mencakup repo Anda."
    echo
    echo "    Anda juga dapat memilih [C] untuk mencoba repository berdasarkan nama."
    empty_choice=$(ask "    C = coba nama repo / Enter = kembali: ")
    if [[ "$empty_choice" =~ ^[Cc]$ ]]; then
      echo
      manual_repo=$(ask "    Nama repository (contoh: cbt): ")
      if [ -n "$manual_repo" ]; then
        local one
        one=$(api GET "/repos/$GH_USER/$manual_repo" 2>/dev/null) || one=""
        if [ -n "$one" ] && command -v jq >/dev/null 2>&1 && [ "$(jq -r '.name // empty' <<< "$one")" = "$manual_repo" ]; then
          REPO_NAME=$(jq -r '.name' <<< "$one")
          BRANCH=$(jq -r '.default_branch // "main"' <<< "$one")
          REPO_OWNER="$GH_USER"; CURRENT_PATH=""
          msg_ok "Repository aktif: $REPO_OWNER/$REPO_NAME [$BRANCH]"
          pause; return
        fi
        msg_err "Repository tidak dapat diakses dengan token ini."
        echo "    Pastikan repo tersebut termasuk dalam Repository access token."
        pause
      fi
    else
      pause
    fi
    return
  fi
  local i=1 line name priv branch url
  for line in "${REPO_LINES[@]}"; do
    IFS=$'\t' read -r name priv branch url <<< "$line"
    printf "    %3d. %-38s %-8s branch: %s\n" "$i" "$name" "$([ "$priv" = true ] && echo PRIVATE || echo PUBLIC)" "$branch"
    ((i++))
  done
  echo
  echo "    ${C_DIM}M = menu utama${C_RESET}"
  ans=$(ask "    Pilih nomor repo: ")
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
    choice=$(ask "    Pilihan: ")
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
  local local_file="$1" remote="$2" msg="$3" existing_sha="${4:-}"
  local payload="$TMP_ROOT/upload-$$.json" resp="$TMP_ROOT/upload-resp-$$.json" code
  make_upload_json "$local_file" "$remote" "$msg" "$payload" || return 2

  if [ -z "$existing_sha" ]; then
    local meta
    meta=$(curl -sS -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$API/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$remote")?ref=$(urlenc "$BRANCH")" 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1; then
      existing_sha=$(printf '%s' "$meta" | jq -r '.sha // empty' 2>/dev/null)
    else
      existing_sha=$(printf '%s' "$meta" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    fi
  fi
  if [ -n "$existing_sha" ] && command -v jq >/dev/null 2>&1; then
    jq --arg sha "$existing_sha" '.sha=$sha' "$payload" >"$payload.tmp" && mv "$payload.tmp" "$payload"
  fi

  code=$(curl -sS -o "$resp" -w '%{http_code}' -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "$API/repos/$REPO_OWNER/$REPO_NAME/contents/$(urlenc "$remote")" --data-binary @"$payload" 2>/dev/null || echo "000")

  if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    rm -f "$payload" "$resp"; return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    if gh api -X PUT "repos/$REPO_OWNER/$REPO_NAME/contents/$remote" --input "$payload" >/dev/null 2>&1; then
      rm -f "$payload" "$resp"; return 0
    fi
  fi

  LAST_UPLOAD_CODE="$code"
  if command -v jq >/dev/null 2>&1; then
    LAST_UPLOAD_MSG=$(jq -r '.message // empty' "$resp" 2>/dev/null)
  else
    LAST_UPLOAD_MSG=$(sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$resp" | head -1)
  fi
  rm -f "$payload" "$resp"
  return 1
}

check_write_access(){
  local code
  code=$(curl -sS -o "$TMP_ROOT/perm.json" -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API/repos/$REPO_OWNER/$REPO_NAME" 2>/dev/null || echo "000")
  if [ "$code" != "200" ]; then
    msg_err "Tidak bisa akses repo $REPO_OWNER/$REPO_NAME (HTTP $code)."
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    local can_push
    can_push=$(jq -r '.permissions.push // false' "$TMP_ROOT/perm.json" 2>/dev/null)
    local can_admin
    can_admin=$(jq -r '.permissions.admin // false' "$TMP_ROOT/perm.json" 2>/dev/null)
    if [ "$can_push" != "true" ] && [ "$can_admin" != "true" ]; then
      msg_err "Token TIDAK punya izin WRITE ke $REPO_OWNER/$REPO_NAME."
      echo
      echo "    ${C_BOLD}Ini penyebab HTTP 403.${C_RESET}"
      echo "    Token Codespaces bawaan biasanya HANYA boleh write ke repo tempat"
      echo "    Codespace dibuka (videogallery), bukan ke darulistiqomah."
      echo
      echo "    ${C_BOLD}Perbaiki dengan salah satu:${C_RESET}"
      echo "      1) Menu 1 Login → opsi [3] tempel PAT (Contents: Read and write"
      echo "         untuk repo darulistiqomah / classic PAT scope repo)"
      echo "      2) Buka Codespace dari repo darulistiqomah sendiri"
      echo "      3) Di terminal Codespaces: gh auth login  (lalu login ulang di menu)"
      echo
      return 1
    fi
  fi
  msg_ok "Izin write ke $REPO_OWNER/$REPO_NAME terdeteksi."
  return 0
}

# --- Path resolver: Windows / WSL / Git Bash / Codespaces ---
# User boleh input C:\Users\... ; di Codespaces dicari folder yang sama namanya di /workspaces
resolve_local_dir(){
  local raw="$1" p drive rest cand leaf parent
  RESOLVED_DIR=""
  p=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']//;s/["'\'']$//')
  p=$(printf '%s' "$p" | sed 's|\\|/|g')
  [[ "$p" == ~* ]] && p="${p/#\~/$HOME}"

  local candidates=()
  candidates+=("$p")
  if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
    drive="${BASH_REMATCH[1],,}"; rest="${BASH_REMATCH[2]}"
    candidates+=("/${drive}/${rest}" "/mnt/${drive}/${rest}" "/cygdrive/${drive}/${rest}")
  fi
  if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    drive="${BASH_REMATCH[1],,}"; rest="${BASH_REMATCH[2]}"
    candidates+=("/${drive}/${rest}" "/mnt/${drive}/${rest}" "/cygdrive/${drive}/${rest}")
  fi

  local seen="|" 
  for cand in "${candidates[@]}"; do
    [ -z "$cand" ] && continue
    [[ "$seen" == *"|$cand|"* ]] && continue
    seen="${seen}${cand}|"
    if [ -d "$cand" ]; then
      RESOLVED_DIR=$(cd "$cand" 2>/dev/null && pwd)
      [ -n "$RESOLVED_DIR" ] && return 0
    fi
  done

  # Fallback cerdas: ambil nama folder terakhir dari path Windows
  # C:\Users\JW\Downloads\darulistiqomah-website\darulistiqomah → darulistiqomah
  leaf="${p##*/}"
  leaf="${leaf%/}"
  [ -z "$leaf" ] && return 1

  echo "    ${C_DIM}Path langsung tidak ada di mesin ini. Mencari folder bernama '${leaf}' ...${C_RESET}"

  local found=()
  local search_roots=()
  [ -d /workspaces ] && search_roots+=("/workspaces")
  [ -n "${HOME:-}" ] && search_roots+=("$HOME")
  search_roots+=("$(pwd)" "/tmp")

  local root
  for root in "${search_roots[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' d; do
      found+=("$d")
    done < <(find "$root" -maxdepth 6 -type d -name "$leaf" -print0 2>/dev/null)
  done

  # juga cari parent-leaf (darulistiqomah-website/darulistiqomah)
  parent="${p%/*}"
  parent="${parent##*/}"
  if [ -n "$parent" ] && [ "$parent" != "$leaf" ] && [ "$parent" != "Users" ]; then
    for root in "${search_roots[@]}"; do
      [ -d "$root" ] || continue
      while IFS= read -r -d '' d; do
        found+=("$d")
      done < <(find "$root" -maxdepth 6 -type d -path "*/${parent}/${leaf}" -print0 2>/dev/null)
    done
  fi

  # dedupe found
  local uniq=() u
  seen="|"
  for u in "${found[@]}"; do
    [[ "$seen" == *"|$u|"* ]] && continue
    seen="${seen}${u}|"
    uniq+=("$u")
  done

  if [ "${#uniq[@]}" -eq 1 ]; then
    RESOLVED_DIR="${uniq[0]}"
    echo "    ${C_GREEN}✔ Ditemukan otomatis:${C_RESET} $RESOLVED_DIR"
    return 0
  fi
  if [ "${#uniq[@]}" -gt 1 ]; then
    echo "    Ditemukan beberapa folder '${leaf}':"
    local i=1
    for u in "${uniq[@]}"; do
      printf "      %d) %s\n" "$i" "$u"
      ((i++))
    done
    local pick
    pick=$(ask "    Pilih nomor folder: ")
    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#uniq[@]}" ]; then
      RESOLVED_DIR="${uniq[$((pick-1))]}"
      echo "    ${C_GREEN}✔ Dipilih:${C_RESET} $RESOLVED_DIR"
      return 0
    fi
  fi
  return 1
}

upload_files(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repository dahulu."; pause; return; }
  title
  echo "    ${C_BOLD}UPLOAD SEMUA FILE DARI FOLDER LOKAL${C_RESET}"
  echo
  echo "    Folder tujuan GitHub aktif: ${C_YELLOW}/${CURRENT_PATH}${C_RESET}"
  echo "    Working directory saat ini: ${C_DIM}$(pwd)${C_RESET}"
  echo
  if [ -n "${CODESPACES:-}" ] || [ -n "${CODESPACE_NAME:-}" ]; then
    echo "    ${C_DIM}Mode Codespaces: boleh tempel path Windows (C:\\Users\\...).${C_RESET}"
    echo "    ${C_DIM}Script akan mencari folder dengan nama yang sama di /workspaces.${C_RESET}"
    echo "    ${C_DIM}Pastikan folder sudah ada di Codespaces (sekali saja: drag ke Explorer kiri).${C_RESET}"
    echo
  fi
  echo "    Tempel path folder (Windows / Linux / relative semuanya diterima):"
  echo "      contoh: C:\\Users\\JW\\Downloads\\darulistiqomah-website\\darulistiqomah"
  echo
  localdir=$(ask "    Path folder lokal: ")
  if ! resolve_local_dir "$localdir"; then
    msg_err "Folder tidak ditemukan di mesin tempat script berjalan."
    echo "    Input: $localdir"
    echo
    if [ -n "${CODESPACES:-}" ] || [ -n "${CODESPACE_NAME:-}" ]; then
      echo "    ${C_BOLD}Di Codespaces wajib sekali ini:${C_RESET}"
      echo "      1. Drag folder 'darulistiqomah' ke panel file kiri Codespaces"
      echo "      2. Jalankan upload lagi, tempel path Windows yang sama"
      echo "      Script akan menemukan folder itu otomatis di /workspaces."
      echo
      echo "    Cek cepat apakah folder sudah masuk cloud:"
      echo "      find /workspaces -maxdepth 5 -type d -name 'darulistiqomah' 2>/dev/null"
    else
      echo "    Pastikan path ada. Coba: ls \"/c/Users/JW/Downloads/...\""
    fi
    pause
    return
  fi
  localdir="$RESOLVED_DIR"
  echo "    ${C_GREEN}✔ Siap upload dari:${C_RESET} $localdir"
  mapfile -t LOCAL_FILES < <(find "$localdir" -type f -print 2>/dev/null)
  [ "${#LOCAL_FILES[@]}" -gt 0 ] || { msg_warn "Tidak ada file di folder tersebut."; pause; return; }
  echo
  echo "    Ditemukan ${#LOCAL_FILES[@]} file."
  echo "    Contoh tujuan: ${CURRENT_PATH:-/}"
  echo
  confirm=$(ask "    Ketik UPLOAD untuk mulai: ")
  [ "$confirm" = "UPLOAD" ] || { echo "    Dibatalkan."; pause; return; }
  echo
  if ! check_write_access; then
    pause
    return
  fi
  echo
  local count=0 fail=0 f rel remote
  LAST_UPLOAD_CODE=""; LAST_UPLOAD_MSG=""
  for f in "${LOCAL_FILES[@]}"; do
    rel="${f#"$localdir"/}"
    remote="${CURRENT_PATH:+$CURRENT_PATH/}$rel"
    remote="${remote#/}"
    [[ "$rel" == .git/* ]] && continue
    printf "    Upload: %s → /%s ... " "$rel" "$remote"
    if upload_one "$f" "$remote" "Silverhawk AutoCLI: upload $rel"; then
      echo "${C_GREEN}OK${C_RESET}"; ((count++))
    else
      echo "${C_RED}GAGAL${C_RESET} (HTTP ${LAST_UPLOAD_CODE:-?}${LAST_UPLOAD_MSG:+: $LAST_UPLOAD_MSG})"
      ((fail++))
      if [ "$LAST_UPLOAD_CODE" = "403" ] || [ "$LAST_UPLOAD_CODE" = "401" ]; then
        echo
        msg_err "Izin ditolak — sisa upload dihentikan."
        echo "    Login ulang (menu 1) dengan PAT yang write ke repo $REPO_NAME"
        break
      fi
    fi
  done
  echo; hr
  if [ "$fail" -eq 0 ]; then msg_ok "Upload selesai: $count berhasil, $fail gagal."
  else msg_warn "Upload selesai: $count berhasil, $fail gagal."; fi
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
  sel=$(ask "    Yang akan dihapus: ")
  [[ "$sel" =~ ^[Mm]$ ]] && return
  parse_selection "$sel" || { msg_err "Format pilihan tidak valid."; pause; return; }
  [ "${#SELECTED[@]}" -gt 0 ] || { msg_err "Tidak ada item dipilih."; pause; return; }
  echo; echo "    Item terpilih:"
  for i in "${SELECTED[@]}"; do
    ((i>=1 && i<=${#ITEMS[@]})) || { msg_err "Nomor $i di luar daftar."; pause; return; }
    IFS=$'\t' read -r name typ sha p <<< "${ITEMS[$((i-1))]}"; echo "      - [$typ] $p"
  done
  echo; confirm=$(ask "    Ketik HAPUS untuk konfirmasi: ")
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
  name=$(ask "    Nama repo: "); [ -n "$name" ] || { msg_err "Nama repo kosong."; pause; return; }
  desc=$(ask "    Deskripsi (opsional): "); yn=$(ask "    Private? (y/N): ")
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
  new=$(ask "    Nama baru: "); [ -n "$new" ] || { msg_err "Nama baru kosong."; pause; return; }
  c=$(ask "    Ketik RENAME untuk konfirmasi: "); [ "$c" = RENAME ] || { echo "    Dibatalkan."; pause; return; }
  local payload; payload=$(printf '{"name":%s}' "$(json_escape "$new")")
  if api PATCH "/repos/$REPO_OWNER/$REPO_NAME" "$payload" >/dev/null 2>&1; then REPO_NAME="$new"; msg_ok "Repo sekarang: $REPO_OWNER/$new"; else msg_err "Gagal rename repo. Token perlu Administration: write."; fi
  pause
}
delete_repo(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repo dahulu."; pause; return; }
  title; echo "    ${C_BOLD}HAPUS REPOSITORY${C_RESET}"; echo "    Target: $REPO_OWNER/$REPO_NAME"; echo
  msg_warn "GitHub akan menghapus seluruh isi dan riwayat repo."
  c=$(ask "    Ketik nama repo persis untuk konfirmasi: "); [ "$c" = "$REPO_NAME" ] || { echo "    Dibatalkan."; pause; return; }
  if api DELETE "/repos/$REPO_OWNER/$REPO_NAME" >/dev/null 2>&1; then REPO_NAME=""; BRANCH=""; CURRENT_PATH=""; msg_ok "Repo berhasil dihapus."; else msg_err "Gagal menghapus repo. Token perlu Administration: write."; fi
  pause
}
pages_menu(){
  [ -n "$REPO_NAME" ] || { msg_err "Pilih repo dahulu."; pause; return; }
  title; echo "    ${C_BOLD}GITHUB PAGES / JEKYLL${C_RESET}"; echo
  echo "    1. Aktifkan Pages dari branch aktif ($BRANCH)"
  echo "    2. Matikan Pages"
  echo "    B. Kembali"
  c=$(ask "    Pilihan: ")
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
    c=$(ask "    Pilihan: ")
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
    c=$(ask "    Pilihan: ")
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
    c=$(ask "    Pilihan: ")
    case "$c" in
      1) login;; 2) choose_repo;; 3) file_manager_menu;; 4) delete_files;; 5) create_repo;; 6) rename_repo;; 7) delete_repo;; 8) pages_menu;; 9) branches_menu;; 10) settings_menu;; 11) token_help;; 0) exit 0;; *) msg_warn "Pilihan tidak valid."; sleep 1;;
    esac
  done
}

check_tools
detect_env
# Coba login diam-diam jika token/env sudah ada (Codespaces, dll.)
if auto_login 2>/dev/null; then
  :
else
  TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
fi
main_menu
