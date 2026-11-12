#!/usr/bin/env bash
# custom/window - the capsule on the left of the bar showing the focused app.
#
# Shows the application's NAME (not the window title). river's own `river/window`
# module renders titles, so this replaces the old Hyprland-only python parser with
# an app-name reader.
#
# Source of truth: `wlrctl toplevel list state:activated`. river 0.3 implements
# wlr-foreign-toplevel-management including the activated state, and wlrctl prints
# one line per window as "<app_id>: <title>", so the activated line names the
# focused app. The title rides along as the tooltip.
#
# Fallbacks, in order:
#   1. $WAYBAR_WINDOW_CLASS - a user-provided app id (useful for testing, or if you
#      already export it from your session);
#   2. a "no windows" glyph, which is also what you get when wlrctl is missing.
#
# Output: one JSON line per run (custom module, return-type: json) carrying
# `text`, `tooltip` and `class`. class is "window" whenever there is a window, so
# style.css never has to know about desktop ids.

set -uo pipefail

GLYPH=$(printf '\363\260\226\257')   # nf-md-window_closed_variant
EMPTY_TEXT="no windows"

# app_id -> display name, for the fallback path and for ids whose .desktop name
# is uglier than what you want on the bar.
declare -A NAME_MAP=(
    [firefox]="Firefox"          [librewolf]="LibreWolf"      [chromium]="Chromium"
    [brave-browser]="Brave"      [brave]="Brave"              [google-chrome]="Chrome"
    [kitty]="kitty"              [foot]="foot"                [alacritty]="Alacritty"
    [org.wezfurlong.wezterm]="WezTerm"
    [dolphin]="Dolphin"          [org.kde.dolphin]="Dolphin"  [thunar]="Thunar"
    [nautilus]="Files"           [obsidian]="Obsidian"        [md.obsidian.Obsidian]="Obsidian"
    [code]="VS Code"             [code-oss]="VS Code"         [com.visualstudio.code]="VS Code"
    [discord]="Discord"          [com.discordapp.Discord]="Discord"
    [telegramdesktop]="Telegram" [org.telegram.desktop]="Telegram"
    [mpv]="mpv"                  [imv]="imv"                  [zathura]="zathura"
    [pavucontrol]="pavucontrol"  [nm-connection-editor]="Network"
)

focused=""
if command -v wlrctl >/dev/null 2>&1; then
    focused=$(wlrctl toplevel list state:activated 2>/dev/null | head -n1)
fi

if [[ -n "$focused" ]]; then
    app_id=${focused%%:*}
    name=${NAME_MAP[$app_id]:-${app_id:-${focused#*: }}}
    tooltip=${focused#*: }
    class="window"
elif [[ -n "${WAYBAR_WINDOW_CLASS:-}" ]]; then
    app_id=$WAYBAR_WINDOW_CLASS
    name=${NAME_MAP[$app_id]:-$app_id}
    tooltip=""
    class="window"
else
    name="$GLYPH $EMPTY_TEXT"
    tooltip=""
    class="empty"
fi

jq -cn --arg text "$name" --arg tooltip "$tooltip" --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
