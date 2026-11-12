#!/usr/bin/env bash
# custom/uptime - the box ALWAYS shows uptime; the stopwatch state lives in the
# tooltip.
#   no args -> {text,tooltip,class} JSON  (interval: 1)
# Stopwatch clicks are wired straight to stopwatch.sh in the module config
# (on-click -> toggle, on-click-right -> reset). This script is display only.
# State file: $XDG_CACHE_HOME/waybar/stopwatch_state ("running:start:accumulated")

set -uo pipefail

STATE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/stopwatch_state"

up=$(uptime -p | sed 's/up //; s/ days,/d/; s/ day,/d/; s/ hours,/h/; s/ hour,/h/; s/ minutes/m/; s/ minute/m/')

# nf-md-timer. Octal UTF-8 on purpose: under a POSIX/ASCII locale (which is
# what a systemd user service often runs with) bash's \U escape emits the
# literal text instead of the glyph.
sw=$(printf '\363\261\216\253')

running=0; start=0; acc=0
if [[ -f "$STATE" ]]; then
    IFS=: read -r running start acc < "$STATE"
    running=${running:-0}; start=${start:-0}; acc=${acc:-0}
fi
now=$(date +%s)

if [[ "$running" == "1" ]]; then
    e=$(( acc + now - start ))
else
    e=$acc
fi
printf -v mmss '%02d:%02d' $(( e/60 )) $(( e%60 ))

if [[ "$running" == "1" ]]; then
    cls="running"
    tip="$sw $mmss running  -  left click: pause  -  right click: reset"
elif (( e > 0 )); then
    cls="paused"
    tip="$sw $mmss paused  -  left click: resume  -  right click: reset"
else
    cls="idle"
    tip="Stopwatch  -  left click: start"
fi

jq -cn --arg text "$up" --arg tooltip "$tip" --arg class "$cls" \
    '{text:$text, tooltip:$tooltip, class:$class}'
