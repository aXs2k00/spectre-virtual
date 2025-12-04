#!/usr/bin/env bash
set -euo pipefail

# Build a WireGuard-enabled Kali Installer ISO with a C2-focused package set.
# The script auto-discovers the latest Kali keyring/live-build packages and
# prompts the user for URLs if discovery fails.

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

WG_CONF_SOURCE=${WG_CONF_SOURCE:-"$HOME/Downloads/wg0.conf"}
BUILD_DIR=${BUILD_DIR:-"$HOME/live-build-config"}
DISTRIBUTION=${DISTRIBUTION:-"kali-rolling"}
VERSION=${VERSION:-"c2-installer"}
SUBDIR=${SUBDIR:-"c2-installer"}

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
  local prompt_text default_value reply
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

append_once() {
  # Append content to a file only if a marker is absent.
  # $1: file path, $2: marker string, stdin: content
  local target marker
  target=$1
  marker=$2
  if ! grep -q "$marker" "$target" 2>/dev/null; then
    cat >> "$target"
  else
    warn "Marker '$marker' already present in $target; skipping append."
  fi
}

info "Updating system packages"
sudo apt update
sudo apt full-upgrade -y

info "Installing base dependencies"
sudo apt install -y git live-build simple-cdd cdebootstrap curl wget

info "Discovering latest Kali keyring and live-build packages"
KEYRING_NAME=$(fetch_latest "https://http.kali.org/pool/main/k/kali-archive-keyring/" 'kali-archive-keyring_[0-9.]\+_all\.deb')
LIVEBUILD_NAME=$(fetch_latest "https://http.kali.org/kali/pool/main/l/live-build/" 'live-build_[0-9A-Za-z+]\+_all\.deb')

# Known-good fallbacks in case discovery fails
KEYRING_FALLBACK="https://http.kali.org/pool/main/k/kali-archive-keyring/kali-archive-keyring_2025.1_all.deb"
LIVEBUILD_FALLBACK="https://http.kali.org/kali/pool/main/l/live-build/live-build_20250814+kali1_all.deb"

if [[ -z "$KEYRING_NAME" || -z "$LIVEBUILD_NAME" ]]; then
  warn "Auto-discovery failed; provide URLs or accept defaults."
  KEYRING_URL=$(prompt_for_url "Enter full URL for kali-archive-keyring .deb" "$KEYRING_FALLBACK")
  LIVEBUILD_URL=$(prompt_for_url "Enter full URL for live-build .deb" "$LIVEBUILD_FALLBACK")
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

info "Preparing installer configuration"
PKG_PATH="kali-config/installer-default/packages"
POSTINST_PATH="simple-cdd/profiles/kali.postinst"
HOOK_PATH="kali-config/common/hooks/90-wireguard-enable.chroot"
WG_TARGET_DIR="kali-config/common/includes.chroot/etc/wireguard"

info "Adding C2 package set to installer pool"
mkdir -p "$(dirname "$PKG_PATH")"
append_once "$PKG_PATH" "C2_PROFILE_PACKAGES" <<'EOF'

# C2_PROFILE_PACKAGES
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

info "Ensuring post-install package install and WireGuard enablement"
mkdir -p "$(dirname "$POSTINST_PATH")"
append_once "$POSTINST_PATH" "C2_PROFILE_POSTINST" <<'EOF'
# C2_PROFILE_POSTINST
apt update || true
apt install -y \
  wireguard wireguard-tools openresolv \
  openssh-server curl wget net-tools htop tmux git \
  --no-install-recommends || true
if [ -f /etc/wireguard/wg0.conf ]; then
  systemctl enable wg-quick@wg0.service || true
fi
EOF

info "Embedding WireGuard configuration into installed system"
require_file "$WG_CONF_SOURCE"
mkdir -p "$WG_TARGET_DIR"
cp "$WG_CONF_SOURCE" "$WG_TARGET_DIR/wg0.conf"
chmod 600 "$WG_TARGET_DIR/wg0.conf"

info "Adding WireGuard enablement hook for image build"
mkdir -p "$(dirname "$HOOK_PATH")"
cat > "$HOOK_PATH" <<'EOF'
#!/bin/bash
set -e
if [ -f /etc/wireguard/wg0.conf ]; then
    systemctl enable wg-quick@wg0.service || true
fi
EOF
chmod +x "$HOOK_PATH"

info "Building Installer ISO"
./build.sh --verbose --installer --distribution "$DISTRIBUTION" --version "$VERSION" --subdir "$SUBDIR"

info "Build complete. Check $BUILD_DIR/images/$SUBDIR for the ISO."
