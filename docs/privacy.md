# Privacy

Codex Meter is designed so useful monitoring does not require another monitoring service.

## What the app reads

- Current account-wide quota, credit balance, available reset count, daily token buckets, aggregate lifetime usage and account identity through supported read-only Codex app-server methods (`account/rateLimits/read`, `account/usage/read` and `account/read`).
- Local preferences for alert thresholds, display mode, language and launch at login.
- Saved quota snapshots under `~/Library/Application Support/Codex Meter/QuotaHistory`, isolated by profile and verified account identity. Archives contain account IDs (or email/type on older servers), timestamps and numeric quota/credit fields, not credentials.
- Account profile directories created under `~/.codex-meter/accounts`; Codex owns their credentials and Codex Meter never reads them.

## What the app deliberately ignores

The app does not scan rollout logs. The explicit optional CLI `history` command reads local aggregate token events; it does not represent full account activity. Its history scanner uses a local filter to reduce candidate lines, then decodes narrow structures containing only the exact event discriminator, bounded model ID, timestamp and numeric token totals. Candidate lines exist briefly in process memory, but unknown fields are never retained in models, logs, history or errors.

## What leaves the Mac

Codex Meter has no third-party tracking, telemetry, advertising, account service or history upload. The quota request is handled by the installed Codex process using its existing session. Quota archives remain local. Daily account analytics are fetched from Codex and held in memory; they are not uploaded to any additional service. The app reads no individual conversations for its daily analytics. Optional CLI history, model pricing and USD/AUD/EUR conversion do not make network calls.

Adding an account starts the supported `codex login` browser flow with a profile-specific `CODEX_HOME`. Email, password, SSO and MFA are entered only on OpenAI's secure page; the browser returns the completed session directly to Codex. Codex Meter then starts the read-only app-server under that profile. The app does not copy, parse or display `auth.json`, access tokens, passwords or verification codes.

Deleting a non-default profile requires confirmation and removes its entire local `CODEX_HOME`, including the Codex-owned cached credentials. It does not delete or modify the OpenAI account. If the folder is already absent, Codex Meter still removes the stale profile entry. The app also removes the profile’s quota-history archive.

Choosing **Meter + Codex** is an explicit authentication change. Codex Meter closes the desktop app, asks Codex app-server to log out the default profile, and starts OpenAI's supported ChatGPT browser login. The browser and Codex exchange the credentials directly; Meter only receives the documented success state and account email used to verify that the intended profile was selected. Passwords, SSO secrets, MFA codes, access tokens and `auth.json` contents are never read or copied by Meter.

The banked-reset number is OpenAI's reported `availableCount`, not a local estimate. Available reset-credit details do not provide complete reset history; count changes alone do not prove use. Codex Meter displays the count but never calls the reset-credit consumption method. Credit balances retain the backend credit units and are not converted to currency.

## Cost estimates

ChatGPT subscriptions are not billed as a simple per-token API invoice. Codex Meter therefore does not claim to show money spent. The optional CLI applies a bundled, dated snapshot of official standard API prices entirely offline. The app does not estimate costs from account quota percentages. No local usage is sent to OpenAI's pricing pages.
