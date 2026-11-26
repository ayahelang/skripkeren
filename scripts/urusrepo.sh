#!/usr/bin/env bash
# =============================================================================
#  urusrepo.sh
#  Utilitas interaktif kelola repo GitHub
#  — Codespaces & Git Bash (desktop)
#
#  Developed by James What
# =============================================================================
# Cara jalankan (universal):
#   curl -fsSL https://skripkeren.silverhawk.web.id/scripts/urusrepo.sh | bash
# atau:
#   bash urusrepo.sh
# =============================================================================


# --- Skripkeren auto-deps ---
_SK_DEPS_URL="${SK_DEPS_URL:-https://skripkeren.silverhawk.web.id/scripts/sk-deps.sh}"
_sk_load_deps() {
  if [[ -n "${_SK_DEPS_LOADED:-}" ]]; then return 0; fi
  local _dir _f _tmp
  _dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || _dir="."
  for _f in "$_dir/sk-deps.sh" "./sk-deps.sh"; do
    if [[ -f "$_f" ]]; then
      # shellcheck source=/dev/null
      source "$_f"
      return 0
    fi
  done
  _tmp="$(mktemp 2>/dev/null || echo /tmp/sk-deps-$$.sh)"
  if command -v curl >/dev/null 2>&1 && curl -fsSL "$_SK_DEPS_URL" -o "$_tmp" 2>/dev/null; then
    # shellcheck source=/dev/null
    source "$_tmp"
    rm -f "$_tmp"
    return 0
  fi
  rm -f "$_tmp" 2>/dev/null || true
  return 1
}
_sk_load_deps || true

set -euo pipefail

# ---------- warna & helper ----------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
  RED=; GREEN=; YELLOW=; CYAN=; BOLD=; DIM=; NC=
fi

info()  { printf '%s➜%s %s\n' "$CYAN" "$NC" "$*"; }
ok()    { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%s!%s %s\n' "$YELLOW" "$NC" "$*"; }
err()   { printf '%s✗%s %s\n' "$RED" "$NC" "$*"; }
die()   { err "$*"; exit 1; }
pause() { echo; read -r -p "Tekan Enter untuk lanjut..." _ || true; }

header() {
  clear 2>/dev/null || true
  echo -e "${BOLD}==============================================${NC}"
  echo -e "${BOLD}  urusrepo.sh — kelola repo GitHub${NC}"
  echo -e "${DIM}  Developed by James What${NC}"
  echo -e "${BOLD}==============================================${NC}"
  echo -e " Lingkungan : ${CYAN}${ENV_LABEL}${NC}"
  if [[ -n "${ACTIVE_REPO:-}" ]]; then
    echo -e " Repo aktif : ${CYAN}${ACTIVE_REPO}${NC}"
  fi
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e " Folder     : ${CYAN}$(pwd)${NC}"
    echo -e " Branch     : ${CYAN}$(git branch --show-current 2>/dev/null || echo '?')${NC}"
  fi
  echo
}

confirm() {
  local msg="${1:-Lanjut?}"
  read -r -p "$msg [y/N] " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ---------- deteksi lingkungan ----------
detect_env() {
  ENV_KIND="unknown"
  ENV_LABEL="Tidak diketahui"

  if [[ -n "${CODESPACES:-}" || -n "${GITHUB_CODESPACE_TOKEN:-}" || "${HOSTNAME:-}" == *-codespaces* ]]; then
    ENV_KIND="codespaces"
    ENV_LABEL="GitHub Codespaces"
    return
  fi
  if [[ -f /workspaces/.codespaces/shared/environment-variables.json ]] 2>/dev/null; then
    ENV_KIND="codespaces"
    ENV_LABEL="GitHub Codespaces"
    return
  fi
  # Git Bash / MSYS / Cygwin (desktop Windows)
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*)
      ENV_KIND="gitbash"
      ENV_LABEL="Git Bash (desktop)"
      return
      ;;
  esac
  # macOS / Linux desktop
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    ENV_KIND="gitbash"
    ENV_LABEL="WSL / desktop"
    return
  fi
  ENV_KIND="desktop"
  ENV_LABEL="Desktop / terminal lokal"
}

# ---------- state ----------
ACTIVE_REPO=""
GH_USER=""
GH_TOKEN=""
REMOTE_URL=""

need_git() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Folder ini bukan git repository. cd ke root repo dulu."
}

current_branch() {
  git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}


