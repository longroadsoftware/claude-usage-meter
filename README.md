# Claude Usage Meter

A tiny macOS menu bar app that shows how much of your **Claude plan's usage limit** you have left, always visible at the top of the screen.

```
 ◔ Claude 3% remaining
```

- Reads the same numbers as **claude.ai → Settings → Usage**, straight from Anthropic's usage endpoint.
- Shows **% remaining** or **% used** (your choice), with a ring that turns orange and then red as you run low.
- Click it for every limit (5-hour session, weekly, model-only caps) and when each one resets.
- Optional Dock tile and an optional notification when you drop below a threshold.
- No telemetry and no third-party servers. The only network call goes to `api.anthropic.com`.

> Unofficial. Not affiliated with or endorsed by Anthropic. It uses the same usage endpoint Claude Code uses, which is undocumented and could change.

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)
- A Claude Pro/Max/Team plan, signed in through **Claude Code** on the same Mac (`claude`, then `/login`), **or** any command that prints a token or usage JSON (see [Data sources](#data-sources))
- Xcode Command Line Tools to build (`xcode-select --install`)

## Install

```bash
git clone https://github.com/longroadsoftware/claude-usage-meter.git
cd claude-usage-meter
./build.sh --install
```

This builds `Claude Usage Meter.app`, copies it to `~/Applications` and starts it. Turn on **Open at login** in Settings.

Because it's built on your own Mac, Gatekeeper won't complain. If you download a prebuilt copy that isn't notarized, right-click it and choose **Open** the first time.

## Settings

Click the menu bar item, then **Settings…** (⌘,). Everything is stored in `UserDefaults` under `com.longroadsoftware.claudeusagemeter`, so you can also script it with `defaults write`.

| Setting | Key | Default |
|---|---|---|
| Read usage from | `source` (`claudeCode` / `command`) | `claudeCode` |
| Custom command | `command` | *(empty)* |
| Which limit | `limit` (`tightestAccount`, `tightestAny`, `week`, `session`) | `tightestAccount` |
| Show | `show` (`remaining` / `used`) | `remaining` |
| Menu bar style | `menuBarStyle` (`ringAndText`, `ringAndPercent`, `textOnly`, `ringOnly`) | `ringAndText` |
| Label | `label` | `Claude` |
| Color text when low | `colorText` | off |
| Dock tile | `showInDock` | off |
| Orange below (% remaining) | `warnBelow` | 30 |
| Red below (% remaining) | `criticalBelow` | 10 |
| Notify below (% remaining, 0 = off) | `notifyBelow` | 0 |
| Refresh every (minutes) | `refreshMinutes` | 5 |
| Mark stale after (minutes) | `staleMinutes` | 20 |
| Request timeout (seconds) | `requestTimeout` | 15 |
| Open at login | *(macOS Login Items)* | off |

"Tightest account-wide limit" shows whichever of the 5-hour session and weekly limits is closest to running out. Model-only caps, such as a per-model weekly allowance, are listed in the menu but don't drive the number unless you choose "including model-only caps".

If a check fails, the last good number stays up. After the stale time it's dimmed and marked **(stale)**, so you never mistake an old reading for a live one.

## Data sources

**Claude Code login (default).** The app reads the OAuth login that Claude Code stores in your login Keychain (`Claude Code-credentials`) or in `~/.claude/.credentials.json`. It **only reads** it: it never refreshes or rewrites your login, because refresh tokens are single-use and doing so could sign Claude Code out. If the token has expired, the menu says so. Run `claude` once and it refreshes.

The first time, macOS asks whether *Claude Usage Meter* may use the "Claude Code-credentials" Keychain item. Choose **Always Allow**.

**Custom command.** Point it at any shell command. The command runs in your login shell, and it must print one of:

- an OAuth access token (`sk-ant-oat…`), which the app then uses to call the usage endpoint, or
- usage JSON, either Anthropic's response or `{"windows":[{"label":"Current week","used_percent":97,"resets_at":"2026-11-15T02:00:00Z"}]}`.

Examples:

```bash
# Hermes Agent users
hermes usage --provider anthropic --json
# A token kept in 1Password
op read "op://Private/Claude/token"
```

## Testing without a screen

```bash
"build/Claude Usage Meter.app/Contents/MacOS/ClaudeUsageMeter" --once /tmp/tile.png          # prints every limit, renders the tile
"build/Claude Usage Meter.app/Contents/MacOS/ClaudeUsageMeter" --once /tmp/tile.png --used
```

## Privacy

The app sends your token only to `https://api.anthropic.com/api/oauth/usage`. It stores nothing except its settings. There is no analytics, update check or crash reporting.

## License

MIT. See [LICENSE](LICENSE).
