#!/usr/bin/env bash
# notify.sh toggle - flip the mako "do-not-disturb" mode (custom/notify on-click).
# Kept out of the display script so the click is a single makoctl call.

set -uo pipefail
exec makoctl mode -t do-not-disturb
