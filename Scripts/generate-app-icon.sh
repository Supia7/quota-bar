#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SVG_PATH="${ROOT_DIR}/Resources/QuotaBarLogo.svg"
ICONSET_DIR="${ROOT_DIR}/Resources/QuotaBar.iconset"
ICNS_PATH="${ROOT_DIR}/Resources/QuotaBar.icns"
PREVIEW_PATH="${ROOT_DIR}/docs/images/quotabar-logo.png"

if [[ ! -f "$SVG_PATH" ]]; then
  printf 'Logo source not found: %s\n' "$SVG_PATH" >&2
  exit 1
fi
if ! command -v magick >/dev/null 2>&1; then
  printf 'ImageMagick (magick) is required to render the icon.\n' >&2
  exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
  printf 'iconutil is required to build the macOS ICNS asset.\n' >&2
  exit 1
fi

rm -rf "$ICONSET_DIR" "$ICNS_PATH"
mkdir -p "$ICONSET_DIR" "$(dirname -- "$PREVIEW_PATH")"

render() {
  local pixels="$1"
  local output="$2"
  magick -background none "$SVG_PATH" \
    -resize "${pixels}x${pixels}" \
    -depth 8 \
    "PNG32:${ICONSET_DIR}/${output}.png"
}

render 16 icon_16x16
render 32 icon_16x16@2x
render 32 icon_32x32
render 64 icon_32x32@2x
render 128 icon_128x128
render 256 icon_128x128@2x
render 256 icon_256x256
render 512 icon_256x256@2x
render 512 icon_512x512
render 1024 icon_512x512@2x

iconutil --convert icns --output "$ICNS_PATH" "$ICONSET_DIR"
magick -background none "$SVG_PATH" -resize 512x512 -depth 8 "PNG32:${PREVIEW_PATH}"

printf 'ICNS=%s\nPREVIEW=%s\n' "$ICNS_PATH" "$PREVIEW_PATH"
