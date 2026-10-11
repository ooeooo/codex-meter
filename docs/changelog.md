# Changelog

## 1.6.2 — 2026-10-11

- Fixed the false “Codex is not installed” error for desktop builds that moved their bundled service into `Contents/Resources/codex-cli/`; support the packaged launcher, nested native executable and legacy layout without a separate CLI installation.
- Added a “Select Codex App…” recovery action for installations outside standard locations, persisted the selected app and refreshed desktop discovery when retrying a missing service.
- Clarified the service-not-found message and included searched paths in sanitized diagnostics.
- Added new-layout fixtures and real process handshake checks through a desktop bundle and its packaged launcher.

## 1.6.1 — 2026-10-11

- Fixed quota bucket selection when modern servers return multiple limit IDs without a `codex` key; use the server’s canonical quota instead of an arbitrary product bucket.
- Find the current or registered desktop application, including renamed apps and user installations; prefer the unified ChatGPT desktop, verify its Codex bundle identity, and support absolute PATH locations.
- Report actual quota window durations, reject failed initialization, and protect replacement clients from callbacks belonging to older processes.
- Keep operation errors separate from quota failures, protect account switches against old refresh results, and prevent notification permission prompts from blocking polling.
- Refresh stale menu-bar state regularly and retry after wake; retain bounded, redacted process diagnostics and empty-response diagnostics for troubleshooting.
- Added official-protocol fixtures, executable discovery checks, initialization/reconnection checks and diagnostic privacy checks.

## 1.6.0 — 2026-10-10

- Added an original macOS application icon, generated as ICNS with native system tools at all standard and Retina sizes; included PNG and ICO source assets.
- Added English and Simplified Chinese interfaces with system language detection, a persistent Settings language selector and immediate UI refresh.
- Localized usage charts, settings, account dialogs, notifications, accessibility labels, dates and common errors; kept CLI output and JSON labels stable in English.
- Added localization regression checks and verified icon and language resources in the final release package.
- Updated installation instructions for current macOS Gatekeeper prompts.

## 1.5.0 — 2026-07-15

- Moved the named account switcher beside refresh with an explicit down-arrow affordance.
- Added a confirmation choice for Meter-only or Meter plus Codex desktop switching.
- Implemented desktop switching with OpenAI's documented app-server logout, secure browser login, account verification and relaunch flow.
- Fixed Codex opening with the supported settings deep link plus bundle-ID and application-path fallbacks.
- Fixed deletion for stale account records whose local profile directory is already missing.
- Added visible banked-reset counts from OpenAI's authoritative `rateLimitResetCredits.availableCount` field, with an honest unavailable state.
- Added live account-read, reset-history and profile-deletion validation.

## 1.4.0 — 2026-07-15

- Added confirmed deletion of unused local account profiles and their Codex-owned credentials.
- Clarified the boundary between meter profiles and the separately authenticated Codex desktop app.
- Added an in-app handoff to open Codex for desktop account switching.

## 1.3.2 — 2026-07-15

- Changed Add Account to the normal OpenAI browser sign-in flow so email, password, SSO and MFA stay on OpenAI's page.
- Isolated each saved account with file-scoped Codex credentials and activated it only after successful login.

## 1.3.1 — 2026-07-15

- Clarified USD, AUD and EUR symbols in model costs, savings and CLI output.
- Restored the translucent liquid-glass surface, material section depth and restrained native motion.

## 1.2.0 — 2026-07-15

- Added local token attribution by the model recorded for each Codex turn.
- Added model-by-model token totals, shares and API-equivalent estimates in the popover and CLI.
- Added persistent USD, AUD and EUR display currencies plus CLI exchange-rate overrides.
- Added automatic standard pricing for locally observed GPT-5.4, GPT-5.5 and GPT-5.6 model families from official OpenAI model pages.
- Added explicit price-source dating, unknown-model handling and custom fallback rates.
- Bumped history JSON to schema version 2 with structured pricing metadata.
- Expanded model-switch, duplicate-log, counter-reset, unknown-model and pricing coverage.

## 1.3.0 — 2026-07-15

- Added isolated `CODEX_HOME` account profiles with supported device-login flow and one-click hot swap.
- Added collapsible usage, local-activity and settings sections.
- Added menu-bar savings total and in-app milestone banners for savings, tokens, low usage and banked resets.

## 1.1.0 — 2026-07-15

- Added privacy-safe seven-day token activity history from local Codex session logs.
- Added a compact native activity chart in the popover.
- Added optional API-equivalent cost estimates with user-owned rates.
- Added four configurable menu-bar display modes.
- Added the universal `codex-meter` CLI with JSON, history and threshold exit codes.
- Added explicit privacy documentation and the production WidgetKit signing roadmap.
- Expanded honest-error, inspectability, low-footprint and zero-dependency product positioning.

## 1.0.0 — 2026-07-15

- Added native menu-bar usage display.
- Added primary and secondary Codex usage windows with local reset times.
- Added configurable low-usage notifications and launch-at-login support.
- Added resilient multi-bucket response parsing and unit coverage.
- Added universal Apple silicon and Intel packaging.
- Added open-source community, security, CI, and release documentation.
