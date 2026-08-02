#!/bin/zsh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
INFO_PLIST="$ROOT/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
SIGNING_IDENTITY="${DEX_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${DEX_NOTARY_PROFILE:-DEX_NOTARY}"
DIST_DIR="$ROOT/dist"
DMG_ROOT="$ROOT/build/dmg.noindex"
APP="$ROOT/build/staging.noindex/Dex.app"
DMG="$DIST_DIR/Dex-$VERSION.dmg"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    SIGNING_IDENTITY="$(awk -F\" '/"Developer ID Application:/ { print $2; exit }' <<< "$AVAILABLE_IDENTITIES")"
fi

if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
    echo "A Developer ID Application certificate is required to publish DEX." >&2
    echo "Install one in Keychain or set DEX_SIGNING_IDENTITY explicitly." >&2
    exit 1
fi

if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "Refusing to publish with a non-Developer ID Application identity." >&2
    exit 1
fi

DEX_SIGNING_IDENTITY="$SIGNING_IDENTITY" "$ROOT/scripts/build-app.sh" release
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT" "$DIST_DIR"
ditto "$APP" "$DMG_ROOT/Dex.app"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "DEX" \
    -srcfolder "$DMG_ROOT" \
    -format UDZO \
    -ov \
    "$DMG"

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

rm -rf "$DMG_ROOT" "$ROOT/build/staging.noindex"
echo "Release ready: $DMG"
