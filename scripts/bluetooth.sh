#!/usr/bin/env bash
# custom/bluetooth - Bluetooth indicator, split out of the old wifi_bt.sh.
#
# Shows one glyph for the controller state; the tooltip carries the power state
# and every connected device (with battery percentage when BlueZ reports one).
# Classes, so style.css can color them:
#   off       - controller powered off (or missing)
#   on        - controller powered, no devices connected
#   connected  - at least one device is connected
#
# Clicks (wired up in the waybar config, NixOS module and Fedora config alike):
#   left click  -> toggle the controller power   (`bluetooth.sh toggle`)
#   right click -> open blueman-manager
# The power toggle is best effort: BlueZ decides who may set Powered, and on
# some setups that is restricted to root/polkit - the right click always works.
#
# Output: {text,tooltip,class} JSON on every change (custom module, interval 10).

set -uo pipefail

# Octal UTF-8 rather than bash's \U escape: under a POSIX locale (the usual
# locale of a systemd user service / a display-manager session) \U emits the
# literal text instead of the glyph.
BT=$(printf '\363\260\202\257')          # nf-md-bluetooth
BT_ACTIVE=$(printf '\363\260\202\260')   # nf-md-bluetooth-audio (in use)
BT_OFF=$(printf '\363\260\202\262')      # nf-md-bluetooth off/muted

# --- `bluetooth.sh toggle`: flip controller power, then exit -----------------
if [[ "${1:-}" == "toggle" ]]; then
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        echo "bluetooth.sh: bluetoothctl not found - is bluez installed?" >&2
        exit 1
    fi
    powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')
    if [[ "$powered" == "yes" ]]; then
        exec bluetoothctl power off
    else
        exec bluetoothctl power on
    fi
fi

# --- status ------------------------------------------------------------------
if ! command -v bluetoothctl >/dev/null 2>&1; then
    jq -cn --arg text "$BT_OFF" \
           --arg tooltip "<b>Bluetooth</b>  bluetoothctl not found (install bluez)" \
           --arg class "off" \
        '{text:$text, tooltip:$tooltip, class:$class}'
    exit 0
fi

powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')

if [[ "$powered" != "yes" ]]; then
    jq -cn --arg text "$BT_OFF" \
           --arg tooltip "<b>Bluetooth</b>  off  -  click: power on, right click: manager" \
           --arg class "off" \
        '{text:$text, tooltip:$tooltip, class:$class}'
    exit 0
fi

connected=$(bluetoothctl devices Connected 2>/dev/null)
if [[ -z "$connected" ]]; then
    jq -cn --arg text "$BT" \
           --arg tooltip "<b>Bluetooth</b>  on, no connected devices  -  click: power off, right click: manager" \
           --arg class "on" \
        '{text:$text, tooltip:$tooltip, class:$class}'
    exit 0
fi

tip="<b>Bluetooth</b>  connected:"
while read -r _ mac name; do
    [[ -z "${mac:-}" ]] && continue
    batt=$(bluetoothctl info "$mac" 2>/dev/null \
           | sed -n 's/.*Battery Percentage:.*(\([0-9]\+\)).*/\1/p')
    if [[ -n "$batt" ]]; then
        tip+=$'\n'"  ${name}  -  ${batt}%"
    else
        tip+=$'\n'"  ${name}"
    fi
done <<< "$connected"

jq -cn --arg text "$BT_ACTIVE" --arg tooltip "$tip" --arg class "connected" \
    '{text:$text, tooltip:$tooltip, class:$class}'
