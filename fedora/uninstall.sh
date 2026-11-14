#!/usr/bin/env bash
# uninstall.sh — remove what install.sh put in place. Leaves dnf packages and
# the timestamped .bak.* backups alone. Nothing is restored automatically;
# move a backup back by hand if you want the old config.

set -euo pipefail

removed=0
remove() {
    if [[ -e "$1" ]]; then
        rm -rf "$1"
        printf 'removed %s\n' "$1"
        removed=$((removed + 1))
    fi
}

remove "$HOME/.config/waybar/config"
remove "$HOME/.config/waybar/style.css"
for s in bluetooth.sh wifi.sh uptime.sh stopwatch.sh sysinfo.sh system-reset.sh \
         toggle-tag-bar.sh notify.sh notify-toggle.sh window.sh launch.sh wifi_bt.sh; do
    remove "$HOME/.config/waybar/scripts/$s"
done
# rmdir only succeeds when the directory is empty - i.e. nothing of yours there
rmdir "$HOME/.config/waybar/scripts" 2>/dev/null || true
remove "$HOME/.config/mako/config"
remove "$HOME/.config/river/init"
remove "$HOME/.local/bin/waybar-launch"
# rmdir only succeeds when a directory is empty
for d in "$HOME/.config/river" "$HOME/.config/mako" "$HOME/.config/waybar" "$HOME/.local/bin"; do
    rmdir "$d" 2>/dev/null || true
done

echo
echo "removed $removed item(s). dnf packages were left alone:"
echo "  sudo dnf remove river-classic waybar mako wlrctl blueman   # if you want them gone"
echo "backups, if any, are next to the files as <name>.bak.<timestamp>"
