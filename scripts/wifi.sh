#!/usr/bin/env bash
# custom/wifi - compact WiFi indicator (icon + signal %).
#
# Split out of the old wifi_bt.sh: the Bluetooth half is now its own widget
# (scripts/bluetooth.sh, custom/bluetooth), placed next to this one on the bar.
# Neither nmcli state nor bluetoothctl has a native waybar module, so nmcli
# (NetworkManager) is polled here.
#
# Differences from the Hyprland original (kept from that port):
#   * the interface is not hardcoded to wlo1 - it is auto-detected from
#     NetworkManager, with WAYBAR_WIFI_IFACE as an override;
#   * `nmcli` is resolved from PATH, which the module's
#     systemd unit / wrapper builds explicitly (see modules/waybar-river.nix);
#     on Fedora the scripts run straight from ~/.config/waybar/scripts.

set -uo pipefail

iface=${WAYBAR_WIFI_IFACE:-}
if [[ -z "$iface" ]]; then
    # first wifi device NetworkManager knows about
    iface=$(nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
fi

state=""
if [[ -n "$iface" ]]; then
    state=$(nmcli -t -f DEVICE,STATE dev status 2>/dev/null | awk -F: -v i="$iface" '$1==i{print $2; exit}')
fi

if [[ "$state" == connected* ]]; then
    # --rescan no: a plain `nmcli dev wifi` rescans when the last scan is older
    # than 30s, so polling it every 10s kept the radio off-channel a few seconds
    # at a time, with visible throughput dips.
    line=$(nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list --rescan no 2>/dev/null \
           | awk -F: '$1=="yes"{print; exit}')

    if [[ -n "$line" ]]; then
        ssid=${line#yes:}; ssid=${ssid%:*}
        signal=${line##*:}
        [[ -z "$signal" ]] && signal=0
        class="connected"
        if   (( signal >= 75 )); then icon=$(printf '\363\260\244\250')
        elif (( signal >= 50 )); then icon=$(printf '\363\260\244\242')
        elif (( signal >= 25 )); then icon=$(printf '\363\260\244\237')
        else                          icon=$(printf '\363\260\244\257')
        fi
        text="$icon ${signal}%"
        tooltip="<b>WiFi</b>  ${ssid}  -  ${signal}%"
    else
        class="disconnected"
        text=$(printf '\363\260\244\255')
        tooltip="<b>WiFi</b>  connected (no SSID reported)"
    fi
else
    class="disconnected"
    text=$(printf '\363\260\244\255')
    tooltip="<b>WiFi</b>  not connected"
fi

jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
