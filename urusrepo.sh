#!/usr/bin/env bash
# =============================================================================
#  urusrepo.sh
#  Utilitas interaktif kelola repo GitHub
#  — Codespaces & Git Bash (desktop)
#
#  Developed by James What
# =============================================================================
# Cara jalankan (universal):
#   curl -fsSL https://skripkeren.silverhawk.web.id/urusrepo.sh | bash
# atau:
#   bash urusrepo.sh
# =============================================================================

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

  if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
    die "python3 diperlukan untuk parse daftar repo."
  fi
  local PY=python3
  command -v python3 >/dev/null 2>&1 || PY=python

  mapfile -t REPO_LIST < <(echo "$api_resp" | $PY -c '
import sys, json
try:
  data = json.load(sys.stdin)
except Exception as e:
  sys.exit(1)
for i, r in enumerate(data, 1):
  print("%d\t%s\t%s" % (i, r.get("full_name",""), r.get("clone_url","")))
' 2>/dev/null) || die "Gagal parse daftar repo."

  if [[ ${#REPO_LIST[@]} -eq 0 ]]; then
    die "Tidak ada repo ditemukan."
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

  # kumpulkan file (bukan folder)
  local -a files=()
  local f
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$folder" -maxdepth 1 -type f -print0 | sort -z)

  local count=${#files[@]}
  if (( count == 0 )); then
    warn "Tidak ada file di $folder"
    pause
    return
  fi

  local width
  width=$(pad_width_for "$count")
  info "Ditemukan $count file. Lebar nomor: $width digit."
  echo
  echo "Pratinjau (10 pertama):"
  local i=0
  local base ext stem newstem newname dir
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
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ -n "$custom_base" ]]; then
      newstem=$(sanitize_stem "$custom_base")
      newstem=$(printf "%s_%0${width}d" "$newstem" "$i")
    else
      newstem=$(sanitize_stem "$stem")
    fi
    newname="${newstem}${ext}"
    if (( i <= 10 )); then
      printf "  %s  →  %s\n" "$base" "$newname"
    fi
  done
  (( count > 10 )) && echo "  … dan $((count - 10)) file lainnya"
  echo
  confirm "Terapkan rename?" || { warn "Dibatalkan."; pause; return; }

  # dua tahap: rename ke temp dulu agar tidak bentrok
  i=0
  local -a plan_src=() plan_dst=()
  declare -A used=()
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
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ -n "$custom_base" ]]; then
      newstem=$(sanitize_stem "$custom_base")
      newstem=$(printf "%s_%0${width}d" "$newstem" "$i")
    else
      newstem=$(sanitize_stem "$stem")
    fi
    # unique
    local candidate="${newstem}${ext}"
    local n=1
    while [[ -n "${used[$candidate]+x}" ]]; do
      candidate=$(printf "%s_%0${width}d%s" "$newstem" "$n" "$ext")
      ((n++)) || true
    done
    used["$candidate"]=1
    plan_src+=("$f")
    plan_dst+=("$dir/$candidate")
  done

  # tahap 1: ke nama sementara
  i=0
  for f in "${plan_src[@]}"; do
    local tmp="$folder/.urusrepo_tmp_$$_$i"
    mv -f "$f" "$tmp"
    plan_src[$i]="$tmp"
    ((i++)) || true
  done
  # tahap 2: ke nama final
  i=0
  for tmp in "${plan_src[@]}"; do
    mv -f "$tmp" "${plan_dst[$i]}"
    ok "$(basename "${plan_dst[$i]}")"
    ((i++)) || true
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
  read -r -p "Pesan commit [update via urusrepo.sh]: " msg
  msg="${msg:-update via urusrepo.sh}"
  confirm "Add semua + commit + push?" || { warn "Dibatalkan."; pause; return; }

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

# ---------- menu utama ----------
main_menu() {
  while true; do
    header
    echo -e "${BOLD}Menu:${NC}"
    echo "  1) Kosongkan isi repo (kecuali CNAME, *.sh, + exclude opsional)"
    echo "  2) Rename massal file di folder (aturan web-safe + nomor)"
    echo "  3) Samakan lokal  ←  GitHub   (fetch + reset hard)"
    echo "  4) Samakan GitHub ←  lokal    (add + commit + push)"
    echo "  5) Ganti / pilih repo lagi (wizard login)"
    echo "  0) Keluar"
    echo
    read -r -p "Pilih [0-5]: " choice || true
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
