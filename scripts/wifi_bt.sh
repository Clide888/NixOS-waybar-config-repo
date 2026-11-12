#!/usr/bin/env bash
# custom/wifi - compact WiFi indicator (icon + signal %), with WiFi + Bluetooth
# merged into a single tooltip on hover. Neither of these has a native waybar
# module, so nmcli (NetworkManager) and bluetoothctl are combined here.
#
# Differences from the Hyprland original:
#   * the interface is no longer hardcoded to wlo1 - it is auto-detected from
#     NetworkManager, with WAYBAR_WIFI_IFACE as an override;
#   * `nmcli`/`bluetoothctl` are resolved from PATH, which the module's
#     systemd unit / wrapper builds explicitly (see modules/waybar-river.nix).

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
        wifi_tip="<b>WiFi</b>  ${ssid}  -  ${signal}%"
    else
        class="disconnected"
        text=$(printf '\363\260\244\255')
        wifi_tip="<b>WiFi</b>  connected (no SSID reported)"
    fi
else
    class="disconnected"
    text=$(printf '\363\260\244\255')
    wifi_tip="<b>WiFi</b>  not connected"
fi

# --- Bluetooth ---
powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')
if [[ "$powered" != "yes" ]]; then
    bt_tip="<b>Bluetooth</b>  off"
else
    connected=$(bluetoothctl devices Connected 2>/dev/null)
    if [[ -z "$connected" ]]; then
        bt_tip="<b>Bluetooth</b>  no connected devices"
    else
        bt_tip="<b>Bluetooth</b>"
        while read -r _ mac name; do
            [[ -z "${mac:-}" ]] && continue
            batt=$(bluetoothctl info "$mac" 2>/dev/null \
                   | sed -n 's/.*Battery Percentage:.*(\([0-9]\+\)).*/\1/p')
            if [[ -n "$batt" ]]; then
                bt_tip+=$'\n'"  ${name}  -  ${batt}%"
            else
                bt_tip+=$'\n'"  ${name}"
            fi
        done <<< "$connected"
    fi
fi

tooltip="${wifi_tip}"$'\n'"${bt_tip}"

jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
