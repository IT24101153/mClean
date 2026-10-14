#!/bin/bash
# Copies one version of the Mole engine (shell scripts + Go helpers) into
# Engine/Mole so the app bundle is self-contained.
#
# Usage: Scripts/vendor-mole.sh [source]
#
# source is either:
#   - an installed Mole release that ships its Go helpers, such as Homebrew's
#     /opt/homebrew/opt/mole/libexec (the default when present), or
#   - a Mole source checkout, whose Go helpers are built with Go.
#
# Scripts and helpers always come from the same source, never mixed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Engine/Mole"

default_source="/opt/homebrew/opt/mole/libexec"
[[ -d "$default_source" ]] || default_source="$HOME/Downloads/Mole-main"
SRC="$(cd "${1:-$default_source}" && pwd -P)"

if [[ ! -f "$SRC/mole" || ! -f "$SRC/lib/core/common.sh" ]]; then
    echo "Not a Mole engine folder: $SRC" >&2
    exit 1
fi

license=""
for candidate in "$SRC/LICENSE" "$SRC/../LICENSE"; do
    if [[ -f "$candidate" ]]; then
        license="$candidate"
        break
    fi
done

if [[ -f "$SRC/go.mod" && -d "$SRC/cmd" ]]; then
    kind="source checkout"
    if ! command -v go > /dev/null 2>&1; then
        echo "$SRC is a source checkout; its Go helpers need Go (brew install go)." >&2
        exit 1
    fi
elif [[ -x "$SRC/bin/analyze-go" && -x "$SRC/bin/status-go" ]]; then
    kind="release"
else
    echo "$SRC has neither Go sources nor prebuilt helpers." >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/bin"
cp "$SRC/mole" "$DEST/"
cp -R "$SRC/lib" "$DEST/lib"
cp "$SRC"/bin/*.sh "$DEST/bin/"
[[ -n "$license" ]] && cp "$license" "$DEST/LICENSE"

if [[ "$kind" == "source checkout" ]]; then
    echo "Building Go helpers from $SRC"
    (
        cd "$SRC"
        CGO_ENABLED=0 go build -ldflags="-s -w" -o "$DEST/bin/analyze-go" ./cmd/analyze
        CGO_ENABLED=0 go build -ldflags="-s -w" -o "$DEST/bin/status-go" ./cmd/status
    )
else
    cp "$SRC/bin/analyze-go" "$SRC/bin/status-go" "$DEST/bin/"
fi

chmod +x "$DEST/mole" "$DEST"/bin/*.sh "$DEST/bin/analyze-go" "$DEST/bin/status-go"
version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$DEST/mole" | head -1)
printf 'Mole %s (%s: %s)\n' "${version:-unknown}" "$kind" "$SRC" > "$DEST/ENGINE_SOURCE"
echo "Vendored Mole ${version:-unknown} from a $kind into $DEST"
