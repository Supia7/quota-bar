#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/Sources/QuotaBar/QuotaBarApp.swift"

if grep -q 'MenuBarExtra' "$APP_SOURCE"; then
  printf 'legacy SwiftUI MenuBarExtra host is still present\n' >&2
  exit 1
fi

grep -q 'NSStatusItem' "$APP_SOURCE"
grep -q 'NSPopover' "$APP_SOURCE"
grep -q 'applicationDidFinishLaunching' "$APP_SOURCE"
printf 'QuotaBar menu-bar host check passed\n'
