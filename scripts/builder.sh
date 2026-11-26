#!/usr/bin/env bash
# =============================================================================
#  builder.sh — Deteksi repo + siapkan build (APK / EXE / binary / image)
#  Skripkeren | jalan di Git Bash, Linux, macOS, Codespaces
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

WORK=""
REPO_URL=""
OWNER=""
REPO=""
LANGS=()
TARGETS=()
HAS_WORKFLOW=0
CLONE_DIR=""

cleanup() {
  if [[ -n "$CLONE_DIR" && -d "$CLONE_DIR" && "${KEEP_CLONE:-0}" != "1" ]]; then
    rm -rf "$CLONE_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

banner() {
  clear 2>/dev/null || true
  echo -e "${C}"
  echo "╔════════════════════════════════════════════════════╗"
  echo "║           builder.sh — Repo Build Helper           ║"
  echo "║   Deteksi stack · workflow · artefak siap pakai    ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo -e "${N}"
}

parse_repo_url() {
  local u="$1"
  u=$(echo "$u" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  u=${u%.git}
  if [[ "$u" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    REPO_URL="https://github.com/${OWNER}/${REPO}"
    return 0
  fi
  return 1
}

clone_repo() {
  CLONE_DIR=$(mktemp -d 2>/dev/null || echo "/tmp/builder-$$")
  echo -e "${C}Mengambil repo (shallow clone)...${N}"
  if ! git clone --depth 1 --single-branch "$REPO_URL.git" "$CLONE_DIR" 2>/dev/null; then
    if command -v curl >/dev/null 2>&1; then
      echo -e "${Y}git clone gagal — coba unduh ZIP dari GitHub...${N}"
      local zip="$CLONE_DIR/src.zip"
      mkdir -p "$CLONE_DIR/src"
      if curl -fsSL "https://github.com/${OWNER}/${REPO}/archive/refs/heads/main.zip" -o "$zip" 2>/dev/null \
        || curl -fsSL "https://github.com/${OWNER}/${REPO}/archive/refs/heads/master.zip" -o "$zip" 2>/dev/null; then
        command -v unzip >/dev/null 2>&1 && unzip -q "$zip" -d "$CLONE_DIR/src" 2>/dev/null
        local inner
        inner=$(find "$CLONE_DIR/src" -mindepth 1 -maxdepth 1 -type d | head -1)
        if [[ -n "$inner" ]]; then
          CLONE_DIR="$inner"
          return 0
        fi
      fi
    fi
    echo -e "${R}Gagal mengambil source. Cek URL / jaringan / repo private.${N}"
    return 1
  fi
  return 0
}

file_exists() { [[ -f "$CLONE_DIR/$1" ]]; }
dir_exists()  { [[ -d "$CLONE_DIR/$1" ]]; }
any_glob() {
  local p
  shopt -s nullglob
  p=("$CLONE_DIR"/$1)
  shopt -u nullglob
  [[ ${#p[@]} -gt 0 ]]
}

detect_stack() {
  LANGS=()
  TARGETS=()
  HAS_WORKFLOW=0

  if dir_exists ".github/workflows" && any_glob ".github/workflows/*.{yml,yaml}"; then
    HAS_WORKFLOW=1
  fi

  # Node / web
  if file_exists "package.json"; then
    LANGS+=("JavaScript/TypeScript (Node)")
    if grep -qE '"react"|"next"|"vue"|"nuxt"|"svelte"|"angular"' "$CLONE_DIR/package.json" 2>/dev/null; then
      LANGS+=("Frontend framework (React/Next/Vue/dll)")
      TARGETS+=("static-web" "docker-image")
    fi
    if grep -qE '"electron"' "$CLONE_DIR/package.json" 2>/dev/null; then
      LANGS+=("Electron")
      TARGETS+=("exe-win" "dmg-mac" "appimage-linux")
    fi
    if grep -qE '"react-native"|"expo"' "$CLONE_DIR/package.json" 2>/dev/null || file_exists "app.json"; then
      LANGS+=("React Native / Expo")
      TARGETS+=("apk" "ipa-note")
    fi
    TARGETS+=("node-bundle")
  fi

  # Python
  if file_exists "requirements.txt" || file_exists "pyproject.toml" || file_exists "setup.py" || file_exists "Pipfile"; then
    LANGS+=("Python")
    TARGETS+=("python-wheel" "docker-image")
    if grep -qE 'pyinstaller|cx_Freeze|nuitka' "$CLONE_DIR/requirements.txt" 2>/dev/null \
      || file_exists "pyinstaller.spec"; then
      TARGETS+=("exe-win" "bin-linux")
    fi
    if file_exists "manage.py" || grep -q django "$CLONE_DIR/requirements.txt" 2>/dev/null; then
      LANGS+=("Django")
    fi
    if grep -qE 'flask|fastapi|uvicorn' "$CLONE_DIR/requirements.txt" 2>/dev/null; then
      LANGS+=("Python web API")
    fi
  fi

  # Go
  if file_exists "go.mod"; then
    LANGS+=("Go")
    TARGETS+=("bin-linux" "exe-win" "bin-mac" "docker-image")
  fi

  # Rust
  if file_exists "Cargo.toml"; then
    LANGS+=("Rust")
    TARGETS+=("bin-linux" "exe-win" "bin-mac")
  fi

  # .NET / C#
  if any_glob "*.csproj" || any_glob "*.sln" || file_exists "global.json"; then
    LANGS+=(".NET / C#")
    TARGETS+=("exe-win" "bin-linux" "dotnet-publish")
  fi

  # Java / Kotlin / Android
  if file_exists "pom.xml" || file_exists "build.gradle" || file_exists "build.gradle.kts" || file_exists "settings.gradle"; then
    LANGS+=("Java/Kotlin (Gradle/Maven)")
    TARGETS+=("jar")
    if file_exists "AndroidManifest.xml" || dir_exists "app/src/main" || grep -q 'com.android' "$CLONE_DIR/build.gradle" 2>/dev/null \
      || grep -q 'com.android' "$CLONE_DIR/app/build.gradle" 2>/dev/null; then
      LANGS+=("Android")
      TARGETS+=("apk" "aab")
    fi
  fi
  if any_glob "**/AndroidManifest.xml"; then
    LANGS+=("Android")
    TARGETS+=("apk" "aab")
  fi

  # Flutter
  if file_exists "pubspec.yaml"; then
    LANGS+=("Flutter/Dart")
    TARGETS+=("apk" "exe-win" "bin-linux")
  fi

  # C/C++
  if file_exists "CMakeLists.txt" || file_exists "Makefile" || any_glob "*.cpp" && file_exists "Makefile"; then
    LANGS+=("C/C++")
    TARGETS+=("bin-linux" "exe-win")
  fi

  # Docker
  if file_exists "Dockerfile" || file_exists "docker-compose.yml" || file_exists "compose.yaml"; then
    LANGS+=("Docker")
    TARGETS+=("docker-image")
  fi

  # Unity (hint)
  if dir_exists "Assets" && dir_exists "ProjectSettings"; then
    LANGS+=("Unity")
    TARGETS+=("exe-win" "apk")
  fi

  # Dedupe targets
  if [[ ${#TARGETS[@]} -gt 0 ]]; then
    local u
    u=$(printf '%s\n' "${TARGETS[@]}" | sort -u | tr '\n' ' ')
    read -r -a TARGETS <<< "$u"
  fi
  if [[ ${#LANGS[@]} -eq 0 ]]; then
    LANGS+=("Tidak terdeteksi jelas (mungkin script / static HTML)")
    if any_glob "*.html"; then TARGETS+=("static-web"); fi
  fi
}

print_report() {
  echo ""
  echo -e "${B}Repository:${N} ${G}${OWNER}/${REPO}${N}"
  echo -e "${B}URL:${N}       $REPO_URL"
  echo ""
  echo -e "${B}Bahasa / teknologi terdeteksi:${N}"
  local x
  for x in "${LANGS[@]}"; do echo "  - $x"; done
  echo ""
  echo -e "${B}Target build yang masuk akal:${N}"
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "  (belum bisa ditentukan otomatis)"
  else
    for x in "${TARGETS[@]}"; do
      case "$x" in
        apk) echo "  - APK (Android)" ;;
        aab) echo "  - AAB (Play Store)" ;;
        exe-win) echo "  - EXE / installer Windows" ;;
        dmg-mac) echo "  - DMG macOS" ;;
        appimage-linux|bin-linux) echo "  - Binary / AppImage Linux" ;;
        bin-mac) echo "  - Binary macOS" ;;
        jar) echo "  - JAR" ;;
        docker-image) echo "  - Docker image" ;;
        static-web) echo "  - Static web (HTML/JS build)" ;;
        node-bundle) echo "  - Node bundle / npm pack" ;;
        python-wheel) echo "  - Python wheel / package" ;;
        dotnet-publish) echo "  - dotnet publish" ;;
        ipa-note) echo "  - IPA (iOS — butuh Mac + sertifikat Apple)" ;;
        *) echo "  - $x" ;;
      esac
    done
  fi
  echo ""
  if [[ "$HAS_WORKFLOW" -eq 1 ]]; then
    echo -e "GitHub Actions workflow: ${G}ADA${N}"
    find "$CLONE_DIR/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | while read -r w; do
      echo "  - ${w#$CLONE_DIR/}"
    done
  else
    echo -e "GitHub Actions workflow: ${Y}BELUM ADA${N}"
  fi
}

