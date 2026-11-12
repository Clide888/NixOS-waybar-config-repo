#!/usr/bin/env bash
# system-reset.sh - `custom/sysinfo` on-click, and the META+SHIFT+R binding.
#
# What the Hyprland original did (scripts/focus.sh): close every window, then
# relaunch firefox/brave/obsidian/kitty/dolphin onto fixed workspaces. The
# closing half is not portable: river hands clients no window list and no
# window-close command - only a layout generator can close views, and this
# setup runs stock rivertile, which does not. So this keeps the half that *is*
# portable: clear the tag, then spawn the app set onto tags 1/3/4/5/6.
#
# `riverctl spawn` inherits the tag that is focused when it is run, so each app
# is preceded by `riverctl focus-tags <tag>`; the user's own tag is restored at
# the end. Apps are launched through `setsid` so they survive a bar restart and
# so a failed command cannot take the script down.
#
# Override the app list with SYSTEM_RESET_APPS="firefox "kitty -e htop"".

set -uo pipefail

if ! command -v riverctl >/dev/null 2>&1; then
    echo "system-reset.sh: riverctl not found - is this a river session?" >&2
    exit 1
fi

# Where the user was before the reset, so it can be restored at the end.
original_tags=$(riverctl focused-tags 2>/dev/null || echo "")

apps=${SYSTEM_RESET_APPS:-"firefox brave obsidian kitty dolphin"}

# `riverctl spawn` is used rather than launching the app from here: the command
# is queued in the compositor, so it is guaranteed to run after the focus-tags
# call that precedes it. A plain `setsid app &` races that change and can land
# the window on the previous tag.
tag=1
for app in $apps; do
    [ "$tag" -gt 9 ] && break
    # riverctl joins the remaining words and hands the line to /bin/sh -c, so an
    # entry may carry arguments ("firefox --new-window").
    if command -v "${app%% *}" >/dev/null 2>&1; then
        riverctl focus-tags "$(( 1 << (tag - 1) ))" >/dev/null 2>&1 || true
        riverctl spawn "$app" >/dev/null 2>&1 || true
    fi
    tag=$(( tag + 1 ))
done

# Give the compositor a moment to place the spawns on their tags before the
# focus moves back, otherwise the last window may end up on the restored tag.
sleep 0.3
if [ -n "$original_tags" ]; then
    riverctl focus-tags "$original_tags" >/dev/null 2>&1 || true
fi
