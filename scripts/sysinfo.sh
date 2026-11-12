#!/usr/bin/env bash
# custom/sysinfo - CPU + RAM in one capsule, single icon (no numbers). When a
# threshold is crossed the CSS class changes (normal -> warning -> critical) and
# the color turns orange/red. Exact numbers only in the hover tooltip.
# Called with `interval: 2` from the waybar module.
#
# Ported from the Hyprland config unchanged, minus the on-click handler: that
# button used to run scripts/focus.sh ("close every Hyprland window, relaunch a
# fixed app set"), which has no river equivalent - river exposes no window list
# or window-closing API to clients, so the action is gone rather than faked.

set -uo pipefail

cpu_snap() { awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5+$6}' /proc/stat; }

read -r t1 i1 < <(cpu_snap)
sleep 1
read -r t2 i2 < <(cpu_snap)

cpu=$(awk -v t1="$t1" -v i1="$i1" -v t2="$t2" -v i2="$i2" \
      'BEGIN{dt=t2-t1; di=i2-i1; printf "%d", (dt>0)?(100*(dt-di)/dt):0}')

read -r total avail < <(free -b | awk '/^Mem:/{print $2, $7}')
used=$(( total - avail ))
ram_pct=$(( 100 * used / total ))
ram_gi=$(awk -v u="$used" 'BEGIN{printf "%.1f", u/1073741824}')

class="normal"
if   (( cpu > 90 || ram_pct > 90 )); then class="critical"
elif (( cpu > 70 || ram_pct > 80 )); then class="warning"
fi

# nf-md-cpu. Octal UTF-8: bash's \U escape emits literal text under a POSIX
# locale, which is what a systemd user service often has.
icon=$(printf '\363\260\222\274')

jq -cn --arg text "$icon" \
       --arg tooltip "$(printf 'CPU  -  %s%%\nRAM  -  %s Gi  (%s%%)' "$cpu" "$ram_gi" "$ram_pct")" \
       --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
