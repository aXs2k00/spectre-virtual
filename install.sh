#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
BACKUP_ROOT="$HOME/.config/spectre-backups/$(date +%Y%m%d-%H%M%S)"

CONFIG_TARGET="$HOME/.config"
OPENBOX_DIR="$CONFIG_TARGET/openbox"
CONKY_DIR="$CONFIG_TARGET/conky"
TINT2_DIR="$CONFIG_TARGET/tint2"
WALL_DIR="$HOME/Pictures/wallpapers"

packages=(openbox tint2 conky-all feh fonts-ibm-plex)

install_packages() {
  echo "[+] Installing packages: ${packages[*]}";
  sudo apt-get update;
  sudo apt-get install -y "${packages[@]}";
}

backup_existing() {
  mkdir -p "$BACKUP_ROOT";
  for dir in "$OPENBOX_DIR" "$CONKY_DIR" "$TINT2_DIR"; do
    if [ -d "$dir" ]; then
      echo "[+] Backing up $dir to $BACKUP_ROOT";
      cp -a "$dir" "$BACKUP_ROOT";
    fi
  done
}

deploy_configs() {
  mkdir -p "$OPENBOX_DIR" "$CONKY_DIR" "$TINT2_DIR" "$WALL_DIR";
  install -m 644 "$REPO_DIR/configs/openbox/rc.xml" "$OPENBOX_DIR/rc.xml";
  install -m 755 "$REPO_DIR/configs/openbox/autostart" "$OPENBOX_DIR/autostart";
  install -m 644 "$REPO_DIR/configs/tint2/top-taskbar.tint2rc" "$TINT2_DIR/top-taskbar.tint2rc";
  install -m 644 "$REPO_DIR/configs/tint2/bottom-launcher.tint2rc" "$TINT2_DIR/bottom-launcher.tint2rc";
  install -m 644 "$REPO_DIR/configs/conky/conky.conf" "$CONKY_DIR/conky.conf";
}

place_wallpaper() {
  mkdir -p "$WALL_DIR";
  local target_png="$WALL_DIR/spectre-vaporwave.png";
  local source_svg="$REPO_DIR/assets/spectre-vaporwave.svg";

  if command -v rsvg-convert >/dev/null 2>&1; then
    echo "[+] Rendering wallpaper PNG via rsvg-convert";
    rsvg-convert -w 1920 -h 1080 -o "$target_png" "$source_svg";
  elif command -v convert >/dev/null 2>&1; then
    echo "[+] Rendering wallpaper PNG via ImageMagick";
    convert -resize 1920x1080! "$source_svg" "$target_png";
  else
    echo "[!] Neither rsvg-convert nor convert found; copying SVG as fallback";
    cp "$source_svg" "$WALL_DIR/spectre-vaporwave.svg";
    target_png="$WALL_DIR/spectre-vaporwave.svg";
  fi

  echo "[+] Wallpaper placed at $target_png"
}

main() {
  install_packages;
  backup_existing;
  deploy_configs;
  place_wallpaper;
  echo "[+] Install complete. Log into Openbox to see the new panels and Conky overlay.";
}

main "$@"
