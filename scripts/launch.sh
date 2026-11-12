#!/usr/bin/env bash
# launch.sh - restart the bar.
#
# The Hyprland version was `pgrep -x waybar && killall waybar || waybar &`, which
# is a no-op when waybar is running: `killall` succeeds, so the `|| waybar`
# branch never fires and the bar simply disappears. This version always waits
# for the old process to go and then starts exactly one new one.

set -uo pipefail

if pgrep -x waybar >/dev/null 2>&1; then
    pkill -x waybar
    for _ in $(seq 1 50); do
        pgrep -x waybar >/dev/null 2>&1 || break
        sleep 0.02
    done
fi

# setsid: keep the bar alive after the terminal/launcher that ran this closes.
exec setsid -f waybar
