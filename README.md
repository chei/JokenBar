# JokenBar

**How much of your Claude usage is left? One glance at the menu bar.**

A tiny macOS app (~2 MB) that shows your Claude / Claude Code usage in the menu
bar. No Dock icon, no system permissions, one request to claude.ai every
10 minutes.

<!-- Screenshot: docs/screenshot.png -->

| Menu bar | Meaning |
|---|---|
| 🎁 `$740` | work (Enterprise) account: what's left of the *Included usage* grant |
| 💲 `$150` | work account: what's left of the monthly limit once included usage has expired |
| ⏱ `34%` | personal Pro/Max account: 5-hour limit used |

Color: 🟢 plenty left · 🟠 running low · 🔴 almost gone.

Click it (or press **⌃⌥J**) for details: included usage and its expiry, monthly
limit and reset, Pro/Max weekly limit, several accounts at once.

## Install

Requires macOS 14 (Sonoma) or later.

### 1. One command (recommended)

Open **Terminal**, paste, press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/chei/JokenBar/main/install.sh | bash
```

It downloads the latest release, copies it to Applications and starts it. Run
the same command to update. The script is short – [read it](install.sh) first
if you like.

### 2. Download

1. [**Download JokenBar.zip**](https://github.com/chei/JokenBar/releases/latest/download/JokenBar.zip),
   unzip it and drag the app to **Applications**.
2. Open it. macOS will say it *"cannot be verified"* – click **Done**.
3. **System Settings → Privacy & Security**, scroll down:
   *"JokenBar was blocked…"* → **Open Anyway** → enter your password.

You only need to do this once. (The app isn't signed with a paid Apple
Developer certificate, so macOS asks.)

### 3. From source

Requires Xcode Command Line Tools:

```sh
git clone https://github.com/chei/JokenBar.git && cd JokenBar
scripts/build-app.sh && cp -R dist/JokenBar.app /Applications/ && open /Applications/JokenBar.app
```

## First launch

1. The icon appears in the menu bar and a small window opens → **Add Account…**
2. Sign in to claude.ai just like in your browser (company SSO, Google or email
   code). The window closes by itself once you're in.
3. Personal account too? ⚙ → **Add Account…** → sign in again. Star the account
   to show in the menu bar (the first one by default).
4. Optionally ⚙ → **Launch at Login**. The ⚙ section can also turn off the
   ⌃⌥J shortcut.

## Security and privacy

- The app only talks to **claude.ai** and reads the same data the claude.ai
  *Settings → Usage* page shows. It reads nothing else and sends nothing anywhere.
- It never sees your password: you sign in on claude.ai's own page in a built-in
  browser window. Each account's session is stored separately on your Mac.
- It asks for no access to your screen, files or keyboard.
- Open source, about 1000 lines of Swift – anyone can review it.

## Update and uninstall

**Update:** run the install command again, or download the zip again.

**Uninstall:** in the app, remove each account with its trash button, then ⚙ → **Quit JokenBar**, then:

```sh
rm -rf /Applications/JokenBar.app ~/Applications/JokenBar.app
rm -rf ~/Library/WebKit/io.github.chei.jokenbar ~/Library/Caches/io.github.chei.jokenbar
defaults delete io.github.chei.jokenbar
```

## FAQ

**Why isn't it on the App Store / why does macOS warn me?**
Signing requires a $99/year Apple Developer membership. The one-command install
avoids the warning.

**Is this an official Anthropic app?**
No. It uses undocumented internal claude.ai endpoints, so a change on
Anthropic's side may break it until the next update.

**What is Included usage?**
Some Enterprise users get a dollar grant with an expiry date when they start.
While it lasts, usage comes out of the grant and the monthly limit stays
untouched. After it expires, the monthly limit set by the admin applies, and it
resets at the start of every month.

**I can't sign in with Google.**
Try the email code instead, or open an issue.

## How it works

| Endpoint | Purpose |
|---|---|
| `GET /api/organizations` | organizations the account belongs to |
| `GET /api/organizations/{org}/usage` | all limits in one response |

- Any object with `limit_dollars` / `used_dollars` / `remaining_dollars` → a
  dollar allowance (today: `copper_kite` = Included usage, `resets_at` = expiry).
  The app finds it **by shape**, because the keys are rotating code names.
- `spend` (with `extra_usage` as fallback) → monthly spend limit, in cents.
- `limits[]`, `five_hour`, `seven_day` → Pro/Max percent limits.
- `cedar_ember.grants[]` → promotional limit resets.

Each account gets its own WebKit data store (`WKWebsiteDataStore(forIdentifier:)`);
requests are a `fetch` running in an invisible web view on claude.ai. The API
doesn't return the monthly reset date, so the app shows the first day of next
month ("≈").

## Development

```sh
scripts/test.sh             # QuotaCore unit tests (swift test; also works with Command Line Tools only)
swift run JokenBar          # run
scripts/build-app.sh        # dist/JokenBar.app + dist/JokenBar.zip (universal with Xcode, host arch otherwise)
```

- `Sources/QuotaCore` – JSON parsing and display logic (Foundation only)
- `Sources/JokenBar` – menu bar item, SwiftUI popover, WebKit sign-in

Release: bump `VERSION` and push to `main` → GitHub Actions tags `v<VERSION>`,
builds and uploads `JokenBar.zip` to Releases.

## Roadmap

- Burn rate and forecast (will included usage expire unused?)
- Configurable hotkey

## License

[MIT](LICENSE)
