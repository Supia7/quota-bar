#!/usr/bin/env python3
"""Regression check for the AppKit popover's compact SwiftUI layout."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
app_source = (root / "Sources/QuotaBar/QuotaBarApp.swift").read_text()
ui_source = (root / "Sources/QuotaBarUI/QuotaBarUI.swift").read_text()
preview_source = (root / "Sources/QuotaBarPreview/PreviewApp.swift").read_text()

popover_match = re.search(
    r"popover\.contentSize\s*=\s*NSSize\(width:\s*([0-9.]+),\s*height:\s*([0-9.]+)\)",
    app_source,
)
if not popover_match:
    raise SystemExit("popover content size must remain explicit and inspectable")
popover_width = float(popover_match.group(1))
popover_height = float(popover_match.group(2))
if popover_width > 460:
    raise SystemExit(
        f"popover width {popover_width:g} is too wide for the compact monitor"
    )
if popover_height < 320:
    raise SystemExit(
        f"popover height {popover_height:g} is too small for the monitor header, empty state, and footer"
    )

empty_match = re.search(
    r"guard\s+!model\.groups\.isEmpty\s+else\s*\{\s*return\s+([0-9.]+)",
    ui_source,
)
if not empty_match:
    raise SystemExit("empty monitor height contract is missing")
empty_height = float(empty_match.group(1))
if empty_height < 300:
    raise SystemExit(
        f"empty monitor height {empty_height:g} is too small to keep the header and footer visible"
    )

frame_match = re.search(
    r"\.frame\(\s*\n\s*minWidth:\s*([0-9.]+),\s*\n\s*idealWidth:\s*([0-9.]+),\s*\n\s*maxWidth:\s*([0-9.]+),",
    ui_source,
)
if not frame_match:
    raise SystemExit("compact SwiftUI width contract is missing")
frame_widths = [float(value) for value in frame_match.groups()]
if frame_widths[1] > 460 or frame_widths[2] > 500:
    raise SystemExit(
        "SwiftUI monitor frame must keep its ideal width <= 460 and max width <= 500"
    )

if "private var header: some View" not in ui_source:
    raise SystemExit("compact provider monitor header is missing")
if "private var toolbar: some View" in ui_source:
    raise SystemExit("legacy bottom action toolbar must be removed")
if "private var viewToolbar: some View" not in ui_source:
    raise SystemExit("compact bottom view toolbar is missing")
if "private struct ProviderQuotaBlock: View" not in ui_source:
    raise SystemExit("provider-first quota block is missing")
if "private struct QuotaProgressBar: View" not in ui_source:
    raise SystemExit("primary quota progress bar is missing")
for control_key in ("monitor.title", "update.check", "settings.title", "monitor.refresh"):
    if control_key not in ui_source:
        raise SystemExit(f"compact header is missing {control_key}")
if ".system(size: 36" not in ui_source:
    raise SystemExit("primary quota percentage must use a glanceable large value")
if "compactResetText" not in ui_source:
    raise SystemExit("primary quota reset countdown is missing")

preview_match = re.search(
    r"\.defaultSize\(width:\s*([0-9.]+),\s*height:\s*([0-9.]+)\)",
    preview_source,
)
if not preview_match or float(preview_match.group(1)) > 460:
    raise SystemExit("Preview default width must match the compact monitor")

if "hostingController.view.translatesAutoresizingMaskIntoConstraints = false" in app_source:
    raise SystemExit("popover hosting view must not force an unconstrained root layout")

print("QuotaBar popover layout check passed")
