#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ARM64_APP="${ARM64_APP:?ARM64_APP is required}"
X86_64_APP="${X86_64_APP:?X86_64_APP is required}"
VERSION="${VERSION:?VERSION is required}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist-universal}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:?SIGN_IDENTITY is required}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}"

for app in "$ARM64_APP" "$X86_64_APP"; do
  if [[ ! -d "$app" ]]; then
    printf 'App bundle not found: %s\n' "$app" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"
APP_DIR="$OUTPUT_DIR/QuotaBar.app"
ZIP_PATH="$OUTPUT_DIR/QuotaBar-macos-universal.zip"
DMG_PATH="$OUTPUT_DIR/QuotaBar-macos-universal.dmg"
CHECKSUM_PATH="$OUTPUT_DIR/SHA256SUMS-universal"
rm -rf "$APP_DIR" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"

ditto "$ARM64_APP" "$APP_DIR"
lipo -create \
  "$ARM64_APP/Contents/MacOS/QuotaBar" \
  "$X86_64_APP/Contents/MacOS/QuotaBar" \
  -output "$APP_DIR/Contents/MacOS/QuotaBar"
chmod 755 "$APP_DIR/Contents/MacOS/QuotaBar"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

lipo -info "$APP_DIR/Contents/MacOS/QuotaBar" | grep -q 'arm64' || {
  printf 'Universal executable is missing arm64.\n' >&2
  exit 1
}
lipo -info "$APP_DIR/Contents/MacOS/QuotaBar" | grep -q 'x86_64' || {
  printf 'Universal executable is missing x86_64.\n' >&2
  exit 1
}

SPARKLE_BINARY="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/Current/Sparkle"
lipo -info "$SPARKLE_BINARY" | grep -q 'arm64' || {
  printf 'Sparkle framework is missing arm64.\n' >&2
  exit 1
}
lipo -info "$SPARKLE_BINARY" | grep -q 'x86_64' || {
  printf 'Sparkle framework is missing x86_64.\n' >&2
  exit 1
}

codesign --force --deep --timestamp --options runtime \
  --sign "$SIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
codesign --force --timestamp --options runtime \
  --sign "$SIGN_IDENTITY" "$APP_DIR/Contents/MacOS/QuotaBar"
codesign --force --timestamp --options runtime \
  --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

actual_team_id="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ "$actual_team_id" != "$APPLE_TEAM_ID" ]]; then
  printf 'TeamIdentifier mismatch: expected %s, got %s\n' "$APPLE_TEAM_ID" "$actual_team_id" >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait
xcrun stapler staple "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

hdiutil create \
  -volname "QuotaBar" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait
xcrun stapler staple "$DMG_PATH"

spctl --assess --type execute --verbose=2 "$APP_DIR"
xcrun stapler validate "$APP_DIR"
xcrun stapler validate "$DMG_PATH"
shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUM_PATH"

printf 'APP=%s\nZIP=%s\nDMG=%s\nCHECKSUMS=%s\n' \
  "$APP_DIR" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
