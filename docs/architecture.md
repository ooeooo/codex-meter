# Architecture

Codex Meter is a SwiftUI/AppKit status-bar application with seven small layers:

1. `AppDelegate` owns `NSStatusItem` and `NSPopover` lifecycle.
2. `UsageStore` owns polling, preferences, login-item registration, and low-usage notifications.
3. `CodexAppServerClient` owns one local stdio JSONL session with `codex app-server`.
4. `RateLimitParser` and `AccountUsageParser` convert versioned app-server payloads into stable UI models.
5. `AccountQuotaHistoryStore` persists account snapshots, and `AccountQuotaHistory` compares windows without combining cycles or accounts.
6. `LocalActivityScanner` provides aggregate-only token events for the optional CLI history command.
7. `CodexMeterCLI` exposes stable status/history DTOs for local scripts without importing AppKit.

`UsageStore` can select an isolated account profile. Each profile is a Codex-owned `CODEX_HOME` directory with file-scoped credential storage, and the client starts `codex app-server` with that environment only. Adding a profile invokes Codex's supported browser login flow and activates the account only after login succeeds; Codex Meter never inspects the profile's credentials.

Account deletion removes the selected non-default profile only after a native confirmation. Missing profile folders are treated as an already-completed filesystem removal so stale account records can still be cleared.

The desktop Codex app uses the default Codex authentication profile. A confirmed **Meter + Codex** switch closes the desktop app, creates a default-home app-server connection, calls the documented `account/logout` method, starts `account/login/start` with ChatGPT browser authentication, waits for `account/login/completed`, verifies the result with `account/read`, and relaunches Codex. This is deliberately a fresh OAuth flow: Codex Meter does not copy tokens between profiles, collect passwords or MFA codes, call internal token-login modes, or request Accessibility control.

The client performs the required `initialize` handshake before calling `account/rateLimits/read`. It prefers the `codex` entry in the multi-bucket response and falls back to the server’s canonical backward-compatible `rateLimits` snapshot. It never selects an arbitrary unrelated quota bucket. Initialization errors are propagated, and each process and account handoff has a generation guard so old callbacks cannot overwrite a replacement connection. Percentages are clamped to 0–100, and the menu bar displays the lowest remaining percentage across returned windows.

The app intentionally does not consume rate-limit reset credits or expose conversation, configuration, or usage-changing methods. Its only authentication writes are explicit user-confirmed logout/login operations during desktop account switching.

The executable locator checks explicit `CODEX_PATH`, selected/active/registered official desktop bundles, system and user application directories, absolute inherited `PATH` entries, then common CLI directories. Desktop bundles must have the `com.openai.codex` identifier; the classic ChatGPT app is not a Codex service. Within a validated bundle, it tries the new `codex-cli/bin/codex` launcher, nested `codex-cli/CodexCLI.app/Contents/MacOS/codex` and legacy `Resources/codex`. It never launches the Electron GUI executable as an app-server. A native app picker saves a validated desktop location and restarts the same profile's client. Retrying a missing service refreshes the running/registered bundle snapshot. The client preserves Codex’s configured credential storage and does not inspect credentials. Diagnostics include the effective `CODEX_HOME`, protocol stage, process exit code, searched paths on discovery failure and a bounded redacted stderr summary.

Quota errors, account operation errors and quota-history storage errors have separate display states. Notification authorization does not block polling. The status item checks data age every 30 seconds and refreshes quota after macOS wakes.

## Account quota history

The app records the same backend account snapshot every two minutes; it no longer scans rollout logs. `credits` is the backend credit balance, not money or tokens. Missing balances and reset counts stay unavailable. Account snapshots include usage from cloud sessions and other devices; the source does not identify which device caused a change.

`AccountQuotaHistoryStore` atomically writes bounded JSON archives under `~/Library/Application Support/Codex Meter/QuotaHistory/<profile UUID>.json` (directory permissions 0700, file permissions 0600). Each profile archive separates accounts by backend `accountId`. Older servers use matching `account/read` email/type responses before and after the quota read. Without a verifiable identity, the app displays current quota and does not combine history. Corrupt archives are reported and preserved. Deleting a profile also removes its quota archive.

Within a matching plan, bucket, duration and future reset deadline, lower remaining quota produces a **net percentage-point decrease**, including changes since the app last ran. Primary and secondary windows are never added together. Each change retains its full observation interval instead of assigning downtime usage to the restart date. First observations establish a baseline, not historical consumption.

A reset deadline advancing past its previous end to a future deadline marks a new cycle, even if usage is now higher than before. The app retains the old scheduled reset and the newly reported next reset, and displays current-cycle used percentage separately from unknown earlier-interval consumption. If a reported deadline has passed but the backend still returns an expired window, the app marks **waiting for updated quota**, even when the percentage is unchanged. Repeated identical pending responses do not create repeated reset events. Once a fresh cycle arrives, its snapshot becomes the baseline for subsequent differences.

An early deadline change, plan change, unknown deadline, or remaining-quota increase is shown as a new/unverified window or possible reset/adjustment. Cross-cycle total consumption stays unknown: a scheduled deadline is not a complete reset ledger, and an unsampled tail of the previous cycle cannot be recovered from the next cycle’s percentage. An unchanged value does not prove that no activity or hidden reset occurred. Intervals longer than five minutes are marked unobserved. Recent quota changes and reset times are shown within the daily-history details, without another chart. Both menu-bar percentages and weekly pace wait for a fresh cycle when any allowance has expired; the previous value is explicitly historical. The menu-bar history uses server-provided daily token counts, independently of quota availability.

