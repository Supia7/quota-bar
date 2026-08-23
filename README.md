# QuotaBar

**A native macOS menu-bar monitor for Claude and Codex OAuth subscription usage.**

Compare multiple accounts by account or by limit type, while keeping aliases and email visibility under your control.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

<p>
  <img src="docs/images/quotabar-logo.png" width="96" alt="QuotaBar mascot logo">
</p>

> **Status:** Early public release. Claude and Codex usage endpoints are internal endpoints used by their coding clients rather than stable public billing APIs, so provider changes are handled as explicit errors instead of guesses.

## Screenshots

> These screenshots are generated from the explicit `QuotaBarPreview` fixture with no connected credentials. A fresh installed app shows an empty state, never these example accounts.

<table>
  <tr>
    <td width="50%"><img src="docs/images/quotabar-accounts.png" alt="Compact Accounts view with one row per Claude or Codex account"></td>
    <td width="50%"><img src="docs/images/quotabar-limit-types.png" alt="Compact limit-types view grouping one-row account summaries by five-hour, weekly, and Fable limits"></td>
  </tr>
  <tr>
    <td align="center"><sub>Compact accounts view</sub></td>
    <td align="center"><sub>Compact limit types view</sub></td>
  </tr>
</table>

## What it shows

### Claude

- Five-hour rolling window
- All-model weekly limit
- Fable/model-scoped weekly limit
- If Fable data is absent, QuotaBar shows `Unavailable` instead of inventing 0% usage

### Codex

- OAuth subscription weekly limit
- Remaining percentage and reset time

### Account management

- No hard account limit
- Stable per-account UUIDs — duplicate emails remain separate accounts
- Editable local aliases
- Show or hide the provider email per account
- `Accounts` and `Limit types` layouts
- Compact one-row account summaries with expandable quota details
- The selected layout is persisted locally

## Installation

### For users — DMG recommended

1. Download `QuotaBar-macos-arm64.dmg` from [Releases](https://github.com/Supia7/quota-bar/releases/latest).
2. Open the DMG and drag `QuotaBar.app` to `Applications`.
3. On first launch, if macOS shows a warning, right-click the app and choose **Open**.

Current published releases are Developer ID signed and notarized. Local source builds remain ad-hoc signed and may require a manual confirmation from macOS.

### Terminal — install the latest release

After cloning the repository, run this one command. It downloads the release for the current Mac architecture, verifies the checksum, and installs it under `~/Applications`.

```bash
./Scripts/install-release.sh
```

### Developers — build and install from source

```bash
./Scripts/install.sh
```

This builds the release binary, creates the `.app` bundle, applies an ad-hoc signature, copies it to `~/Applications/QuotaBar.app`, and launches it.

### Updates

QuotaBar checks GitHub Releases when it launches and every six hours. Starting with v0.1.8, Sparkle also verifies the signed HTTPS appcast and update archive before offering an update. Updates still require user approval; QuotaBar never performs a silent executable replacement.

If QuotaBar is opened directly from a DMG, Downloads, or another temporary/read-only location, it now stops before Sparkle and offers to copy itself to `~/Applications`. Sparkle can only replace an installed writable app bundle, so this avoids the macOS “can’t be updated because it was opened from a read-only or temporary location” dialog.

v0.1.7 predates Sparkle, so users on v0.1.7 must install v0.1.8 once from the DMG. v0.1.9 added in-app OAuth sign-in; v0.1.10 added the install-location guard and app icon; v0.1.12 adds explicit light/dark card contrast and refreshed compact UI screenshots.

### Requirements

- macOS 26+
- Swift 6.2+
- Browser OAuth sign-in for Claude and Codex

### Build and run

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBar
```

`QuotaBarPreview` displays the same Monitor UI in a regular window for development and visual QA.

### Connect an account

Open Settings and choose `Sign in with Claude` or `Sign in with Codex` to start a provider OAuth login in your browser. After approval, paste the complete callback URL, or the one-time authorization code, back into QuotaBar. Do not paste an access or refresh token. QuotaBar exchanges the code, verifies one real quota response, and only then stores the resulting access/refresh tokens in the macOS Keychain.

## Security boundary

- New OAuth tokens are stored in the macOS Keychain, not `accounts.json`
- Account registry stores only provider, alias, email, Keychain source metadata, and deduplication identity
- App-owned Keychain credentials refresh through the provider token endpoint
- Existing CLI credential JSON files are not imported
- OAuth only — API-key billing data is not treated as subscription quota
- Claude and Codex use fixed HTTPS authorization/token/usage endpoint policies
- HTTP redirects are rejected
- No Claude Web cookie scraping
- No external CLI execution
- No telemetry or analytics
- Refreshes automatically every five minutes
- Manual Refresh requests an immediate snapshot
- Failed refreshes keep the last known screen visible
- Expired or revoked tokens produce an explicit re-authentication state

> The Claude OAuth usage endpoint and Codex subscription usage endpoint are not public stable APIs. If their schema or rate-limit policy changes, QuotaBar reports an explicit error rather than showing an estimate.

## Local data

| Location | Contents |
| --- | --- |
| `~/Library/Application Support/QuotaBar/accounts.json` | provider, alias, email, Keychain source metadata, deduplication identity |
| macOS Keychain (`com.supia.quotabar.oauth`) | access/refresh tokens for in-app OAuth accounts |
| `~/Library/Application Support/QuotaBar/display-preferences.json` | per-account alias and email display settings |

OAuth access and refresh tokens are not written to these files.

## Developer guide

```text
Sources/QuotaBarCore/       domain models, decoders, credential boundary, provider client
Sources/QuotaBarUI/         menu-bar UI, localization resources, compact layouts, polling, account editor
Sources/QuotaBar/            menu-bar app entry point
Sources/QuotaBarPreview/     regular-window Preview entry point
Sources/QuotaBarChecks/      framework-free self-check
```

Verification:

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
git diff --check
```

The current Command Line Tools environment does not expose XCTest/Testing, so the repository uses a framework-free self-check executable.

## Roadmap

- Native callback handling instead of manual callback paste where provider policy permits
- Automatic email lookup through Claude/Codex profile endpoints
- Per-account stale and re-authentication cards
- Broader provider token-rotation and revocation tests
- Full Xcode test target and continued signed/notarized release hardening

## License

QuotaBar is released under the [MIT License](LICENSE). Commercial use, modification, redistribution, and forks are allowed; retain the copyright and license notice.

## Repository

- GitHub: <https://github.com/Supia7/quota-bar>
- Plan: [`docs/2026-08-21-multi-account-oauth-plan.md`](docs/2026-08-21-multi-account-oauth-plan.md)
- Requirements: [`docs/2026-08-21-multi-account-oauth-requirements.md`](docs/2026-08-21-multi-account-oauth-requirements.md)
