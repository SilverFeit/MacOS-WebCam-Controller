#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
VERSION="${1:-1.0}"

"${SCRIPT_DIR}/build_app.sh"

APP_NAME="WebCam Controller"
APP_BUNDLE="${PACKAGE_DIR}/dist/${APP_NAME}.app"
RELEASE_DIR="${PACKAGE_DIR}/dist/release"
DMG_STAGE="/tmp/WebCamControllerDMGStage"

ZIP_NAME="MacOS-WebCam-Controller-${VERSION}.app.zip"
DMG_NAME="MacOS-WebCam-Controller-${VERSION}.dmg"

rm -rf "${RELEASE_DIR}" "${DMG_STAGE}"
mkdir -p "${RELEASE_DIR}" "${DMG_STAGE}"

echo "[5/6] Creating '${ZIP_NAME}'..."
ditto -c -k --norsrc --noextattr --keepParent "${APP_BUNDLE}" "${RELEASE_DIR}/${ZIP_NAME}"

echo "[6/6] Assembling '${DMG_NAME}' with Applications shortcut & volume icon..."
ditto --norsrc --noextattr "${APP_BUNDLE}" "${DMG_STAGE}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGE}/Applications"
cp "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" "${DMG_STAGE}/.VolumeIcon.icns"

if diskutil image create --help >/dev/null 2>&1; then
    diskutil image create from \
        --format UDZO \
        --volumeName "MacOS WebCam Controller" \
        "${DMG_STAGE}" \
        "${RELEASE_DIR}/${DMG_NAME}"
else
    hdiutil create \
        -volname "MacOS WebCam Controller" \
        -srcfolder "${DMG_STAGE}" \
        -ov \
        -format UDZO \
        "${RELEASE_DIR}/${DMG_NAME}"
fi

rm -rf "${DMG_STAGE}"

(
    cd "${RELEASE_DIR}"
    shasum -a 256 "${DMG_NAME}" "${ZIP_NAME}" > SHA256SUMS.txt
)

echo "Release artifacts ready in ${RELEASE_DIR}:"
cat "${RELEASE_DIR}/SHA256SUMS.txt"
