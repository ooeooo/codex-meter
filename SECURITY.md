# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security vulnerability. Use GitHub's private vulnerability reporting for this repository instead.

Include the affected version, reproduction steps, impact, and any suggested mitigation. Do not include access tokens, account identifiers, or raw authenticated Codex traffic.

## Security model

Codex Meter starts the local `codex app-server` process and uses read-only `account/rateLimits/read`, `account/usage/read` and `account/read` methods for monitoring. It does not read `~/.codex/auth.json`, store credentials, add third-party telemetry, or send usage data to a separate service.

The app persists bounded account quota snapshots with account identity, quota windows, credit balance and available reset count under Application Support. Account daily token analytics remain in memory and are verified against the account before and after each usage read. It does not scan session logs or consume reset credits. Explicit profile deletion also removes its quota archive.

The optional CLI history command scans only aggregate `token_count` records from recent Codex rollout logs. Those source files can contain private content, so the scanner prefilters exact record types, decodes a narrow numeric DTO, never logs source lines, and keeps aggregate results on the Mac.

The distributed app is built by GitHub Actions from the tagged source. Release artifacts should be verified against the source before use in sensitive environments.
