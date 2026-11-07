#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
VERSION="$(tr -d '[:space:]' < "${PACKAGE_DIR}/VERSION" 2>/dev/null || echo "1.2.0")"
APP_NAME="WebCam Controller"
STAGE_BUNDLE="/tmp/${APP_NAME}.app"
APP_BUNDLE="${PACKAGE_DIR}/dist/${APP_NAME}.app"

export CLANG_MODULE_CACHE_PATH="/tmp/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/swiftpm-module-cache"
SCRATCH_DIR="${SWIFT_SCRATCH_DIR:-/tmp/webcamcontroller-spm-build}"

echo "[1/4] Building Release binaries (WebcamControllerApp + webcamctl v${VERSION}) via SwiftPM..."
swift build -c release --arch arm64 --product WebcamControllerApp --package-path "${PACKAGE_DIR}" --scratch-path "${SCRATCH_DIR}" --disable-sandbox
swift build -c release --arch arm64 --product webcamctl --package-path "${PACKAGE_DIR}" --scratch-path "${SCRATCH_DIR}" --disable-sandbox

APP_BIN_PATH="${SCRATCH_DIR}/release/WebcamControllerApp"
CLI_BIN_PATH="${SCRATCH_DIR}/release/webcamctl"

echo "[2/4] Generating high-DPI macOS AppIcon.icns..."
ICONSET_DIR="/tmp/WebcamControllerIcon.iconset"
rm -rf "${ICONSET_DIR}"
swift -module-cache-path "${CLANG_MODULE_CACHE_PATH}" "${SCRIPT_DIR}/generate_icns.swift" "${ICONSET_DIR}"

echo "[3/4] Assembling '${APP_NAME}.app' bundle (v${VERSION}) with bundled 'webcamctl' CLI..."
rm -rf "${STAGE_BUNDLE}"
mkdir -p "${STAGE_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGE_BUNDLE}/Contents/Resources"

cp "${APP_BIN_PATH}" "${STAGE_BUNDLE}/Contents/MacOS/WebcamControllerApp"
cp "${CLI_BIN_PATH}" "${STAGE_BUNDLE}/Contents/MacOS/webcamctl"
chmod +x "${STAGE_BUNDLE}/Contents/MacOS/WebcamControllerApp"
chmod +x "${STAGE_BUNDLE}/Contents/MacOS/webcamctl"
iconutil -c icns "${ICONSET_DIR}" -o "${STAGE_BUNDLE}/Contents/Resources/AppIcon.icns"

cat << EOF > "${STAGE_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>WebCam Controller</string>
    <key>CFBundleExecutable</key>
    <string>WebcamControllerApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.webcamcontroller.uvc</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WebCam Controller</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.webcamcontroller.uvc</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>webcamcontroller</string>
            </array>
        </dict>
    </array>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Released under the MIT License. Copyright © 2026 SilverFeit.</string>
</dict>
</plist>
EOF

plutil -lint "${STAGE_BUNDLE}/Contents/Info.plist"

echo "[4/4] Stripping resource forks, signing & verifying '${APP_NAME}.app' + 'webcamctl'..."
xattr -cr "${STAGE_BUNDLE}"
codesign --force --sign - "${STAGE_BUNDLE}/Contents/MacOS/webcamctl"
codesign --force --deep --sign - "${STAGE_BUNDLE}"
codesign --verify --deep --strict "${STAGE_BUNDLE}"

mkdir -p "${PACKAGE_DIR}/dist"
rm -rf "${APP_BUNDLE}"
ditto --norsrc --noextattr "${STAGE_BUNDLE}" "${APP_BUNDLE}"
cp "${STAGE_BUNDLE}/Contents/MacOS/webcamctl" "${PACKAGE_DIR}/dist/webcamctl"
chmod +x "${PACKAGE_DIR}/dist/webcamctl"

echo "Successfully built and verified: ${APP_BUNDLE} (v${VERSION}) + webcamctl"
