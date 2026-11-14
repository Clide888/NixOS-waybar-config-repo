#!/usr/bin/env bash
# install.sh — set up the Fedora port of the river-classic waybar config.
#
# What it does (idempotent; safe to re-run):
#   1. dnf: river-classic, waybar, mako, the script tools, blueman, fonts tools
#   2. JetBrainsMono Nerd Font -> ~/.local/share/fonts (v3.5.1, GitHub release)
#   3. backs up anything it would overwrite (timestamped .bak.* next to it)
#   4. installs waybar config + shared style.css, the custom/* scripts,
#      mako config and the river init script
#   5. enables NetworkManager / bluetooth / power-profiles-daemon (best effort)
#
# Options:
#   --no-dnf    skip step 1 (packages already installed)
#   --no-font   skip step 2 (font already installed)
#   -h, --help  show this text
#
# Afterwards: log out, pick the "river" session in the display manager.
# Nothing here needs a reboot.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip"

WITH_DNF=1
WITH_FONT=1
for arg in "$@"; do
    case "$arg" in
        --no-dnf)  WITH_DNF=0 ;;
        --no-font) WITH_FONT=0 ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "install.sh: unknown option '$arg' (see --help)" >&2; exit 2 ;;
    esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

if [[ ! -f /etc/fedora-release ]]; then
    warn "this does not look like Fedora - the package names assume dnf and the Fedora repos"
fi

# river-classic is in the official Fedora repos since F43. Do NOT install the
# plain `river` package from F44+ instead: that is the river 0.4/0.5 rewrite,
# which river/tags speaks a different status protocol to and the waybar tags
# module renders blank. The two conflict; river-classic wins.
if rpm -q river >/dev/null 2>&1 && ! rpm -q river-classic >/dev/null 2>&1; then
    warn "the 'river' package is installed. On Fedora 44+ that is river 0.4/0.5, which is not river-classic."
    warn "install river-classic and let dnf remove river (they conflict): sudo dnf swap river river-classic"
fi

# ---- 1. packages -----------------------------------------------------------
if (( WITH_DNF )); then
    log "installing packages with dnf (sudo)"
    sudo dnf install -y \
        river-classic \
        waybar mako wlrctl \
        jq gawk procps-ng util-linux \
        NetworkManager bluez blueman \
        wireplumber pavucontrol \
        libnotify brightnessctl \
        upower power-profiles-daemon \
        curl unzip tar
fi

# ---- 2. JetBrainsMono Nerd Font -------------------------------------------
# Not in the Fedora repos; the nerd-fonts GitHub release is the upstream
# distribution. The bar needs the glyphs, not the plain JetBrains Mono font.
if (( WITH_FONT )); then
    if fc-list 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd'; then
        log "JetBrainsMono Nerd Font already visible to fontconfig - skipping"
    else
        log "installing JetBrainsMono Nerd Font 3.5.1 into ~/.local/share/fonts"
        font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
        tmp="$(mktemp -d)"
        if curl -fL --retry 3 --connect-timeout 15 -o "$tmp/JetBrainsMono.zip" "$FONT_URL" \
           && unzip -oq "$tmp/JetBrainsMono.zip" -d "$font_dir"; then
            rm -f "$font_dir"/*Windows* "$font_dir"/*.md 2>/dev/null || true
            command -v fc-cache >/dev/null && fc-cache -f "$HOME/.local/share/fonts" >/dev/null
            log "font installed"
        else
            warn "font download failed - install it by hand from $FONT_URL"
            warn "(unpack into ~/.local/share/fonts and run: fc-cache -f)"
        fi
        rm -rf "$tmp"
    fi
fi

# ---- 3. backup + 4. install ------------------------------------------------
ts="$(date +%Y%m%d-%H%M%S)"
backup() {  # backup <path> - copy to path.bak.<ts> if it exists
    local p="$1"
    if [[ -e "$p" ]]; then
        cp -a "$p" "$p.bak.$ts"
        log "backed up $p -> $p.bak.$ts"
    fi
}

WAYBAR_DIR="$HOME/.config/waybar"
SCRIPTS_DIR="$WAYBAR_DIR/scripts"

backup "$WAYBAR_DIR/config"
backup "$WAYBAR_DIR/style.css"
backup "$SCRIPTS_DIR"
backup "$HOME/.config/mako/config"
backup "$HOME/.config/river/init"

log "installing waybar config"
install -Dm644 "$REPO_ROOT/fedora/waybar/config.jsonc" "$WAYBAR_DIR/config"
# style.css is shared with the NixOS port - single source of truth at repo root
install -Dm644 "$REPO_ROOT/style.css" "$WAYBAR_DIR/style.css"

log "installing custom/* scripts"
install -dm755 "$SCRIPTS_DIR"
for s in "$REPO_ROOT"/scripts/*.sh; do
    install -Dm755 "$s" "$SCRIPTS_DIR/$(basename "$s")"
done
# superseded by wifi.sh + bluetooth.sh; drop our own old artifact if present
rm -f "$SCRIPTS_DIR/wifi_bt.sh"

log "installing mako config"
install -Dm644 "$REPO_ROOT/fedora/mako/config" "$HOME/.config/mako/config"

log "installing river init"
install -Dm755 "$REPO_ROOT/fedora/river/init" "$HOME/.config/river/init"

log "installing waybar-launch into ~/.local/bin"
install -Dm755 "$REPO_ROOT/scripts/launch.sh" "$HOME/.local/bin/waybar-launch"

# ---- 5. system services (best effort; they are system-wide) ----------------
for unit in NetworkManager.service bluetooth.service power-profiles-daemon.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        log "ensuring $unit is enabled and running"
        sudo systemctl enable --now "$unit" || warn "could not enable $unit - check it by hand"
    else
        warn "$unit not found - skipping (upower is D-Bus activated and needs no enabling)"
    fi
done

# ---- checks -----------------------------------------------------------------
log "checking the pieces"
missing=0
for cmd in river riverctl rivertile waybar mako wlrctl nmcli bluetoothctl jq wpctl makoctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "'$cmd' not found on PATH"
        missing=1
    fi
done
[[ -x "$HOME/.config/river/init" ]] || { warn "river init is not executable"; missing=1; }

echo
if (( missing )); then
    warn "some pieces are missing - read the warnings above"
else
    log "all pieces present"
fi
cat <<'EOF'

Next steps:
  1. log out
  2. in the display manager, pick the "river" session (river-classic ships it)
  3. the bar and notifications start with river - nothing else to enable

Useful after login:
  waybar-launch            # restart the bar (or: pkill waybar; waybar &)
  makoctl mode           # should list nothing unless DND is on
  ~/.config/waybar/scripts/bluetooth.sh   # smoke-test the bluetooth widget

The bar shows a Bluetooth glyph next to WiFi; left click it to toggle the
radio power, right click to open blueman-manager.
EOF
