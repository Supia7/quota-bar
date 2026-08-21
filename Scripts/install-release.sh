#!/usr/bin/env bash
set -euo pipefail

OWNER_REPO="Supia7/quota-bar"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *)
    printf 'Unsupported architecture: %s\n' "$ARCH" >&2
    exit 2
    ;;
esac

BASE_URL="https://github.com/${OWNER_REPO}/releases/latest/download"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
ARCHIVE="QuotaBar-macos-${ARCH}.zip"
CHECKSUMS="SHA256SUMS"

curl --fail --location --silent --show-error \
  "$BASE_URL/$ARCHIVE" \
  --output "$TEMP_DIR/$ARCHIVE"
curl --fail --location --silent --show-error \
  "$BASE_URL/$CHECKSUMS" \
  --output "$TEMP_DIR/$CHECKSUMS"

EXPECTED="$(awk -v file="$ARCHIVE" '$2 == file { print $1; exit }' "$TEMP_DIR/$CHECKSUMS")"
ACTUAL="$(shasum -a 256 "$TEMP_DIR/$ARCHIVE" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  printf 'Checksum verification failed for %s\n' "$ARCHIVE" >&2
  exit 1
fi

mkdir -p "$TEMP_DIR/extracted"
ditto -x -k "$TEMP_DIR/$ARCHIVE" "$TEMP_DIR/extracted"
SOURCE_APP="$TEMP_DIR/QuotaBar.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  printf 'Release archive did not contain QuotaBar.app\n' >&2
  exit 1
fi

INSTALL_DIR="${QUOTABAR_INSTALL_DIR:-${HOME}/Applications}"
DEST_APP="$INSTALL_DIR/QuotaBar.app"
mkdir -p "$INSTALL_DIR"
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"

printf 'Installed verified release to:\n  %s\n' "$DEST_APP"
printf 'If macOS asks for confirmation, review the publisher before opening.\n'
open "$DEST_APP"
