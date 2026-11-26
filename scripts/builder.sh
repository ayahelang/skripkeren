#!/usr/bin/env bash
# =============================================================================
#  builder.sh — Deteksi repo + build lewat akun GitHub ANDA
#  Skripkeren | Git Bash / Linux / macOS / Codespaces
#
#  Alur untuk repo orang lain (tanpa akses write):
#    1. Clone source
#    2. Login GitHub (gh atau PAT)
#    3. Buat repo baru di akun ANDA (mirror/build)
#    4. Push source + workflow
#    5. Trigger Actions → unduh artifact
#
#  curl -fsSL https://skripkeren.silverhawk.web.id/scripts/builder.sh | bash
# =============================================================================

set +e

_SK_DEPS_URL="${SK_DEPS_URL:-https://skripkeren.silverhawk.web.id/scripts/sk-deps.sh}"
_sk_load_deps() {
  if [[ -n "${_SK_DEPS_LOADED:-}" ]]; then return 0; fi
  local _dir _f _tmp
  _dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || _dir="."
  for _f in "$_dir/sk-deps.sh" "./sk-deps.sh"; do
    [[ -f "$_f" ]] && { source "$_f"; return 0; }
  done
  _tmp="$(mktemp 2>/dev/null || echo /tmp/sk-deps-$$.sh)"
  if command -v curl >/dev/null 2>&1 && curl -fsSL "$_SK_DEPS_URL" -o "$_tmp" 2>/dev/null; then
    source "$_tmp"; rm -f "$_tmp"; return 0
  fi
  rm -f "$_tmp" 2>/dev/null || true
  return 1
}
_sk_load_deps 2>/dev/null || true

if [[ -t 1 ]] || [[ -n "${MSYSTEM:-}" ]]; then
  R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; C=$'\033[0;36m'; B=$'\033[1m'; N=$'\033[0m'
else
  R=; G=; Y=; C=; B=; N=
fi

TTY=/dev/tty
[[ -c "$TTY" && -r "$TTY" && -w "$TTY" ]] || TTY=/dev/stdin
ask() {
  local a
  printf "%s" "$1" >"$TTY" 2>/dev/null || printf "%s" "$1"
  IFS= read -r a <"$TTY" 2>/dev/null || a=""
  printf "%s" "$a"
}
ask_secret() {
  local a
  printf "%s" "$1" >"$TTY" 2>/dev/null || printf "%s" "$1"
  if [[ -c /dev/tty ]]; then
    stty -echo 2>/dev/null || true
    IFS= read -r a <"$TTY" 2>/dev/null || a=""
    stty echo 2>/dev/null || true
    printf "\n" >"$TTY" 2>/dev/null || echo
  else
    IFS= read -r a <"$TTY" 2>/dev/null || a=""
  fi
  printf "%s" "$a"
}

REPO_URL=""; OWNER=""; REPO=""
LANGS=(); TARGETS=(); HAS_WORKFLOW=0
CLONE_DIR=""; KEEP_CLONE=0
GH_USER=""; GH_TOKEN=""; MY_REPO=""; MY_REPO_URL=""
PRIMARY_TARGET=""
BUILD_ROOT="${HOME}/skripkeren-build"

banner() {
  clear 2>/dev/null || true
  echo -e "${C}"
  echo "╔════════════════════════════════════════════════════╗"
  echo "║        builder.sh — Build di akun GitHub ANDA      ║"
  echo "║  Repo orang lain → mirror → Actions → artifact     ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo -e "${N}"
}

have_gh() { command -v gh >/dev/null 2>&1; }

