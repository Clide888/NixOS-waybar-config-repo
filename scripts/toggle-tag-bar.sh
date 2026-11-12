#!/usr/bin/env bash
# toggle-tag-bar.sh - the SUPER+A "hide the bar" button, ported to river.
#
# Appends the current tag bitmask (what `riverctl focused-tags` prints) to
# $XDG_CACHE_HOME/waybar/hidden_tags, or removes it if it is already there, and
# stops/starts waybar to apply the change.
#
# What changed from the Hyprland version: there, a background daemon listened on
# Hyprland's socket2 and relaunched the bar whenever you switched back to a
# visible workspace. River exposes tag state only over its Wayland status
# protocol, and nothing packaged in nixpkgs can subscribe to that, so there is no
# auto-restore. The bar stays hidden on the tags you marked until you press the
# binding again; the cache file is only a record of which tags those were.
#
# The tag is stored as a bitmask rather than a number because that is what
# riverctl reports, and the list is global rather than per-output because
# riverctl cannot say which output is focused.

set -uo pipefail

if ! command -v riverctl >/dev/null 2>&1; then
    echo "toggle-tag-bar.sh: riverctl not found - is this a river session?" >&2
    exit 1
fi

HIDDEN="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/hidden_tags"
mkdir -p "$(dirname "$HIDDEN")"
touch "$HIDDEN"

mask=$(riverctl focused-tags 2>/dev/null || true)
if [ -z "$mask" ]; then
    echo "toggle-tag-bar.sh: riverctl focused-tags returned nothing" >&2
    exit 1
fi

if grep -qxF "$mask" "$HIDDEN"; then
    grep -vxF "$mask" "$HIDDEN" > "$HIDDEN.tmp" || true
    mv "$HIDDEN.tmp" "$HIDDEN"
    if ! pgrep -x waybar >/dev/null 2>&1; then
        setsid -f waybar >/dev/null 2>&1
    fi
else
    echo "$mask" >> "$HIDDEN"
    if pgrep -x waybar >/dev/null 2>&1; then
        pkill -x waybar
    fi
fi
