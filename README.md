# QuotaBar

QuotaBar is an original macOS menu-bar quota monitor for coding-agent accounts.

## MVP status

The first vertical slice is intentionally offline:

- SwiftUI `MenuBarExtra` monitor surface
- Claude, Codex, and Kimi sample rows
- Clear `SAMPLE DATA` marker
- Provider-neutral `QuotaProvider` boundary
- No network requests
- No credentials
- No external CLI execution
- No telemetry
- No auto-update framework

Real provider integrations will be added only behind explicit security contracts:
Keychain-only credentials, HTTPS host allowlists, redirect rejection, account
isolation, and provider-specific qualification tests.

## Requirements

- macOS 26+
- Swift 6.2+

The current Mac has Swift 6.2.3 available through Command Line Tools. The
standard XCTest/Testing modules are unavailable until full Xcode is selected,
so the repository currently uses a framework-free executable self-check.

## Verify

```sh
swift run QuotaBarChecks
swift build --product QuotaBar
```

## Run the sample UI

```sh
swift run QuotaBar
```

The app is a menu-bar application. Open its menu-bar gauge to inspect the
sample monitor surface. The settings panel documents the intentionally offline
MVP boundary.

## Project boundary

Do not add provider credentials, API calls, or copied provider adapters to the
MVP without updating the plan in `docs/2026-08-21-mvp-plan.md` and adding a
security-focused verification path first.
