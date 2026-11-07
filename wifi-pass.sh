#!/usr/bin/env bash
# ==============================================
#  Reveal Password WiFi — Linux / Termux / Android
#  Skripkeren by Ted
#
#  Cara jalankan:
#    bash <(curl -fsSL https://skripkeren.silverhawk.web.id/wifi-pass.sh)
#  atau:
#    curl -fsSL https://skripkeren.silverhawk.web.id/wifi-pass.sh -o wifi-pass.sh
#    chmod +x wifi-pass.sh && ./wifi-pass.sh
# ==============================================

set -u

# Warna
if [ -t 1 ]; then
  C_RESET=$'\033[0m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_BOLD=""
fi

title() {
  clear 2>/dev/null || true
  echo
  echo "  ${C_CYAN}${C_BOLD}╔════════════════════════════════════════════════════╗${C_RESET}"
  echo "  ${C_CYAN}${C_BOLD}║          Reveal Password WiFi — Skripkeren         ║${C_RESET}"
  echo "  ${C_CYAN}${C_BOLD}║              (Linux / Termux / Android)            ║${C_RESET}"
  echo "  ${C_CYAN}${C_BOLD}╚════════════════════════════════════════════════════╝${C_RESET}"
  echo
}

is_android() {
  [ -f /system/build.prop ] || [ -d /system/app ] || [ "$(uname -o 2>/dev/null)" = "Android" ] || [ -n "${ANDROID_ROOT:-}" ]
}

is_termux() {
  [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]
}

has_root() {
  if command -v su >/dev/null 2>&1; then
    su -c "id -u" 2>/dev/null | grep -q '^0$' && return 0
  fi
  [ "$(id -u)" -eq 0 ] && return 0
  return 1
}

get_current_ssid() {
  # Coba beberapa cara
  if command -v iwgetid >/dev/null 2>&1; then
    iwgetid -r 2>/dev/null && return
  fi
  if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
    return
  fi
  if is_android; then
    # dumpsys (kadang tersedia di Termux)
    if command -v dumpsys >/dev/null 2>&1; then
      dumpsys wifi 2>/dev/null | grep -oE 'SSID: "[^"]+"' | head -1 | sed 's/SSID: "//;s/"$//'
      return
    fi
  fi
  echo ""
}

# ---------- Linux (NetworkManager / wpa_supplicant) ----------
show_linux_passwords() {
  echo "  ${C_CYAN}▶ Mencari password WiFi tersimpan (Linux)...${C_RESET}"
  echo "  ────────────────────────────────────────────────────"

  local found=0

  # NetworkManager
  if [ -d /etc/NetworkManager/system-connections ]; then
    if [ -r /etc/NetworkManager/system-connections ] || has_root; then
      local files
      if has_root; then
        files=$(su -c "ls /etc/NetworkManager/system-connections/" 2>/dev/null || true)
      else
        files=$(ls /etc/NetworkManager/system-connections/ 2>/dev/null || true)
      fi

      for f in $files; do
        local content ssid psk
        if has_root; then
          content=$(su -c "cat '/etc/NetworkManager/system-connections/$f'" 2>/dev/null || true)
        else
          content=$(cat "/etc/NetworkManager/system-connections/$f" 2>/dev/null || true)
        fi
        [ -z "$content" ] && continue

        ssid=$(printf '%s' "$content" | grep -E '^\s*ssid=' | head -1 | cut -d= -f2- | tr -d '"' || true)
        psk=$(printf '%s' "$content" | grep -E '^\s*psk=' | head -1 | cut -d= -f2- | tr -d '"' || true)

        if [ -n "$ssid" ]; then
          found=1
          echo "  SSID     : ${C_GREEN}$ssid${C_RESET}"
          if [ -n "$psk" ]; then
            echo "  Password : ${C_YELLOW}$psk${C_RESET}"
          else
            echo "  Password : ${C_DIM}(tidak ada / open)${C_RESET}"
          fi
          echo
        fi
      done
    fi
  fi

  # wpa_supplicant
  for conf in /etc/wpa_supplicant/wpa_supplicant.conf /data/misc/wifi/wpa_supplicant.conf; do
    if [ -f "$conf" ]; then
      local content
      if has_root; then
        content=$(su -c "cat '$conf'" 2>/dev/null || true)
      else
        content=$(cat "$conf" 2>/dev/null || true)
      fi
      if [ -n "$content" ]; then
        echo "$content" | awk '
          /ssid=/ { ssid=$0; sub(/.*ssid="/, "", ssid); sub(/".*/, "", ssid) }
          /psk=/  { psk=$0;  sub(/.*psk="/, "", psk);  sub(/".*/, "", psk);
                    if (ssid != "") {
                      print "  SSID     : " ssid
                      print "  Password : " psk
                      print ""
                      ssid=""
                    }
                  }
        '
        found=1
      fi
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "  ${C_DIM}Tidak menemukan password yang bisa dibaca.${C_RESET}"
    echo "  ${C_DIM}Coba jalankan dengan root / sudo.${C_RESET}"
    echo
  fi
}

