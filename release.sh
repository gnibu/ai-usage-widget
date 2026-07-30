#!/bin/sh
# Build a signed, notarized, universal Tokens on Track.dmg for direct
# distribution outside the Mac App Store.
#
# build.sh is the development loop: host architecture, ad-hoc signature, no
# network. This is the shipping loop, and it is slower for good reasons — it
# compiles twice, waits on Apple's notary service, and produces something a
# stranger's Mac will open without a Gatekeeper warning.
#
# Command Line Tools are enough. There is no Xcode project and none is needed:
# the two-triple build below is what `--arch` would have routed through xcbuild
# for, and notarytool ships with the CLT.
#
# One-time setup:
#
#   1. Join the Apple Developer Program and create a "Developer ID Application"
#      certificate, then install it in your login keychain. Confirm with:
#          security find-identity -v -p codesigning
#
#   2. Store notary credentials once, so this script never sees a password.
#      Use an app-specific password from appleid.apple.com, not your Apple ID
#      password:
#          xcrun notarytool store-credentials tokens-on-track-notary \
#              --apple-id you@example.com --team-id TEAMID
#
#   3. Export the signing identity, copied verbatim from find-identity:
#          export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#
# Then:
#
#   ./release.sh            build dist/Tokens on Track-<version>.dmg
#
# Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist
# before each release; both are read from there rather than passed in, so the
# plist stays the single source of truth.
set -eu

cd "$(dirname "$0")"

APP_NAME="Tokens on Track"
DIST_DIR="dist"
BUNDLE="${DIST_DIR}/${APP_NAME}.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-tokens-on-track-notary}"

# Must match Package.swift's platforms declaration.
DEPLOYMENT_TARGET="14.0"
TRIPLES="arm64-apple-macosx${DEPLOYMENT_TARGET} x86_64-apple-macosx${DEPLOYMENT_TARGET}"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "error: $*" >&2; exit 1; }

# --------------------------------------------------------------------- #
# Preflight
#
# Every check here maps to a failure that would otherwise surface minutes
# later, after a full two-architecture compile or a round trip to Apple.
# --------------------------------------------------------------------- #
echo "==> preflight"

[ -n "${DEVELOPER_ID:-}" ] || fail 'DEVELOPER_ID is unset. See the header of this script.'

security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID" \
    || fail "no codesigning identity matching \"${DEVELOPER_ID}\" in the keychain.
       Run: security find-identity -v -p codesigning"

case "$DEVELOPER_ID" in
    "Developer ID Application:"*) ;;
    *) fail 'DEVELOPER_ID must be a "Developer ID Application: ..." identity.
       An Apple Development or 3rd Party Mac Developer certificate will sign
       fine and then fail notarization.' ;;
esac

xcrun --find notarytool >/dev/null 2>&1 || fail 'notarytool not found. Install the Command Line Tools.'

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notary profile \"${NOTARY_PROFILE}\" is missing or invalid.
       Run: xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id ... --team-id ..."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "    ${APP_NAME} ${VERSION} (${BUILD_NUMBER})"
echo "    signing as ${DEVELOPER_ID}"

WORK="$(mktemp -d)"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# --------------------------------------------------------------------- #
# Compile both architectures and fuse them
#
# swift build cannot emit a universal binary directly without xcbuild, so it
# runs once per triple and lipo stitches the results. --show-bin-path is asked
# per triple because each one lands in its own .build subdirectory.
# --------------------------------------------------------------------- #
echo "==> compiling universal binary"

SLICES=""
for triple in $TRIPLES; do
    echo "    ${triple}"
    swift build -c release --triple "$triple"
    SLICES="${SLICES} $(swift build -c release --triple "$triple" --show-bin-path)/AIUsage"
done

# shellcheck disable=SC2086 # SLICES is a deliberate list of paths.
lipo -create -output "${WORK}/AIUsage" $SLICES
lipo -info "${WORK}/AIUsage" | sed 's/^/    /'

# --------------------------------------------------------------------- #
# Assemble the bundle
# --------------------------------------------------------------------- #
echo "==> assembling ${BUNDLE}"

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "${WORK}/AIUsage" "$BUNDLE/Contents/MacOS/AIUsage"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp -R Resources/Icons "$BUNDLE/Contents/Resources/Icons"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# --------------------------------------------------------------------- #
# Sign
#
# --options runtime opts into the hardened runtime, which notarization
# requires. No entitlements file is needed: the app reads the Claude keychain
# item by spawning /usr/bin/security, and the hardened runtime only restricts
# what loads *into* this process, not what it exec's. ~/.codex/auth.json is a
# plain read from an unsandboxed process. Adding entitlements here would be
# cargo cult.
#
# --timestamp is mandatory, which is why build.sh's --timestamp=none cannot be
# reused: a signature without a trusted timestamp is rejected by the notary.
# --------------------------------------------------------------------- #
echo "==> signing app"

codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$BUNDLE"
codesign --verify --strict --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/    /'

# --------------------------------------------------------------------- #
# Notarize the app
#
# Two submissions happen in this script: the app, then the finished disk image.
# Stapling both means the app still validates offline if a user drags it out of
# the .dmg, and the .dmg itself opens cleanly on a machine that has never seen
# it. One submission would leave one of those two paths depending on a live
# lookup against Apple.
# --------------------------------------------------------------------- #
notarize() {
    target="$1"
    label="$2"
    result="${WORK}/notary-${label}.json"

    echo "==> notarizing ${label} (this waits on Apple, typically 1-5 min)"

    # --wait can still exit 0 on a rejected submission, so the status is read
    # back explicitly rather than trusted to the exit code.
    xcrun notarytool submit "$target" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$result"

    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    submission="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo '')"

    if [ "$status" != "Accepted" ]; then
        echo "    status: ${status}" >&2
        [ -n "$submission" ] && xcrun notarytool log "$submission" \
            --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fail "notarization of ${label} failed"
    fi
    echo "    accepted (${submission})"
}

ditto -c -k --keepParent "$BUNDLE" "${WORK}/app.zip"
notarize "${WORK}/app.zip" "app"

echo "==> stapling app"
xcrun stapler staple "$BUNDLE" | sed 's/^/    /'

# --------------------------------------------------------------------- #
# Disk image
#
# The /Applications symlink is what makes the window a drag-to-install target
# rather than something the user has to think about.
# --------------------------------------------------------------------- #
echo "==> building ${DMG}"

DMG_ROOT="${WORK}/dmg"
mkdir -p "$DMG_ROOT"
cp -R "$BUNDLE" "$DMG_ROOT/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ -format UDZO -ov \
    "$DMG" | sed 's/^/    /'

echo "==> signing dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

notarize "$DMG" "dmg"

echo "==> stapling dmg"
xcrun stapler staple "$DMG" | sed 's/^/    /'

# --------------------------------------------------------------------- #
# Verify the way Gatekeeper will
#
# codesign --verify only proves the signature is intact. spctl is what actually
# answers "will this open on a Mac that has never seen it", so it runs last and
# against the stapled artifacts.
# --------------------------------------------------------------------- #
echo "==> verifying"

spctl --assess --type exec --verbose=4 "$BUNDLE" 2>&1 | sed 's/^/    app: /'
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1 | sed 's/^/    dmg: /'
xcrun stapler validate "$BUNDLE" | sed 's/^/    /'
xcrun stapler validate "$DMG" | sed 's/^/    /'

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo
echo "    ${DMG} (${SIZE})"
echo "    ready to upload."
