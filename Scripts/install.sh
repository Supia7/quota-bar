#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${1:-${ROOT_DIR}/dist/QuotaBar.app}"
INSTALL_DIR="${QUOTABAR_INSTALL_DIR:-${HOME}/Applications}"
DEST_APP="$INSTALL_DIR/QuotaBar.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  printf 'No app bundle found at %s. Building it first…\n' "$SOURCE_APP"
  "$ROOT_DIR/Scripts/package-app.sh"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  printf 'QuotaBar.app was not created at %s\n' "$SOURCE_APP" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"

printf '\nInstalled QuotaBar to:\n  %s\n' "$DEST_APP"
printf 'This local build is ad-hoc signed. Launching it now.\n'
open "$DEST_APP"
