# QuotaBar

**A compact macOS menu-bar monitor for Claude and Codex OAuth quota.**

See remaining subscription quota across accounts without opening a full dashboard.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

<p align="center">
  <img src="docs/images/quotabar-accounts.png" width="420" alt="Compact QuotaBar monitor view">
</p>

> QuotaBar uses the provider usage endpoints used by Claude Code and Codex. They are not stable public billing APIs, so provider errors are shown explicitly instead of being estimated.

## Highlights

- **At a glance:** remaining percentages and reset times from the menu bar.
- **Multiple accounts:** compare accounts or group them by limit type.
- **Compact by default:** the important numbers stay visible; details expand only when needed.
- **OAuth + Keychain:** browser sign-in, with access and refresh tokens stored in the macOS Keychain.
- **Reset awareness:** detect an unexpected quota recovery, including Codex resets that happen before the displayed renewal date.
- **Local usage:** when local session logs exist, show today's token and session count inside the provider block.
- **Local-first:** no telemetry, analytics, cookie scraping, API-key billing, or external CLI execution.

## What it shows

| Provider | Usage windows |
| --- | --- |
| Claude | 5-hour rolling, all-model weekly, Fable/model-scoped weekly |
| Codex | OAuth subscription weekly quota and reset time |

If a provider does not return a window, QuotaBar shows `Unavailable` rather than inventing a value. If no local session log is available, the local usage line is simply omitted.

## Getting started

### Install the release

1. Download `QuotaBar-macos-arm64.dmg` from [Releases](https://github.com/Supia7/quota-bar/releases/latest).
2. Drag `QuotaBar.app` to `Applications`.
3. Open it and click the menu-bar icon.
4. Open **Settings**, then choose **Sign in with Claude** or **Sign in with Codex**.

Codex normally completes through its localhost callback. Claude accepts the complete callback URL or the one-time authorization code shown after browser approval. Never paste an access or refresh token.

### Install from the terminal

```bash
./Scripts/install-release.sh
```

The script downloads the release for the current architecture, verifies its checksum, installs it under `~/Applications`, and launches it.

## Build from source

Requirements: macOS 26+ and Swift 6.2+.

```bash
./Scripts/install.sh
```

Or run the checks and Preview window directly:

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBarPreview
```

`QuotaBarPreview` uses explicit fixture data for visual QA. A fresh production install shows an empty state until an OAuth account is connected.

## Data and security

- OAuth tokens live in the macOS Keychain under the QuotaBar service.
- `accounts.json` contains account metadata only: provider, alias, email, and Keychain identity.
- Existing CLI credential files are not imported.
- Local usage reads only today's Claude/Codex JSONL session records; message content is not retained or sent anywhere.
- Claude and Codex calls use fixed HTTPS endpoint policies; redirects are rejected.
- Failed refreshes keep the last known screen visible.
- Refresh runs automatically every five minutes, with a manual refresh in the bottom toolbar.

Local metadata is stored under:

```text
~/Library/Application Support/QuotaBar/
```

## Project layout

```text
Sources/QuotaBarCore/    models, OAuth, Keychain, provider decoders
Sources/QuotaBarUI/      compact monitor, Settings, localization
Sources/QuotaBar/        AppKit menu-bar host and popover
Sources/QuotaBarPreview/ fixture-based visual QA window
Sources/QuotaBarChecks/  framework-free self-check executable
```

The local usage summary is an independent Swift implementation inspired by the local analytics direction of [CodeBurn](https://github.com/getagentseal/codeburn). QuotaBar does not bundle or execute CodeBurn's CLI. License and attribution details are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Verification

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
python3 Scripts/check-popover-layout.py
bash Scripts/check-menu-bar-host.sh
git diff --check
```

## Status

QuotaBar is an early public release. Provider endpoint or schema changes may require a follow-up update.

## License

[MIT](LICENSE)

Repository: <https://github.com/Supia7/quota-bar>
