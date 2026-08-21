# QuotaBar

QuotaBar is an original macOS menu-bar quota monitor for Claude and Codex OAuth subscriptions.

## Current implementation

- SwiftUI `MenuBarExtra` monitor surface
- Claude OAuth usage windows:
  - 5-hour rolling window
  - all-model weekly window
  - Fable/model-scoped weekly window when returned; otherwise `Unavailable`
- Codex OAuth weekly subscription window
- Unlimited account descriptors; no email-based deduplication or hard account cap
- `Accounts` view and `Limit types` view
- Account alias editing
- Per-account email hiding
- Local JSON registry containing only provider, alias, email, and credential file path
- Provider-managed OAuth credential files are read at refresh time; tokens are never copied into QuotaBar JSON
- Fixed HTTPS host/path policies and redirect rejection in the URLSession client
- Manual refresh plus bounded 180-second background polling
- Last-known data stays visible if refresh fails
- No Claude Web cookie scraping
- No external CLI execution
- No telemetry or auto-update framework

## OAuth account setup

Open Settings from the app and choose the provider credential JSON file:

- Claude: the Claude Code `~/.claude/.credentials.json` file
- Codex: the Codex `auth.json` file, normally under `~/.codex/`

QuotaBar stores the selected path, not the OAuth access or refresh token. Multiple
credential files can be added; each gets its own stable account ID, alias, and
email visibility setting.

The first-party provider files remain the source of truth for OAuth login and
token rotation. If a token expires, QuotaBar reports re-authentication required;
it does not silently invoke a CLI or write a refreshed token back into a provider
file.

## Important endpoint note

The Claude OAuth usage endpoint and Codex subscription usage endpoint are not
public, stable billing APIs. They are the read-only endpoints used by the
corresponding coding clients and may change or rate-limit third-party clients.
The code treats 401/403/429 and schema changes as explicit refresh failures.

## Requirements

- macOS 26+
- Swift 6.2+

The current Mac has Swift 6.2.3 available through Command Line Tools. The
standard XCTest/Testing modules are unavailable until full Xcode is selected,
so the repository uses a framework-free executable self-check.

## Verify

```sh
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
```

## Run

```sh
swift run QuotaBar
```

For a normal app bundle during local development, build the product and place it
under `Contents/MacOS` of a `.app` bundle with `Resources/Info.plist`.

## Source layout

- `Sources/QuotaBarCore/` — models, grouping, credential decoding, endpoint policy, provider clients, persistence
- `Sources/QuotaBarUI/` — shared menu-bar/Preview UI, polling, alias/email settings
- `Sources/QuotaBar/` — menu-bar app entry point
- `Sources/QuotaBarPreview/` — regular-window UI preview entry point
- `Sources/QuotaBarChecks/` — framework-free red/green self-check executable
- `docs/2026-08-21-multi-account-oauth-requirements.md` — current acceptance contract
