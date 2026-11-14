#!/usr/bin/env bash
# install.sh — set up the Fedora port of the river-classic waybar config.
#
# What it does (idempotent; safe to re-run):
#   1. detects every dependency (dnf packages, the Terra repository, ghostty,
#      the nerd font) and SKIPS steps 2-4 entirely when they are all present -
#      in that case it goes straight on to the backups and the config files
#   2. enables the Terra repository (Fyra Labs / Ultramarine) and installs
#      ghostty from it - the default river init spawns ghostty on Super+Return
#      and ghostty is NOT in the official Fedora repos
#   3. dnf: river-classic, waybar, mako, the script tools, blueman, ...
#   4. JetBrainsMono Nerd Font -> ~/.local/share/fonts (v3.5.1, GitHub release)
#   5. backs up anything it would overwrite (timestamped .bak.* next to it)
#   6. installs waybar config + shared style.css, the custom/* scripts,
#      mako config and the river init script
#   7. enables NetworkManager / bluetooth / power-profiles-daemon (best effort)
#
# Options:
#   --no-dnf     skip the Terra/ghostty and dnf package steps (config only)
#   --no-font    skip the font download (font already installed)
#   --no-terra   do not enable the Terra repository or install ghostty; the
#                default Super+Return binding needs ghostty from somewhere -
#                see README if you opt out
#   -h, --help   show this text
#
# Afterwards: log out, pick the "river" session in the display manager.
# Nothing here needs a reboot.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip"
TERRA_REPO_URL="https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo"
TERRA_REPO_FILE="/etc/yum.repos.d/terra.repo"
TERRA_REPOPATH="terra,https://repos.fyralabs.com/terra\$releasever"

WITH_DNF=1
WITH_FONT=1
WITH_TERRA=1
for arg in "$@"; do
    case "$arg" in
        --no-dnf)    WITH_DNF=0 ;;
        --no-font)   WITH_FONT=0 ;;
        --no-terra)  WITH_TERRA=0 ;;
        -h|--help)
            cat <<'USAGE'
install.sh — set up the Fedora port of the river-classic waybar config.

  --no-dnf     skip the Terra/ghostty and dnf package steps (config only)
  --no-font    skip the font download (font already installed)
  --no-terra   do not enable the Terra repository or install ghostty
  -h, --help   show this text

Idempotent. If all dependencies are already present the package and font
steps are skipped automatically and only the config files are (re)installed.
USAGE
            exit 0 ;;
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