# ---------- dependency: Python (Git Bash / Windows) ----------
# Cari interpreter Python yang benar-benar bisa import sys (bukan alias Microsoft Store)
find_working_python() {
  local cand cmd
  # 1) perintah di PATH, uji import
  for cmd in python python3 py; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if [[ "$cmd" == "py" ]]; then
        if py -3 -c "import sys" >/dev/null 2>&1; then
          echo "py -3"
          return 0
        fi
      else
        if "$cmd" -c "import sys" >/dev/null 2>&1; then
          # Tolak WindowsApps (Store stub) jika path mengarah ke sana
          local resolved
          resolved=$(command -v "$cmd" 2>/dev/null || true)
          if [[ "$resolved" == *WindowsApps* ]]; then
            continue
          fi
          echo "$cmd"
          return 0
        fi
      fi
    fi
  done

  # 2) Path umum installer python.org (tanpa restart Git Bash)
  local home winuser
  home="${HOME:-}"
  winuser="${USERNAME:-${USER:-}}"
  local -a paths=(
    "$home/AppData/Local/Programs/Python/Python312/python.exe"
    "$home/AppData/Local/Programs/Python/Python313/python.exe"
    "$home/AppData/Local/Programs/Python/Python311/python.exe"
    "$home/AppData/Local/Programs/Python/Python310/python.exe"
    "/c/Users/$winuser/AppData/Local/Programs/Python/Python312/python.exe"
    "/c/Users/$winuser/AppData/Local/Programs/Python/Python313/python.exe"
    "/c/Users/$winuser/AppData/Local/Programs/Python/Python311/python.exe"
    "/c/Python312/python.exe"
    "/c/Python313/python.exe"
    "/c/Program Files/Python312/python.exe"
    "/c/Program Files/Python313/python.exe"
  )
  # glob Python3*
  local d
  for d in "$home"/AppData/Local/Programs/Python/Python3*/python.exe \
           /c/Users/"$winuser"/AppData/Local/Programs/Python/Python3*/python.exe; do
    [[ -x "$d" || -f "$d" ]] && paths+=("$d")
  done

  for cand in "${paths[@]}"; do
    if [[ -f "$cand" ]] && "$cand" -c "import sys" >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

disable_windows_python_store_alias() {
  # Hapus stub Microsoft Store agar tidak menahan nama "python"
  local apps
  apps="${LOCALAPPDATA:-$HOME/AppData/Local}/Microsoft/WindowsApps"
  if [[ -d "$apps" ]]; then
    info "Menonaktifkan alias Microsoft Store untuk python (jika ada)…"
    rm -f "$apps/python.exe" "$apps/python3.exe" "$apps/python3.12.exe" "$apps/python3.11.exe" 2>/dev/null || true
    # Via PowerShell registry AppExecutionAlias (best-effort)
    powershell.exe -NoProfile -Command '
      $names = @("python.exe","python3.exe")
      foreach ($n in $names) {
        $p = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\$n"
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
      }
    ' 2>/dev/null || true
  fi
}

install_python_windows() {
  info "Mencoba install Python otomatis…"
  echo "  Metode: winget (Python.Python.3.12) — butuh koneksi internet"
  echo "  Setelah install, PATH mungkin perlu sesi Git Bash baru."
  echo

  if command -v winget >/dev/null 2>&1; then
    info "Menjalankan winget install Python.Python.3.12 …"
    winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements \
      || cmd.exe //c "winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements" \
      || return 1
  elif command -v cmd.exe >/dev/null 2>&1; then
    info "winget via cmd.exe…"
    cmd.exe //c "winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements" || return 1
  else
    err "winget tidak tersedia. Install manual: https://www.python.org/downloads/ (centang Add to PATH)"
    return 1
  fi

  # Refresh PATH di sesi ini (best-effort)
  local winuser home
  home="${HOME:-}"
  winuser="${USERNAME:-${USER:-}}"
  local d
  for d in "$home"/AppData/Local/Programs/Python/Python3* \
           /c/Users/"$winuser"/AppData/Local/Programs/Python/Python3*; do
    if [[ -d "$d" && -f "$d/python.exe" ]]; then
      export PATH="$d:$d/Scripts:$PATH"
      info "PATH sesi ini ditambah: $d"
    fi
  done
  return 0
}

# Pastikan Python siap; auto-install di Windows/Git Bash jika kurang
ensure_python() {
  local found
  found=$(find_working_python 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    PY_CMD="$found"
    return 0
  fi

  warn "Python belum terdeteksi (atau hanya alias Microsoft Store)."
  echo
  echo "Script akan mencoba:"
  echo "  1) Nonaktifkan alias Store python.exe / python3.exe"
  echo "  2) Install Python 3.12 lewat winget (jika belum ada)"
  echo "  3) Cari lagi python.exe di folder installer umum"
  echo
  if [[ "${ENV_KIND:-}" == "gitbash" || "$(uname -s 2>/dev/null)" == MINGW* || "$(uname -s 2>/dev/null)" == MSYS* ]]; then
    printf "Lanjut auto-setup Python di Windows? [Y/n] "
    local a=""
    read -r a || true
    a="${a:-Y}"
    if [[ "${a,,}" == "n" || "${a,,}" == "no" ]]; then
      die "Python wajib. Install dari https://www.python.org/downloads/ (centang Add to PATH), tutup Git Bash, buka lagi."
    fi
    disable_windows_python_store_alias
    found=$(find_working_python 2>/dev/null || true)
    if [[ -n "$found" ]]; then
      PY_CMD="$found"
      ok "Python ditemukan setelah menonaktifkan alias Store: $PY_CMD"
      return 0
    fi
    install_python_windows || true
    disable_windows_python_store_alias
    found=$(find_working_python 2>/dev/null || true)
    if [[ -n "$found" ]]; then
      PY_CMD="$found"
      ok "Python siap: $PY_CMD"
      return 0
    fi
    err "Python masih belum terdeteksi di sesi ini."
    echo "  Lakukan:"
    echo "  1) Tutup SEMUA jendela Git Bash"
    echo "  2) Buka Git Bash baru"
    echo "  3) Jalankan: python --version"
    echo "  4) Ulangi urusrepo.sh"
    die "Restart Git Bash lalu coba lagi."
  fi

  die "Python tidak tersedia. Install python3 lalu jalankan ulang script."
}


# ---------- wizard login (desktop / git bash) ----------
wizard_login() {
  header
  echo -e "${BOLD}Login GitHub${NC}"
  echo -e "${DIM}Catatan: GitHub tidak lagi menerima password akun biasa untuk API/git."
  echo -e "Pakai Personal Access Token (PAT) dengan scope: repo.${NC}"
  echo
  read -r -p "Username GitHub: " GH_USER
  [[ -z "$GH_USER" ]] && die "Username wajib."
  echo -n "Personal Access Token (PAT): "
  # sembunyikan input
  stty -echo 2>/dev/null || true
  read -r GH_TOKEN
  stty echo 2>/dev/null || true
  echo
  [[ -z "$GH_TOKEN" ]] && die "Token wajib."

  info "Mengambil daftar repo milik ${GH_USER}…"
  local api_resp
  api_resp=$(curl -fsSL -H "Authorization: token ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner" 2>/dev/null) \
    || die "Gagal login / ambil repo. Cek username & token."

  # Pastikan Python siap (deteksi path Windows + auto-install winget bila perlu)
  local PY=""
  PY_CMD=""
  if [[ -n "${SK_PYTHON:-}" ]]; then
    PY="$SK_PYTHON"
  else
    ensure_python
    PY="$PY_CMD"
  fi
  info "Parser: ${PY} ($($PY -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo '?'))"

  # Parse via file sementara (lebih andal di Git Bash daripada mapfile + process substitution)
  local tmp_json tmp_list
  tmp_json=$(mktemp 2>/dev/null || echo "./.urusrepo-repos-$$.json")
  tmp_list=$(mktemp 2>/dev/null || echo "./.urusrepo-list-$$.txt")
  printf '%s' "$api_resp" > "$tmp_json"

  if ! $PY -c '
import sys, json
path = sys.argv[1]
try:
  data = json.load(open(path, encoding="utf-8"))
except Exception as e:
  print("JSON error:", e, file=sys.stderr)
  sys.exit(1)
if isinstance(data, dict):
  msg = data.get("message") or data.get("error") or str(data)
  print(msg, file=sys.stderr)
  sys.exit(2)
if not isinstance(data, list):
  print("Unexpected API response type", file=sys.stderr)
  sys.exit(2)
for i, r in enumerate(data, 1):
  if not isinstance(r, dict):
    continue
  print("%d\t%s\t%s" % (i, r.get("full_name", ""), r.get("clone_url", "")))
' "$tmp_json" > "$tmp_list"; then
    rm -f "$tmp_json" "$tmp_list" 2>/dev/null || true
    die "Gagal parse daftar repo. Cek token (scope repo) / response API."
  fi

  REPO_LIST=()
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] && REPO_LIST+=("$line")
  done < "$tmp_list"
  rm -f "$tmp_json" "$tmp_list" 2>/dev/null || true

  if [[ ${#REPO_LIST[@]} -eq 0 ]]; then
    die "Tidak ada repo ditemukan. Pastikan token classic scope \"repo\", atau fine-grained: Repository access + Metadata read."
  fi

  echo
  echo -e "${BOLD}Pilih repo:${NC}"
  local line num name
  for line in "${REPO_LIST[@]}"; do
    num="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    name="${rest%%$'\t'*}"
    printf "  %3s) %s\n" "$num" "$name"
  done
  echo
  read -r -p "Nomor repo: " pick
  local chosen=""
  for line in "${REPO_LIST[@]}"; do
    num="${line%%$'\t'*}"
    if [[ "$num" == "$pick" ]]; then
      chosen="$line"
      break
    fi
  done
  [[ -z "$chosen" ]] && die "Nomor tidak valid."

  rest="${chosen#*$'\t'}"
  ACTIVE_REPO="${rest%%$'\t'*}"
  REMOTE_URL="${rest#*$'\t'}"

  ok "Repo dipilih: ${ACTIVE_REPO}"

  # Clone atau masuk folder
  local repo_dir="${ACTIVE_REPO##*/}"
  if [[ -d "$repo_dir/.git" ]]; then
    info "Folder ${repo_dir} sudah ada. Masuk ke sana."
    cd "$repo_dir"
  else
    info "Clone ${ACTIVE_REPO}…"
    # embed token untuk HTTPS clone sekali
    local auth_url="https://${GH_USER}:${GH_TOKEN}@github.com/${ACTIVE_REPO}.git"
    git clone "$auth_url" "$repo_dir" || die "Clone gagal."
    cd "$repo_dir"
    # jangan simpan token di remote URL permanen
    git remote set-url origin "https://github.com/${ACTIVE_REPO}.git"
  fi

  # credential helper session (opsional)
  git config --local credential.helper "store --file=/tmp/.urusrepo-cred-$$" 2>/dev/null || true
  printf 'https://%s:%s@github.com\n' "$GH_USER" "$GH_TOKEN" > "/tmp/.urusrepo-cred-$$" 2>/dev/null || true

  ok "Siap mengurus: $(pwd)"
  pause
}

# ---------- 1) kosongkan repo (kecuali CNAME, *.sh, exclude user) ----------
menu_empty_repo() {
  header
  echo -e "${BOLD}[1] Kosongkan isi repo (kecuali CNAME & file .sh)${NC}"
  echo
  need_git
  warn "PERINGATAN: file/folder di working tree akan dihapus (kecuali yang dikecualikan)."
  warn "Ini belum otomatis push — hanya lokal di Codespaces/folder ini."
  echo
  read -r -p "Pengecualian tambahan (spasi-pisah, opsional, contoh: README.md images): " extra_ex
  echo
  echo "Yang TIDAK dihapus:"
  echo "  - CNAME"
  echo "  - semua file *.sh"
  echo "  - .git/"
  [[ -n "$extra_ex" ]] && echo "  - tambahan: $extra_ex"
  echo
  confirm "Yakin kosongkan repo lokal?" || { warn "Dibatalkan."; pause; return; }

  # bangun find exclusions
  local -a find_args=( . -mindepth 1 -maxdepth 1 )
  # skip .git
  find_args+=( ! -name '.git' )
  find_args+=( ! -name 'CNAME' )
  find_args+=( ! -name '*.sh' )
  # extra
  local x
  for x in $extra_ex; do
    find_args+=( ! -name "$x" )
  done

  local item
  while IFS= read -r -d '' item; do
    rm -rf "$item"
    ok "Dihapus: ${item#./}"
  done < <(find "${find_args[@]}" -print0 2>/dev/null)

  ok "Selesai mengosongkan (lokal). Cek dengan: ls -la"
  info "Untuk samakan ke GitHub, pakai menu [4] (push) setelah review."
  pause
}

# ---------- sanitize nama file ----------
# Aturan default:
# - spasi → _
# - huruf besar di tengah → _ + huruf kecil (CamelCase dipecah), huruf besar di awal hanya dilower
# - karakter selain [a-z0-9._-] dibuang
# - multiple _ digabung
sanitize_stem() {
  local s="$1"
  # CamelCase / PascalCase: sisipkan _ sebelum huruf besar yang tidak di posisi 0
  s=$(printf '%s' "$s" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g')
  # lower
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
  # spasi & tab → _
  s=$(printf '%s' "$s" | tr ' \t' '__')
  # buang karakter terlarang
  s=$(printf '%s' "$s" | sed -E 's/[^a-z0-9._-]+/_/g')
  # collapse _
  s=$(printf '%s' "$s" | sed -E 's/_+/_/g; s/^_//; s/_$//')
  [[ -z "$s" ]] && s="file"
  printf '%s' "$s"
}

pad_width_for() {
  local n="$1"
  if (( n > 99 )); then echo 3
  elif (( n > 9 )); then echo 2
  else echo 2   # minimal 2 agar rapi (01, 02, …)
  fi
}

# ---------- 2) rename massal isi folder ----------
menu_rename_folder() {
  header
  echo -e "${BOLD}[2] Rename massal file di dalam folder${NC}"
  echo
  need_git
  read -r -p "Path folder (contoh: images/foto/mabit): " folder
  folder="${folder#/}"
  folder="${folder%/}"
  [[ -z "$folder" ]] && { err "Folder wajib."; pause; return; }
  [[ ! -d "$folder" ]] && { err "Folder tidak ada: $folder"; pause; return; }

  echo
  echo "Aturan default nama:"
  echo "  • spasi → underscore"
  echo "  • huruf besar dipecah (CamelCase → camel_case), lalu lowercase"
  echo "  • karakter khusus dihapus"
  echo "  • bentrok → ditambah nomor leading zero"
  echo
  read -r -p "Nama dasar kustom (kosong = pakai aturan default per file): " custom_base

  info "Memindai file di ${folder}…"
  # Kumpulkan file tanpa sort -z (sering lambat/aneh di Git Bash)
  local -a files=()
  local f
  # null-delimited find; sort by name via plain sort after
  local tmp_find
  tmp_find=$(mktemp 2>/dev/null || echo "./.urusrepo-find-$$.txt")
  find "$folder" -maxdepth 1 -type f -printf '%f\t%p\n' 2>/dev/null | LC_ALL=C sort > "$tmp_find" \
    || find "$folder" -maxdepth 1 -type f -print 2>/dev/null | LC_ALL=C sort > "$tmp_find"
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "${line:-}" ]] && continue
    # format: name\tpath  OR plain path
    if [[ "$line" == *$'\t'* ]]; then
      f="${line#*$'\t'}"
    else
      f="$line"
    fi
    [[ -f "$f" ]] && files+=("$f")
  done < "$tmp_find"
  rm -f "$tmp_find" 2>/dev/null || true

  local count=${#files[@]}
  if (( count == 0 )); then
    warn "Tidak ada file di $folder"
    pause
    return
  fi

  local width
  width=$(pad_width_for "$count")
  info "Ditemukan $count file. Lebar nomor: $width digit."

  # sanitize nama dasar sekali saja (bukan 78x)
  local custom_stem=""
  if [[ -n "$custom_base" ]]; then
    custom_stem=$(sanitize_stem "$custom_base")
  fi

  # Bangun rencana rename SEKALI
  info "Menyusun rencana rename…"
  local i=0
  local base ext stem newstem dir candidate n
  local -a plan_src=() plan_dst=() plan_show=()
  declare -A used=() 2>/dev/null || true

  for f in "${files[@]}"; do
    ((i++)) || true
    dir=$(dirname "$f")
    base=$(basename "$f")
    if [[ "$base" == *.* ]]; then
      ext=".${base##*.}"
      stem="${base%.*}"
    else
      ext=""
      stem="$base"
    fi
    # lowercase extension tanpa subshell berantai
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ -n "$custom_stem" ]]; then
      newstem=$(printf "%s_%0${width}d" "$custom_stem" "$i")
    else
      newstem=$(sanitize_stem "$stem")
    fi
    candidate="${newstem}${ext}"
    n=1
    # hindari bentrok nama
    while [[ -e "$dir/$candidate" && "$dir/$candidate" != "$f" ]] || [[ -n "${used[$candidate]+x}" ]]; do
      candidate=$(printf "%s_%0${width}d%s" "$newstem" "$n" "$ext")
      ((n++)) || true
      (( n > 9999 )) && break
    done
    used["$candidate"]=1
    plan_src+=("$f")
    plan_dst+=("$dir/$candidate")
    plan_show+=("$base  →  $candidate")
  done

  echo
  echo "Pratinjau (10 pertama):"
  i=0
  for s in "${plan_show[@]}"; do
    ((i++)) || true
    if (( i <= 10 )); then
      printf "  %s\n" "$s"
    fi
  done
  (( count > 10 )) && echo "  … dan $((count - 10)) file lainnya"
  echo
  # flush prompt segera
  printf "Terapkan rename %s file? [y/N] " "$count"
  local ans=""
  read -r ans || true
  if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
    warn "Dibatalkan."
    pause
    return
  fi

  # dua tahap: temp dulu agar tidak menimpa
  info "Tahap 1/2: nama sementara…"
  i=0
  for f in "${plan_src[@]}"; do
    local tmp="$folder/.urusrepo_tmp_$$_$i"
    mv -f "$f" "$tmp" || { err "Gagal mv: $f"; pause; return; }
    plan_src[$i]="$tmp"
    ((i++)) || true
    # progress tiap 20 file
    if (( i % 20 == 0 )); then
      printf "  … %s/%s\n" "$i" "$count"
    fi
  done

  info "Tahap 2/2: nama final…"
  i=0
  for tmp in "${plan_src[@]}"; do
    mv -f "$tmp" "${plan_dst[$i]}" || { err "Gagal mv → ${plan_dst[$i]}"; pause; return; }
    ((i++)) || true
    if (( i % 20 == 0 || i == count )); then
      printf "  … %s/%s\n" "$i" "$count"
    fi
  done

  ok "Rename selesai ($count file)."
  info "Perubahan masih lokal. Pakai menu [4] untuk push ke GitHub."
  pause
}

# ---------- 3) samakan Codespaces dengan GitHub (pull / reset ke remote) ----------
menu_sync_from_github() {
  header
  echo -e "${BOLD}[3] Samakan lokal (Codespaces) ← GitHub${NC}"
  echo
  need_git
  warn "Perubahan lokal yang belum di-commit/push bisa hilang (reset ke remote)."
  confirm "Lanjut fetch + reset --hard ke origin?" || { warn "Dibatalkan."; pause; return; }

  local br
  br=$(current_branch)
  info "Fetch origin…"
  git fetch origin || die "fetch gagal"
  if git rev-parse --verify "origin/${br}" >/dev/null 2>&1; then
    git reset --hard "origin/${br}"
    git clean -fd
    ok "Lokal sekarang sama dengan origin/${br}"
  else
    err "Branch origin/${br} tidak ditemukan."
  fi
  pause
}

# ---------- 4) samakan GitHub dengan Codespaces (add + commit + push) ----------
menu_sync_to_github() {
  header
  echo -e "${BOLD}[4] Samakan GitHub ← lokal (Codespaces)${NC}"
  echo
  need_git
  git status -sb || true
  echo
  warn "Mode ini memakai git add -A → file yang hilang di lokal AKAN dihapus di GitHub."
  echo
  read -r -p "Pesan commit [update via urusrepo.sh]: " msg
  msg="${msg:-update via urusrepo.sh}"
  confirm "Add semua + commit + push (termasuk penghapusan)?" || { warn "Dibatalkan."; pause; return; }

  git add -A
  if git diff --cached --quiet 2>/dev/null; then
    warn "Tidak ada perubahan untuk di-commit."
  else
    git commit -m "$msg" || warn "commit gagal"
  fi
  local br
  br=$(current_branch)
  info "Push ke origin/${br}…"
  if [[ -n "${GH_TOKEN:-}" && -n "${GH_USER:-}" && -n "${ACTIVE_REPO:-}" ]]; then
    git push "https://${GH_USER}:${GH_TOKEN}@github.com/${ACTIVE_REPO}.git" "HEAD:refs/heads/${br}" || die "push gagal"
  else
    git push origin "HEAD:refs/heads/${br}" || die "push gagal (cek auth git)"
  fi
  ok "GitHub sudah disamakan dengan lokal."
  pause
}

# ---------- 6) upload lokal → GitHub TANPA menghapus file remote ----------
menu_upload_keep_remote() {
  header
  echo -e "${BOLD}[6] Upload lokal → GitHub (tanpa hapus file remote)${NC}"
  echo
  need_git
  echo -e "Mode ini akan:"
  echo "  • Menambahkan file/folder baru dari lokal"
  echo "  • Memperbarui file yang sudah ada (isi berubah)"
  echo "  • ${GREEN}TIDAK menghapus${NC} file/folder yang ada di GitHub tapi tidak ada di lokal"
  echo
  info "Status saat ini:"
  git status -sb || true
  echo

  # Tunjukkan untracked agar user yakin
  local untracked_count=0
  untracked_count=$(git ls-files -o --exclude-standard | wc -l | tr -d ' ')
  info "File untracked (belum di-git): ${untracked_count}"
  if [[ "${untracked_count}" -gt 0 ]]; then
    git ls-files -o --exclude-standard | head -n 30 | sed 's/^/  + /'
    if [[ "${untracked_count}" -gt 30 ]]; then
      echo "  … dan $((untracked_count - 30)) lainnya"
    fi
  fi
  echo

  read -r -p "Pesan commit [upload via urusrepo.sh (keep remote)]: " msg
  msg="${msg:-upload via urusrepo.sh (keep remote)}"
  printf "Upload + commit + push (tanpa hapus file remote)? [y/N] "
  local ans=""
  read -r ans || true
  if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
    warn "Dibatalkan."
    pause
    return
  fi

  info "Staging file baru & yang berubah (deletion di-skip)…"

  # 1) Untracked files (eksplisit — andal di Git Bash/Windows)
  local f n_add=0 n_fail=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if git add -- "$f" 2>/dev/null; then
      ((n_add++)) || true
    else
      ((n_fail++)) || true
      warn "Gagal add: $f"
    fi
    if (( n_add % 50 == 0 && n_add > 0 )); then
      printf "  … staged %s file\n" "$n_add"
    fi
  done < <(git ls-files -o --exclude-standard)

  # 2) Modified / added tracked (bukan deleted)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if git add -- "$f" 2>/dev/null; then
      ((n_add++)) || true
    else
      ((n_fail++)) || true
      warn "Gagal add (modified): $f"
    fi
  done < <(git diff --name-only --diff-filter=ACMR 2>/dev/null)

  # 3) Cadangan: coba add folder images bila masih ada untracked di dalamnya
  if [[ -d images ]]; then
    git add -- images 2>/dev/null || true
  fi

  # 4) Pastikan tidak ada deletion di index
  local deleted
  deleted=$(git diff --cached --name-only --diff-filter=D 2>/dev/null || true)
  if [[ -n "$deleted" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] && git reset HEAD -- "$f" >/dev/null 2>&1 || true
    done <<< "$deleted"
    info "Deletion di-unstage (file remote tetap dipertahankan)."
  fi

  echo
  info "Ringkasan stage: ~${n_add} add attempt, ${n_fail} gagal"
  git status -sb || true
  echo

  if git diff --cached --quiet 2>/dev/null; then
    warn "Tidak ada file baru/berubah untuk di-upload."
    echo
    echo "Troubleshooting cepat:"
    echo "  1) git check-ignore -v path/ke/file.jpg   # apakah di-ignore?"
    echo "  2) git ls-files -o --exclude-standard | head"
    echo "  3) Pastikan file bukan di folder repo lain / submodule"
    echo
    info "Mencoba push saja (jika ada commit lokal yang belum di-push)…"
  else
    echo
    info "File yang akan di-commit (maks 40 baris):"
    git diff --cached --name-status | head -n 40 | sed 's/^/  /' || true
    local staged_n
    staged_n=$(git diff --cached --name-only | wc -l | tr -d ' ')
    echo "  Total staged: ${staged_n}"
    echo
    git commit -m "$msg" || warn "commit gagal"
  fi

  local br
  br=$(current_branch)
  info "Push ke origin/${br}…"
  if [[ -n "${GH_TOKEN:-}" && -n "${GH_USER:-}" && -n "${ACTIVE_REPO:-}" ]]; then
    git push "https://${GH_USER}:${GH_TOKEN}@github.com/${ACTIVE_REPO}.git" "HEAD:refs/heads/${br}" \
      || die "push gagal (cek token scope repo)"
  else
    git push origin "HEAD:refs/heads/${br}" || die "push gagal (cek auth git)"
  fi
  ok "Upload selesai. File yang hanya ada di GitHub tetap utuh."
  pause
}


# ---------- 7) salin isi repo A → repo B (jaga file SEO / custom domain) ----------
# Contoh: sditdaarulistiqomah → darulistiqomah tanpa overwrite CNAME, robots.txt, sitemap*
menu_copy_repo_preserve_seo() {
  header
  echo -e "${BOLD}[7] Salin isi repo sumber → repo tujuan (jaga SEO / custom domain)${NC}"
  echo
  echo "File di repo TUJUAN yang TIDAK akan di-overwrite / dihapus:"
  echo "  CNAME, robots.txt, sitemap.xml, sitemap*.xml,"
  echo "  ads.txt, humans.txt, security.txt, .well-known/,"
  echo "  serta pola SEO lain yang Anda tambahkan."
  echo
  echo "Contoh:"
  echo "  Sumber : ayahelang/sditdaarulistiqomah"
  echo "  Tujuan : ayahelang/darulistiqomah"
  echo

  local src_in dst_in src_owner src_repo dst_owner dst_repo
  read -r -p "Repo SUMBER (owner/repo atau URL): " src_in
  read -r -p "Repo TUJUAN (owner/repo atau URL): " dst_in
  [[ -z "$src_in" || -z "$dst_in" ]] && { warn "Sumber & tujuan wajib diisi."; pause; return; }

  # normalisasi owner/repo
  parse_owner_repo() {
    local u="$1"
    u=$(echo "$u" | sed 's|^https\?://github.com/||; s|\.git$||; s|/$||')
    if [[ "$u" =~ ^([^/]+)/([^/]+)$ ]]; then
      printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0
    fi
    return 1
  }
  read -r src_owner src_repo < <(parse_owner_repo "$src_in") || { err "Format sumber tidak valid"; pause; return; }
  read -r dst_owner dst_repo < <(parse_owner_repo "$dst_in") || { err "Format tujuan tidak valid"; pause; return; }

  local extra
  read -r -p "Pengecualian tambahan di tujuan (spasi-pisah, opsional): " extra
  echo
  echo "Sumber : ${src_owner}/${src_repo}"
  echo "Tujuan : ${dst_owner}/${dst_repo}"
  [[ -n "$extra" ]] && echo "Extra  : $extra"
  echo
  confirm "Lanjut salin (working tree lokal + push ke tujuan)?" || { warn "Dibatalkan."; pause; return; }

  command -v git >/dev/null 2>&1 || die "git tidak ditemukan di PATH"
  local work root src_dir dst_dir
  root="${TMPDIR:-/tmp}/urusrepo-copy-$$"
  src_dir="${root}/src"
  dst_dir="${root}/dst"
  mkdir -p "$src_dir" "$dst_dir"
  # shellcheck disable=SC2064
  trap "rm -rf '$root'" RETURN

  info "Clone sumber (shallow)..."
  git clone --depth 1 "https://github.com/${src_owner}/${src_repo}.git" "$src_dir" \
    || die "Gagal clone sumber"

  info "Clone tujuan (shallow)..."
  # butuh akses write — pakai remote yang sama dengan auth user (gh/credential)
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh repo clone "${dst_owner}/${dst_repo}" "$dst_dir" -- --depth 1 \
      || git clone --depth 1 "https://github.com/${dst_owner}/${dst_repo}.git" "$dst_dir" \
      || die "Gagal clone tujuan"
  else
    git clone --depth 1 "https://github.com/${dst_owner}/${dst_repo}.git" "$dst_dir" \
      || die "Gagal clone tujuan (login/credential git diperlukan untuk push)"
  fi

  # daftar protect (basename + path relative patterns)
  local -a protect=(
    CNAME robots.txt ads.txt humans.txt security.txt
    sitemap.xml sitemap.txt
  )
  # kumpulkan file SEO yang sudah ada di tujuan untuk di-restore setelah rsync
  local bak="${root}/seo-bak"
  mkdir -p "$bak"
  local f
  for f in "${protect[@]}"; do
    if [[ -e "${dst_dir}/${f}" ]]; then
      mkdir -p "${bak}/$(dirname "$f")"
      cp -a "${dst_dir}/${f}" "${bak}/${f}"
      ok "Lindungi: $f"
    fi
  done
  # sitemap* & .well-known
  if [[ -d "${dst_dir}/.well-known" ]]; then
    cp -a "${dst_dir}/.well-known" "${bak}/.well-known"
    ok "Lindungi: .well-known/"
  fi
  local s
  shopt -s nullglob
  for s in "${dst_dir}"/sitemap*.xml "${dst_dir}"/sitemap*.txt; do
    [[ -e "$s" ]] || continue
    local base="${s#${dst_dir}/}"
    mkdir -p "${bak}/$(dirname "$base")"
    cp -a "$s" "${bak}/${base}"
    ok "Lindungi: $base"
  done
  for x in $extra; do
    if [[ -e "${dst_dir}/${x}" ]]; then
      mkdir -p "${bak}/$(dirname "$x")"
      cp -a "${dst_dir}/${x}" "${bak}/${x}"
      ok "Lindungi (extra): $x"
    fi
  done
  shopt -u nullglob

  info "Menyalin isi sumber → tujuan (mengganti konten lain)..."
  # hapus isi tujuan kecuali .git dan yang dilindungi (akan di-restore)
  find "$dst_dir" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

  # salin semua dari sumber kecuali .git
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git' "${src_dir}/" "${dst_dir}/"
  else
    (cd "$src_dir" && tar cf - --exclude='.git' .) | (cd "$dst_dir" && tar xf -)
  fi

  # restore SEO
  if [[ -d "$bak" ]]; then
    info "Mengembalikan file SEO / custom domain tujuan..."
    (cd "$bak" && tar cf - .) | (cd "$dst_dir" && tar xf -)
  fi

  info "Commit & push ke tujuan..."
  (
    cd "$dst_dir" || exit 1
    git add -A
    if git diff --cached --quiet; then
      ok "Tidak ada perubahan untuk di-commit."
    else
      git -c user.email="${GIT_AUTHOR_EMAIL:-urusrepo@skripkeren.local}" \
          -c user.name="${GIT_AUTHOR_NAME:-urusrepo}" \
          commit -m "urusrepo: salin dari ${src_owner}/${src_repo} (jaga SEO/CNAME)"
      # push
      if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        git push origin HEAD || die "Push gagal"
      else
        git push origin HEAD || die "Push gagal — pastikan credential git/PAT"
      fi
      ok "Push ke ${dst_owner}/${dst_repo} berhasil."
    fi
  ) || die "Commit/push gagal"

  ok "Selesai. Cek: https://github.com/${dst_owner}/${dst_repo}"
  pause
}


# ---------- menu utama ----------

# Cek & lengkapi dependency sebelum menu utama
if declare -F sk_ensure_basic >/dev/null 2>&1; then
  sk_ensure_basic curl git python || {
    echo "Dependency belum lengkap. Selesaikan install di atas lalu jalankan ulang."
    exit 1
  }
fi

main_menu() {
  while true; do
    header
    echo -e "${BOLD}Menu:${NC}"
    echo "  1) Kosongkan isi repo (kecuali CNAME, *.sh, + exclude opsional)"
    echo "  2) Rename massal file di folder (aturan web-safe + nomor)"
    echo "  3) Samakan lokal  ←  GitHub   (fetch + reset hard)"
    echo "  4) Samakan GitHub ←  lokal    (add + commit + push, TERMASUK hapus)"
    echo "  5) Ganti / pilih repo lagi (wizard login)"
    echo "  6) Upload lokal → GitHub     (tanpa hapus file yang hanya ada di remote)"
    echo "  7) Salin repo A → repo B     (jaga CNAME/robots/sitemap SEO tujuan)"
    echo "  0) Keluar"
    echo
    read -r -p "Pilih [0-6]: " choice || true
    case "${choice}" in
      1) menu_empty_repo ;;
      2) menu_rename_folder ;;
      3) menu_sync_from_github ;;
      4) menu_sync_to_github ;;
      5)
        if [[ "$ENV_KIND" == "codespaces" ]]; then
          warn "Di Codespaces biasanya repo sudah aktif di folder ini."
          read -r -p "Tetap jalankan wizard login? [y/N] " a
          if [[ "${a,,}" == "y" ]]; then wizard_login; fi
        else
          wizard_login
        fi
        ;;
      6) menu_upload_keep_remote ;;
      7) menu_copy_repo_preserve_seo ;;
      0) echo; ok "Selesai. Developed by James What"; exit 0 ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ---------- entry ----------
main() {
  detect_env
  header
  info "Deteksi lingkungan: ${ENV_LABEL}"
  echo

  if [[ "$ENV_KIND" == "codespaces" ]]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      ACTIVE_REPO=$(git config --get remote.origin.url 2>/dev/null | sed -E 's#.*github.com[:/]##;s#\.git$##' || true)
      ok "Repo terdeteksi dari origin: ${ACTIVE_REPO:-?}"
    else
      warn "Tidak di dalam git repo. cd ke root repo Codespaces dulu."
    fi
    pause
    main_menu
  else
    # Git Bash / desktop: wizard dulu
    echo "Mode desktop / Git Bash: login & pilih repo terlebih dahulu."
    pause
    wizard_login
    main_menu
  fi
}

main "$@"