parse_repo_url() {
  local u="$1"
  u=$(echo "$u" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\.git$//')
  if [[ "$u" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    REPO_URL="https://github.com/${OWNER}/${REPO}"
    return 0
  fi
  return 1
}

ensure_github_auth() {
  echo ""
  echo -e "${B}Akses GitHub (akun ANDA)${N}"
  echo "Diperlukan agar script bisa membuat repo mirror + push workflow + trigger Actions."
  echo "Repo sumber (orang lain) hanya di-clone; tidak perlu akses write ke sana."
  echo ""

  if have_gh; then
    local who
    who=$(gh api user --jq .login 2>/dev/null || true)
    if [[ -n "$who" ]]; then
      GH_USER="$who"
      echo -e "  ${G}gh sudah login sebagai: ${GH_USER}${N}"
      local a
      a=$(ask "Pakai akun ini? [Y/n]: ")
      a=$(echo "${a:-Y}" | tr '[:upper:]' '[:lower:]')
      if [[ "$a" != "n" && "$a" != "no" ]]; then
        return 0
      fi
    fi
  fi

  echo "Pilih cara login:"
  echo "  1) GitHub CLI (gh auth login) — disarankan"
  echo "  2) Tempel Personal Access Token (PAT) scope: repo, workflow"
  echo "  3) Sudah set env GITHUB_TOKEN / GH_TOKEN"
  local c
  c=$(ask "Pilih [1]: ")
  c=${c:-1}

  case "$c" in
    2)
      echo "Buat PAT: https://github.com/settings/tokens (classic: repo + workflow)"
      GH_TOKEN=$(ask_secret "Tempel PAT: ")
      if [[ -z "$GH_TOKEN" ]]; then
        echo -e "${R}Token kosong.${N}"; return 1
      fi
      export GH_TOKEN GITHUB_TOKEN="$GH_TOKEN"
      GH_USER=$(curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
        https://api.github.com/user 2>/dev/null | sed -n 's/.*"login": "\([^"]*\)".*/\1/p' | head -1)
      if [[ -z "$GH_USER" ]]; then
        echo -e "${R}Token tidak valid / tidak bisa baca user.${N}"; return 1
      fi
      echo -e "${G}Login API sebagai: ${GH_USER}${N}"
      ;;
    3)
      GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
      if [[ -z "$GH_TOKEN" ]]; then
        echo -e "${R}Env GH_TOKEN / GITHUB_TOKEN kosong.${N}"; return 1
      fi
      export GITHUB_TOKEN="$GH_TOKEN"
      GH_USER=$(curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
        https://api.github.com/user 2>/dev/null | sed -n 's/.*"login": "\([^"]*\)".*/\1/p' | head -1)
      [[ -n "$GH_USER" ]] || { echo -e "${R}Token env tidak valid.${N}"; return 1; }
      echo -e "${G}Login dari env sebagai: ${GH_USER}${N}"
      ;;
    *)
      if ! have_gh; then
        echo -e "${Y}gh belum ada — mencoba install...${N}"
        if declare -F sk_ensure_gh >/dev/null 2>&1; then
          sk_ensure_gh || true
        fi
      fi
      if ! have_gh; then
        echo -e "${R}Install GitHub CLI: https://cli.github.com/${N}"
        echo "Atau pilih opsi 2 (PAT)."
        return 1
      fi
      echo "Menjalankan: gh auth login"
      gh auth login || return 1
      GH_USER=$(gh api user --jq .login 2>/dev/null)
      [[ -n "$GH_USER" ]] || return 1
      echo -e "${G}Login sebagai: ${GH_USER}${N}"
      ;;
  esac
  return 0
}

gh_or_curl() {
  local method="$1" path="$2" body="${3:-}"
  if have_gh && gh auth status >/dev/null 2>&1; then
    if [[ -n "$body" ]]; then
      printf '%s' "$body" | gh api -X "$method" "$path" --input -
    else
      gh api -X "$method" "$path"
    fi
    return $?
  fi
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  local args=(-fsSL -X "$method" -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}" "https://api.github.com${path}"
}

clone_repo() {
  CLONE_DIR="${BUILD_ROOT}/src_${OWNER}_${REPO}"
  rm -rf "$CLONE_DIR" 2>/dev/null || true
  mkdir -p "$BUILD_ROOT"
  echo -e "${C}Clone ${REPO_URL} ...${N}"
  if git clone --depth 1 --single-branch "${REPO_URL}.git" "$CLONE_DIR" 2>/dev/null; then
    return 0
  fi
  echo -e "${Y}git clone gagal — unduh ZIP...${N}"
  local zip="${BUILD_ROOT}/${REPO}.zip" extract="${BUILD_ROOT}/extract_$$"
  mkdir -p "$extract"
  if curl -fsSL "https://github.com/${OWNER}/${REPO}/archive/refs/heads/main.zip" -o "$zip" 2>/dev/null \
    || curl -fsSL "https://github.com/${OWNER}/${REPO}/archive/refs/heads/master.zip" -o "$zip" 2>/dev/null; then
    command -v unzip >/dev/null 2>&1 && unzip -q "$zip" -d "$extract"
    local inner
    inner=$(find "$extract" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [[ -n "$inner" ]]; then
      mv "$inner" "$CLONE_DIR"
      rm -rf "$extract" "$zip" 2>/dev/null || true
      (cd "$CLONE_DIR" && git init -q && git add -A && git -c user.email="builder@skripkeren.local" -c user.name="builder" commit -qm "import from ${OWNER}/${REPO}" 2>/dev/null) || true
      return 0
    fi
  fi
  echo -e "${R}Gagal mengambil source.${N}"
  return 1
}

file_exists() { [[ -f "$CLONE_DIR/$1" ]]; }
dir_exists()  { [[ -d "$CLONE_DIR/$1" ]]; }
any_glob() {
  shopt -s nullglob
  local p=("$CLONE_DIR"/$1)
  shopt -u nullglob
  [[ ${#p[@]} -gt 0 ]]
}

detect_stack() {
  LANGS=(); TARGETS=(); HAS_WORKFLOW=0
  if dir_exists ".github/workflows" && any_glob ".github/workflows/*.{yml,yaml}"; then HAS_WORKFLOW=1; fi

  if file_exists "package.json"; then
    LANGS+=("JavaScript/TypeScript (Node)")
    grep -qE '"react"|"next"|"vue"' "$CLONE_DIR/package.json" 2>/dev/null && LANGS+=("Frontend web") && TARGETS+=("static-web")
    grep -qE '"electron"' "$CLONE_DIR/package.json" 2>/dev/null && LANGS+=("Electron") && TARGETS+=("exe-win")
    grep -qE '"react-native"|"expo"' "$CLONE_DIR/package.json" 2>/dev/null && LANGS+=("React Native") && TARGETS+=("apk")
    TARGETS+=("node-bundle")
  fi
  if file_exists "requirements.txt" || file_exists "pyproject.toml"; then
    LANGS+=("Python"); TARGETS+=("python-wheel" "docker-image" "exe-win")
  fi
  if file_exists "go.mod"; then LANGS+=("Go"); TARGETS+=("bin-linux" "exe-win"); fi
  if file_exists "Cargo.toml"; then LANGS+=("Rust"); TARGETS+=("bin-linux" "exe-win"); fi
  if any_glob "*.csproj" || any_glob "*.sln"; then LANGS+=(".NET/C#"); TARGETS+=("exe-win" "dotnet-publish"); fi
  if file_exists "pom.xml" || file_exists "build.gradle" || file_exists "build.gradle.kts" || file_exists "settings.gradle"; then
    LANGS+=("Java/Kotlin (Gradle/Maven)"); TARGETS+=("jar")
    if file_exists "AndroidManifest.xml" || dir_exists "app/src/main" \
      || grep -rq 'com.android' "$CLONE_DIR/build.gradle" "$CLONE_DIR/app/build.gradle" 2>/dev/null \
      || grep -rq 'com.android.application' "$CLONE_DIR" --include="*.gradle*" 2>/dev/null; then
      LANGS+=("Android"); TARGETS+=("apk" "aab")
    fi
  fi
  if any_glob "**/AndroidManifest.xml"; then LANGS+=("Android"); TARGETS+=("apk" "aab"); fi
  if file_exists "pubspec.yaml"; then LANGS+=("Flutter"); TARGETS+=("apk" "exe-win"); fi
  if file_exists "Dockerfile"; then LANGS+=("Docker"); TARGETS+=("docker-image"); fi
  if file_exists "CMakeLists.txt" || file_exists "Makefile"; then LANGS+=("C/C++"); TARGETS+=("bin-linux" "exe-win"); fi

  if [[ ${#TARGETS[@]} -gt 0 ]]; then
    local u; u=$(printf '%s\n' "${TARGETS[@]}" | sort -u | tr '\n' ' ')
    read -r -a TARGETS <<< "$u"
  fi
  [[ ${#LANGS[@]} -eq 0 ]] && LANGS+=("Tidak terdeteksi jelas") && TARGETS+=("static-web")
}

print_report() {
  echo ""
  echo -e "${B}Sumber:${N}  ${OWNER}/${REPO}"
  echo -e "${B}URL:${N}     $REPO_URL"
  echo ""
  echo -e "${B}Stack:${N}"
  local x; for x in "${LANGS[@]}"; do echo "  - $x"; done
  echo ""
  echo -e "${B}Target build:${N}"
  for x in "${TARGETS[@]}"; do
    case "$x" in
      apk) echo "  - APK (Android)" ;;
      aab) echo "  - AAB (Play Store)" ;;
      exe-win) echo "  - EXE Windows" ;;
      bin-linux) echo "  - Binary Linux" ;;
      jar) echo "  - JAR" ;;
      docker-image) echo "  - Docker image" ;;
      static-web) echo "  - Static web" ;;
      *) echo "  - $x" ;;
    esac
  done
  if [[ "$HAS_WORKFLOW" -eq 1 ]]; then
    echo -e "Workflow di sumber: ${G}ADA${N}"
  else
    echo -e "Workflow di sumber: ${Y}BELUM ADA (akan dibuat di repo ANDA)${N}"
  fi
}

gen_workflow() {
  local target="$1"
  local outdir="$CLONE_DIR/.github/workflows"
  mkdir -p "$outdir"
  local wf=""
  case "$target" in
    apk|aab)
      if file_exists "pubspec.yaml"; then
        wf="$outdir/build-apk.yml"
        cat > "$wf" << 'YML'
name: Build APK (Flutter)
on:
  workflow_dispatch:
  push:
    branches: [main, master]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/*.apk
YML
      else
        wf="$outdir/build-apk.yml"
        cat > "$wf" << 'YML'
name: Build APK (Android)
on:
  workflow_dispatch:
  push:
    branches: [main, master]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4
      - name: Build debug APK
        run: |
          if [ -f gradlew ]; then chmod +x gradlew && ./gradlew assembleDebug --stacktrace
          elif [ -f app/build.gradle ] || [ -f app/build.gradle.kts ]; then
            gradle :app:assembleDebug --stacktrace || true
          else
            gradle assembleDebug --stacktrace || true
          fi
      - uses: actions/upload-artifact@v4
        with:
          name: debug-apk
          path: |
            **/build/outputs/apk/**/*.apk
            app/build/outputs/apk/**/*.apk
          if-no-files-found: warn
YML
      fi
      ;;
    exe-win|dotnet-publish)
      if any_glob "*.csproj" || any_glob "*.sln"; then
        wf="$outdir/build-exe.yml"
        cat > "$wf" << 'YML'
name: Build Windows EXE (.NET)
on: { workflow_dispatch: {}, push: { branches: [main, master] } }
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: "8.0.x" }
      - run: dotnet publish -c Release -r win-x64 --self-contained true -o publish
      - uses: actions/upload-artifact@v4
        with: { name: win-exe, path: publish/** }
YML
      else
        wf="$outdir/build-apk.yml"
        cat > "$wf" << 'YML'
name: Build APK (Android) — recommended for this repo
on:
  workflow_dispatch:
  push:
    branches: [main, master]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - uses: gradle/actions/setup-gradle@v4
      - run: |
          if [ -f gradlew ]; then chmod +x gradlew && ./gradlew assembleDebug --stacktrace; fi
      - uses: actions/upload-artifact@v4
        with:
          name: debug-apk
          path: "**/build/outputs/apk/**/*.apk"
          if-no-files-found: warn
YML
        echo -e "${Y}Catatan: repo ini Android — workflow APK dibuat (EXE tidak cocok).${N}"
      fi
      ;;
    docker-image)
      wf="$outdir/build-docker.yml"
      [[ -f "$CLONE_DIR/Dockerfile" ]] || printf '%s\n' 'FROM alpine:3.20' 'COPY . /app' 'WORKDIR /app' 'CMD ["sleep","infinity"]' > "$CLONE_DIR/Dockerfile"
      cat > "$wf" << 'YML'
name: Build Docker
on: { workflow_dispatch: {} }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: app:local
          outputs: type=docker,dest=/tmp/image.tar
      - uses: actions/upload-artifact@v4
        with: { name: docker-image, path: /tmp/image.tar }
YML
      ;;
    *)
      wf="$outdir/build.yml"
      cat > "$wf" << 'YML'
name: Build
on: { workflow_dispatch: {}, push: { branches: [main, master] } }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }
      - run: |
          if [ -f gradlew ]; then chmod +x gradlew && ./gradlew assembleDebug || ./gradlew build || true; fi
          if [ -f package.json ]; then npm ci || npm install; npm run build || true; fi
          if [ -f go.mod ]; then go build -o app . || true; fi
          find . -name '*.apk' -o -name '*.jar' -o -name 'app' 2>/dev/null | head
      - uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: |
            **/build/outputs/**/*.apk
            **/build/libs/*.jar
            dist/**
            app
          if-no-files-found: warn
YML
      ;;
  esac
  echo -e "${G}Workflow:${N} ${wf#$CLONE_DIR/}"
}

create_and_push_mirror() {
  local default_name="build-${REPO}"
  local name
  name=$(ask "Nama repo di akun Anda [${default_name}]: ")
  name=${name:-$default_name}
  name=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/-/g')
  MY_REPO="$name"
  MY_REPO_URL="https://github.com/${GH_USER}/${MY_REPO}"

  echo -e "${C}Membuat repo ${GH_USER}/${MY_REPO} (public)...${N}"
  local created=0
  if have_gh && gh auth status >/dev/null 2>&1; then
    if gh repo create "${GH_USER}/${MY_REPO}" --public --description "Build mirror of ${OWNER}/${REPO} (via builder.sh)" 2>/dev/null; then
      created=1
    elif gh repo view "${GH_USER}/${MY_REPO}" >/dev/null 2>&1; then
      echo -e "${Y}Repo sudah ada — akan push ke sana.${N}"
      created=1
    fi
  fi
  if [[ "$created" -eq 0 ]]; then
    local body
    body=$(printf '{"name":"%s","description":"Build mirror of %s/%s (builder.sh)","private":false}' "$MY_REPO" "$OWNER" "$REPO")
    if gh_or_curl POST "/user/repos" "$body" >/dev/null 2>&1; then
      created=1
    else
      if gh_or_curl GET "/repos/${GH_USER}/${MY_REPO}" >/dev/null 2>&1; then
        echo -e "${Y}Repo sudah ada.${N}"
        created=1
      fi
    fi
  fi
  if [[ "$created" -eq 0 ]]; then
    echo -e "${R}Gagal membuat repo. Cek scope token (repo) / login gh.${N}"
    return 1
  fi

  echo -e "${C}Push source + workflow ke ${MY_REPO_URL} ...${N}"
  (
    cd "$CLONE_DIR" || exit 1
    git init -q 2>/dev/null || true
    git checkout -B main 2>/dev/null || git branch -M main 2>/dev/null || true
    git add -A
    git -c user.email="builder@skripkeren.local" -c user.name="Skripkeren Builder" commit -qm "build mirror of ${OWNER}/${REPO}" 2>/dev/null || true

    local push_url="https://github.com/${GH_USER}/${MY_REPO}.git"
    if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
      push_url="https://x-access-token:${GH_TOKEN:-$GITHUB_TOKEN}@github.com/${GH_USER}/${MY_REPO}.git"
    fi
    git remote remove origin 2>/dev/null || true
    if have_gh && gh auth status >/dev/null 2>&1; then
      git remote add origin "https://github.com/${GH_USER}/${MY_REPO}.git"
      git push -u origin main --force 2>&1 | tail -20
    else
      git remote add origin "$push_url"
      git push -u origin main --force 2>&1 | tail -20
    fi
  )
  local st=$?
  if [[ $st -ne 0 ]]; then
    echo -e "${R}Push gagal. Pastikan token punya scope repo / gh login OK.${N}"
    return 1
  fi
  echo -e "${G}Push OK → ${MY_REPO_URL}${N}"
  KEEP_CLONE=1
  return 0
}

trigger_workflow() {
  echo -e "${C}Menjalankan workflow (workflow_dispatch)...${N}"
  sleep 3
  local wf_file wf_name
  wf_file=$(find "$CLONE_DIR/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | head -1)
  wf_name=$(basename "$wf_file")
  if have_gh && gh auth status >/dev/null 2>&1; then
    gh workflow list -R "${GH_USER}/${MY_REPO}" 2>/dev/null || true
    if gh workflow run "$wf_name" -R "${GH_USER}/${MY_REPO}" 2>/dev/null \
      || gh workflow run "$(basename "$wf_name" .yml)" -R "${GH_USER}/${MY_REPO}" 2>/dev/null; then
      echo -e "${G}Workflow di-trigger.${N}"
    else
      echo -e "${Y}Auto-trigger gagal — jalankan manual di tab Actions.${N}"
    fi
  else
    echo -e "${Y}Buka Actions dan klik Run workflow:${N}"
  fi
  echo "  ${MY_REPO_URL}/actions"
}

wait_and_download_artifact() {
  echo ""
  echo -e "${B}Unduh artifact${N}"
  echo "  1) Otomatis tunggu + unduh (butuh gh CLI, bisa beberapa menit)"
  echo "  2) Saya unduh manual dari browser"
  local c
  c=$(ask "Pilih [2]: ")
  c=${c:-2}
  if [[ "$c" != "1" ]]; then
    echo "Setelah job hijau: buka job → Artifacts → unduh ZIP."
    echo "Link: ${MY_REPO_URL}/actions"
    return 0
  fi
  if ! have_gh; then
    echo -e "${Y}gh tidak ada — unduh manual: ${MY_REPO_URL}/actions${N}"
    return 0
  fi
  echo "Menunggu run selesai (maks ~15 menit)..."
  local i run_id status
  for i in $(seq 1 45); do
    run_id=$(gh run list -R "${GH_USER}/${MY_REPO}" --limit 1 --json databaseId,status,conclusion -q '.[0].databaseId' 2>/dev/null)
    status=$(gh run list -R "${GH_USER}/${MY_REPO}" --limit 1 --json status,conclusion -q '.[0].status' 2>/dev/null)
    echo "  ... status=$status run=$run_id"
    if [[ "$status" == "completed" ]]; then
      break
    fi
    sleep 20
  done
  if [[ -z "$run_id" ]]; then
    echo -e "${Y}Belum ada run. Cek ${MY_REPO_URL}/actions${N}"
    return 0
  fi
  local outdir="${BUILD_ROOT}/artifacts_${GH_USER}_${MY_REPO}"
  mkdir -p "$outdir"
  if gh run download "$run_id" -R "${GH_USER}/${MY_REPO}" -D "$outdir" 2>/dev/null; then
    echo -e "${G}Artifact diunduh ke:${N} $outdir"
    find "$outdir" -type f 2>/dev/null | while read -r f; do
      echo "  - $f  ($(wc -c <"$f" | tr -d ' ') bytes)"
    done
    if command -v zip >/dev/null 2>&1; then
      local z="${BUILD_ROOT}/${MY_REPO}_artifacts.zip"
      (cd "$outdir" && zip -r "$z" .) >/dev/null 2>&1
      [[ -f "$z" ]] && echo -e "ZIP gabungan: ${G}$z${N} ($(wc -c <"$z" | tr -d ' ') bytes)"
    fi
  else
    echo -e "${Y}Download gagal / belum ada artifact. Cek job log di Actions.${N}"
    echo "  ${MY_REPO_URL}/actions"
  fi
}

main() {
  banner
  if declare -F sk_ensure_basic >/dev/null 2>&1; then
    sk_ensure_basic curl git 2>/dev/null || true
  fi

  local url
  url=$(ask "Tempel URL repo GitHub (boleh milik orang lain): ")
  parse_repo_url "$url" || { echo -e "${R}URL tidak valid.${N}"; exit 1; }

  clone_repo || exit 1
  detect_stack
  print_report

  echo ""
  echo "Target prioritas:"
  local i=1 t
  for t in "${TARGETS[@]}"; do echo "  $i) $t"; i=$((i+1)); done
  local p
  p=$(ask "Nomor target [1]: "); p=${p:-1}
  if [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -ge 1 && "$p" -le ${#TARGETS[@]} ]]; then
    PRIMARY_TARGET="${TARGETS[$((p-1))]}"
  else
    PRIMARY_TARGET="${TARGETS[0]}"
  fi
  if printf '%s\n' "${LANGS[@]}" | grep -q Android; then
    if [[ "$PRIMARY_TARGET" == "exe-win" || "$PRIMARY_TARGET" == "bin-linux" ]]; then
      echo -e "${Y}Repo Android — memakai target apk.${N}"
      PRIMARY_TARGET="apk"
    fi
  fi

  echo ""
  echo "Mode:"
  echo "  1) Build di akun GitHub SAYA (disarankan untuk repo orang lain)"
  echo "  2) Hanya buat file workflow lokal (tanpa push)"
  echo "  0) Keluar"
  local mode
  mode=$(ask "Pilih [1]: "); mode=${mode:-1}

  gen_workflow "$PRIMARY_TARGET"

  if [[ "$mode" == "0" ]]; then
    echo "Selesai."; exit 0
  fi

  if [[ "$mode" == "2" ]]; then
    local pack="${BUILD_ROOT}/${OWNER}_${REPO}_ci"
    mkdir -p "$pack"
    cp -a "$CLONE_DIR/.github" "$pack/" 2>/dev/null || true
    echo -e "${G}Workflow lokal:${N} $pack"
    echo "Tanpa akses push ke repo orang lain, file ini hanya bisa Anda pakai di repo sendiri."
    exit 0
  fi

  ensure_github_auth || exit 1
  create_and_push_mirror || exit 1
  trigger_workflow
  wait_and_download_artifact

  echo ""
  echo -e "${B}Selesai.${N}"
  echo "  Sumber : $REPO_URL"
  echo "  Mirror : $MY_REPO_URL"
  echo "  Actions: ${MY_REPO_URL}/actions"
  echo "  Lokal  : $BUILD_ROOT"
  echo ""
  echo "Anda tidak perlu akses write ke repo orang lain."
  echo "Semua build jalan di repo mirror milik: $GH_USER"
}

main "$@"
