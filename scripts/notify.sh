#!/usr/bin/env bash
# custom/swaync -> replaced by mako.
#
# mako keeps no unread counter, so there is nothing to put in the bar text; this
# module is a static glyph whose TOOLTIP carries the DND state, and whose clicks
# mirror the old swaync button:
#   left click  -> toggle Do Not Disturb   (was: open the notification centre)
#   right click -> dismiss every notification (was: toggle DND)
#
# DND is a mako *mode*: the "do-not-disturb" mode is bound to invisible=1 in the
# mako config, and `makoctl mode` with no options prints the active modes.
#
# Output: {text,tooltip,class} JSON on every change (custom module, interval 5).

set -uo pipefail

# Octal UTF-8 rather than bash's \U escape, which emits literal text under a
# POSIX locale (the usual locale of a systemd user service).
BELL=$(printf '\363\260\257\226')     # nf-md-bell_outline
BELL_OFF=$(printf '\363\260\257\205') # nf-md-bell_off_outline

modes=$(makoctl mode 2>/dev/null || true)

if grep -qx 'do-not-disturb' <<< "$modes"; then
    text=$BELL_OFF
    tip="Notifications: Do Not Disturb  -  click to unmute, right click to clear"
    class="dnd"
else
    text=$BELL
    tip="Notifications: on  -  click for Do Not Disturb, right click to clear all"
    class="normal"
fi

jq -cn --arg text "$text" --arg tooltip "$tip" --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
