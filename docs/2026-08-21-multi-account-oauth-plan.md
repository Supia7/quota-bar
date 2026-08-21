# Multi-account OAuth Usage Monitor Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build an original macOS menu-bar monitor that shows live Claude and Codex OAuth subscription limits for an unlimited number of accounts.

**Architecture:** `QuotaBarCore` owns provider-neutral accounts/windows, view grouping, token-free registry/preferences, OAuth credential decoding, fixed endpoint policies, and provider clients. `QuotaBarUI` owns polling, local alias/email preferences, account setup, and the two monitor layouts. `QuotaBar` is the menu-bar entry point; `QuotaBarPreview` is the same surface in a regular window for visual QA. Provider login/token rotation remains owned by Claude Code/Codex; QuotaBar only reads the provider-managed credential files.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Package Manager, macOS 26, URLSession, Foundation JSON.

---

## Acceptance contract

- Claude: 5-hour, all-model weekly, and Fable/model-scoped weekly row when available; missing Fable is `Unavailable`, never 0%.
- Codex: weekly subscription row.
- Multiple accounts are keyed by stable UUID and have no hard maximum.
- `Accounts` and `Limit types` layouts are selectable and locally persisted.
- Alias is editable; provider email is display-only and can be hidden per account.
- Only provider, alias, email, visibility, and credential path are persisted by QuotaBar.
- Access/refresh tokens never enter QuotaBar JSON or logs.
- OAuth requests use fixed HTTPS host/path policies and reject redirects.
- Manual refresh plus bounded background polling; failed refresh preserves last data.

## Completed slices

### Task 1: Domain models and grouping

**Files:**
- `Sources/QuotaBarCore/QuotaModels.swift`
- `Sources/QuotaBarCore/QuotaProvider.swift`
- `Sources/QuotaBarChecks/main.swift`

**Verification:** `swift run QuotaBarChecks`

### Task 2: Provider response decoders and endpoint policy

**Files:**
- `Sources/QuotaBarCore/UsageDecoders.swift`
- `Sources/QuotaBarCore/OAuthEndpointPolicy.swift`

**Verification:** fixture JSON checks for Claude legacy/new shapes, Fable mapping, Codex weekly mapping, and trusted/untrusted hosts.

### Task 3: Token-free registry and display preferences

**Files:**
- `Sources/QuotaBarCore/OAuthCredentials.swift`
- `Sources/QuotaBarCore/AccountRegistryStore.swift`
- `Sources/QuotaBarCore/AccountDisplayPreferencesStore.swift`

**Verification:** credential decode checks, registry JSON token absence, registry and preference round trips.

### Task 4: OAuth HTTP boundary and live provider

**Files:**
- `Sources/QuotaBarCore/OAuthHTTPClient.swift`
- `Sources/QuotaBarCore/LiveOAuthQuotaProvider.swift`
- `Sources/QuotaBarChecks/main.swift`

**Verification:** fixture transport loads two credential files and returns two live accounts without a cap; real HTTP client only permits fixed HTTPS endpoints and rejects redirects.

### Task 5: Monitor layouts and account editing

**Files:**
- `Sources/QuotaBarUI/QuotaBarUI.swift`
- `Sources/QuotaBar/QuotaBarApp.swift`
- `Sources/QuotaBarPreview/PreviewApp.swift`

**Verification:** `swift build --product QuotaBar`; `swift build --product QuotaBarPreview`; Preview window screenshot.

### Task 6: Settings account onboarding

**Files:**
- `Sources/QuotaBarUI/QuotaBarUI.swift`
- `Sources/QuotaBarCore/AccountRegistryStore.swift`

**Verification:** JSON file importer adds a descriptor, app switches from sample provider to live provider, and removing the last descriptor restores sample mode.

## Remaining hardening

1. Add Keychain-backed credential reading where the provider stores credentials in Keychain instead of a readable JSON file.
2. Add provider profile lookups so email can be discovered rather than manually entered; keep manual email as a fallback.
3. Make live refresh best-effort per account so one expired account becomes a card-level re-auth state instead of failing the whole refresh.
4. Add URLSession redirect/error fixture tests and a cooldown test for the 180-second polling policy.
5. Select full Xcode and restore a native XCTest target in addition to the current framework-free checks.
6. Add code signing/notarization and a reviewed release pipeline only after provider behavior is stable.