Seven days and at most 6,000 observations per account are retained. The last persisted observation is compared before pruning, so a long downtime can still reveal a changed cycle without fabricating its intermediate history. Storage failures keep current quota visible with a warning that new history may be lost on quit.

### Reset API limits

The contract was inspected using `codex-cli 0.159.2` and `codex app-server generate-ts --out /tmp/codex-protocol`. `GetAccountRateLimitsResponse` contains `accountId`, quota snapshots and `rateLimitResetCredits`. `RateLimitResetCreditsSummary.credits` describes **available** credits, may be null or capped, and has grant/expiry fields but no redemption timestamp. There is no complete subscription-reset history read in this protocol. Count decreases can reflect use or expiry; increases can reflect grants. Neither proves that a quota reset happened. Meter never calls `account/rateLimitResetCredit/consume`.

## Daily account analytics

`CodexAppServerClient.readAccountUsage()` calls `account/usage/read` with empty parameters, intentionally omitting `threadId` to request account-wide history. The installed 0.159.2 protocol returns `summary` and nullable `dailyUsageBuckets` with `startDate` and `tokens`. It exposes no date-range parameters or model/project/source/currency breakdown fields. The app does not invent those dimensions or use local rollout logs to fill them.

The account history section selects the last 7 or 30 calendar labels, including today, and shows one daily token chart by default. A single, initially closed disclosure contains the sum and peak of reported days, coverage, active-day count, daily rows, account lifetime totals, streaks and recent quota changes. Date lookup, newest/oldest and high/low usage sorting, and the active-days toggle affect the detail table; the chart and summary keep their period scope. Selecting a row highlights that day in the chart. Expanded content scrolls within an explicit viewport bounded by the status item's screen height. The AppKit popover and SwiftUI root receive the same size before opening; no document-height preference controls viewport height. A timer updates displayed dates and countdowns without placing TimelineView in the scroll document. No separate Analytics view or quota chart is added.

Date-only labels are preserved. ISO day-boundary timestamps are validated and normalized to their original calendar label without shifting dates into another time zone. The plotting calendar uses UTC only as a stable coordinate system. The range ends on the user's current Gregorian calendar date. DST cannot duplicate or omit a label. Missing days remain nil, explicit zero counts remain zero, and null daily detail differs from an empty result. Identical duplicate days are deduplicated; conflicting duplicates, invalid dates, negative/fractional/boolean counts and overflowed individual counters fail visibly. Integer token counters retain 64-bit precision; an overflowing period sum remains unavailable.

Quota and daily history use independent polling tasks, every two and ten minutes respectively. Slow history responses cannot delay quota polling. Both refresh on startup and after wake; manual refresh reads them concurrently. Account reads before and after the usage request must match. Profile switches and externally observed account changes clear analytics and invalidate pending results using both client and analytics generation guards. Old results cannot populate another profile's view. Analytics have independent loading/errors and never turn a successful quota read into a failure. Unsupported methods prompt updating Codex or using its built-in settings page. Daily analytics remain in memory, while quota snapshots keep their existing bounded disk archive.

## Optional CLI local history

The explicit `codex-meter history` command still scans recent `.jsonl` files under `~/.codex/sessions` and `~/.codex/archived_sessions`. It prefilters `turn_context` and `token_count` records and retains only bounded model IDs, timestamps and numeric totals. This local-token workflow is independent of the app's account quota history.

## Cost estimates

`OpenAIPriceCatalog` is a dated, inspectable snapshot of standard per-million-token prices from official OpenAI model pages. Matching is exact by model ID; unknown models remain visibly unpriced unless the user supplies fallback rates. There is no runtime pricing request or external dependency.

`DisplayCurrency` converts the USD base estimate to USD, AUD or EUR using a dated ECB reference-rate snapshot. The CLI selects a display currency and can override the USD-to-selected-currency rate. No live FX request runs.

Cost estimates are available only in the optional local-token CLI workflow. The app does not infer tokens, model costs or savings from quota percentages. Banked resets come directly from `rateLimitResetCredits.availableCount`, and missing fields remain unavailable.

Cached input is a subset of input, so estimates price non-cached input as `input - cached`, then apply model-specific input, cached-input and output rates. Reasoning output is not added again because it is contained in output totals. Aggregate logs cannot reliably reveal request-level pricing adjustments such as long context, so the CLI calls the result an API-equivalent estimate rather than a bill.

## Distribution

Both the app and CLI are compiled for arm64 and x86_64 and merged into universal binaries. The free release is ad-hoc signed. WidgetKit is excluded until a Developer ID/App Group/notarization pipeline can preserve its capabilities reliably.

## Login and notification lifecycle

Each pending profile login retains its app-server client. Profile deletion cancels the task and stops that client before removing local credentials. Completion callbacks verify that the login still belongs to an existing profile; stopped login waits fail immediately, including waits registered after stop. Failed login of an active pending profile falls back to the default profile. Low-quota notifications skip expired allowances, recheck the source payload after permission requests and record delivery only after the notification service accepts the request. Banner dismissal timers belong to a specific message generation, so an old timer cannot hide a newer message.
