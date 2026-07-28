#!/bin/sh
# Build AI Usage.app from the SwiftPM target. Needs the Command Line Tools
# only — there is no Xcode project to open.
#
#   ./build.sh              build into .build/AI Usage.app
#   ./build.sh --install    also copy it to /Applications and launch it
set -eu

cd "$(dirname "$0")"

APP_NAME="AI Usage"
BUNDLE=".build/${APP_NAME}.app"
INSTALL_DIR="/Applications"

# Built for the host architecture. A universal binary needs `--arch arm64
# --arch x86_64`, which routes through xcbuild and so requires full Xcode.
echo "==> compiling"
swift build -c release
BINARY="$(swift build -c release --show-bin-path)/AIUsage"

echo "==> assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/AIUsage"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Ad-hoc signature. Without one, macOS refuses to hand the app a notification
# token and the login item registration is rejected.
echo "==> signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$BUNDLE"

if [ "${1:-}" = "--install" ]; then
    echo "==> installing to ${INSTALL_DIR}"
    osascript -e 'quit app "AI Usage"' 2>/dev/null || true
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    cp -R "$BUNDLE" "${INSTALL_DIR}/"
    open "${INSTALL_DIR}/${APP_NAME}.app"
    echo "    running — look for the ring in the menu bar"
else
    echo "    built. Install with: $0 --install"
fi
