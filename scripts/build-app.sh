#!/bin/zsh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
SIGNING_IDENTITY="${DEX_SIGNING_IDENTITY:-}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 2
fi

swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --product Dex
BIN_DIR="$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --show-bin-path)"

APP="$ROOT/build/staging.noindex/Dex.app"
LEGACY_APP="$ROOT/build/Dex.app"
rm -rf "$APP" "$LEGACY_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

ditto "$BIN_DIR/Dex" "$APP/Contents/MacOS/Dex"
ditto "$ROOT/Resources/Dex.icns" "$APP/Contents/Resources/Dex.icns"
ditto "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    SIGNING_IDENTITY="$(awk '/"Developer ID Application:/ { print $2; exit }' <<< "$AVAILABLE_IDENTITIES")"
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="$(awk '/"Apple Development:/ { print $2; exit }' <<< "$AVAILABLE_IDENTITIES")"
    fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="-"
    echo "Warning: no persistent signing identity found; macOS may require Accessibility access again after rebuilding." >&2
fi

codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP"

echo "Signed Dex with: $SIGNING_IDENTITY"
echo "$APP"