# ---------- Android (butuh root) ----------
show_android_passwords() {
  echo "  ${C_CYAN}▶ Mencari password WiFi tersimpan (Android)...${C_RESET}"
  echo "  ────────────────────────────────────────────────────"

  if ! has_root; then
    echo "  ${C_RED}✖ Perangkat belum di-root.${C_RESET}"
    echo
    echo "  Di Android, password WiFi disimpan di lokasi sistem yang"
    echo "  dilindungi. Tanpa root, terminal (Termux dll) tidak bisa"
    echo "  membacanya."
    echo
    echo "  ${C_DIM}Yang bisa dilakukan tanpa root:${C_RESET}"
    echo "  • Melihat SSID yang sedang terhubung (jika tersedia)"
    echo "  • Tidak bisa mengambil password"
    echo
    return
  fi

  local found=0
  local xml="/data/misc/wifi/WifiConfigStore.xml"
  local oldconf="/data/misc/wifi/wpa_supplicant.conf"

  # Format baru (Android 8+)
  if su -c "test -f $xml" 2>/dev/null; then
    local content
    content=$(su -c "cat $xml" 2>/dev/null || true)
    if [ -n "$content" ]; then
      # Parsing sederhana ConfigKey / PreSharedKey
      echo "$content" | awk '
        /ConfigKey/ {
          if (match($0, /&quot;([^&]+)&quot;/, a)) ssid=a[1]
          else if (match($0, /"([^"]+)"/, a)) ssid=a[1]
        }
        /PreSharedKey/ {
          if (match($0, /&quot;([^&]*)&quot;/, a)) psk=a[1]
          else if (match($0, /"([^"]*)"/, a)) psk=a[1]
          if (ssid != "") {
            print "  SSID     : " ssid
            if (psk != "") print "  Password : " psk
            else print "  Password : (tidak ada / open)"
            print ""
            ssid=""; psk=""
            found=1
          }
        }
      '
      found=1
    fi
  fi

  # Format lama
  if su -c "test -f $oldconf" 2>/dev/null; then
    local content
    content=$(su -c "cat $oldconf" 2>/dev/null || true)
    if [ -n "$content" ]; then
      echo "$content" | awk '
        /ssid=/ { ssid=$0; sub(/.*ssid="/, "", ssid); sub(/".*/, "", ssid) }
        /psk=/  { psk=$0;  sub(/.*psk="/, "", psk);  sub(/".*/, "", psk);
                  if (ssid != "") {
                    print "  SSID     : " ssid
                    print "  Password : " psk
                    print ""
                    ssid=""
                  }
                }
      '
      found=1
    fi
  fi

  if [ "$found" -eq 0 ]; then
    echo "  ${C_DIM}Root tersedia, tapi file konfigurasi WiFi tidak ditemukan${C_RESET}"
    echo "  ${C_DIM}atau formatnya tidak dikenali.${C_RESET}"
    echo
  fi
}

# ---------- Main ----------
title

echo "  Deteksi lingkungan..."
if is_android || is_termux; then
  echo "  Platform : ${C_GREEN}Android / Termux${C_RESET}"
else
  echo "  Platform : ${C_GREEN}Linux${C_RESET}"
fi

if has_root; then
  echo "  Root     : ${C_GREEN}Ya${C_RESET}"
else
  echo "  Root     : ${C_YELLOW}Tidak${C_RESET}"
fi
echo

# Tampilkan SSID yang sedang terhubung
current=$(get_current_ssid)
if [ -n "$current" ]; then
  echo "  ${C_CYAN}▶ WiFi yang sedang terhubung${C_RESET}"
  echo "  ────────────────────────────────────────────────────"
  echo "  SSID     : ${C_GREEN}$current${C_RESET}"
  echo
else
  echo "  ${C_DIM}ℹ  Tidak berhasil mendeteksi SSID yang sedang terhubung.${C_RESET}"
  echo
fi

# Tampilkan password sesuai platform
if is_android || is_termux; then
  show_android_passwords
else
  show_linux_passwords
fi

echo "  ────────────────────────────────────────────────────"
echo "  ${C_DIM}Catatan: Password hanya tersedia untuk jaringan yang${C_RESET}"
echo "  ${C_DIM}sudah pernah berhasil terhubung dan tersimpan.${C_RESET}"
echo
