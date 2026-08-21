# QuotaBar

**A native macOS menu-bar monitor for Claude and Codex OAuth subscription usage.**

Compare multiple accounts by account or by limit type, while keeping aliases and email visibility under your control.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

> **Status:** Early public release. Claude and Codex usage endpoints are internal endpoints used by their coding clients rather than stable public billing APIs, so provider changes are handled as explicit errors instead of guesses.

## Screenshots

> These screenshots use **sample data** with no connected credentials. No real tokens or account data are included.

<table>
  <tr>
    <td width="50%"><img src="docs/images/quotabar-accounts.png" alt="Accounts view showing Claude and Codex accounts"></td>
    <td width="50%"><img src="docs/images/quotabar-limit-types.png" alt="Limit types view grouping five-hour, weekly, and Fable limits"></td>
  </tr>
  <tr>
    <td align="center"><sub>Accounts view</sub></td>
    <td align="center"><sub>Limit types view</sub></td>
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
- The selected layout is persisted locally

## Installation

### For users — DMG recommended

1. Download `QuotaBar-macos-arm64.dmg` from [Releases](https://github.com/Supia7/quota-bar/releases/latest).
2. Open the DMG and drag `QuotaBar.app` to `Applications`.
3. On first launch, if macOS shows a warning, right-click the app and choose **Open**.

Current release artifacts are ad-hoc signed. Until a Developer ID signature and Apple notarization are added, Gatekeeper may ask you to confirm the developer.

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

Because v0.1.7 predates Sparkle, users on v0.1.7 must install v0.1.8 once from the DMG. v0.1.9 adds in-app OAuth sign-in; later versions can use the signed Sparkle update path.

### Requirements

- macOS 26+
- Swift 6.2+
- OAuth credential JSON managed by Claude Code or Codex

### Build and run

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBar
```

`QuotaBarPreview` displays the same Monitor UI in a regular window for development and visual QA.

### Connect an account

Open Settings and choose `Sign in with Claude` or `Sign in with Codex` to start a provider OAuth login in your browser. After approval, paste the callback URL or authorization code back into QuotaBar. QuotaBar exchanges the code, verifies one real quota response, and only then stores the resulting access/refresh tokens in the macOS Keychain.

`Use existing credential file (fallback)` remains available for users who already have a CLI login:

- Claude: `~/.claude/.credentials.json`
- Codex: `~/.codex/auth.json`

Use the JSON picker only when the credential is stored elsewhere.

## Security boundary

- New OAuth tokens are stored in the macOS Keychain, not `accounts.json`
- Account registry stores only provider, alias, email, source metadata, and deduplication identity
- App-owned Keychain credentials refresh through the provider token endpoint
- Existing CLI credential files remain a compatibility fallback
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
| `~/Library/Application Support/QuotaBar/accounts.json` | provider, alias, email, source, credential path when using file fallback, deduplication identity |
| macOS Keychain (`com.supia.quotabar.oauth`) | access/refresh tokens for in-app OAuth accounts |
| `~/Library/Application Support/QuotaBar/display-preferences.json` | per-account alias and email display settings |

OAuth access and refresh tokens are not written to these files.

## Developer guide

```text
Sources/QuotaBarCore/       domain models, decoders, credential boundary, provider client
Sources/QuotaBarUI/         menu-bar UI, two layouts, polling, account editor
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
