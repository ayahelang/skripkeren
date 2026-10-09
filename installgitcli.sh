#!/usr/bin/env bash
# ===================================================
# Script: installgitcli.sh
# Tujuan: Menginstall GitHub CLI (gh) di Windows, macOS, dan Linux
# Update: 2026.10 — versi Windows dinamis, deteksi OS lebih lengkap
# ===================================================

set -euo pipefail

echo "=============================================="
echo " 🚀 Installer GitHub CLI (gh)"
echo "=============================================="

# Sudah terpasang?
if command -v gh >/dev/null 2>&1; then
  echo "✅ gh sudah terpasang:"
  gh --version
  read -r -p "Install / upgrade ulang? (y/N): " ans || true
  if [[ ! "${ans:-}" =~ ^[Yy]$ ]]; then
    echo "Selesai."
    exit 0
  fi
fi

# Deteksi sistem operasi
OS=""
if [[ "${OSTYPE:-}" == linux-gnu* ]] || [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
  OS="linux"
elif [[ "${OSTYPE:-}" == darwin* ]] || [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
  OS="macos"
elif [[ "${OSTYPE:-}" == msys* ]] || [[ "${OSTYPE:-}" == cygwin* ]] || [[ "${OSTYPE:-}" == win32* ]] || [[ -n "${MSYSTEM:-}" ]]; then
  OS="windows"
else
  echo "❌ OS tidak dikenali: ${OSTYPE:-unknown}"
  echo "Install manual: https://cli.github.com/"
  exit 1
fi

case "$OS" in
  linux)
    echo "🔧 Deteksi: Linux"
    if command -v apt >/dev/null 2>&1; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt update
      sudo apt install -y gh
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y 'dnf-command(config-manager)'
      sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install -y gh
    elif command -v yum >/dev/null 2>&1; then
      sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      sudo yum install -y gh
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Syu --noconfirm github-cli
    elif command -v zypper >/dev/null 2>&1; then
      sudo zypper install -y gh
    else
      echo "❌ Package manager tidak dikenali."
      echo "Install manual dari https://cli.github.com/"
      exit 1
    fi
    ;;
  macos)
    echo "🔧 Deteksi: macOS"
    if command -v brew >/dev/null 2>&1; then
      brew install gh || brew upgrade gh
    else
      echo "❌ Homebrew belum terpasang. Install dengan:"
      echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      exit 1
    fi
    ;;
  windows)
    echo "🔧 Deteksi: Windows (Git Bash / MSYS / Cygwin)"
    echo "⬇️ Mencari rilis terbaru GitHub CLI..."
    API_JSON=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest)
    GH_URL=$(echo "$API_JSON" | grep -oE 'https://github.com/cli/cli/releases/download/[^"]+_windows_amd64\.msi' | head -1)
    if [ -z "$GH_URL" ]; then
      if command -v winget >/dev/null 2>&1; then
        echo "📦 Memakai winget..."
        winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
      elif command -v scoop >/dev/null 2>&1; then
        echo "📦 Memakai scoop..."
        scoop install gh
      else
        echo "❌ Gagal mendapatkan URL MSI. Install manual: https://cli.github.com/"
        exit 1
      fi
    else
      INSTALLER="ghcli.msi"
      echo "⬇️ Mengunduh: $GH_URL"
      curl -fL "$GH_URL" -o "$INSTALLER"
      echo "⚙️ Menjalankan installer (butuh izin admin)..."
      msiexec //i "$INSTALLER" //qn || true
      rm -f "$INSTALLER"
    fi
    ;;
esac

echo
echo "✅ Instalasi selesai. Versi terpasang:"
gh --version 2>/dev/null || echo "⚠️ Jika perintah 'gh' belum dikenali, tutup & buka ulang terminal."
