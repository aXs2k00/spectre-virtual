# Spectre Virtual Installer Assets

This repository provides themed configuration and an installer script for an OffSec-oriented Devuan environment using Openbox, Tint2, and Conky. The aesthetic is intentionally subtle vaporwave: dark tones with neon highlights, pixel fonts, and soft gradients.

## What's included
- **Installer script** (`install.sh`) that installs dependencies and links configuration files into your `$HOME/.config` paths.
- **Openbox** configuration tuned for keyboard-driven workflows and lightweight compositing hints.
- **Tint2** configurations for a top taskbar and bottom icon-only launcher.
- **Conky** configuration for at-a-glance system telemetry.

## Usage
1. Review the script before executing.
2. Run `./install.sh` from this repo. It will:
   - Install the required packages (`openbox`, `tint2`, `conky-all`, `feh`, `fonts-ibm-plex`).
   - Backup existing configs to `~/.config/spectre-backups/<timestamp>/`.
   - Deploy the new Openbox, Tint2, and Conky configs.
   - Place the vaporwave wallpaper in `~/Pictures/wallpapers/spectre-vaporwave.png` and set it via `feh`.
3. Log into an Openbox session. Tint2 will spawn a top taskbar and bottom launcher; Conky will pin to the right edge by default.

> Note: Devuan ships without systemd; the installer sticks to user-level configuration and does not install services.

## Testing
- Run `make test` to perform a syntax check of `install.sh` via `bash -n`.

## Customization tips
- Update launcher icons/commands in `configs/tint2/bottom-launcher.tint2rc`.
- Adjust Conky metrics or colors in `configs/conky/conky.conf`.
- Modify keybindings in `configs/openbox/rc.xml`.

## License
MIT
