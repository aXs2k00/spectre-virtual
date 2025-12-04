#!/usr/bin/env bash
set -euo pipefail

# Build a WireGuard-enabled Kali Live ISO with a C2-focused variant.
# The script auto-discovers the latest Kali keyring/live-build packages
# and falls back to prompting the user if discovery fails.

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Default configuration (override via environment variables if desired).
WG_CONF_SOURCE=${WG_CONF_SOURCE:-"/path/to/wg0.conf"}
VARIANT=${VARIANT:-"c2"}
BUILD_DIR=${BUILD_DIR:-"$HOME/live-build-config"}

info() { printf "%b[*]%b %s\n" "$GREEN" "$RESET" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YELLOW" "$RESET" "$*"; }
err()  { printf "%b[x]%b %s\n" "$RED" "$RESET" "$*"; }

fetch_latest() {
  # $1: pool URL, $2: regex pattern
  local url pattern latest
  url=$1
  pattern=$2
  latest=$(curl -fsSL "$url" | grep -oE "$pattern" | sort -V | tail -n1 || true)
  printf '%s' "$latest"
}

prompt_for_url() {
  local prompt_text default_value
  prompt_text=$1
  default_value=${2:-}
  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " reply
    echo "${reply:-$default_value}"
  else
    read -r -p "$prompt_text: " reply
    echo "$reply"
  fi
}

require_file() {
  local path=$1
  if [[ ! -f "$path" ]]; then
    err "Required file not found: $path"
    exit 1
  fi
}

info "Updating system packages"
sudo apt update
sudo apt full-upgrade -y

info "Installing base dependencies"
sudo apt install -y git live-build simple-cdd cdebootstrap curl wget

info "Discovering latest Kali keyring and live-build packages"
KEYRING_NAME=$(fetch_latest "https://http.kali.org/pool/main/k/kali-archive-keyring/" 'kali-archive-keyring_[0-9.]+_all\.deb')
LIVEBUILD_NAME=$(fetch_latest "https://http.kali.org/kali/pool/main/l/live-build/" 'live-build_[0-9A-Za-z+]+_all\.deb')

if [[ -z "$KEYRING_NAME" || -z "$LIVEBUILD_NAME" ]]; then
  warn "Auto-discovery failed; please provide the package URLs."
  KEYRING_URL=$(prompt_for_url "Enter full URL for kali-archive-keyring .deb")
  LIVEBUILD_URL=$(prompt_for_url "Enter full URL for live-build .deb")
else
  KEYRING_URL="https://http.kali.org/pool/main/k/kali-archive-keyring/$KEYRING_NAME"
  LIVEBUILD_URL="https://http.kali.org/kali/pool/main/l/live-build/$LIVEBUILD_NAME"
  info "Using keyring: $KEYRING_URL"
  info "Using live-build: $LIVEBUILD_URL"
fi

if [[ -z "${KEYRING_URL:-}" || -z "${LIVEBUILD_URL:-}" ]]; then
  err "Package URLs are required; aborting."
  exit 1
fi

info "Downloading Kali packages"
wget -q "$KEYRING_URL" -O kali-archive-keyring.deb
wget -q "$LIVEBUILD_URL" -O live-build.deb

info "Installing Kali keyring and live-build"
sudo dpkg -i kali-archive-keyring.deb
sudo dpkg -i live-build.deb

info "Configuring debootstrap for kali-rolling"
cd /usr/share/debootstrap/scripts/
(echo "default_mirror http://http.kali.org/kali"; \
 sed -e "s/debian-archive-keyring.gpg/kali-archive-keyring.gpg/g" sid) > /tmp/kali
sudo mv /tmp/kali .
sudo ln -sf kali kali-rolling

info "Cloning or updating live-build-config repository"
cd "$HOME"
if [[ ! -d "$BUILD_DIR" ]]; then
  git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git "$BUILD_DIR"
fi

cd "$BUILD_DIR"

info "Preparing custom variant: $VARIANT"
cd kali-config
rm -rf "variant-$VARIANT"
cp -a variant-default "variant-$VARIANT"

PKG_LIST="variant-$VARIANT/package-lists/kali.list.chroot"
info "Appending C2 package set"
cat >> "$PKG_LIST" <<'EOF'

# -------- C2 Headless Profile --------
wireguard
wireguard-tools
openresolv
openssh-server
curl
wget
net-tools
htop
tmux
git
EOF

info "Embedding WireGuard configuration"
require_file "$WG_CONF_SOURCE"
mkdir -p "variant-$VARIANT/includes.chroot/etc/wireguard"
cp "$WG_CONF_SOURCE" "variant-$VARIANT/includes.chroot/etc/wireguard/wg0.conf"
chmod 600 "variant-$VARIANT/includes.chroot/etc/wireguard/wg0.conf"

info "Adding WireGuard boot hook"
mkdir -p "variant-$VARIANT/hooks/live"
cat > "variant-$VARIANT/hooks/live/90-wireguard-enable.hook.chroot" <<'EOF'
#!/bin/bash
set -e
if [ -f /etc/wireguard/wg0.conf ]; then
    systemctl enable wg-quick@wg0.service || true
fi
EOF
chmod +x "variant-$VARIANT/hooks/live/90-wireguard-enable.hook.chroot"

info "Disabling NetworkManager autoconnect"
mkdir -p "variant-$VARIANT/includes.chroot/etc/NetworkManager/conf.d/"
cat > "variant-$VARIANT/includes.chroot/etc/NetworkManager/conf.d/disable-auto-connect.conf" <<'EOF'
[connection]
autoconnect=false
EOF

info "Building ISO"
cd "$BUILD_DIR"
./build.sh --verbose --variant "$VARIANT"

info "Build complete. Check $BUILD_DIR/images for the ISO."
