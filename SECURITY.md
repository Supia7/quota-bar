# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected credential, OAuth, token, or
update-chain vulnerability.

Report it privately through the repository's GitHub security advisory flow:

<https://github.com/Supia7/quota-bar/security/advisories/new>

If GitHub's private advisory flow is unavailable, open a minimal issue asking
for a private contact channel without including credentials or exploit details.

## Scope

The most sensitive areas are:

- OAuth credential file handling
- Claude and Codex usage endpoint requests
- account registry and display preference persistence
- release packaging, signing, and update artifacts

Never include access tokens, refresh tokens, cookies, credential files, or
private account information in an issue, pull request, screenshot, or log.
