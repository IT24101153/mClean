#!/bin/sh
# Xcode build phase: copies the vendored Mole engine and mClean's helper
# scripts into the app's Resources, then signs the Go helpers with the app's identity.

set -e

ENGINE="${SRCROOT}/Engine"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [ ! -x "${ENGINE}/Mole/mole" ]; then
    echo "error: Mole engine is missing. Run Scripts/vendor-mole.sh first."
    exit 1
fi

mkdir -p "${DEST}"
rsync -a --delete "${ENGINE}/Mole/" "${DEST}/Mole/"
install -m 755 "${ENGINE}/askpass.sh" "${DEST}/askpass.sh"
install -m 755 "${ENGINE}/mclean-protect.sh" "${DEST}/mclean-protect.sh"
install -m 755 "${ENGINE}/mclean-admin-trash.sh" "${DEST}/mclean-admin-trash.sh"

for helper in "${DEST}/Mole/bin/analyze-go" "${DEST}/Mole/bin/status-go"; do
    if [ -f "${helper}" ]; then
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${helper}"
    fi
done
