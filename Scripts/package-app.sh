#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.2}"
ARCH="${ARCH:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist}"
BUILD_BIN="${BUILD_BIN:-}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

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
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/QuotaBar"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/QuotaBar"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing makes the local bundle structurally valid. Public releases
# still need a Developer ID signature and Apple notarization for Gatekeeper.
codesign --force --deep --sign - "$APP_DIR" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
hdiutil create \
  -volname "QuotaBar" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUM_PATH"

printf 'APP=%s\nZIP=%s\nDMG=%s\nCHECKSUMS=%s\n' \
  "$APP_DIR" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
