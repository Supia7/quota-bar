#!/usr/bin/env bash
set -euo pipefail

ARCHIVES_DIR="${1:?usage: generate-appcast.sh ARCHIVES_DIR DOWNLOAD_URL_PREFIX}"
DOWNLOAD_URL_PREFIX="${2:?usage: generate-appcast.sh ARCHIVES_DIR DOWNLOAD_URL_PREFIX}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:?SPARKLE_GENERATE_APPCAST is required}"

if [[ ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
  printf 'generate_appcast tool is not executable: %s\n' "$SPARKLE_GENERATE_APPCAST" >&2
  exit 1
fi
if [[ ! -d "$ARCHIVES_DIR" ]]; then
  printf 'Archives directory not found: %s\n' "$ARCHIVES_DIR" >&2
  exit 1
fi
if [[ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
  printf 'SPARKLE_ED25519_PRIVATE_KEY is required.\n' >&2
  exit 1
fi

printf '%s\n' "$SPARKLE_ED25519_PRIVATE_KEY" | \
  "$SPARKLE_GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --disable-signing-warning \
    "$ARCHIVES_DIR"

APPCAST_PATH="$ARCHIVES_DIR/appcast.xml"
test -s "$APPCAST_PATH"
if ! grep -q 'edSignature' "$APPCAST_PATH" || ! grep -q 'sparkle-signatures:' "$APPCAST_PATH"; then
  printf 'Generated appcast is missing required EdDSA signatures.\n' >&2
  exit 1
fi
printf 'APPCAST=%s\n' "$APPCAST_PATH"