# ---- 1. dependency detection ------------------------------------------------
# Everything the config needs, checked before touching anything:
# every dnf package, the Terra repo, ghostty and the nerd font. If they are
# all present the package/font steps become no-ops and only the config is
# (re)installed - that is the common case on a re-run on a machine that was
# already set up.
rpm_ok()  { command -v rpm >/dev/null 2>&1 && rpm -q "$1" >/dev/null 2>&1; }
font_ok() { command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd'; }
terra_ok() { [[ -f "$TERRA_REPO_FILE" ]] || rpm_ok terra-release; }

PACKAGES=(
    river-classic waybar mako wlrctl fuzzel
    jq gawk procps-ng util-linux
    NetworkManager bluez blueman
    wireplumber pavucontrol
    libnotify brightnessctl
    upower power-profiles-daemon
    curl unzip tar
)

missing_pkgs=()
if command -v rpm >/dev/null 2>&1; then
    for p in "${PACKAGES[@]}"; do
        rpm_ok "$p" || missing_pkgs+=("$p")
    done
else
    warn "rpm not found - assuming packages are missing (dependency detection needs rpm)"
    missing_pkgs=("${PACKAGES[@]}")
fi
have_font=1;    font_ok                       || have_font=0
have_terra=1;   terra_ok                      || have_terra=0
have_ghostty=1; command -v ghostty >/dev/null 2>&1 || have_ghostty=0

# Terra + ghostty only count as dependencies when the user has not opted out;
# --no-terra means "I will sort out a terminal myself".
deps_ok=1
((${#missing_pkgs[@]} == 0)) || deps_ok=0
(( have_font ))              || deps_ok=0
if (( WITH_TERRA )); then
    (( have_terra && have_ghostty )) || deps_ok=0
fi

if (( WITH_DNF )) && (( deps_ok )); then
    if (( WITH_TERRA )); then
        log "all dependencies already present (packages, Terra repo, ghostty, nerd font) - skipping to the config"
    else
        log "all dependencies already present (packages, nerd font; Terra opted out) - skipping to the config"
    fi
    WITH_DNF=0
    WITH_FONT=0
    WITH_TERRA=0
else
    if (( WITH_DNF )); then
        ((${#missing_pkgs[@]})) && log "missing packages: ${missing_pkgs[*]}"
        (( have_font )) || log "JetBrainsMono Nerd Font not visible to fontconfig"
        if (( WITH_TERRA )); then
            (( have_terra ))   || log "Terra repository not enabled (ghostty lives there)"
            (( have_ghostty )) || log "ghostty not installed"
        fi
    fi
fi

# ---- 2. Terra repository + ghostty ------------------------------------------
# Fyra Labs' third-party repo (the Ultramarine team). It is GPG-signed and
# carries ghostty, which is not in the official repos. Opt out with --no-terra.
ensure_terra() {
    if terra_ok; then
        log "Terra repository already enabled"
        return 0
    fi
    log "enabling the Terra repository (third-party, GPG-signed) for ghostty"
    if sudo dnf config-manager addrepo --from-repofile="$TERRA_REPO_URL" 2>/dev/null; then
        return 0
    elif sudo dnf config-manager --add-repo "$TERRA_REPO_URL" 2>/dev/null; then
        # dnf 4 syntax
        return 0
    else
        warn "dnf config-manager failed - falling back to a direct repofrompath install of terra-release"
        sudo dnf install -y --nogpgcheck --repofrompath "$TERRA_REPOPATH" terra-release
    fi
}

if (( WITH_DNF && WITH_TERRA )); then
    if ensure_terra; then
        if command -v ghostty >/dev/null 2>&1; then
            log "ghostty already installed"
        else
            log "installing ghostty from Terra"
            sudo dnf install -y ghostty \
                || warn "ghostty install failed - Super+Return needs it; install it by hand or edit fedora/river/init"
        fi
    else
        warn "could not enable the Terra repository - ghostty was not installed"
        warn "enable it by hand (see fedora/README.md) or change the Super+Return binding in fedora/river/init"
    fi
fi

# ---- 3. packages -------------------------------------------------------------
if (( WITH_DNF )); then
    log "installing packages with dnf (sudo)"
    sudo dnf install -y \
        river-classic \
        waybar mako wlrctl fuzzel \
        jq gawk procps-ng util-linux \
        NetworkManager bluez blueman \
        wireplumber pavucontrol \
        libnotify brightnessctl \
        upower power-profiles-daemon \
        curl unzip tar
fi

# ---- 4. JetBrainsMono Nerd Font ---------------------------------------------
# Not in the Fedora repos; the nerd-fonts GitHub release is the upstream
# distribution. The bar needs the glyphs, not the plain JetBrains Mono font.
if (( WITH_FONT )); then
    if font_ok; then
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

# ---- 5. backup + 6. install -------------------------------------------------
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
# waybar's config file must be a top-level JSON *array* of bar objects (that is
# what home-manager's programs.waybar.settings emits on NixOS). A bare object
# parses, but no output ever matches it, the bar is never constructed, and
# waybar sits there spawned with nothing on screen - so check the shape.
if command -v jq >/dev/null 2>&1; then
    if ! jq -e 'type == "array" and (.[0] | has("modules-left") and has("modules-right") and has("position"))' \
            "$WAYBAR_DIR/config" >/dev/null; then
        echo "install.sh: $WAYBAR_DIR/config is not a waybar bar array - aborting" >&2
        echo "(see fedora/README.md - \"waybar spawns but no bar appears\")" >&2
        exit 1
    fi
    log "waybar config sanity check passed"
fi
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

# ---- 7. system services (best effort; they are system-wide) ----------------
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
for cmd in river riverctl rivertile waybar mako wlrctl fuzzel nmcli bluetoothctl jq wpctl makoctl ghostty; do
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
