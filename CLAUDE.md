# JokenBar

Tiny macOS menu bar app showing Claude / Claude Code usage limits.

## Principles
- Keep it minimal: no notifications, no extra settings, no Dock icon.
- Everything committed (code, comments, docs, commit messages, fixtures) is in English, with no references to any specific company or person. Fixtures use generic values (Example Org, example.com, $1000 included, $150 monthly).
- Public repo, MIT license, copyright "chei".

## Architecture
- `Sources/QuotaCore`: Foundation-only parsing and display logic, unit tested with swift-testing (`scripts/test.sh`; plain `swift test` needs Xcode).
- `Sources/JokenBar`: AppKit `NSStatusItem` + `NSPopover` with SwiftUI, Carbon global hotkey ⌃⌥U (no Accessibility permission), `WKWebView` sign-in.
- Each account has its own `WKWebsiteDataStore(forIdentifier:)`. Requests run as `fetch` inside an invisible web view on claude.ai, so WebKit handles cookies, SSO and Cloudflare; a Safari user agent keeps Google sign-in working. The app stores no tokens or cookies.

## Data source (undocumented claude.ai endpoints)
- `GET /api/organizations` → `[{uuid, name, capabilities}]`; keep only orgs whose capabilities contain `"chat"`.
- `GET /api/organizations/{uuid}/usage`:
  - Any top-level object with `limit_dollars`/`used_dollars`/`remaining_dollars` is a dollar allowance (currently `copper_kite` = Enterprise "Included usage"; `resets_at` = expiry). Detect by shape, never by key name: keys are rotating code names.
  - `spend` (fallback `extra_usage`): monthly per-user spend limit in minor units (`amount_minor`, `exponent`). No reset date is returned; the app shows the 1st of next month with "≈".
  - `limits[]` (fallback `five_hour`/`seven_day`): Pro/Max percent limits. Empty on Enterprise.
  - `cedar_ember.grants[]`: promotional usage-limit resets.
- Menu bar headline priority: active included allowance → monthly limit → highest percent limit.
- Enterprise claude.ai sessions typically expire after 7 days; the popover then shows "Session expired – Sign In…".

## Release
- Bump `VERSION` and push to `main`: GitHub Actions runs tests, builds `dist/JokenBar.zip`, creates tag `v<VERSION>` and the release.
- `install.sh` installs/updates from `releases/latest/download/JokenBar.zip` (curl download avoids Gatekeeper quarantine). Unsigned app, ad-hoc codesign.

## Ideas (not committed to)
- Burn rate / forecast line for included usage.
- Configurable hotkey.
- Hardening: allow only GET to the two endpoints above in `WebFetcher`.
