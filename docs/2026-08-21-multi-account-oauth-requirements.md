# Multi-account OAuth Usage Requirements

> **Status:** MVP implementation contract
> **Date:** 2026-08-21

## Goal

Build a native macOS menu-bar monitor for OAuth-backed Claude and Codex subscriptions. It must show live server-side quota state for an unlimited number of configured accounts without copying provider tokens into QuotaBar-owned plaintext storage.

## Acceptance criteria

1. **Providers**
   - Claude and Codex are first-class providers.
   - API-key billing data is not treated as subscription quota.
   - OAuth credentials are read through an explicit credential boundary.

2. **Quota windows**
   - Claude: 5-hour rolling window, all-model weekly window, and a Fable/model-scoped weekly window when the provider returns one.
   - Codex: weekly subscription window.
   - Every window includes remaining percentage and reset time when available.
   - Missing provider fields remain unavailable; they are never rendered as 0% or inferred.

3. **Live refresh**
   - Manual refresh is available.
   - Background refresh is bounded and provider-aware; Claude OAuth usage is polled every five minutes by default.
   - Last-known data remains visible with stale/error state when a refresh fails.

4. **Unlimited multi-account**
   - Account collections are unbounded in code and UI; no fixed `maxAccounts` constant.
   - Accounts are keyed by stable local IDs, not email, so duplicate emails or multiple workspaces remain distinct.

5. **Views**
   - `Account` view: one card per account with its quota rows.
   - `Limit type` view: one section per quota kind with all matching accounts underneath.
   - The selected view persists locally.

6. **Identity display**
   - Each account has an editable local alias and a provider-reported email.
   - Alias is the primary label when present.
   - Email can be hidden per account; hiding affects UI only and does not mutate provider data.
   - Email is never editable in the alias editor.

## Security contract

- Never log, print, or persist access/refresh tokens in QuotaBar-owned JSON.
- Provider requests use fixed HTTPS hosts and reject redirects to other hosts.
- Claude OAuth uses `https://api.anthropic.com/api/oauth/usage` with the documented-for-Claude-Code beta header, but this endpoint is undocumented and may change.
- Codex subscription usage uses the read-only ChatGPT backend usage endpoint used by Codex clients; it is also an internal endpoint and may change.
- A 401/403 must become an explicit re-authentication state; no silent fallback to cookies or API keys.

## Deliberate non-goals for this slice

- No Claude Web cookie scraping.
- No external CLI execution.
- No token paste field.
- No automatic account cap or account deduplication.
- No fake sample row mixed with real provider rows; sample mode stays visibly marked.
