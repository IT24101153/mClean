#!/bin/bash
# SUDO_ASKPASS helper: sudo runs this when Mole needs admin rights and there
# is no terminal. Shows a native password dialog and prints the answer.
# Exits non-zero when the user cancels, which sudo treats as a refusal.

prompt="mClean needs your administrator password to continue."
if [[ -n "${1:-}" && "$1" != "Password:" && "$1" != *"password for"* ]]; then
    prompt="$1"
fi
prompt="${prompt//\\/\\\\}"
prompt="${prompt//\"/\\\"}"

/usr/bin/osascript \
    -e "display dialog \"$prompt\" default answer \"\" with title \"mClean\" with icon caution with hidden answer buttons {\"Cancel\", \"OK\"} default button \"OK\"" \
    -e 'text returned of result' 2> /dev/null
