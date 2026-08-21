#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.8}"
ARCH="${ARCH:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist}"
BUILD_BIN="${BUILD_BIN:-}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# Optional Developer ID signing / notarization.
# When SIGN_IDENTITY is empty the script falls back to an ad-hoc signature,
# which keeps local development builds working without any Apple credentials.
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

case "$ARCH" in
  arm64|x86_64) ;;
  *)
    printf 'Unsupported architecture: %s\n' "$ARCH" >&2
    exit 2
    ;;
esac

if [[ -z "$BUILD_BIN" ]]; then
  swift_args=(build -c release --product QuotaBar --arch "$ARCH")
  (
    cd "$ROOT_DIR"
    swift "${swift_args[@]}"
    BUILD_BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)/QuotaBar"
    printf '%s\n' "$BUILD_BIN" > "$ROOT_DIR/.quotabar-build-bin"
  )
  BUILD_BIN="$(<"$ROOT_DIR/.quotabar-build-bin")"
  rm -f "$ROOT_DIR/.quotabar-build-bin"
fi

if [[ ! -x "$BUILD_BIN" ]]; then
  printf 'QuotaBar binary not found or not executable: %s\n' "$BUILD_BIN" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
APP_DIR="$OUTPUT_DIR/QuotaBar.app"
ZIP_PATH="$OUTPUT_DIR/QuotaBar-macos-${ARCH}.zip"
DMG_PATH="$OUTPUT_DIR/QuotaBar-macos-${ARCH}.dmg"
CHECKSUM_PATH="$OUTPUT_DIR/SHA256SUMS-${ARCH}"

rm -rf "$APP_DIR" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/QuotaBar"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/QuotaBar"

BUILD_BIN_DIR="$(dirname "$BUILD_BIN")"
SPARKLE_FRAMEWORK="$BUILD_BIN_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  printf 'Sparkle.framework not found next to build binary: %s\n' "$SPARKLE_FRAMEWORK" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/QuotaBar"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

notarization_enabled() {
  [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" ]]
}

notarize() {
  local target="$1"
  printf 'Submitting %s for notarization...\n' "$(basename "$target")"
  xcrun notarytool submit "$target" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
}

make_zip() {
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
}

make_dmg() {
  rm -f "$DMG_PATH"
  hdiutil create \
    -volname "QuotaBar" \
    -srcfolder "$APP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
}

if [[ -n "$SIGN_IDENTITY" ]]; then
  # Sparkle contains nested helper apps and must be signed before the host app.
  codesign --force --deep --timestamp --options runtime \
    --sign "$SIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
  # Hardened runtime + secure timestamp are both required for notarization.
  codesign --force --timestamp --options runtime \
    --sign "$SIGN_IDENTITY" "$APP_DIR/Contents/MacOS/QuotaBar"
  codesign --force --timestamp --options runtime \
    --sign "$SIGN_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  if [[ -z "$APPLE_TEAM_ID" ]]; then
    printf 'APPLE_TEAM_ID is required for signed builds.\n' >&2
    exit 1
  fi
  actual_team_id="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  if [[ "$actual_team_id" != "$APPLE_TEAM_ID" ]]; then
    printf 'TeamIdentifier mismatch: expected %s, got %s\n' "$APPLE_TEAM_ID" "$actual_team_id" >&2
    exit 1
  fi
else
  # Ad-hoc signing makes the local bundle structurally valid. Public releases
  # still need a Developer ID signature and Apple notarization for Gatekeeper.
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

make_zip

if [[ -n "$SIGN_IDENTITY" ]] && notarization_enabled; then
  notarize "$ZIP_PATH"
  xcrun stapler staple "$APP_DIR"
  # Repackage so the shipped archive contains the stapled ticket.
  make_zip
  make_dmg
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  notarize "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type execute --verbose=2 "$APP_DIR"
else
  make_dmg
fi

shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUM_PATH"

printf 'APP=%s\nZIP=%s\nDMG=%s\nCHECKSUMS=%s\n' \
  "$APP_DIR" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
