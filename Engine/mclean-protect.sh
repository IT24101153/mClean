#!/bin/bash
# Reads and writes Mole's clean protection list (~/.config/mole/whitelist)
# through Mole's own functions, so mClean follows Mole's rules exactly.
#
# Usage:
#   mclean-protect.sh <mole-dir> state
#       item<TAB>0|1<TAB>name<TAB>pattern<TAB>category   one per protectable cache
#       custom<TAB>pattern                                 protections without a menu row
#   mclean-protect.sh <mole-dir> save < patterns
#       Saves the complete list, one pattern per line on stdin.
#
# Saving writes the file, and an existing file replaces Mole's optional
# defaults, so callers pass every pattern to keep: the protected menu items
# plus every custom pattern from `state`, which includes those defaults.

set -euo pipefail

MOLE_DIR="$1"
COMMAND="$2"

# shellcheck source=/dev/null
source "$MOLE_DIR/lib/core/common.sh"
# shellcheck source=/dev/null
source "$MOLE_DIR/lib/manage/whitelist.sh"

case "$COMMAND" in
    state)
        load_whitelist clean
        menu_patterns=()
        while IFS='|' read -r name pattern category; do
            [[ -n "$name" ]] || continue
            pattern="${pattern/\$HOME/$HOME}"
            menu_patterns+=("$pattern")
            protected=0
            is_whitelisted "$pattern" && protected=1
            printf 'item\t%s\t%s\t%s\t%s\n' "$protected" "$name" "$pattern" "$category"
        done <<< "$(get_all_cache_items)"

        for current in ${CURRENT_WHITELIST_PATTERNS[@]+"${CURRENT_WHITELIST_PATTERNS[@]}"}; do
            known=false
            for pattern in "${menu_patterns[@]}" ${SAFETY_WHITELIST_PATTERNS[@]+"${SAFETY_WHITELIST_PATTERNS[@]}"}; do
                if patterns_equivalent "$current" "$pattern"; then
                    known=true
                    break
                fi
            done
            [[ "$known" == "true" ]] || printf 'custom\t%s\n' "$current"
        done
        ;;
    save)
        patterns=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && patterns+=("$line")
        done
        if [[ ${#patterns[@]} -gt 0 ]]; then
            save_whitelist_patterns clean "${patterns[@]}"
        else
            save_whitelist_patterns clean
        fi
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        exit 1
        ;;
esac
