#!/usr/bin/env bash
# install_chrome_bookworm_puppy.sh
# Installer for Google Chrome (Debian Bookworm or Puppy-like systems)
# Now includes setup for official Google repo & signing key for auto updates.
# Usage: sudo ./install_chrome_bookworm_puppy.sh
set -euo pipefail

LOG_PREFIX="[install-chrome]"
info(){ echo "${LOG_PREFIX} $*"; }
warn(){ echo "${LOG_PREFIX} WARNING: $*"; }
err(){ echo "${LOG_PREFIX} ERROR: $*" >&2; }

SUDO_USER_HOME="${SUDO_USER:+/home/$SUDO_USER}${SUDO_USER:-}" 
USER_HOME="${SUDO_USER_HOME:-${HOME:-/root}}"
DESKTOP_DIR="$USER_HOME/Desktop"
mkdir -p "$DESKTOP_DIR" || true
LOCAL_APPS_DIR="$USER_HOME/.local/share/applications"
mkdir -p "$LOCAL_APPS_DIR" || true

TMPDIR="$(mktemp -d)"
DEB_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
DEB_PATH="$TMPDIR/google-chrome-stable_current_amd64.deb"
ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
ARCH="${ARCH:-$(uname -m)}"

trap 'rc=$?; if [ $rc -ne 0 ]; then err "Script failed with exit code $rc"; fi; rm -rf "$TMPDIR"' EXIT

if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "x86_64" ]; then
  err "This script targets 64-bit x86 (amd64). Detected arch: $ARCH"
  exit 1
fi

IS_PUPPY=false
if [ -f /etc/os-release ]; then
  if grep -qi "puppy" /etc/os-release 2>/dev/null; then IS_PUPPY=true; fi
fi
if grep -qi "puppy" /etc/issue 2>/dev/null; then IS_PUPPY=true; fi

run_as_root(){
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

info "Downloading Google Chrome from $DEB_URL ..."
if command -v wget >/dev/null 2>&1; then
  wget -q --show-progress -O "$DEB_PATH" "$DEB_URL"
elif command -v curl >/dev/null 2>&1; then
  curl -L -o "$DEB_PATH" "$DEB_URL"
else
  err "Neither wget nor curl is available."
  exit 1
fi

if [ ! -s "$DEB_PATH" ]; then
  err "Download failed or file empty."
  exit 1
fi

install_via_apt(){
  if command -v apt >/dev/null 2>&1; then
    info "Installing with apt..."
    run_as_root apt update -y || true
    run_as_root apt install -y "$DEB_PATH" || {
      warn "apt install failed, trying apt -f install..."
      run_as_root apt -f install -y || true
      run_as_root apt install -y "$DEB_PATH"
    }
    return 0
  fi
  return 1
}

install_via_gdebi(){
  if command -v gdebi >/dev/null 2>&1; then
    info "Using gdebi..."
    run_as_root gdebi -n "$DEB_PATH"
    return 0
  fi
  return 1
}

install_via_dpkg_then_fix(){
  if command -v dpkg >/dev/null 2>&1; then
    info "Trying dpkg..."
    run_as_root dpkg -i "$DEB_PATH" || true
    if command -v apt-get >/dev/null 2>&1; then
      run_as_root apt-get -f install -y || true
    fi
    return 0
  fi
  return 1
}

install_using_puppy_tools(){
  info "Attempting Puppy-specific tools..."
  for cmd in petget ppm pinstall; do
    if command -v "$cmd" >/dev/null 2>&1; then
      warn "Found $cmd, please use GUI to finish install if auto fails."
      run_as_root "$cmd" "$DEB_PATH" || true
      return 0
    fi
  done
  return 1
}

fallback_extract_and_wrapper(){
  warn "Falling back to extraction..."
  mkdir -p "$USER_HOME/.local/google-chrome" || true
  dpkg-deb -x "$DEB_PATH" "$USER_HOME/.local/google-chrome" 2>/dev/null || ar x "$DEB_PATH" || true
  BIN="$(find "$USER_HOME/.local/google-chrome" -type f -name google-chrome -print -quit || true)"
  if [ -n "$BIN" ]; then
    WRAPPER="$USER_HOME/.local/bin/google-chrome-stable"
    mkdir -p "$USER_HOME/.local/bin"
    cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
DIR="\$HOME/.local/google-chrome/opt/google/chrome"
export LD_LIBRARY_PATH="\$DIR:\$LD_LIBRARY_PATH"
"\$DIR/google-chrome" "\$@"
EOF
    chmod +x "$WRAPPER"
    info "Created wrapper: $WRAPPER"
    return 0
  fi
  return 1
}

create_desktop_launcher(){
  DESKTOP_FILE="$DESKTOP_DIR/google-chrome.desktop"
  LOCAL_DESKTOP="$LOCAL_APPS_DIR/google-chrome.desktop"
  info "Creating desktop launcher..."
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
EOF
  chmod +x "$DESKTOP_FILE"
  cp -f "$DESKTOP_FILE" "$LOCAL_DESKTOP" 2>/dev/null || true
}

setup_google_repo(){
  if command -v apt >/dev/null 2>&1; then
    info "Setting up Google repo for auto updates..."
    run_as_root mkdir -p /etc/apt/keyrings
    run_as_root sh -c 'wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /etc/apt/keyrings/google-linux.gpg'
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | run_as_root tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
    run_as_root apt update -y || true
  fi
}

INSTALL_OK=false
if install_via_apt; then INSTALL_OK=true; fi
if [ "$INSTALL_OK" = false ] && install_via_gdebi; then INSTALL_OK=true; fi
if [ "$INSTALL_OK" = false ] && install_via_dpkg_then_fix; then INSTALL_OK=true; fi
if [ "$INSTALL_OK" = false ] && [ "$IS_PUPPY" = true ] && install_using_puppy_tools; then INSTALL_OK=true; fi
if [ "$INSTALL_OK" = false ] && fallback_extract_and_wrapper; then INSTALL_OK=true; fi

if [ "$INSTALL_OK" = false ]; then
  err "All install attempts failed. Consider Puppy-specific Chrome/Chromium builds."
  exit 2
fi

create_desktop_launcher
setup_google_repo

info "Done. Google Chrome installed. It will now receive updates automatically via apt if supported."
exit 0