# Generate workflow content based on primary target
gen_workflow() {
  local target="$1"
  local outdir="$CLONE_DIR/.github/workflows"
  mkdir -p "$outdir"
  local wf=""
  case "$target" in
    apk)
      if file_exists "pubspec.yaml"; then
        wf="$outdir/build-apk-flutter.yml"
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
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: app-release-apk
          path: build/app/outputs/flutter-apk/*.apk
YML
      else
        wf="$outdir/build-apk-android.yml"
        cat > "$wf" << 'YML'
name: Build APK (Android Gradle)
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
      - name: Grant gradlew
        run: chmod +x gradlew || true
      - name: Build debug APK
        run: |
          if [ -f gradlew ]; then ./gradlew assembleDebug; else gradle assembleDebug; fi
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug-apk
          path: |
            app/build/outputs/apk/**/*.apk
            build/outputs/apk/**/*.apk
YML
      fi
      ;;
    exe-win|dotnet-publish)
      if any_glob "*.csproj" || any_glob "*.sln"; then
        wf="$outdir/build-exe-dotnet.yml"
        cat > "$wf" << 'YML'
name: Build Windows EXE (.NET)
on:
  workflow_dispatch:
  push:
    branches: [main, master]
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "8.0.x"
      - run: dotnet publish -c Release -r win-x64 --self-contained true -o publish
      - uses: actions/upload-artifact@v4
        with:
          name: win-exe
          path: publish/**
YML
      elif file_exists "package.json" && grep -q electron "$CLONE_DIR/package.json" 2>/dev/null; then
        wf="$outdir/build-exe-electron.yml"
        cat > "$wf" << 'YML'
name: Build Electron (Windows)
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci || npm install
      - run: npm run build || true
      - run: npx electron-builder --win || npm run dist || true
      - uses: actions/upload-artifact@v4
        with:
          name: electron-win
          path: |
            dist/*.exe
            release/*.exe
YML
      else
        wf="$outdir/build-generic-windows.yml"
        cat > "$wf" << 'YML'
name: Build (Windows runner)
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Detect and build
        shell: bash
        run: |
          if [ -f package.json ]; then npm ci || npm install; npm run build || true; fi
          if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
          ls -la
      - uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: |
            dist/**
            build/**
            publish/**
          if-no-files-found: warn
YML
      fi
      ;;
    docker-image)
      wf="$outdir/build-docker.yml"
      if ! file_exists "Dockerfile"; then
        # minimal Dockerfile substitute
        if file_exists "package.json"; then
          cat > "$CLONE_DIR/Dockerfile" << 'DF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci || npm install
COPY . .
RUN npm run build || true
EXPOSE 3000
CMD ["npm", "start"]
DF
        elif file_exists "requirements.txt"; then
          cat > "$CLONE_DIR/Dockerfile" << 'DF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "-m", "http.server", "8000"]
DF
        else
          cat > "$CLONE_DIR/Dockerfile" << 'DF'
FROM alpine:3.20
WORKDIR /app
COPY . .
CMD ["sh", "-c", "echo 'No default CMD; override when running' && sleep infinity"]
DF
        fi
        echo -e "${G}Dockerfile dibuat (template).${N}"
      fi
      cat > "$wf" << 'YML'
name: Build Docker image
on:
  workflow_dispatch:
  push:
    branches: [main, master]
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
        with:
          name: docker-image-tar
          path: /tmp/image.tar
YML
      ;;
    static-web|node-bundle)
      wf="$outdir/build-static.yml"
      cat > "$wf" << 'YML'
name: Build static / Node
on:
  workflow_dispatch:
  push:
    branches: [main, master]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci || npm install
      - run: npm run build || npm run export || true
      - uses: actions/upload-artifact@v4
        with:
          name: static-site
          path: |
            dist/**
            build/**
            out/**
            public/**
          if-no-files-found: warn
YML
      ;;
    bin-linux|jar|python-wheel)
      wf="$outdir/build-linux.yml"
      cat > "$wf" << 'YML'
name: Build (Linux)
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build hints
        run: |
          set -e
          if [ -f go.mod ]; then go build -o app .; fi
          if [ -f Cargo.toml ]; then cargo build --release; fi
          if [ -f pom.xml ]; then mvn -q -DskipTests package; fi
          if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
            chmod +x gradlew 2>/dev/null || true
            ./gradlew build || gradle build || true
          fi
          if [ -f requirements.txt ]; then pip install -r requirements.txt; pip install pyinstaller; fi
          ls -la
      - uses: actions/upload-artifact@v4
        with:
          name: linux-build
          path: |
            app
            target/**/*.jar
            build/libs/*.jar
            target/release/*
          if-no-files-found: warn
YML
      ;;
    *)
      wf="$outdir/build-manual.yml"
      cat > "$wf" << 'YML'
name: Manual build scaffold
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Sesuaikan langkah build dengan stack proyek"
      - uses: actions/upload-artifact@v4
        with:
          name: workspace-snapshot
          path: .
          if-no-files-found: ignore
YML
      ;;
  esac
  echo -e "${G}Workflow ditulis:${N} ${wf#$CLONE_DIR/}"
}

try_local_build() {
  local target="$1"
  local out="$HOME/skripkeren-build/${OWNER}_${REPO}"
  mkdir -p "$out"
  echo -e "${C}Mencoba build lokal (jika tool tersedia)...${N}"
  echo "Output folder: $out"

  case "$target" in
    static-web|node-bundle)
      if command -v npm >/dev/null 2>&1 && file_exists "package.json"; then
        (cd "$CLONE_DIR" && npm ci 2>/dev/null || npm install) || true
        (cd "$CLONE_DIR" && npm run build) 2>/dev/null || true
        for d in dist build out public; do
          [[ -d "$CLONE_DIR/$d" ]] && cp -a "$CLONE_DIR/$d" "$out/" 2>/dev/null || true
        done
      fi
      ;;
    docker-image)
      if command -v docker >/dev/null 2>&1 && file_exists "Dockerfile"; then
        docker build -t "${REPO}:local" "$CLONE_DIR" && docker save "${REPO}:local" -o "$out/${REPO}-image.tar" 2>/dev/null || true
      else
        echo -e "${Y}Docker tidak tersedia di mesin ini — andalkan GitHub Actions.${N}"
      fi
      ;;
    bin-linux)
      if file_exists "go.mod" && command -v go >/dev/null 2>&1; then
        (cd "$CLONE_DIR" && go build -o "$out/app" .) || true
      fi
      if file_exists "Cargo.toml" && command -v cargo >/dev/null 2>&1; then
        (cd "$CLONE_DIR" && cargo build --release) && cp -a "$CLONE_DIR/target/release/"* "$out/" 2>/dev/null || true
      fi
      ;;
    *)
      echo -e "${Y}Build lokal penuh untuk target ini biasanya butuh CI (GitHub Actions).${N}"
      ;;
  esac

  # Report files
  echo ""
  echo -e "${B}Isi folder hasil (jika ada):${N} $out"
  if [[ -d "$out" ]]; then
    local found=0
    while IFS= read -r f; do
      found=1
      local sz
      sz=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
      echo "  - $(basename "$f")  (${sz} bytes)"
    done < <(find "$out" -type f 2>/dev/null | head -30)
    if [[ "$found" -eq 0 ]]; then
      echo "  (belum ada artefak lokal — pakai workflow di GitHub Actions)"
      echo ""
      echo "Langkah di GitHub:"
      echo "  1. Push file .github/workflows yang dibuat (jika belum di repo)"
      echo "  2. Tab Actions → pilih workflow → Run workflow"
      echo "  3. Unduh Artifact dari ringkasan job"
      echo "  Link repo: $REPO_URL/actions"
    else
      echo ""
      echo -e "${G}Artefak lokal siap.${N}"
      if command -v zip >/dev/null 2>&1; then
        local zpath="$HOME/skripkeren-build/${OWNER}_${REPO}_artifacts.zip"
        (cd "$out" && zip -r "$zpath" .) >/dev/null 2>&1
        if [[ -f "$zpath" ]]; then
          local zsz
          zsz=$(wc -c <"$zpath" | tr -d ' ')
          echo -e "ZIP: ${G}$zpath${N}  (size: ${zsz} bytes)"
          echo "Salin/unduh file itu dari mesin ini."
        fi
      fi
    fi
  fi
}

copy_workflow_pack() {
  # Paket siap-commit untuk user
  local pack="$HOME/skripkeren-build/${OWNER}_${REPO}_ci"
  mkdir -p "$pack"
  if [[ -d "$CLONE_DIR/.github" ]]; then
    cp -a "$CLONE_DIR/.github" "$pack/" 2>/dev/null || true
  fi
  if file_exists "Dockerfile"; then
    cp -a "$CLONE_DIR/Dockerfile" "$pack/" 2>/dev/null || true
  fi
  cat > "$pack/README_BUILD.txt" << EOF
Paket CI untuk ${OWNER}/${REPO}
==============================
1. Salin folder .github (dan Dockerfile jika ada) ke root repo kamu.
2. git add .github Dockerfile
3. git commit -m "ci: add build workflow"
4. git push
5. Buka: ${REPO_URL}/actions
6. Jalankan workflow (Run workflow), unduh Artifact.

Dibuat oleh builder.sh (Skripkeren)
EOF
  echo -e "${G}Paket CI disimpan:${N} $pack"
  if command -v zip >/dev/null 2>&1; then
    local z="$HOME/skripkeren-build/${OWNER}_${REPO}_ci.zip"
    (cd "$pack" && zip -r "$z" .) >/dev/null 2>&1
    if [[ -f "$z" ]]; then
      echo -e "ZIP CI: ${G}$z${N}  ($(wc -c <"$z" | tr -d ' ') bytes)"
    fi
  fi
}

main_menu() {
  banner
  if declare -F sk_ensure_basic >/dev/null 2>&1; then
    sk_ensure_basic curl git 2>/dev/null || true
  fi

  local url
  url=$(ask "Tempel URL repo GitHub (contoh https://github.com/user/repo): ")
  if ! parse_repo_url "$url"; then
    echo -e "${R}URL tidak dikenali. Pakai format https://github.com/owner/repo${N}"
    exit 1
  fi

  if ! clone_repo; then
    exit 1
  fi

  detect_stack
  print_report

  echo ""
  echo "Apa yang ingin dilakukan?"
  echo "  1) Buat / lengkapi GitHub Actions workflow (+ Dockerfile jika perlu)"
  echo "  2) Coba build lokal sekarang"
  echo "  3) Keduanya"
  echo "  0) Hanya laporan (selesai)"
  local c
  c=$(ask "Pilih: ")
  c=$(echo "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  local primary="${TARGETS[0]:-static-web}"
  if [[ ${#TARGETS[@]} -gt 1 ]]; then
    echo ""
    echo "Target terdeteksi (pilih nomor untuk prioritas workflow):"
    local i=1
    for t in "${TARGETS[@]}"; do
      echo "  $i) $t"
      i=$((i+1))
    done
    local p
    p=$(ask "Nomor target [1]: ")
    p=${p:-1}
    if [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -ge 1 && "$p" -le ${#TARGETS[@]} ]]; then
      primary="${TARGETS[$((p-1))]}"
    fi
  fi

  case "$c" in
    1)
      gen_workflow "$primary"
      copy_workflow_pack
      ;;
    2)
      try_local_build "$primary"
      ;;
    3)
      gen_workflow "$primary"
      copy_workflow_pack
      try_local_build "$primary"
      ;;
    *)
      echo "Hanya laporan. Selesai."
      ;;
  esac

  echo ""
  echo -e "${B}Ringkasan langkah di GitHub (jika pakai Actions):${N}"
  echo "  1. Pastikan workflow ada di branch default (.github/workflows/)"
  echo "  2. Actions → Run workflow"
  echo "  3. Setelah hijau, buka job → Artifacts → unduh"
  echo "  4. Link: $REPO_URL/actions"
  echo ""
  echo "Folder kerja lokal builder: $HOME/skripkeren-build/"
  KEEP_CLONE=0
}

main_menu "$@"
