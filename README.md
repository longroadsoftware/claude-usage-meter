# Claude Usage Meter

A tiny macOS menu bar app that shows how much of your **Claude plan's usage limit** you have left, always visible at the top of the screen.

```
 ◔ Claude 3% remaining
```

- Shows the same numbers as **claude.ai → Settings → Usage**.
- Shows **% remaining** or **% used**, with a ring that turns orange and then red as you run low.
- Click it to see every limit (5-hour session, weekly, model-only caps) and when each one resets.
- Optional Dock tile, and an optional notification when you're running low.
- No telemetry and no third-party servers. It only talks to Anthropic.

Free, from [Long Road Software](https://longroadsoftware.com/?utm_source=github&utm_medium=readme&utm_campaign=claude-usage-meter), makers of dependable software, starting on the Mac.

> Unofficial. Not affiliated with or endorsed by Anthropic.

## Install

**[⬇︎ Download the latest release](https://github.com/longroadsoftware/claude-usage-meter/releases/latest)**, unzip it, and drag **Claude Usage Meter** into Applications. Then open it.

It's signed and notarized by Apple, so it opens normally with no security warnings.

Or, in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/longroadsoftware/claude-usage-meter/main/install.sh | bash
```

Requires macOS 14 Sonoma or later. Works on Apple silicon and Intel Macs, with a Claude Pro, Max or Team plan.

## First run

1. Your browser opens claude.ai. Click **Authorize**.
2. That's it. The browser hands the sign-in back to the app, and the meter appears at the top right of your screen.

Sign in with the Claude account **that has your Pro or Max plan**.

**If you use Claude Code**, there may be nothing to do: when Claude Code is signed in on the same Mac, the meter uses that automatically.

Your sign-in is stored in your Mac's Keychain and is only used to read your usage. To remove it, click the meter and choose **Sign Out of Claude**.

## Troubleshooting

**claude.ai asks you to upgrade, but you already have Pro or Max.**
Your browser is signed in to claude.ai with a *different* Claude account, one without a plan. It's common if you have a work and a personal account. claude.ai checks whichever account the browser is using, sees no plan, and offers an upgrade. Your plan is fine.

To fix it:
1. On claude.ai, click your name at the bottom left and choose **Log out**.
2. Sign in with the account that has your plan.
3. Click the meter and choose **Sign in with Claude…** again.

To keep your other account signed in, open a private window instead (⌘⇧N in Chrome, ⇧⌘N in Safari). Sign in there with the right account, then choose **Sign in with Claude…** while that window is in front.

**Not sure which account has your plan?** On claude.ai, open **Settings → Billing**. The account with the plan shows it there.

**"Sign-in timed out."** The meter waits 5 minutes for you to click Authorize. Choose **Sign in with Claude…** again.

**The meter says (stale).** It couldn't check for a while, usually because the Mac was offline or asleep. It catches up on its own. Click the meter for the last error, or choose **Refresh Now**.

## Settings

Click the meter, then **Settings…** (⌘,).

- **Show:** percent remaining or percent used.
- **Which limit:** the tightest one (default), weekly only, or the 5-hour session only.
- **Menu bar:** ring + text, ring + %, text only, or ring only. You can also change the label.
- **Colors:** orange and red thresholds, with optional colored text.
- **Notify** when you drop below a level you choose.
- **Refresh interval**, when a reading counts as stale, and the request timeout.
- **Dock tile** and **Open at login**.

If a check fails, the last good number stays up. After a while it's marked **(stale)**, so you never mistake an old reading for a live one.

<details>
<summary>Advanced: custom command</summary>

Under **Settings → Read usage from → Custom command**, you can point the app at any shell command. The command must print either an OAuth access token (`sk-ant-oat…`) or usage JSON, such as `{"windows":[{"label":"Current week","used_percent":97,"resets_at":"2026-11-15T02:00:00Z"}]}`.

```bash
hermes usage --provider anthropic --json      # Hermes Agent
op read "op://Private/Claude/token"            # a token kept in 1Password
```

Every setting is also in `UserDefaults` under `com.longroadsoftware.claudeusagemeter`, if you'd rather script it with `defaults write`.
</details>

<details>
<summary>Build it yourself</summary>

```bash
xcode-select --install          # once, if you don't have the command line tools
git clone https://github.com/longroadsoftware/claude-usage-meter.git
cd claude-usage-meter && ./build.sh --install
```

`./release.sh` builds the signed, notarized zip. It needs a Developer ID certificate.
</details>

## Privacy

Your Claude sign-in goes only to Anthropic (`claude.ai`, `platform.claude.com`, `api.anthropic.com`). The app stores its settings and your sign-in in the Keychain, and nothing else. There is no analytics, update check or crash reporting.

The usage endpoint is the same undocumented one Claude Code uses, so Anthropic could change it.

## License

MIT. See [LICENSE](LICENSE).
