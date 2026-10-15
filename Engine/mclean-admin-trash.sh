#!/bin/bash
# Moves audio plug-ins and presets that only an administrator can change into
# the user's Trash, then gives them to the user so the Trash can be emptied
# normally. Runs as root through macOS's administrator prompt, so it accepts
# nothing outside the audio plug-in and preset folders.
#
# Usage: mclean-admin-trash.sh <uid> <gid> <home> <path>...
# Prints "moved<TAB>path" or "failed<TAB>path" for each path.

set -u

uid="$1"
gid="$2"
home="$3"
shift 3

trash="$home/.Trash"
if [[ ! -d "$trash" || -L "$trash" ]]; then
    echo "The Trash folder is missing: $trash" >&2
    exit 2
fi

allowed() {
    case "$1" in
        *"/../"* | *"/.." | *"/./"*) return 1 ;;
        "/Library/Audio/Plug-Ins/"?* | "/Library/Application Support/Avid/Audio/Plug-Ins/"?* | \
            "/Library/Application Support/Avid/Audio/Plug-Ins (Unused)/"?* | "/Library/Audio/Presets/"?* | \
            "$home/Library/Audio/Plug-Ins/"?* | "$home/Library/Audio/Presets/"?*)
            return 0
            ;;
    esac
    return 1
}

status=0
for path in "$@"; do
    if ! allowed "$path" || [[ -L "$path" ]]; then
        printf 'failed\t%s\n' "$path"
        status=1
        continue
    fi
    [[ -e "$path" ]] || continue

    base="${path##*/}"
    dest="$trash/$base"
    if [[ -e "$dest" || -L "$dest" ]]; then
        stem="${base%.*}"
        ext="${base##*.}"
        stamp="$(date +%H.%M.%S)"
        if [[ "$stem" == "$base" ]]; then
            dest="$trash/$base $stamp"
        else
            dest="$trash/$stem $stamp.$ext"
        fi
    fi

    if /bin/mv "$path" "$dest" && /usr/sbin/chown -Rh "$uid:$gid" "$dest"; then
        printf 'moved\t%s\n' "$path"
    else
        printf 'failed\t%s\n' "$path"
        status=1
    fi
done
exit "$status"
