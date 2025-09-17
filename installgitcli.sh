#!/bin/bash
# ===================================================
# Script: installgitcli.sh
# Tujuan: Menginstall GitHub CLI (gh) di Windows, macOS, dan Linux
# ===================================================

set -e

echo "=============================================="
echo " 🚀 Installer GitHub CLI (gh)"
echo "=============================================="

# Deteksi sistem operasi
OS=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    OS="windows"
else
    echo "❌ OS tidak dikenali: $OSTYPE"
    exit 1
fi

case "$OS" in
  linux)
    echo "🔧 Deteksi: Linux"
    if command -v apt >/dev/null 2>&1; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
          sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
          https://cli.github.com/packages stable main" | \
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
    else
        echo "❌ Package manager tidak dikenali, install manual dari https://cli.github.com/"
        exit 1
    fi
    ;;
  macos)
    echo "🔧 Deteksi: macOS"
    if command -v brew >/dev/null 2>&1; then
        brew install gh
    else
        echo "❌ Homebrew belum terpasang. Install dengan:"
        echo "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    ;;
  windows)
    echo "🔧 Deteksi: Windows (Git Bash)"
    GH_URL="https://github.com/cli/cli/releases/latest/download/gh_2.63.2_windows_amd64.msi"
    INSTALLER="ghcli.msi"
    echo "⬇️ Mengunduh GitHub CLI dari $GH_URL ..."
    curl -L $GH_URL -o $INSTALLER
    echo "⚙️ Menjalankan installer..."
    msiexec //i $INSTALLER //qn
    rm -f $INSTALLER
    ;;
esac

echo "✅ Instalasi selesai. Versi terpasang:"
gh --version || echo "⚠️ Jika tidak dikenali, restart terminal dulu."
